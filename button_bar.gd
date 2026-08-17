extends PanelContainer

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

    if _tab_bar.tab_count == 0:
        return

    var current_category := _get_current_category()
    for item in GameState.get_node_list():
        if not item is Dictionary:
            continue

        if str(item.get("category", "")) != current_category:
            continue

        if not GameState.is_node_available(str(item.get("name", ""))):
            continue

        var button := Button.new()
        button.text = str(item.get("label", ""))
        button.custom_minimum_size = Vector2(30, 30)
        button.pressed.connect(_on_button_pressed.bind(item))
        _button_container.add_child(button)


func _get_current_category() -> String:
    if _tab_bar == null or _tab_bar.tab_count == 0:
        return ""

    return _tab_bar.get_tab_title(_tab_bar.current_tab)


func _on_button_pressed(item: Dictionary) -> void:
    if _graph_edit == null:
        push_error("GraphEdit not found")
        return

    _graph_edit.create_node_from_config(item)
