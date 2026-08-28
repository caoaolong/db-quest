class_name DiskNode
extends BaseNode

"""
{
    "size": 0
}
"""

@export var title: String = "磁盘"

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
    _update_size_display()


func _update_size_display() -> void:
    var size_bytes := int(data.get("size", 0))
    if size_bytes > 0:
        set_subtitle("- / %d MB" % int(size_bytes / (1024.0 * 1024.0)))
    else:
        set_subtitle("- / -")


func _get_disk_size_bytes() -> int:
    var size_bytes := int(data.get("size", 0))
    if size_bytes > 0:
        return size_bytes
    return VirtualDisk.get_size_bytes()


func _on_display_clicked() -> void:
    action.display_data({
        "disk_path": GameState.virtual_disk_path,
        "total_bytes": _get_disk_size_bytes(),
        "page_size": VirtualDisk.SECTOR_SIZE,
    }, DisplayDialog.DataType.BINARY)


func run(inputs: Dictionary = {}) -> Variant:
    var slot_inputs := _get_slot_inputs(inputs)
    var operation := _normalize_operation(slot_inputs.get(2, ""))
    var disk_path := GameState.virtual_disk_path

    match operation:
        "IDENTIFY":
            return _run_identify()
        "READ":
            return _run_read(disk_path, slot_inputs)
        "WRITE":
            return _run_write(disk_path, slot_inputs)
        "":
            EditorLog.warn("磁盘未收到操作码，请将 Load String 接到 Control Bus")
            return {
                "error": "Missing operation",
            }
        _:
            EditorLog.warn("Unknown disk operation: %s" % operation)
            return {
                "error": "Unknown operation: %s" % operation,
            }


func _run_identify() -> Dictionary:
    var size_bytes := VirtualDisk.get_size_bytes()
    var size_mb := VirtualDisk.get_size_mb()
    data["size"] = size_bytes
    _update_size_display()
    schedule_save()
    return {
        "operation": "IDENTIFY",
        "size_bytes": size_bytes,
        "size_mb": size_mb,
    }


func _run_read(disk_path: String, slot_inputs: Dictionary) -> PackedByteArray:
    var count := _get_sector_count(slot_inputs.get(5, 1))
    var base_sector := _get_sector_index(slot_inputs.get(4, 0))
    var sector_index := base_sector + queue_index * count
    var length := count * VirtualDisk.SECTOR_SIZE
    var sector_data := VirtualDisk.read_bytes(disk_path, sector_index * VirtualDisk.SECTOR_SIZE, length)
    EditorLog.info("磁盘读取扇区 %d 起共 %d 个（%d 字节）" % [
        sector_index,
        count,
        sector_data.size(),
    ])
    if not sector_data.is_empty():
        GameState.read_buffer.record(sector_index, sector_data)
        var graph_edit := get_graph_edit()
        if graph_edit != null:
            TaskTrigger.handle(TaskTrigger.AFTER_VD_READ, graph_edit)
    return sector_data


func _run_write(disk_path: String, slot_inputs: Dictionary) -> PackedByteArray:
    var source_bytes := _to_byte_array(slot_inputs.get(3))
    var requested_count := _get_sector_count(slot_inputs.get(5, 1))
    var base_sector := _get_sector_index(slot_inputs.get(4, 0))
    # 队列波次里每一包是一块数据：按实际占用扇区推进地址，避免 Count=2 时写成 0、2 而跳过 1。
    var write_count := requested_count
    if _is_queue_io():
        write_count = _sector_count_for_payload(source_bytes.size())
    var sector_index := base_sector + queue_index * write_count
    var encoded := _encode_write_data(source_bytes, write_count)
    var sector_data: PackedByteArray = encoded["payload"]
    EditorLog.info("磁盘写入扇区 %d 起共 %d 个（源 %d 字节）" % [
        sector_index,
        write_count,
        int(encoded["source_size"]),
    ])
    var success := VirtualDisk.write_sectors(disk_path, sector_index, write_count, sector_data)
    if success:
        var graph_edit := get_graph_edit()
        if graph_edit != null:
            TaskTrigger.handle(TaskTrigger.AFTER_VD_WRITE, graph_edit)
        return sector_data
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


func _get_sector_index(value: Variant) -> int:
    return UintCodec.decode(value, UintCodec.TYPE_UINT64)


func _get_sector_count(value: Variant) -> int:
    return maxi(1, _get_sector_index(value))


func _is_queue_io() -> bool:
    return queue_total > 1 or queue_index > 0


func _sector_count_for_payload(byte_count: int) -> int:
    if byte_count <= 0:
        return 1
    return ceili(byte_count / float(VirtualDisk.SECTOR_SIZE))


func _encode_write_data(source_bytes: PackedByteArray, count: int) -> Dictionary:
    var length := count * VirtualDisk.SECTOR_SIZE
    var payload := VirtualDisk.clip_to_length(source_bytes, length)

    return {
        "payload": payload,
        "source_size": source_bytes.size(),
        "truncated": source_bytes.size() > length,
        "padded": source_bytes.size() < length,
    }


func _to_byte_array(value: Variant) -> PackedByteArray:
    if value == null:
        return PackedByteArray()

    if value is PackedByteArray:
        return value

    if value is Array:
        var bytes := PackedByteArray()
        for item in value:
            bytes.append_array(_to_byte_array(item))
        return bytes

    return str(value).to_utf8_buffer()
