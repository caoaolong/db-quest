class_name BaseNode
extends PanelContainer

"""
{
    "rows": {
        "1": 0
    }
}
"""

@export var subtitle: String = ""
var category: String = ""
var data: Dictionary = {}
var spend: int = 0
var queue_index: int = 0
var queue_total: int = 1
var queue_length: int = 0

@onready var action: NodeActionBar = $VBoxContainer/NodeActionBar


func set_subtitle(value: String) -> void:
    subtitle = value
    _sync_subtitle_label()


func collect_data() -> Dictionary:
    _sync_data_from_controls()
    return data.duplicate(true)


func apply_data(saved: Dictionary) -> void:
    data = saved.duplicate(true)
    _sync_controls_from_data()
    _sync_queue_progress_label()


func collect_persisted_data() -> Dictionary:
    var result := collect_data()
    var graph_node := get_parent() as GraphNode
    if graph_node:
        var rows := _collect_row_data(graph_node)
        if not rows.is_empty():
            result["rows"] = rows
    return result


func clear_run_data() -> void:
    pass


func apply_persisted_data(saved: Dictionary) -> void:
    if saved.is_empty():
        return

    var payload := saved.duplicate(true)
    var rows: Variant = payload.get("rows", {})
    payload.erase("rows")
    apply_data(payload)

    var graph_node := get_parent() as GraphNode
    if graph_node and rows is Dictionary:
        _apply_row_data(graph_node, rows)


func schedule_save() -> void:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return

    var graph_edit := graph_node.get_parent()
    if graph_edit == null:
        return
    if graph_edit.has_method("is_restoring") and graph_edit.is_restoring():
        return
    if graph_edit.has_method("schedule_save"):
        graph_edit.schedule_save()


func get_graph_edit() -> GraphEdit:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return null
    return graph_node.get_parent() as GraphEdit


func run(_inputs: Dictionary = {}) -> Variant:
    return null


func get_spend() -> int:
    return maxi(0, spend)


func play_spend() -> void:
    if action == null:
        return
    await action.play_spend(get_spend())


func get_user_input() -> Variant:
    _sync_data_from_controls()
    return data.get("value")


func _sync_data_from_controls() -> void:
    pass


func _sync_controls_from_data() -> void:
    pass


func _collect_row_data(graph_node: GraphNode) -> Dictionary:
    var rows := {}
    for slot_index in range(1, graph_node.get_child_count()):
        var row_control := _get_row_control(graph_node, slot_index)
        if row_control is SpinBox:
            rows[str(slot_index)] = int((row_control as SpinBox).value)
        elif row_control is OptionButton:
            rows[str(slot_index)] = int((row_control as OptionButton).selected)
        elif row_control is LineEdit:
            rows[str(slot_index)] = (row_control as LineEdit).text
    return rows


func _apply_row_data(graph_node: GraphNode, rows: Dictionary) -> void:
    for key in rows.keys():
        var slot_index := int(key)
        var row_control := _get_row_control(graph_node, slot_index)
        if row_control is SpinBox:
            (row_control as SpinBox).value = int(rows[key])
        elif row_control is OptionButton:
            (row_control as OptionButton).selected = int(rows[key])
        elif row_control is LineEdit:
            (row_control as LineEdit).text = str(rows[key])


func _get_row_hbox(graph_node: GraphNode, slot_index: int) -> HBoxContainer:
    if slot_index < 1 or slot_index >= graph_node.get_child_count():
        return null

    var wrapper := graph_node.get_child(slot_index) as Control
    if wrapper == null or wrapper.get_child_count() == 0:
        return null
    return wrapper.get_child(0) as HBoxContainer


func _get_row_control(graph_node: GraphNode, slot_index: int) -> Control:
    var row := _get_row_hbox(graph_node, slot_index)
    if row == null:
        return null
    for child in row.get_children():
        if child is Control and (child as Control).has_meta("row_field"):
            return child as Control
        if child is SpinBox or child is LineEdit or child is OptionButton:
            return child as Control
    return null


func _get_row_label(graph_node: GraphNode, slot_index: int) -> Label:
    var row := _get_row_hbox(graph_node, slot_index)
    if row == null:
        return null
    for child in row.get_children():
        if child is Label and (child as Label).has_meta("row_name_label"):
            return child as Label
        if child is Label:
            return child as Label
    return null


func _sync_subtitle_label() -> void:
    var label := get_node_or_null("VBoxContainer/Label") as Label
    if label:
        label.text = subtitle


func set_queue_progress(current: int, total: int) -> void:
    data["queue_current"] = current
    data["queue_total"] = total
    _sync_queue_progress_label()


func reset_queue_progress() -> void:
    data.erase("queue_current")
    data.erase("queue_total")
    _sync_queue_progress_label()


func _sync_queue_progress_label() -> void:
    var label := get_node_or_null("VBoxContainer/Queue") as Label
    if label == null:
        return
    label.text = "%d / %d" % [int(data.get("queue_current", 0)), int(data.get("queue_total", 0))]


func _ready() -> void:
    _sync_subtitle_label()
    _sync_queue_progress_label()
    _bind_action_bar()
    _configure_action_bar()
    _apply_body_layout()


## 与 GraphEdit.ROW_PORT_SIDE_MARGIN 保持一致，使内容区与 slot 行左右对齐。
const BODY_SIDE_MARGIN := 28


func _apply_body_layout() -> void:
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var vbox := get_node_or_null("VBoxContainer") as VBoxContainer
    if vbox:
        vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    var box := StyleBoxEmpty.new()
    box.content_margin_left = BODY_SIDE_MARGIN
    box.content_margin_right = BODY_SIDE_MARGIN
    box.content_margin_top = 0
    box.content_margin_bottom = 0
    add_theme_stylebox_override("panel", box)
    _bleed_action_bar_full_width()


## NodeActionBar 左右突破内容边距，占满节点宽度。
func _bleed_action_bar_full_width() -> void:
    if action == null:
        return
    action.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    var parent := action.get_parent() as Control
    if parent == null:
        return
    if parent.has_meta("action_bar_bleed"):
        return

    var index := action.get_index()
    var bleed := MarginContainer.new()
    bleed.set_meta("action_bar_bleed", true)
    bleed.mouse_filter = Control.MOUSE_FILTER_IGNORE
    bleed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bleed.add_theme_constant_override("margin_left", -BODY_SIDE_MARGIN)
    bleed.add_theme_constant_override("margin_right", -BODY_SIDE_MARGIN)

    parent.remove_child(action)
    bleed.add_child(action)
    parent.add_child(bleed)
    parent.move_child(bleed, index)


func _configure_action_bar() -> void:
    pass


func _bind_action_bar() -> void:
    if action == null:
        return

    action.display_clicked.connect(_on_display_clicked)


func _on_display_clicked() -> void:
    pass
