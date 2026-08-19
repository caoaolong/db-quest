class_name CheckNode
extends BaseNode

"""
{
    "values": {
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

    var progress_bar := action.get_node_or_null("ProgressBar") as ProgressBar
    if progress_bar:
        progress_bar.visible = false


func set_subtitle(_value: String) -> void:
    pass


func refresh_display() -> void:
    _sync_controls_from_data()


func _sync_data_from_controls() -> void:
    pass


func _sync_controls_from_data() -> void:
    _update_value_display()


func run(inputs: Dictionary = {}) -> Variant:
    if not data.has("values"):
        data["values"] = {}

    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return data["values"].duplicate(true)

    for port_key in inputs.keys():
        var port_index := int(port_key)
        var slot_index := graph_node.get_input_port_slot(port_index)
        data["values"][str(slot_index)] = _normalize_check_value(inputs[port_key])

    _sync_controls_from_data()
    schedule_save()

    if not inputs.is_empty():
        var graph_edit := get_graph_edit()
        if graph_edit != null:
            TaskTrigger.handle(TaskTrigger.ON_CHECK_INPUT, graph_edit)

    return data["values"].duplicate(true)


func get_check_value(index: int) -> String:
    var values: Variant = data.get("values", {})
    if values is Dictionary:
        return str(values.get(str(index), ""))
    return ""


func _update_value_display() -> void:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return

    var values: Dictionary = data.get("values", {})
    var slot_count := _get_slot_count()
    for slot_index in range(1, slot_count + 1):
        var row_control := _get_row_control(graph_node, slot_index)
        if not row_control is Label:
            continue

        var label := row_control as Label
        if not label.has_meta("row_name"):
            label.set_meta("row_name", label.text)

        var row_name := str(label.get_meta("row_name", ""))
        var value_text := str(values.get(str(slot_index), ""))
        var display_value := value_text if not value_text.is_empty() else "-"
        if row_name.is_empty():
            label.text = display_value
        else:
            label.text = "%s  %s" % [row_name, display_value]
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


func _get_slot_count() -> int:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return 0
    return maxi(graph_node.get_child_count() - 1, 0)


func _normalize_check_value(value: Variant) -> String:
    if value == null:
        return ""

    if value is PackedByteArray:
        return (value as PackedByteArray).get_string_from_utf8()

    if value is Dictionary:
        var payload := value as Dictionary
        if payload.has("data") and payload["data"] is PackedByteArray:
            return (payload["data"] as PackedByteArray).get_string_from_utf8()
        if payload.has("data"):
            return str(payload["data"])
        return str(value)

    return str(value)


func _on_display_clicked() -> void:
    action.display_data(data.get("values", {}))
