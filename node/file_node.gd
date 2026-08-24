class_name FileNode
extends BaseNode

"""
{
    "size": 0
}
"""

const SLOT_CODE := 1
const SLOT_DATA := 2
const SLOT_PAGE := 3
const SLOT_COUNT := 4

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
        "page_size": VirtualDisk.SECTOR_SIZE,
    }, DisplayDialog.DataType.BINARY)


func run(inputs: Dictionary = {}) -> Variant:
    var slot_inputs := _get_slot_inputs(inputs)
    var operation := _normalize_operation(slot_inputs.get(SLOT_CODE, ""))
    var file_path := GameState.virtual_file_path
    var result: Variant

    match operation:
        "READ":
            result = _run_read(file_path, slot_inputs)
        "WRITE":
            result = _run_write(file_path, slot_inputs)
        "":
            EditorLog.warn("文件未收到操作码，请将 Load Operation 接到 Code")
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
    var count := _get_page_count(slot_inputs.get(SLOT_COUNT, 1))
    var page_index := _resolve_read_page_index(slot_inputs, count)
    var length := count * VirtualFile.PAGE_SIZE
    var page_data := VirtualFile.read_bytes(file_path, page_index * VirtualFile.PAGE_SIZE, length)
    data["size"] = VirtualFile.get_size_bytes()
    data["page"] = page_index
    _update_size_display()
    schedule_save()
    EditorLog.info("文件读取第 %d 页起共 %d 页（%d 字节）" % [page_index, count, page_data.size()])
    if not page_data.is_empty():
        var start_sector := floori(float(page_index * VirtualFile.PAGE_SIZE) / float(VirtualDisk.SECTOR_SIZE))
        GameState.read_buffer.record(start_sector, page_data)
        var graph_edit := get_graph_edit()
        if graph_edit != null:
            TaskTrigger.handle(TaskTrigger.AFTER_VF_READ, graph_edit)
    return page_data


func _run_write(file_path: String, slot_inputs: Dictionary) -> PackedByteArray:
    var page_index := _resolve_write_page_index(slot_inputs)
    var encoded: Dictionary = _encode_write_data(slot_inputs.get(SLOT_DATA, null))
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

    var by_slot := {}
    for port_key in inputs.keys():
        var port_index := int(port_key)
        var slot_index := graph_node.get_input_port_slot(port_index)
        by_slot[slot_index] = inputs[port_key]
    return by_slot


func _normalize_operation(value: Variant) -> String:
    return str(value).strip_edges().to_upper()


func _parse_page_index(value: Variant) -> int:
    if value is PackedByteArray or value is Array:
        EditorLog.warn("页码端口收到了二进制数据，请检查 File 的 Page 与 Data 连线")
        return 0
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


func _get_page_count(value: Variant) -> int:
    return maxi(1, _parse_page_index(value))


func _resolve_write_page_index(slot_inputs: Dictionary) -> int:
    # WRITE 忽略 Count，每次只写单个文件页
    var base_page := _parse_page_index(slot_inputs.get(SLOT_PAGE, 0))
    if _page_input_tracks_queue_wave(base_page):
        return base_page
    return base_page + queue_index


func _resolve_read_page_index(slot_inputs: Dictionary, count: int) -> int:
    var base_page := _parse_page_index(slot_inputs.get(SLOT_PAGE, 0))
    if _page_input_tracks_queue_wave(base_page):
        return base_page
    return base_page + queue_index * count


func _page_input_tracks_queue_wave(base_page: int) -> bool:
    # Page 接 DataSplit Index 时，每波输入已是目标页码，不再叠加 queue_index
    return queue_total > 1 and base_page == queue_index


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
