extends Control

const BACKPACK_SCENE := preload("res://dialog/backpack.tscn")

var _backpack: PopupPanel = null

func _ready() -> void:
    set_process_input(true)

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("Backpack"):
        _get_backpack().popup()

func _create_backpack() -> PopupPanel:
    var instance := BACKPACK_SCENE.instantiate()
    add_child(instance)
    return instance as PopupPanel


func _get_backpack() -> PopupPanel:
    if _backpack == null or not is_instance_valid(_backpack):
        _backpack = _create_backpack()
    return _backpack


func _process(_delta: float) -> void:
    pass
