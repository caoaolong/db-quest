class_name FileNode
extends BaseNode

"""
{
    "size": 0
}
"""

@export var title: String = "文件"

@onready var progress: ProgressBar = $VBoxContainer/ProgressBar


func _ready() -> void:
    super._ready()
    _sync_controls_from_data()


func _sync_data_from_controls() -> void:
    pass


func _sync_controls_from_data() -> void:
    _update_size_display()


func clear_run_data() -> void:
    data["size"] = 0
    data.erase("page")
    _update_size_display()


func _update_size_display() -> void:
    var page_count := VirtualFile.get_page_count()
    if not data.has("page"):
        set_subtitle("- / %d pages" % page_count)
        return
    set_subtitle("%d / %d pages" % [int(data.get("page", 0)), page_count])


func _on_display_clicked() -> void:
    action.display_data({
        "file_path": GameState.virtual_file_path,
        "total_bytes": VirtualFile.get_size_bytes(),
        "page_size": VirtualFile.PAGE_SIZE,
    }, DisplayDialog.DataType.BINARY)


func run(inputs: Dictionary = {}) -> Variant:
    var slot_inputs := _get_slot_inputs(inputs)
    var operation := _normalize_operation(slot_inputs.get(1, ""))
    var file_path := GameState.virtual_file_path
    var result: Variant

    match operation:
        "READ":
            result = _run_read(file_path, slot_inputs)
        "WRITE":
            result = _run_write(file_path, slot_inputs)
        "":
            EditorLog.warn("文件未收到操作码，请将 Operation 接到 Code")
            result = {
                "error": "Missing operation",
            }
        _:
            EditorLog.warn("Unknown file operation: %s" % operation)
            result = {
                "error": "Unknown operation: %s" % operation,
            }

    _notify_file_run()
    return result


func _notify_file_run() -> void:
    var graph_edit := get_graph_edit()
    if graph_edit != null:
        TaskTrigger.handle(TaskTrigger.AFTER_FILE_RUN, graph_edit)


func _run_read(file_path: String, slot_inputs: Dictionary) -> PackedByteArray:
    var page_index := _get_page_index(slot_inputs.get(2, 0))
    var page_data := VirtualFile.read_page(file_path, page_index)
    data["size"] = VirtualFile.get_size_bytes()
    data["page"] = page_index
    _update_size_display()
    schedule_save()
    EditorLog.info("文件读取第 %d 页（%d 字节）" % [page_index, page_data.size()])
    return page_data


func _run_write(file_path: String, slot_inputs: Dictionary) -> PackedByteArray:
    var page_index := _get_page_index(slot_inputs.get(2, 0))
    var encoded: Dictionary = _encode_write_data(slot_inputs.get(3))
    var page_data: PackedByteArray = encoded["payload"] as PackedByteArray
    data["size"] = VirtualFile.get_size_bytes()
    data["page"] = page_index
    _update_size_display()
    schedule_save()
    EditorLog.info("文件写入第 %d 页（源 %d 字节）" % [
        page_index,
        int(encoded["source_size"]),
    ])
    var success := VirtualFile.write_page(file_path, page_index, page_data)
    if success:
        var graph_edit := get_graph_edit()
        if graph_edit != null:
            TaskTrigger.handle(TaskTrigger.AFTER_VF_WRITE, graph_edit)
        return page_data
    return PackedByteArray()


func _get_slot_inputs(inputs: Dictionary) -> Dictionary:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return {}

    var by_slot: Dictionary = {}
    for port_key in inputs.keys():
        var port_index := int(port_key)
        var slot_index: int = graph_node.get_input_port_slot(port_index)
        by_slot[slot_index] = inputs[port_key]
    return by_slot


func _normalize_operation(value: Variant) -> String:
    return str(value).strip_edges().to_upper()


func _get_page_index(value: Variant) -> int:
    var page_index := 0
    if value is int:
        page_index = value
    elif value is float:
        page_index = int(value)
    else:
        page_index = int(str(value))
    return maxi(0, page_index + queue_index)


func _encode_write_data(value: Variant) -> Dictionary:
    var source_bytes := _to_byte_array(value)
    var payload := VirtualFile.clip_to_page(source_bytes)
    return {
        "payload": payload,
        "source_size": source_bytes.size(),
        "truncated": source_bytes.size() > VirtualFile.PAGE_SIZE,
        "padded": source_bytes.size() < VirtualFile.PAGE_SIZE,
    }


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
