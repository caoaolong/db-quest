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

    var file_vars := GameState.get_file_variables()
    var output_port := 0
    for slot_index in range(1, graph_node.get_child_count()):
        var file_index := slot_index - 1
        if file_index >= file_vars.size():
            break

        var file_var: Dictionary = file_vars[file_index]
        var path := str(file_var.get("path", ""))
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

    var file_vars := GameState.get_file_variables()
    for slot_index in range(1, graph_node.get_child_count()):
        var row_control := _get_row_control(graph_node, slot_index)
        if not row_control is Label:
            continue

        var label := row_control as Label
        if not label.has_meta("row_name"):
            label.set_meta("row_name", label.text)

        var row_name := str(label.get_meta("row_name", ""))
        var file_index := slot_index - 1
        var suffix := ""
        if file_index < file_vars.size():
            var path := str(file_vars[file_index].get("path", ""))
            var file_name := path.get_file()
            if not file_name.is_empty():
                suffix = file_name

        if suffix.is_empty():
            label.text = row_name
        elif row_name.is_empty() or row_name == suffix:
            label.text = suffix
        else:
            label.text = "%s  %s" % [row_name, suffix]
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


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
