class_name UintCodec
extends RefCounted

const TYPE_UINT8 := "UINT8"
const TYPE_UINT16 := "UINT16"
const TYPE_UINT32 := "UINT32"
const TYPE_UINT64 := "UINT64"

const TYPE_NAMES := [TYPE_UINT8, TYPE_UINT16, TYPE_UINT32, TYPE_UINT64]

const TYPE_BYTES := {
    TYPE_UINT8: 1,
    TYPE_UINT16: 2,
    TYPE_UINT32: 4,
    TYPE_UINT64: 8,
}

const TYPE_MAX := {
    TYPE_UINT8: 255,
    TYPE_UINT16: 65535,
    TYPE_UINT32: 4294967295,
    # SpinBox 基于 float，无法精确表示完整 UINT64 域
    TYPE_UINT64: 9223372036854775807,
}


static func normalize_type(type_name: String) -> String:
    var key := type_name.strip_edges().to_upper()
    if key == "INT":
        return TYPE_UINT64
    if TYPE_BYTES.has(key):
        return key
    return TYPE_UINT64


static func byte_width(type_name: String) -> int:
    return int(TYPE_BYTES.get(normalize_type(type_name), 8))


static func max_value(type_name: String) -> int:
    return int(TYPE_MAX.get(normalize_type(type_name), TYPE_MAX[TYPE_UINT64]))


static func encode(value: int, type_name: String) -> PackedByteArray:
    var width := byte_width(type_name)
    var max_v := max_value(type_name)
    var clamped := clampi(value, 0, max_v)
    var out := PackedByteArray()
    out.resize(width)
    for i in width:
        out[i] = (clamped >> (8 * i)) & 0xFF
    return out


static func decode(value: Variant, type_name: String = TYPE_UINT64) -> int:
    if value == null:
        return 0
    if value is int:
        return maxi(0, value)
    if value is float:
        return maxi(0, int(value))
    if value is String:
        var text := (value as String).strip_edges()
        if text.is_valid_int():
            return maxi(0, int(text))
        return 0
    if value is PackedByteArray:
        return decode_bytes(value as PackedByteArray, type_name)
    if value is Array:
        var bytes := PackedByteArray()
        for item in value:
            if item is int:
                bytes.append(clampi(int(item), 0, 255))
        return decode_bytes(bytes, type_name)
    return 0


static func decode_bytes(bytes: PackedByteArray, type_name: String = TYPE_UINT64) -> int:
    var width := byte_width(type_name)
    var result := 0
    var limit := mini(bytes.size(), width)
    for i in limit:
        result |= int(bytes[i]) << (8 * i)
    return result
