class_name BaseNode
extends PanelContainer

@export var subtitle: String = ""
var category: String = ""
var data: Dictionary = {}

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


func collect_persisted_data() -> Dictionary:
    var result := collect_data()
    var graph_node := get_parent() as GraphNode
    if graph_node:
        var rows := _collect_row_data(graph_node)
        if not rows.is_empty():
            result["rows"] = rows
    return result


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


func run(_inputs: Dictionary = {}) -> Variant:
    return null


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
    return rows


func _apply_row_data(graph_node: GraphNode, rows: Dictionary) -> void:
    for key in rows.keys():
        var slot_index := int(key)
        var row_control := _get_row_control(graph_node, slot_index)
        if row_control is SpinBox:
            (row_control as SpinBox).value = int(rows[key])
        elif row_control is OptionButton:
            (row_control as OptionButton).selected = int(rows[key])


func _get_row_control(graph_node: GraphNode, slot_index: int) -> Control:
    if slot_index < 1 or slot_index >= graph_node.get_child_count():
        return null

    var wrapper := graph_node.get_child(slot_index) as Control
    if wrapper == null or wrapper.get_child_count() == 0:
        return null
    return wrapper.get_child(0) as Control


func _sync_subtitle_label() -> void:
    var label := get_node_or_null("VBoxContainer/Label") as Label
    if label:
        label.text = subtitle


func _ready() -> void:
    _sync_subtitle_label()
    _bind_action_bar()
    _configure_action_bar()


func _configure_action_bar() -> void:
    if action == null:
        return
    action.set_run_visible(category != "Tools")


func _bind_action_bar() -> void:
    if action == null:
        return

    action.delete_clicked.connect(_on_delete_clicked)
    action.display_clicked.connect(_on_display_clicked)
    action.run_clicked.connect(_on_run_clicked)


func _on_run_clicked() -> void:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return

    var graph_edit := graph_node.get_parent()
    if graph_edit != null and graph_edit.has_method("run_node"):
        graph_edit.run_node(graph_node)


func _on_display_clicked() -> void:
    pass


func _on_delete_clicked() -> void:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return

    var graph_edit := graph_node.get_parent()
    if graph_edit == null:
        return
    if graph_edit.has_method("is_restoring") and graph_edit.is_restoring():
        return

    schedule_save()
    graph_edit.remove_child(graph_node)
    graph_node.queue_free()
