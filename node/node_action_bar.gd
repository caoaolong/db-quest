extends VBoxContainer
class_name NodeActionBar

signal display_clicked
signal delete_clicked
signal help_clicked
signal run_clicked

var display_dialog: DisplayDialog = null

@onready var run_button: Button = $HBoxContainer/Run


func _ready() -> void:
    _bind_display_dialog()


func set_run_visible(_is_visible: bool) -> void:
    if run_button:
        run_button.visible = _is_visible


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


func _on_delete_pressed() -> void:
    delete_clicked.emit()


func _on_run_pressed() -> void:
    run_clicked.emit()


func _on_display_pressed() -> void:
    display_clicked.emit()


func _on_help_pressed() -> void:
    help_clicked.emit()
