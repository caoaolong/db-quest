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
    var operation := _normalize_operation(slot_inputs.get(1, ""))
    var disk_path := GameState.virtual_disk_path

    match operation:
        "IDENTIFY":
            return _run_identify()
        "READ":
            return _run_read(disk_path, slot_inputs)
        "WRITE":
            return _run_write(disk_path, slot_inputs)
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


func _run_read(disk_path: String, slot_inputs: Dictionary) -> Dictionary:
    var sector_index := _get_sector_index(slot_inputs.get(3, 0))
    var sector_data := VirtualDisk.read_sector(disk_path, sector_index)
    return {
        "operation": "READ",
        "sector": sector_index,
        "data": sector_data,
        "data_hex": sector_data.hex_encode(),
    }


func _run_write(disk_path: String, slot_inputs: Dictionary) -> Dictionary:
    var sector_index := _get_sector_index(slot_inputs.get(3, 0))
    var encoded := _encode_sector_data(slot_inputs.get(2))
    var sector_data: PackedByteArray = encoded["sector"]
    var success := VirtualDisk.write_sector(disk_path, sector_index, sector_data)
    if success:
        var graph_edit := get_graph_edit()
        if graph_edit != null:
            TaskTrigger.handle(TaskTrigger.AFTER_VD_WRITE, graph_edit)
    return {
        "operation": "WRITE",
        "sector": sector_index,
        "source_bytes": encoded["source_size"],
        "truncated": encoded["truncated"],
        "bytes_written": sector_data.size(),
        "success": success,
    }


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
    if value is int:
        return value
    if value is float:
        return int(value)
    return int(str(value))


func _encode_sector_data(value: Variant) -> Dictionary:
    var source_bytes := _to_byte_array(value)
    var truncated := source_bytes.size() > VirtualDisk.SECTOR_SIZE
    var sector := VirtualDisk.clip_to_sector(source_bytes)

    return {
        "sector": sector,
        "source_size": source_bytes.size(),
        "truncated": truncated,
        "padded": source_bytes.size() < VirtualDisk.SECTOR_SIZE,
    }


func _to_byte_array(value: Variant) -> PackedByteArray:
    if value == null:
        return PackedByteArray()

    if value is PackedByteArray:
        return value

    return str(value).to_utf8_buffer()
