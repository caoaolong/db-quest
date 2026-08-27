class_name PageSchema
extends RefCounted

const SCHEMAS_DIR := "res://data/schemas/"


static func describe_page(page: PackedByteArray, schema_name: String) -> Array:
    var schema := load_schema(schema_name)
    if schema.is_empty():
        return []
    var rows: Array = []
    for entry in schema:
        if not entry is Dictionary:
            continue
        var field := entry as Dictionary
        var range_spec := PageRule.parse_byte_range(str(field.get("range", "")))
        if range_spec.is_empty():
            continue
        var start := int(range_spec["start"])
        var end := int(range_spec["end"])
        if start < 0 or end < start or end >= page.size():
            rows.append({
                "label": str(field.get("label", str(field.get("range", "")))),
                "value": "<out of range>",
            })
            continue
        var slice := page.slice(start, end + 1)
        rows.append({
            "label": str(field.get("label", str(field.get("range", "")))),
            "value": _format_value(slice, str(field.get("format", "hex"))),
        })
    return rows


static func load_schema(schema_name: String) -> Array:
    var name := schema_name.strip_edges()
    if name.is_empty():
        return []
    var path := "%s%s.json" % [SCHEMAS_DIR, name]
    if not FileAccess.file_exists(path):
        return []
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return []
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if parsed is Array:
        return parsed as Array
    return []


static func _format_value(bytes: PackedByteArray, format_name: String) -> String:
    match format_name.strip_edges().to_lower():
        "ascii", "string":
            return _format_ascii(bytes)
        "version":
            var version := UintCodec.decode_bytes(bytes, _width_type(bytes.size()))
            return "%d.0" % version
        "uint", "int":
            return str(UintCodec.decode_bytes(bytes, _width_type(bytes.size())))
        "hex":
            return _format_hex(bytes)
        _:
            return _format_hex(bytes)


static func _format_ascii(bytes: PackedByteArray) -> String:
    var end := bytes.size()
    while end > 0 and bytes[end - 1] == 0:
        end -= 1
    if end <= 0:
        return ""
    return bytes.slice(0, end).get_string_from_utf8()


static func _format_hex(bytes: PackedByteArray) -> String:
    if bytes.is_empty():
        return "0x0"
    var parts: PackedStringArray = PackedStringArray()
    for byte in bytes:
        parts.append("%02X" % int(byte))
    return "0x" + "".join(parts)


static func _width_type(byte_count: int) -> String:
    match byte_count:
        1:
            return UintCodec.TYPE_UINT8
        2:
            return UintCodec.TYPE_UINT16
        4:
            return UintCodec.TYPE_UINT32
        8:
            return UintCodec.TYPE_UINT64
        _:
            return UintCodec.TYPE_UINT32
