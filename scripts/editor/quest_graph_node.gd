class_name QuestGraphNode
extends GraphNode

signal run_enable_state_changed(is_enabled: bool)

enum RunStatus {
    IDLE,
    PENDING,
    RUNNING,
    DONE,
}

const PORT_SIZE := Vector2(14.0, 14.0)

const STATUS_COLORS := {
    RunStatus.IDLE: Color(0.22, 0.22, 0.24, 1),
    RunStatus.PENDING: Color(0.32, 0.38, 0.52, 1),
    RunStatus.RUNNING: Color(0.86, 0.60, 0.14, 1),
    RunStatus.DONE: Color(0.22, 0.56, 0.34, 1),
}

const STATUS_LABELS := {
    RunStatus.IDLE: "",
    RunStatus.PENDING: "等待",
    RunStatus.RUNNING: "运行中",
    RunStatus.DONE: "完成",
}

const DISABLED_TITLEBAR_COLOR := Color(0.16, 0.16, 0.17, 1)

var run_enabled: bool = true
var run_status: RunStatus = RunStatus.IDLE
var _status_label: Label
var _enabled_check: CheckBox
var _delete_button: Button
var _title_editor: LineEdit
var _title_editing: bool = false
var _titlebar_style: StyleBoxFlat
var _titlebar_selected_style: StyleBoxFlat


func _ready() -> void:
    _ensure_titlebar_controls()
    _apply_run_status()
    _apply_run_enabled()


func is_run_enabled() -> bool:
    return run_enabled


func set_run_enabled(enabled: bool) -> void:
    if run_enabled == enabled:
        _sync_enabled_check()
        _apply_run_enabled()
        return
    run_enabled = enabled
    _sync_enabled_check()
    _apply_run_enabled()
    run_enable_state_changed.emit(run_enabled)


func set_run_status(status: RunStatus) -> void:
    run_status = status
    _apply_run_status()


func _ensure_titlebar_controls() -> void:
    var titlebar := get_titlebar_hbox()
    if titlebar == null:
        return

    if _status_label == null:
        _status_label = Label.new()
        _status_label.name = "RunStatus"
        _status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        _status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _status_label.add_theme_font_size_override("font_size", 12)
        _status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        titlebar.add_child(_status_label)

    if _enabled_check == null:
        _enabled_check = CheckBox.new()
        _enabled_check.name = "RunEnabled"
        _enabled_check.text = ""
        _enabled_check.tooltip_text = "启用后参与运行"
        _enabled_check.toggled.connect(_on_enabled_toggled)
        titlebar.add_child(_enabled_check)
        _sync_enabled_check()

    if _delete_button == null:
        _delete_button = Button.new()
        _delete_button.name = "DeleteNode"
        _delete_button.text = "×"
        _delete_button.tooltip_text = "删除节点"
        _delete_button.focus_mode = Control.FOCUS_NONE
        _delete_button.flat = true
        _delete_button.custom_minimum_size = Vector2(22, 0)
        _delete_button.pressed.connect(_on_delete_pressed)
        titlebar.add_child(_delete_button)

    _bind_title_label()
    _sync_delete_button()


func _bind_title_label() -> void:
    var title_label := _builtin_title_label()
    if title_label == null:
        return
    if title_label.has_meta("title_edit_bound"):
        return
    title_label.set_meta("title_edit_bound", true)
    title_label.mouse_filter = Control.MOUSE_FILTER_STOP
    title_label.gui_input.connect(_on_title_label_gui_input)


func _builtin_title_label() -> Label:
    var titlebar := get_titlebar_hbox()
    if titlebar == null:
        return null
    for child in titlebar.get_children():
        if child is Label and child != _status_label:
            return child as Label
    return null


func _on_title_label_gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var mouse := event as InputEventMouseButton
        if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.double_click and mouse.pressed:
            _begin_title_edit()


func _begin_title_edit() -> void:
    if _title_editing:
        return
    var titlebar := get_titlebar_hbox()
    var title_label := _builtin_title_label()
    if titlebar == null or title_label == null:
        return

    if _title_editor == null:
        _title_editor = LineEdit.new()
        _title_editor.name = "TitleEditor"
        _title_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _title_editor.text_submitted.connect(_commit_title_edit)
        _title_editor.focus_exited.connect(_commit_title_edit)

    _title_editing = true
    _title_editor.text = title
    title_label.visible = false
    if _title_editor.get_parent() != titlebar:
        titlebar.add_child(_title_editor)
        titlebar.move_child(_title_editor, title_label.get_index())
    _title_editor.visible = true
    _title_editor.grab_focus()
    _title_editor.select_all()


func _commit_title_edit(_new_text: Variant = null) -> void:
    if not _title_editing or _title_editor == null:
        return

    _title_editing = false
    var title_label := _builtin_title_label()
    var new_title := _title_editor.text.strip_edges()
    if new_title.is_empty():
        new_title = _fallback_title()
    title = new_title
    _title_editor.visible = false
    if title_label:
        title_label.visible = true

    var graph_edit := get_parent()
    if graph_edit != null and graph_edit.has_method("schedule_save"):
        graph_edit.schedule_save()


func _fallback_title() -> String:
    var template_name := str(get_meta("template_name", ""))
    if not template_name.is_empty():
        var entry := GameState.get_node_entry(template_name)
        if not entry.is_empty():
            return str(entry.get("label", template_name))
    return name


func _can_delete() -> bool:
    var template_name := str(get_meta("template_name", ""))
    if GameState.is_system_node_name(template_name):
        return false
    return true


func _sync_delete_button() -> void:
    if _delete_button:
        _delete_button.visible = _can_delete()


func _on_delete_pressed() -> void:
    if not _can_delete():
        return

    var graph_edit := get_parent()
    if graph_edit == null:
        return
    if graph_edit.has_method("is_restoring") and graph_edit.is_restoring():
        return

    graph_edit.remove_child(self)
    queue_free()
    if graph_edit.has_method("schedule_save"):
        graph_edit.schedule_save()


func _sync_enabled_check() -> void:
    if _enabled_check:
        _enabled_check.set_pressed_no_signal(run_enabled)


func _on_enabled_toggled(toggled_on: bool) -> void:
    set_run_enabled(toggled_on)


func _apply_run_enabled() -> void:
    modulate = Color.WHITE if run_enabled else Color(0.72, 0.72, 0.72, 1)
    _apply_run_status()


func _apply_run_status() -> void:
    _ensure_titlebar_controls()
    var color: Color
    if not run_enabled:
        color = DISABLED_TITLEBAR_COLOR
    else:
        color = STATUS_COLORS.get(run_status, STATUS_COLORS[RunStatus.IDLE])
    var text := "" if not run_enabled else str(STATUS_LABELS.get(run_status, ""))

    if _status_label:
        _status_label.text = text
        _status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))

    if _titlebar_style == null:
        _titlebar_style = StyleBoxFlat.new()
        _titlebar_style.corner_radius_top_left = 4
        _titlebar_style.corner_radius_top_right = 4
        _titlebar_style.content_margin_left = 8
        _titlebar_style.content_margin_right = 8
        _titlebar_style.content_margin_top = 4
        _titlebar_style.content_margin_bottom = 4
        _titlebar_selected_style = _titlebar_style.duplicate() as StyleBoxFlat

    _titlebar_style.bg_color = color
    _titlebar_selected_style.bg_color = color.lightened(0.12)
    add_theme_stylebox_override("titlebar", _titlebar_style)
    add_theme_stylebox_override("titlebar_selected", _titlebar_selected_style)


func _draw_port(slot_index: int, port_position: Vector2i, left: bool, color: Color) -> void:
    var center := Vector2(port_position)
    var half_width := PORT_SIZE.x * 0.5
    var half_height := PORT_SIZE.y * 0.5

    if _is_function_port(slot_index, left):
        var diamond := PackedVector2Array([
            center + Vector2(0.0, -half_height),
            center + Vector2(half_width, 0.0),
            center + Vector2(0.0, half_height),
            center + Vector2(-half_width, 0.0),
        ])
        draw_colored_polygon(diamond, color)
        return

    if _is_self_refer_port(slot_index, left):
        draw_circle(center, mini(half_width, half_height), color)
        return

    if _is_refer_port(slot_index, left):
        var square := Rect2(center - Vector2(half_width, half_height), PORT_SIZE)
        draw_rect(square, color, true)
        return

    var points := PackedVector2Array()
    if left:
        points = PackedVector2Array([
            center + Vector2(half_width, 0.0),
            center + Vector2(-half_width, half_height),
            center + Vector2(-half_width, -half_height),
        ])
    else:
        points = PackedVector2Array([
            center + Vector2(half_width, 0.0),
            center + Vector2(-half_width, half_height),
            center + Vector2(-half_width, -half_height),
        ])

    draw_colored_polygon(points, color)


func _is_function_port(slot_index: int, left: bool) -> bool:
    var slot_type := get_slot_type_left(slot_index) if left else get_slot_type_right(slot_index)
    var graph_edit := get_parent()
    if graph_edit != null and graph_edit.has_method("is_function_slot_type"):
        return bool(graph_edit.call("is_function_slot_type", slot_type))
    return false


func _is_refer_port(slot_index: int, left: bool) -> bool:
    var slot_type := get_slot_type_left(slot_index) if left else get_slot_type_right(slot_index)
    var graph_edit := get_parent()
    if graph_edit != null and graph_edit.has_method("is_refer_slot_type"):
        return bool(graph_edit.call("is_refer_slot_type", slot_type))
    return false


func _is_self_refer_port(slot_index: int, left: bool) -> bool:
    if not _is_refer_port(slot_index, left):
        return false
    var graph_edit := get_parent()
    if graph_edit != null and graph_edit.has_method("is_self_refer_slot"):
        return bool(graph_edit.call("is_self_refer_slot", self, slot_index))
    return slot_index == 0
