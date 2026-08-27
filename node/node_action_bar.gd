extends VBoxContainer
class_name NodeActionBar

signal display_clicked
signal help_clicked

var display_dialog: DisplayDialog = null
var _spend_tween: Tween

@onready var progress_bar: ProgressBar = $ProgressBar


func _ready() -> void:
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _bind_display_dialog()
    if progress_bar:
        progress_bar.min_value = 0
        progress_bar.max_value = 100
        progress_bar.value = 0
        progress_bar.show_percentage = false
        progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var button_row := get_node_or_null("HBoxContainer") as HBoxContainer
    if button_row:
        button_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        for child in button_row.get_children():
            if child is Button:
                (child as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL


func set_button_visible(button_name: String, _is_visible: bool) -> void:
    var button := get_node_or_null("HBoxContainer/%s" % button_name) as Button
    if button:
        button.visible = _is_visible


func reset_progress() -> void:
    if _spend_tween:
        _spend_tween.kill()
        _spend_tween = null
    if progress_bar:
        progress_bar.value = 0


func play_spend(spend_ms: int) -> void:
    if progress_bar == null:
        return

    reset_progress()
    progress_bar.visible = true
    if spend_ms <= 0:
        progress_bar.value = 100
        return

    _spend_tween = create_tween()
    _spend_tween.tween_property(progress_bar, "value", 100.0, spend_ms / 1000.0).set_trans(Tween.TRANS_LINEAR)
    await _spend_tween.finished
    _spend_tween = null
    progress_bar.value = 100


func display_data(data: Variant, data_type: DisplayDialog.DataType = DisplayDialog.DataType.STRING) -> void:
    if display_dialog == null:
        _bind_display_dialog()
    if display_dialog == null:
        push_error("DisplayDialog not found")
        return

    display_dialog.load_data(data, data_type)
    display_dialog.show_dialog()


func _bind_display_dialog() -> void:
    var scene_root := get_tree().current_scene
    if scene_root == null:
        return
    display_dialog = scene_root.get_node_or_null("DisplayDialog") as DisplayDialog


func _on_display_pressed() -> void:
    display_clicked.emit()


func _on_help_pressed() -> void:
    help_clicked.emit()
