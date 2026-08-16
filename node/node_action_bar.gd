extends HBoxContainer
class_name NodeActionBar

signal display_clicked
signal delete_clicked
signal help_clicked

var display_dialog: DisplayDialog = null


func _ready() -> void:
	_bind_display_dialog()


func display_data(data: String) -> void:
	if display_dialog == null:
		_bind_display_dialog()
	if display_dialog == null:
		push_error("DisplayDialog not found")
		return

	display_dialog.load_data(data)
	display_dialog.popup()


func _bind_display_dialog() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	display_dialog = scene_root.get_node_or_null("DisplayDialog") as DisplayDialog


func _on_delete_pressed() -> void:
	delete_clicked.emit()


func _on_display_pressed() -> void:
	display_clicked.emit()


func _on_help_pressed() -> void:
	help_clicked.emit()
