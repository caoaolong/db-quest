@tool
extends Node2D

@export_multiline var level_content: String = "关卡":
    set(value):
        level_content = value
        _refresh_label()

@export_range(1, 999) var level_index: int = 1:
    set(value):
        level_index = value
        _refresh_label()

@onready var _button: TextureButton = $TextureButton
@onready var _label: RichTextLabel = $TextureButton/Label


func _ready() -> void:
    if _button == null:
        return
    _button.pressed.connect(_on_pressed)
    _refresh_label()


func _refresh_label() -> void:
    if _label == null:
        return
    if level_content.is_empty():
        _label.text = "第%d关" % level_index
    else:
        _label.text = level_content


func _on_pressed() -> void:
    if Engine.is_editor_hint():
        return
    get_tree().change_scene_to_file("res://scenes/editor.tscn")


func _get_level_name() -> String:
    var first_line_end := level_content.find("\n")
    if first_line_end < 0:
        return level_content.strip_edges()
    return level_content.substr(first_line_end + 1).strip_edges()