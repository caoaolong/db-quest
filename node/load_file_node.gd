class_name LoadFileNode
extends BaseNode

"""
{
    "contents": {
        "1": ""
    }
}
"""


func _ready() -> void:
    super._ready()
    call_deferred("_sync_controls_from_data")


func _configure_action_bar() -> void:
    if action == null:
        return
    action.set_run_visible(true)
    action.set_button_visible("Delete", false)


func set_subtitle(_value: String) -> void:
    pass


func refresh_display() -> void:
    _sync_controls_from_data()


func clear_run_data() -> void:
    data["contents"] = {}


func _sync_data_from_controls() -> void:
    pass


func _sync_controls_from_data() -> void:
    _update_file_display()


func run(_inputs: Dictionary = {}) -> Variant:
    var outputs := _load_all_files()
    _sync_controls_from_data()
    schedule_save()

    if outputs.size() <= 1:
        return outputs.get("0", PackedByteArray())
    return {
        "__outputs": outputs,
    }


func _load_all_files() -> Dictionary:
    var outputs := {}
    var contents := {}
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        data["contents"] = contents
        return outputs

    var entries := GameState.get_level_file_entries()
    var output_port := 0
    for slot_index in range(1, graph_node.get_child_count()):
        var file_index := slot_index - 1
        if file_index >= entries.size():
            break

        var entry: Dictionary = entries[file_index]
        var path := str(entry.get("path", "")).strip_edges()
        var bytes := _read_file_bytes(path)
        contents[str(slot_index)] = bytes
        if graph_node.is_slot_enabled_right(slot_index):
            outputs[str(output_port)] = bytes
            output_port += 1

    data["contents"] = contents
    return outputs


func _read_file_bytes(path: String) -> PackedByteArray:
    if path.is_empty():
        return PackedByteArray()
    if not FileAccess.file_exists(path):
        EditorLog.warn("文件不存在: %s" % path)
        return PackedByteArray()
    return FileAccess.get_file_as_bytes(path)


func _update_file_display() -> void:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return

    var entries := GameState.get_level_file_entries()
    for slot_index in range(1, graph_node.get_child_count()):
        var row_control := _get_row_control(graph_node, slot_index)
        if not row_control is Label:
            continue

        var file_index := slot_index - 1
        if file_index >= entries.size():
            break

        var entry: Dictionary = entries[file_index]
        var file_name := str(entry.get("name", ""))
        var path := str(entry.get("path", "")).strip_edges()
        var label := row_control as Label
        label.set_meta("row_name", file_name)
        label.text = _format_slot_text(file_name, path)
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


func _format_slot_text(file_name: String, path: String) -> String:
    var size := _get_file_size(path)
    if size < 0:
        return file_name
    return "%s(%s)" % [file_name, _format_bytes(size)]


func _get_file_size(path: String) -> int:
    if path.is_empty() or not FileAccess.file_exists(path):
        return -1
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return -1
    return int(file.get_length())


func _format_bytes(byte_count: int) -> String:
    byte_count = maxi(byte_count, 0)
    const UNITS := ["B", "KB", "MB", "GB"]
    var value := float(byte_count)
    var unit_index := 0

    while value >= 1024.0 and unit_index < UNITS.size() - 1:
        value /= 1024.0
        unit_index += 1

    if unit_index == 0:
        return "%d B" % byte_count
    if is_equal_approx(value, round(value)):
        return "%d %s" % [int(round(value)), UNITS[unit_index]]
    return "%.1f %s" % [value, UNITS[unit_index]]


func _on_display_clicked() -> void:
    var contents: Variant = data.get("contents", {})
    if contents is Dictionary and not (contents as Dictionary).is_empty():
        action.display_data(contents)
        return

    var outputs := _load_all_files()
    if outputs.size() == 1:
        action.display_data(outputs.get("0", PackedByteArray()), DisplayDialog.DataType.BINARY)
        return
    action.display_data(outputs)
