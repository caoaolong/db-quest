extends PopupPanel
class_name PopupDialog

const PANEL_STYLE := preload("res://dialog/popup_dialog_panel.tres")
const EMPTY_STYLE := preload("res://dialog/popup_dialog_empty.tres")
const MIN_CONTENT_SIZE := Vector2(320, 80)
const MAX_CONTENT_SIZE := Vector2(1200, 900)
const DRAG_HANDLE_HEIGHT := 30

@export var drag_handle_path: NodePath = ^"VBoxContainer/DragHandle"

var _dragging := false


func _ready() -> void:
    visible = false
    _configure_popup()
    _bind_drag_handle()


func _configure_popup() -> void:
    popup_window = false
    exclusive = false
    unresizable = true
    transient = true
    wrap_controls = true
    transparent = false
    add_theme_stylebox_override("panel", PANEL_STYLE)
    add_theme_stylebox_override("embedded_border", EMPTY_STYLE)
    add_theme_stylebox_override("embedded_unfocused_border", EMPTY_STYLE)


func _bind_drag_handle() -> void:
    if drag_handle_path.is_empty():
        return

    var drag_handle := get_node_or_null(drag_handle_path) as Control
    if drag_handle == null:
        return

    drag_handle.custom_minimum_size = Vector2(0, DRAG_HANDLE_HEIGHT)
    if drag_handle.gui_input.is_connected(_on_drag_handle_gui_input):
        return

    drag_handle.gui_input.connect(_on_drag_handle_gui_input)


func show_dialog() -> void:
    await refresh_popup_size()
    popup_centered()


func refresh_popup_size() -> void:
    await get_tree().process_frame
    reset_size()


func close_dialog() -> void:
    hide()


func set_clamped_content_size(control: Control, desired_size: Vector2) -> void:
    control.custom_minimum_size = Vector2(
        clampf(desired_size.x, MIN_CONTENT_SIZE.x, MAX_CONTENT_SIZE.x),
        clampf(desired_size.y, MIN_CONTENT_SIZE.y, MAX_CONTENT_SIZE.y)
    )


func _on_drag_handle_gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var mouse_event := event as InputEventMouseButton
        if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
            _dragging = true


func _input(event: InputEvent) -> void:
    if not _dragging:
        return

    if event is InputEventMouseMotion:
        position += Vector2i((event as InputEventMouseMotion).relative)
    elif event is InputEventMouseButton:
        var mouse_event := event as InputEventMouseButton
        if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
            _dragging = false
