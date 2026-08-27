class_name PageRule
extends RefCounted

const RULES_DIR := "res://data/rules/"
const SPECIAL_CHECKSUM := "$CHECKSUM"

## IEEE CRC-32 查找表（多项式 0xEDB88320）
static var _crc_table: PackedInt32Array = PackedInt32Array()


static func validate_page(page: PackedByteArray, rule_name: String) -> bool:
    var rule := load_rule(rule_name)
    if rule.is_empty():
        EditorLog.warn("规则不存在或无效: %s" % rule_name)
        return false
    return matches(page, rule)


static func load_rule(rule_name: String) -> Dictionary:
    var name := rule_name.strip_edges()
    if name.is_empty():
        return {}
    var path := "%s%s.json" % [RULES_DIR, name]
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if parsed is Dictionary:
        return parsed as Dictionary
    return {}


static func matches(page: PackedByteArray, rule: Dictionary) -> bool:
    if page.is_empty() or rule.is_empty():
        return false

    for key in rule.keys():
        var range_spec := _parse_byte_range(str(key))
        if range_spec.is_empty():
            EditorLog.warn("无法解析规则字段: %s" % str(key))
            return false
        var start := int(range_spec["start"])
        var end := int(range_spec["end"])
        if start < 0 or end < start or end >= page.size():
            EditorLog.warn("规则字段越界: %s (page=%d)" % [str(key), page.size()])
            return false

        var expected: Variant = rule[key]
        if not _field_matches(page, start, end, expected):
            EditorLog.warn("规则字段不匹配: %s (expected=%s)" % [str(key), str(expected)])
            return false
    return true


static func _field_matches(page: PackedByteArray, start: int, end: int, expected: Variant) -> bool:
    var length := end - start + 1
    var actual := page.slice(start, end + 1)

    if expected is String:
        var text := expected as String
        if text == SPECIAL_CHECKSUM:
            return _checksum_matches(page, start, end)
        var expected_bytes := text.to_utf8_buffer()
        if expected_bytes.size() != length:
            return false
        return actual == expected_bytes

    if expected is float or expected is int:
        var expected_int := int(expected)
        var decoded := UintCodec.decode_bytes(actual, _width_type(length))
        return decoded == expected_int

    return false


static func compute_checksum(
    data: PackedByteArray,
    zero_offset: int = 0,
    zero_length: int = 0
) -> int:
    var scratch := data.duplicate()
    if zero_length > 0:
        var end := mini(zero_offset + zero_length, scratch.size())
        for i in range(maxi(0, zero_offset), end):
            scratch[i] = 0
    return crc32(scratch)


static func _checksum_matches(page: PackedByteArray, start: int, end: int) -> bool:
    var length := end - start + 1
    if length != 4:
        EditorLog.warn("$CHECKSUM 目前仅支持 4 字节字段")
        return false

    var digest := compute_checksum(page, start, length)
    var expected := UintCodec.encode(digest, UintCodec.TYPE_UINT32)
    var actual := page.slice(start, end + 1)
    if actual != expected:
        EditorLog.warn(
            "$CHECKSUM 不匹配: actual=0x%s expected=0x%s" % [
                _format_hex(actual),
                _format_hex(expected),
            ]
        )
    return actual == expected


static func _format_hex(bytes: PackedByteArray) -> String:
    var parts: PackedStringArray = PackedStringArray()
    for byte in bytes:
        parts.append("%02X" % int(byte))
    return "".join(parts)


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


## 解析 "24" 或 "0:3"（闭区间，含两端）
static func parse_byte_range(spec: String) -> Dictionary:
    return _parse_byte_range(spec)


static func _parse_byte_range(spec: String) -> Dictionary:
    var text := spec.strip_edges()
    if text.is_empty():
        return {}
    if text.contains(":"):
        var parts := text.split(":", false, 1)
        if parts.size() != 2:
            return {}
        if not str(parts[0]).is_valid_int() or not str(parts[1]).is_valid_int():
            return {}
        return {
            "start": int(parts[0]),
            "end": int(parts[1]),
        }
    if not text.is_valid_int():
        return {}
    var index := int(text)
    return {
        "start": index,
        "end": index,
    }


static func crc32(data: PackedByteArray) -> int:
    _ensure_crc_table()
    var crc := 0xFFFFFFFF
    for byte in data:
        var index := (crc ^ int(byte)) & 0xFF
        crc = int(_crc_table[index]) ^ ((crc >> 8) & 0x00FFFFFF)
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF


static func _ensure_crc_table() -> void:
    if _crc_table.size() == 256:
        return
    _crc_table.resize(256)
    for i in 256:
        var value := i
        for _bit in 8:
            if (value & 1) != 0:
                value = (0xEDB88320 ^ (value >> 1)) & 0xFFFFFFFF
            else:
                value = (value >> 1) & 0xFFFFFFFF
        _crc_table[i] = value
