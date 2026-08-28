class_name WriteChecksumNode
extends BaseNode

"""
{
    "offset": 20,
    "rows": {
        "1": 0
    }
}
"""

const CHECKSUM_FIELD_LENGTH := 4
const SLOT_PAGE := 2
const SLOT_VALUE := 3

@export var title: String = "写校验和"

@onready var offset_input: SpinBox = $VBoxContainer/OffsetRow/SpinBox


func _ready() -> void:
    super._ready()
    offset_input.min_value = 0
    offset_input.max_value = 65535
    offset_input.value_changed.connect(_on_offset_changed)
    _sync_controls_from_data()


func _sync_data_from_controls() -> void:
    data["offset"] = int(offset_input.value)
    data.erase("zero_offset")
    data.erase("zero_length")


func _sync_controls_from_data() -> void:
    if data.has("offset"):
        offset_input.value = float(int(data["offset"]))
    elif data.has("zero_offset"):
        offset_input.value = float(int(data["zero_offset"]))
    _update_subtitle()


func _update_subtitle() -> void:
    var page := _resolve_page({})
    var offset := int(data.get("offset", offset_input.value))
    set_subtitle("page %d · offset %d" % [page, offset])


func _on_offset_changed(_value: float) -> void:
    _sync_data_from_controls()
    schedule_save()


func run(inputs: Dictionary = {}) -> Variant:
    _sync_data_from_controls()
    var slot_inputs := _get_slot_inputs(inputs)
    var page := _resolve_page(slot_inputs)
    var page_bytes := VirtualFile.read_page(GameState.virtual_file_path, page)
    if page_bytes.is_empty():
        EditorLog.warn("写校验和：页 %d 无数据" % page)
        return {"error": "Empty page"}

    var offset := int(data.get("offset", 0))
    if not _validate_range(offset, CHECKSUM_FIELD_LENGTH):
        return {"error": "Invalid range"}

    var digest := PageRule.compute_checksum(page_bytes, offset, CHECKSUM_FIELD_LENGTH)
    var encoded := UintCodec.encode(digest, UintCodec.TYPE_UINT32)
    for i in CHECKSUM_FIELD_LENGTH:
        page_bytes[offset + i] = encoded[i]

    var success := VirtualFile.write_page(GameState.virtual_file_path, page, page_bytes)
    if not success:
        return {"error": "Write failed"}

    EditorLog.info(
        "写校验和：page=%d offset=%d digest=0x%X 已写入" % [page, offset, digest]
    )
    var graph_edit := get_graph_edit()
    if graph_edit != null:
        TaskTrigger.handle(TaskTrigger.AFTER_VF_WRITE, graph_edit)
    _update_subtitle()
    schedule_save()
    return encoded


func _validate_range(offset: int, length: int) -> bool:
    if offset < 0 or length < 0:
        EditorLog.warn("写校验和偏移/长度非法: offset=%d length=%d" % [offset, length])
        return false
    if offset + length > VirtualFile.PAGE_SIZE:
        EditorLog.warn(
            "写校验和超出页大小 %d: offset=%d length=%d" % [VirtualFile.PAGE_SIZE, offset, length]
        )
        return false
    return true


func _resolve_page(slot_inputs: Dictionary) -> int:
    if slot_inputs.has(SLOT_PAGE):
        return _parse_page_index(slot_inputs[SLOT_PAGE])
    var spin := _row_spin(SLOT_PAGE)
    if spin != null:
        return maxi(0, int(spin.value))
    return 0


func _parse_page_index(value: Variant) -> int:
    if value is PackedByteArray or value is Array:
        return UintCodec.decode(value, UintCodec.TYPE_UINT64)
    if value is int:
        return maxi(0, value)
    if value is float:
        return maxi(0, int(value))
    if value is String:
        var text := (value as String).strip_edges()
        if text.is_valid_int():
            return maxi(0, int(text))
        EditorLog.warn("无法解析页码: %s" % text)
        return 0
    return 0


func _row_spin(slot_index: int) -> SpinBox:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return null
    return _get_row_control(graph_node, slot_index) as SpinBox


func _get_slot_inputs(inputs: Dictionary) -> Dictionary:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return {}
    var by_slot := {}
    for port_key in inputs.keys():
        var port_index := int(port_key)
        var slot_index := graph_node.get_input_port_slot(port_index)
        by_slot[slot_index] = inputs[port_key]
    return by_slot


func _on_display_clicked() -> void:
    var page := _resolve_page({})
    var page_data := VirtualFile.read_page(GameState.virtual_file_path, page)
    var offset := int(data.get("offset", 0))
    if page_data.is_empty():
        action.display_data(page_data, DisplayDialog.DataType.BINARY)
        return
    var end := mini(offset + CHECKSUM_FIELD_LENGTH, page_data.size()) - 1
    if offset > end:
        action.display_data(page_data, DisplayDialog.DataType.BINARY)
        return
    action.display_data({
        "title": "页 %d 校验和 @ %d" % [page, offset],
        "data": page_data.slice(offset, end + 1),
    })
