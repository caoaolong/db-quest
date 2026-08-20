extends PanelContainer

@onready var _tab_bar: TabBar = $VBoxContainer/HBoxContainer/VBoxContainer/TabBar
@onready var _log_label: Label = $VBoxContainer/StatusContainer/Log

var _task_dialog: TaskDialog = null


func _ready() -> void:
    _build_tab_bar()
    _bind_task_dialog()
    _bind_status_log()


func _bind_status_log() -> void:
    if _log_label == null:
        return

    _log_label.text = ""
    EditorLog.message_logged.connect(_on_log_message)


func _on_log_message(message: String, level: String) -> void:
    var prefix := ""
    match level:
        EditorLog.LEVEL_WARN:
            prefix = "[警告] "
        EditorLog.LEVEL_ERROR:
            prefix = "[错误] "
        _:
            prefix = "[信息] "

    _log_label.text = prefix + message


func _on_tasks_pressed() -> void:
    if _task_dialog == null:
        _bind_task_dialog()
    if _task_dialog == null:
        push_error("TaskDialog not found")
        return

    await _task_dialog.show_dialog()


func _bind_task_dialog() -> void:
    _task_dialog = get_node_or_null("TaskDialog") as TaskDialog


func _build_tab_bar() -> void:
    while _tab_bar.tab_count > 0:
        _tab_bar.remove_tab(0)

    for category in GameState.get_categories():
        _tab_bar.add_tab(category)


func _on_back_pressed() -> void:
    get_tree().change_scene_to_file("res://scenes/level_list.tscn")
