class_name DataNode
extends PanelContainer

@export var subtitle: String = ""

@onready var label: Label = $VBoxContainer/Label
@onready var action: NodeActionBar = $VBoxContainer/NodeActionBar

var data: String

func _ready() -> void:
    label.text = subtitle
    action.display_clicked.connect(_on_display_clicked)
    action.delete_clicked.connect(_on_delete_clicked)

func _on_delete_clicked() -> void:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return

    var graph_edit := graph_node.get_parent() as GraphEdit
    if graph_edit == null:
        return

    graph_edit.remove_child(graph_node)
    graph_node.queue_free()

func _on_display_clicked() -> void:
    action.display_data(data)
