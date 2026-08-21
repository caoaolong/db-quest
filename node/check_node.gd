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


func clear_run_data() -> void:
    data["values"] = {}
    _sync_controls_from_data()


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
        var display_value := _status_text(slot_index, value_text)
        var status_color := _status_color(display_value)
        if row_name.is_empty():
            label.text = display_value
        else:
            label.text = "%s  %s" % [row_name, display_value]
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        label.add_theme_color_override("font_color", status_color)


func _status_text(slot_index: int, value_text: String) -> String:
    if value_text.is_empty():
        return "-"
    var graph_edit := get_graph_edit()
    if graph_edit != null and GoalValidator.evaluate_check_row(graph_edit, slot_index):
        return "通过"
    return "未通过"


func _status_color(display_value: String) -> Color:
    match display_value:
        "通过":
            return Color(0.45, 0.85, 0.5)
        "未通过":
            return Color(0.95, 0.45, 0.45)
        _:
            return Color(0.75, 0.75, 0.75)


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
    var values: Dictionary = data.get("values", {})
    var status := {}
    for key in values.keys():
        status[str(key)] = _status_text(int(key), str(values[key]))
    action.display_data(status)
