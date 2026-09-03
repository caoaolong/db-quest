extends PopupPanel

const NODE_LIST_PATH := "res://resources/node_list.json"
const BACKPACK_ITEM_SCENE := preload("res://dialog/backpack/backpack_item.tscn")

signal item_selected(entry: Dictionary)

var _grid: GridContainer


func _ready() -> void:
    _grid = $MarginContainer/GridContainer
    _populate()
    hide()


func _populate() -> void:
    if _grid == null:
        return

    for child in _grid.get_children():
        child.queue_free()

    var entries := _load_node_list()
    for entry in entries:
        if not entry is Dictionary:
            continue
        var item := BACKPACK_ITEM_SCENE.instantiate()
        _grid.add_child(item)
        var _title := item.get_node_or_null("Title") as Label
        if _title:
            _title.text = str(entry.get("name", ""))
        item.pressed.connect(_on_item_pressed.bind(entry))


func _on_item_pressed(entry: Dictionary) -> void:
    item_selected.emit(entry)
    hide()


func _load_node_list() -> Array:
    if not FileAccess.file_exists(NODE_LIST_PATH):
        push_error("Node list file not found: %s" % NODE_LIST_PATH)
        return []

    var file := FileAccess.open(NODE_LIST_PATH, FileAccess.READ)
    if file == null:
        push_error("Failed to open node list: %s" % NODE_LIST_PATH)
        return []

    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if parsed is Array:
        return parsed

    push_error("Unexpected node list JSON format: %s" % NODE_LIST_PATH)
    return []


func _input(event: InputEvent) -> void:
    if event.is_action_released("Backpack"):
        hide()
