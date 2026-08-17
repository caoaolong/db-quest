class_name BaseNode
extends PanelContainer

@export var subtitle: String = ""

@onready var action: NodeActionBar = $VBoxContainer/NodeActionBar


func set_subtitle(value: String) -> void:
    subtitle = value
    _sync_subtitle_label()


func _sync_subtitle_label() -> void:
    var label := get_node_or_null("VBoxContainer/Label") as Label
    if label:
        label.text = subtitle


func _ready() -> void:
    _sync_subtitle_label()
    _bind_action_bar()


func _bind_action_bar() -> void:
    if action == null:
        return

    action.delete_clicked.connect(_on_delete_clicked)
    action.display_clicked.connect(_on_display_clicked)


func _on_display_clicked() -> void:
    pass


func _on_delete_clicked() -> void:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return

    var graph_edit := graph_node.get_parent() as GraphEdit
    if graph_edit == null:
        return

    graph_edit.remove_child(graph_node)
    graph_node.queue_free()
