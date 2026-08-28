class_name FormDialog
extends PopupDialog

signal submitted(values: Dictionary)
signal cancelled
signal closed(accepted: bool)

enum FieldType {
    TEXT,
    CHECKBOX,
    NUMBER,
    OPTION,
    MESSAGE,
}

const LABEL_MIN_WIDTH := 88
const FIELD_SEPARATION := 12
const DEFAULT_FORM_SIZE := Vector2(400, 120)
const EDITOR_MIN_HEIGHT := 28

@onready var _title: Label = $MarginContainer/VBoxContainer/Title
@onready var _fields: VBoxContainer = $MarginContainer/VBoxContainer/Fields
@onready var _confirm_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/Confirm
@onready var _cancel_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/Cancel

var _field_controls: Dictionary = {}
var _field_configs: Array = []
var _accepted := false
var _awaiting_close := false


func _ready() -> void:
    super._ready()
    exclusive = true
    _apply_form_panel_style()
    if _fields:
        _fields.add_theme_constant_override("separation", FIELD_SEPARATION)


func _apply_form_panel_style() -> void:
    var style := PANEL_STYLE.duplicate() as StyleBoxFlat
    if style == null:
        return
    style.content_margin_left = 0
    style.content_margin_right = 0
    style.content_margin_top = 0
    style.content_margin_bottom = 0
    style.set_border_width_all(1)
    style.border_color = Color(0.28, 0.28, 0.28, 1)
    add_theme_stylebox_override("panel", style)


func show_dialog() -> void:
    _fit_form_size()
    await refresh_popup_size()
    _fit_form_size()
    popup_centered()


func _fit_form_size() -> void:
    var margin := get_node_or_null("MarginContainer") as MarginContainer
    if margin == null:
        return
    var content_size := margin.get_combined_minimum_size()
    var width := maxf(DEFAULT_FORM_SIZE.x, content_size.x + 8.0)
    var height := maxf(DEFAULT_FORM_SIZE.y, content_size.y + 8.0)
    set_clamped_content_size(margin, Vector2(width, height))
    size = Vector2i(ceili(width), ceili(height))


func configure(config: Dictionary) -> FormDialog:
    if _title:
        _title.text = str(config.get("title", "表单"))
    if _confirm_button:
        _confirm_button.text = str(config.get("confirm_text", "确定"))
    if _cancel_button:
        _cancel_button.text = str(config.get("cancel_text", "取消"))
        _cancel_button.visible = bool(config.get("show_cancel", true))

    _rebuild_fields(config.get("fields", []))
    return self


## 确定返回字段字典（可能为空）；取消返回 null。
func prompt(config: Dictionary) -> Variant:
    configure(config)
    _accepted = false
    _awaiting_close = true
    await show_dialog()
    if _awaiting_close:
        await closed
    if not _accepted:
        return null
    return collect_values()


func collect_values() -> Dictionary:
    var values := {}
    for field in _field_configs:
        if not field is Dictionary:
            continue
        var field_id := str(field.get("id", "")).strip_edges()
        if field_id.is_empty() or str(field.get("type", "")) == "message":
            continue
        values[field_id] = _read_field_value(field_id, field)
    return values


func set_values(values: Dictionary) -> void:
    for field_id in values.keys():
        _write_field_value(str(field_id), values[field_id])


func _rebuild_fields(fields: Variant) -> void:
    _field_controls.clear()
    _field_configs.clear()
    if _fields == null:
        return

    for child in _fields.get_children():
        _fields.remove_child(child)
        child.free()

    if not fields is Array:
        return

    for field in fields:
        if not field is Dictionary:
            continue
        var control := _create_field_row(field as Dictionary)
        if control == null:
            continue
        _fields.add_child(control)
        _field_configs.append(field)


func _create_field_row(field: Dictionary) -> Control:
    var field_type := _parse_field_type(str(field.get("type", "text")))
    var field_id := str(field.get("id", "")).strip_edges()
    var label_text := str(field.get("label", ""))

    match field_type:
        FieldType.MESSAGE:
            var message := Label.new()
            message.text = label_text
            message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
            message.custom_minimum_size = Vector2(DEFAULT_FORM_SIZE.x, 0)
            return message
        FieldType.CHECKBOX:
            var checkbox_row := HBoxContainer.new()
            checkbox_row.add_theme_constant_override("separation", 12)
            var checkbox := CheckBox.new()
            checkbox.button_pressed = bool(field.get("value", false))
            var checkbox_label := Label.new()
            checkbox_label.text = label_text
            checkbox_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
            checkbox_row.add_child(checkbox)
            checkbox_row.add_child(checkbox_label)
            if not field_id.is_empty():
                _field_controls[field_id] = checkbox
            return checkbox_row
        _:
            var row := HBoxContainer.new()
            row.add_theme_constant_override("separation", 12)
            var label := Label.new()
            label.text = label_text
            label.custom_minimum_size = Vector2(LABEL_MIN_WIDTH, EDITOR_MIN_HEIGHT)
            label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
            row.add_child(label)

            var editor := _create_field_editor(field_type, field)
            if editor:
                editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                row.add_child(editor)
                if not field_id.is_empty():
                    _field_controls[field_id] = editor
            return row


func _create_field_editor(field_type: FieldType, field: Dictionary) -> Control:
    match field_type:
        FieldType.NUMBER:
            var spin := SpinBox.new()
            spin.min_value = float(field.get("min", 0))
            spin.max_value = float(field.get("max", 100))
            spin.step = float(field.get("step", 1))
            spin.value = float(field.get("value", spin.min_value))
            spin.alignment = HORIZONTAL_ALIGNMENT_CENTER
            spin.custom_minimum_size = Vector2(0, EDITOR_MIN_HEIGHT)
            return spin
        FieldType.OPTION:
            var option := OptionButton.new()
            option.custom_minimum_size = Vector2(0, EDITOR_MIN_HEIGHT)
            var options: Variant = field.get("options", [])
            if options is Array:
                for i in (options as Array).size():
                    option.add_item(str(options[i]), i)
            var selected := int(field.get("value", 0))
            if option.item_count > 0:
                option.selected = clampi(selected, 0, option.item_count - 1)
            return option
        _:
            var edit := LineEdit.new()
            edit.placeholder_text = str(field.get("placeholder", ""))
            edit.text = str(field.get("value", ""))
            edit.custom_minimum_size = Vector2(220, EDITOR_MIN_HEIGHT)
            edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            edit.text_submitted.connect(func(_text: String) -> void:
                _on_confirm_pressed()
            )
            return edit


func _parse_field_type(type_name: String) -> FieldType:
    match type_name.strip_edges().to_lower():
        "checkbox", "bool":
            return FieldType.CHECKBOX
        "number", "int", "float":
            return FieldType.NUMBER
        "option", "select":
            return FieldType.OPTION
        "message", "hint":
            return FieldType.MESSAGE
        _:
            return FieldType.TEXT


func _read_field_value(field_id: String, field: Dictionary) -> Variant:
    var control: Variant = _field_controls.get(field_id)
    if control is LineEdit:
        return (control as LineEdit).text.strip_edges()
    if control is CheckBox:
        return (control as CheckBox).button_pressed
    if control is SpinBox:
        return (control as SpinBox).value
    if control is OptionButton:
        return (control as OptionButton).selected
    return field.get("value")


func _write_field_value(field_id: String, value: Variant) -> void:
    var control: Variant = _field_controls.get(field_id)
    if control is LineEdit:
        (control as LineEdit).text = str(value)
    elif control is CheckBox:
        (control as CheckBox).button_pressed = bool(value)
    elif control is SpinBox:
        (control as SpinBox).value = float(value)
    elif control is OptionButton:
        var option := control as OptionButton
        if option.item_count > 0:
            option.selected = clampi(int(value), 0, option.item_count - 1)


func _validate() -> String:
    for field in _field_configs:
        if not field is Dictionary:
            continue
        if not bool(field.get("required", false)):
            continue
        var field_id := str(field.get("id", "")).strip_edges()
        if field_id.is_empty():
            continue
        var value: Variant = _read_field_value(field_id, field)
        if value is String and (value as String).is_empty():
            return "%s不能为空" % str(field.get("label", field_id))
    return ""


func _on_confirm_pressed() -> void:
    var error := _validate()
    if not error.is_empty():
        EditorLog.warn(error)
        return

    _accepted = true
    var values := collect_values()
    submitted.emit(values)
    _finish_prompt()
    close_dialog()


func _on_cancel_pressed() -> void:
    _accepted = false
    cancelled.emit()
    _finish_prompt()
    close_dialog()


func _on_close_pressed() -> void:
    _on_cancel_pressed()


func _finish_prompt() -> void:
    if not _awaiting_close:
        return
    _awaiting_close = false
    closed.emit(_accepted)


func _notification(what: int) -> void:
    if what == NOTIFICATION_VISIBILITY_CHANGED and not visible and _awaiting_close:
        _accepted = false
        cancelled.emit()
        _finish_prompt()
