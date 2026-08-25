class_name FilePageNode
extends BaseNode

"""
{
    "page": 0,
    "offset": 0,
    "length": 0
}
"""

const SLOT_CODE := 1
const SLOT_PAGE := 2
const SLOT_OFFSET := 3
const SLOT_DATA := 4
const SLOT_LENGTH := 5

@export var title: String = "文件页"


func _ready() -> void:
    super._ready()
    _sync_controls_from_data()
    call_deferred("_setup_slot_controls")


func _setup_slot_controls() -> void:
    var page_spin := _get_page_spin()
    if page_spin != null:
        page_spin.min_value = 0
        page_spin.max_value = maxi(0, VirtualFile.get_page_count() - 1)
        if data.has("page"):
            page_spin.set_block_signals(true)
            page_spin.value = float(int(data["page"]))
            page_spin.set_block_signals(false)
        if not page_spin.value_changed.is_connected(_on_page_changed):
            page_spin.value_changed.connect(_on_page_changed)
    _update_subtitle()


func _sync_data_from_controls() -> void:
    var page_spin := _get_page_spin()
    if page_spin != null:
        data["page"] = int(page_spin.value)


func _sync_controls_from_data() -> void:
    var page_spin := _get_page_spin()
    if page_spin != null and data.has("page"):
        page_spin.set_block_signals(true)
        page_spin.value = float(int(data["page"]))
        page_spin.set_block_signals(false)
    _update_subtitle()


func _on_page_changed(_value: float) -> void:
    _sync_data_from_controls()
    _update_subtitle()
    schedule_save()


func clear_run_data() -> void:
    data.erase("offset")
    data.erase("length")
    _update_subtitle()


func _update_subtitle(offset: int = -1, length: int = -1) -> void:
    var page := int(data.get("page", 0))
    var page_spin := _get_page_spin()
    if page_spin != null:
        page = int(page_spin.value)
    var off := offset if offset >= 0 else int(data.get("offset", 0))
    var len := length if length >= 0 else int(data.get("length", 0))
    set_subtitle("page %d · off %d · len %d" % [page, off, len])


func _on_display_clicked() -> void:
    var page := int(data.get("page", 0))
    var page_spin := _get_page_spin()
    if page_spin != null:
        page = int(page_spin.value)
    var page_data := VirtualFile.read_page(GameState.virtual_file_path, page)
    action.display_data(page_data, DisplayDialog.DataType.BINARY)


func run(inputs: Dictionary = {}) -> Variant:
    var slot_inputs := _get_slot_inputs(inputs)
    var operation := _resolve_operation(slot_inputs)
    var page := _resolve_page_index(slot_inputs)
    var offset := UintCodec.decode(slot_inputs.get(SLOT_OFFSET, 0), UintCodec.TYPE_UINT16)
    var length := UintCodec.decode(slot_inputs.get(SLOT_LENGTH, 0), UintCodec.TYPE_UINT16)
    data["page"] = page
    data["offset"] = offset
    data["length"] = length
    var page_spin := _get_page_spin()
    if page_spin != null:
        page_spin.set_block_signals(true)
        page_spin.value = float(page)
        page_spin.set_block_signals(false)
    _update_subtitle(offset, length)
    schedule_save()

    match operation:
        "READ":
            return _run_read(page, offset, length)
        "WRITE":
            return _run_write(page, offset, length, slot_inputs.get(SLOT_DATA, null))
        "":
            EditorLog.warn("文件页未选择操作，请在下拉框选择 READ/WRITE，或接入 Operation")
            return {"error": "Missing operation"}
        _:
            EditorLog.warn("Unknown file page operation: %s" % operation)
            return {"error": "Unknown operation: %s" % operation}


func _run_read(page: int, offset: int, length: int) -> PackedByteArray:
    if length <= 0:
        EditorLog.warn("文件页 READ 需要 Length > 0")
        return PackedByteArray()
    if not _validate_range(offset, length):
        return PackedByteArray()

    var page_data := VirtualFile.read_page(GameState.virtual_file_path, page)
    if page_data.size() < offset + length:
        EditorLog.warn("文件页读取超出页范围: page=%d offset=%d length=%d" % [page, offset, length])
        return PackedByteArray()

    var slice := page_data.slice(offset, offset + length)
    EditorLog.info("文件页读取 page=%d offset=%d length=%d" % [page, offset, length])

    var graph_edit := get_graph_edit()
    if graph_edit != null:
        TaskTrigger.handle(TaskTrigger.AFTER_VF_READ, graph_edit)
    return slice


func _run_write(page: int, offset: int, length: int, raw_data: Variant) -> PackedByteArray:
    var payload := _to_byte_array(raw_data)
    var write_len := length if length > 0 else payload.size()
    if write_len <= 0:
        EditorLog.warn("文件页 WRITE 没有有效数据长度")
        return PackedByteArray()
    if not _validate_range(offset, write_len):
        return PackedByteArray()

    data["length"] = write_len
    _update_subtitle(offset, write_len)

    var page_data := VirtualFile.read_page(GameState.virtual_file_path, page)
    var clipped := VirtualFile.clip_to_length(payload, write_len)
    for i in write_len:
        page_data[offset + i] = clipped[i]

    var success := VirtualFile.write_page(GameState.virtual_file_path, page, page_data)
    if not success:
        return PackedByteArray()

    EditorLog.info("文件页写入 page=%d offset=%d length=%d" % [page, offset, write_len])
    var graph_edit := get_graph_edit()
    if graph_edit != null:
        TaskTrigger.handle(TaskTrigger.AFTER_VF_WRITE, graph_edit)
    return clipped


func _validate_range(offset: int, length: int) -> bool:
    if offset < 0 or length < 0:
        EditorLog.warn("文件页偏移/长度非法: offset=%d length=%d" % [offset, length])
        return false
    if offset + length > VirtualFile.PAGE_SIZE:
        EditorLog.warn(
            "文件页超出页大小 %d: offset=%d length=%d" % [VirtualFile.PAGE_SIZE, offset, length]
        )
        return false
    return true


func _resolve_page_index(slot_inputs: Dictionary) -> int:
    if slot_inputs.has(SLOT_PAGE):
        return maxi(0, UintCodec.decode(slot_inputs[SLOT_PAGE], UintCodec.TYPE_UINT64))
    var page_spin := _get_page_spin()
    if page_spin != null:
        return maxi(0, int(page_spin.value))
    return maxi(0, int(data.get("page", 0)))


func _resolve_operation(slot_inputs: Dictionary) -> String:
    if slot_inputs.has(SLOT_CODE):
        var from_input := _normalize_operation(slot_inputs[SLOT_CODE])
        if not from_input.is_empty():
            return from_input
    return _operation_from_dropdown()


func _operation_from_dropdown() -> String:
    var option := _get_operation_option()
    if option == null or option.selected < 0:
        return ""
    return _normalize_operation(option.get_item_text(option.selected))


func _get_operation_option() -> OptionButton:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return null
    return _get_row_control(graph_node, SLOT_CODE) as OptionButton


func _get_page_spin() -> SpinBox:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return null
    return _get_row_control(graph_node, SLOT_PAGE) as SpinBox


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


func _normalize_operation(value: Variant) -> String:
    return str(value).strip_edges().to_upper()


func _to_byte_array(value: Variant) -> PackedByteArray:
    if value == null:
        return PackedByteArray()
    if value is PackedByteArray:
        return value as PackedByteArray
    if value is Array:
        var bytes := PackedByteArray()
        for item in value:
            bytes.append_array(_to_byte_array(item))
        return bytes
    return str(value).to_utf8_buffer()
