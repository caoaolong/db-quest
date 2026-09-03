extends Control

const BACKPACK_SCENE := preload("res://dialog/backpack.tscn")
const OBJECT_NODE_SCENE := preload("res://components/object_node.tscn")

const NODE_COLORS := {
    "CSDB": Color(0.9, 0.3, 0.4),
    "File": Color(0.3, 0.8, 0.9),
    "Pager": Color(0.3, 0.8, 0.5),
}

var _backpack: PopupPanel = null
var _graph_edit: GraphEdit

func _ready() -> void:
    _graph_edit = $GraphEdit
    set_process_input(true)

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("Backpack"):
        _get_backpack().popup()

func _create_backpack() -> PopupPanel:
    var instance := BACKPACK_SCENE.instantiate()
    add_child(instance)
    instance.item_selected.connect(_on_backpack_item_selected)
    return instance as PopupPanel


func _get_backpack() -> PopupPanel:
    if _backpack == null or not is_instance_valid(_backpack):
        _backpack = _create_backpack()
    return _backpack


func _on_backpack_item_selected(entry: Dictionary) -> void:
    var entry_name: String = str(entry.get("name", ""))
    var graph_node := GraphNode.new()
    graph_node.title = entry_name
    if NODE_COLORS.has(entry_name):
        graph_node.self_modulate = NODE_COLORS[entry_name]
    var default_slot := Label.new()
    default_slot.text = "Pointer(%s)" % entry_name
    graph_node.add_child(default_slot)
    graph_node.set_slot(0, true, 0, Color.WHITE, true, 0, Color.WHITE)
    var ui := OBJECT_NODE_SCENE.instantiate()
    graph_node.add_child(ui)
    var slots: Array = entry.get("slots", [])
    for slot in slots:
        var label := Label.new()
        label.text = str(slot.get("name", ""))
        graph_node.add_child(label)
        var slot_type: String = slot.get("type", "")
        var slot_color: Color = NODE_COLORS.get(slot_type, Color.WHITE)
        var slot_dir: String = slot.get("slot_type", "")
        var left := slot_dir == "input"
        var right := slot_dir == "output"
        var slot_index := graph_node.get_child_count() - 1
        graph_node.set_slot(slot_index, left, 0, slot_color, right, 0, slot_color)
    _graph_edit.add_child(graph_node)


func _process(_delta: float) -> void:
    pass
