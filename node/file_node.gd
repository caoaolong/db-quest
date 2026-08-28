class_name FileNode
extends BaseNode

"""
{
    "size": 0
}
"""

const SLOT_CODE := 2
const SLOT_DATA := 3
const SLOT_PAGE := 4
const SLOT_COUNT := 5

@export var title: String = "文件"

var _handle: FileAccess = null

@onready var progress: ProgressBar = $VBoxContainer/ProgressBar


func _ready() -> void:
    super._ready()
    _sync_controls_from_data()


func _sync_data_from_controls() -> void:
    pass


func _sync_controls_from_data() -> void:
    _update_size_display()


func clear_run_data() -> void:
    _close_handle()
    data["size"] = 0
    data.erase("page")
    _update_size_display()


func has_handle() -> bool:
    return _handle != null


func get_handle() -> FileAccess:
    return _handle


func _close_handle() -> void:
    if _handle != null:
        _handle.close()
        _handle = null


func _update_size_display() -> void:
    if has_handle():
        set_subtitle("opened")
        return
    set_subtitle("- / -")


func _on_display_clicked() -> void:
    action.display_data({
        "disk_path": GameState.virtual_disk_path,
        "opened": has_handle(),
        "total_bytes": VirtualDisk.get_size_bytes(),
        "page_size": VirtualDisk.SECTOR_SIZE,
    }, DisplayDialog.DataType.BINARY)


func run(_inputs: Dictionary = {}) -> Variant:
    _close_handle()

    var disk_path := GameState.virtual_disk_path
    if disk_path.is_empty():
        disk_path = VirtualDisk.ensure_exists()
        GameState.virtual_disk_path = disk_path
    if disk_path.is_empty():
        EditorLog.warn("无法打开虚拟磁盘：路径无效")
        _update_size_display()
        return {
            "error": "Missing virtual disk",
        }

    var file := FileAccess.open(disk_path, FileAccess.READ_WRITE)
    if file == null:
        EditorLog.warn("打开虚拟磁盘失败: %s" % disk_path)
        _update_size_display()
        return {
            "error": "Open virtual disk failed",
        }

    _handle = file
    data["size"] = VirtualDisk.get_size_bytes()
    _update_size_display()
    schedule_save()
    EditorLog.info("已打开虚拟磁盘，获得文件句柄")
    _notify_file_run()
    return {
        "handle": true,
        "path": disk_path,
    }


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
