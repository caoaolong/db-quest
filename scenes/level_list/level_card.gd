extends Button
class_name LevelCard

signal selected(level: int)

const BASE_STYLE := preload("res://scenes/scene_style.tres")

const HOVER_BG_COLOR := Color(0.28, 0.28, 0.28, 1)
const PRESSED_BG_COLOR := Color(0.16, 0.16, 0.16, 1)

@onready var _order: Label = $CenterContainer/VBoxContainer/Order
@onready var _name: Label = $CenterContainer/VBoxContainer/Name
@onready var _stars: HBoxContainer = $DifficultyStars

var _level_data: Dictionary = {}


func setup(level_data: Dictionary) -> LevelCard:
    _level_data = level_data.duplicate(true)
    if is_node_ready():
        _apply_level_data()
    return self


func get_level() -> int:
    return int(_level_data.get("level", 0))


func _ready() -> void:
    text = ""
    focus_mode = Control.FOCUS_NONE
    pivot_offset = custom_minimum_size * 0.5
    _apply_button_styles()

    pressed.connect(_on_pressed)
    mouse_entered.connect(_on_mouse_entered)
    mouse_exited.connect(_on_mouse_exited)
    _set_mouse_filter_ignore($CenterContainer)
    _set_mouse_filter_ignore($DifficultyStars)

    if _level_data.is_empty():
        return
    _apply_level_data()


func _apply_button_styles() -> void:
    var normal_style := BASE_STYLE.duplicate() as StyleBoxFlat
    var hover_style := BASE_STYLE.duplicate() as StyleBoxFlat
    hover_style.bg_color = HOVER_BG_COLOR
    var pressed_style := BASE_STYLE.duplicate() as StyleBoxFlat
    pressed_style.bg_color = PRESSED_BG_COLOR

    add_theme_stylebox_override("normal", normal_style)
    add_theme_stylebox_override("hover", hover_style)
    add_theme_stylebox_override("pressed", pressed_style)
    add_theme_stylebox_override("focus", normal_style.duplicate())
    add_theme_stylebox_override("disabled", normal_style.duplicate())


func _set_mouse_filter_ignore(node: Node) -> void:
    if node is Control:
        (node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

    for child in node.get_children():
        _set_mouse_filter_ignore(child)


func _apply_level_data() -> void:
    var level := int(_level_data.get("level", 0))
    _order.text = _format_level_order(level)
    _name.text = str(_level_data.get("name", ""))
    _apply_difficulty_stars(int(_level_data.get("difficulty", 1)))


func _apply_difficulty_stars(difficulty: int) -> void:
    if _stars == null:
        return

    difficulty = clampi(difficulty, 1, 5)
    var template := _stars.get_node_or_null("Star") as TextureRect
    if template == null:
        return

    var extras: Array[Node] = []
    for child in _stars.get_children():
        if child != template:
            extras.append(child)
    for extra in extras:
        _stars.remove_child(extra)
        extra.free()

    template.visible = true
    for index in range(1, difficulty):
        var star := template.duplicate() as TextureRect
        star.name = "Star%d" % (index + 1)
        star.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _stars.add_child(star)


func _on_mouse_entered() -> void:
    scale = Vector2(1.03, 1.03)


func _on_mouse_exited() -> void:
    scale = Vector2.ONE


func _on_pressed() -> void:
    _enter_level()


func _enter_level() -> void:
    var level := get_level()
    if level <= 0:
        return

    selected.emit(level)
    GameState.set_current_level(level)
    get_tree().change_scene_to_file("res://scenes/editor.tscn")


func _format_level_order(level: int) -> String:
    const ORDINALS := ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
    if level >= 1 and level <= 10:
        return "第%s关" % ORDINALS[level]
    return "第%d关" % level
