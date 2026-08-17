extends PanelContainer

const NODE_LIST_PATH := "res://data/node_list.json"

@onready var _button_container: HBoxContainer = $MarginContainer/HBoxContainer
@onready var _tab_bar: TabBar = get_node("../TabBar")
@onready var _graph_edit: GraphEdit = get_node("../GraphEdit")


func _ready() -> void:
    _tab_bar.tab_changed.connect(_on_tab_changed)
    _build_buttons()


func _on_tab_changed(_tab: int) -> void:
    _build_buttons()


func _build_buttons() -> void:
    for child in _button_container.get_children():
        child.queue_free()

    var current_type := _get_current_type()
    for item in _load_node_list():
        if not item is Dictionary:
            continue

        if GameState.get_node_tab(str(item.get("type", ""))) != current_type:
            continue

        if not GameState.is_node_available(str(item.get("name", ""))):
            continue

        var button := Button.new()
        button.text = str(item.get("label", ""))
        button.custom_minimum_size = Vector2(30, 30)
        button.pressed.connect(_on_button_pressed.bind(item))
        _button_container.add_child(button)


func _get_current_type() -> String:
    if _tab_bar == null:
        return ""

    return _tab_bar.get_tab_title(_tab_bar.current_tab)


func _on_button_pressed(item: Dictionary) -> void:
    if _graph_edit == null:
        push_error("GraphEdit not found")
        return

    _graph_edit.create_node_from_config(item)


func _load_node_list() -> Array:
    if not FileAccess.file_exists(NODE_LIST_PATH):
        push_error("Node list file not found: %s" % NODE_LIST_PATH)
        return []

    var file := FileAccess.open(NODE_LIST_PATH, FileAccess.READ)
    if file == null:
        push_error("Failed to open node list: %s" % NODE_LIST_PATH)
        return []

    var parsed = JSON.parse_string(file.get_as_text())
    if parsed == null:
        push_error("Failed to parse node list JSON: %s" % NODE_LIST_PATH)
        return []

    if parsed is Array:
        return parsed

    if parsed is Dictionary and parsed.has("items") and parsed["items"] is Array:
        return parsed["items"]

    push_error("Unexpected node list JSON format: %s" % NODE_LIST_PATH)
    return []
