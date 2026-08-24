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


func _draw_port(_slot_index: int, port_position: Vector2i, left: bool, color: Color) -> void:
    var center := Vector2(port_position)
    var half_width := PORT_SIZE.x * 0.5
    var half_height := PORT_SIZE.y * 0.5

    var points := PackedVector2Array()
    if left:
        # 输入端口：三角形角朝内（指向节点内部）
        points = PackedVector2Array([
            center + Vector2(half_width, 0.0),
            center + Vector2(-half_width, half_height),
            center + Vector2(-half_width, -half_height),
        ])
    else:
        # 输出端口：三角形角朝外（指向节点外部）
        points = PackedVector2Array([
            center + Vector2(half_width, 0.0),
            center + Vector2(-half_width, half_height),
            center + Vector2(-half_width, -half_height),
        ])

    draw_colored_polygon(points, color)
