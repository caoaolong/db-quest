extends PanelContainer

@onready var _tab_bar: TabBar = $VBoxContainer/HBoxContainer/VBoxContainer/TabBar
@onready var _log_label: Label = $VBoxContainer/StatusContainer/Log
@onready var _spend_label: Label = $VBoxContainer/StatusContainer/Spend
@onready var _graph_edit: GraphEdit = $VBoxContainer/GraphEdit

var _task_dialog: TaskDialog = null
var _help_dialog: HelpDialog = null
var _restart_confirm: ConfirmationDialog


func _ready() -> void:
    _build_tab_bar()
    _bind_task_dialog()
    _bind_help_dialog()
    _bind_status_log()
    _bind_run_spend()
    _setup_restart_confirm()


func _setup_restart_confirm() -> void:
    _restart_confirm = ConfirmationDialog.new()
    _restart_confirm.title = "确认重新开始"
    _restart_confirm.dialog_text = "将清空画布节点与任务进度，是否继续？"
    _restart_confirm.ok_button_text = "确定"
    _restart_confirm.cancel_button_text = "取消"
    _restart_confirm.confirmed.connect(_perform_restart)
    add_child(_restart_confirm)


func _bind_status_log() -> void:
    if _log_label == null:
        return

    _log_label.text = ""
    EditorLog.message_logged.connect(_on_log_message)


func _bind_run_spend() -> void:
    _update_spend_label(0)
    if _graph_edit == null:
        return
    if _graph_edit.has_signal("run_spend_changed"):
        _graph_edit.run_spend_changed.connect(_update_spend_label)


func _update_spend_label(total_ms: int) -> void:
    if _spend_label == null:
        return
    _spend_label.text = "耗时 %d ms" % maxi(0, total_ms)


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


func _bind_help_dialog() -> void:
    _help_dialog = get_node_or_null("HelpDialog") as HelpDialog


func _build_tab_bar() -> void:
    while _tab_bar.tab_count > 0:
        _tab_bar.remove_tab(0)

    for category in GameState.get_categories():
        _tab_bar.add_tab(category)


func _on_back_pressed() -> void:
    get_tree().change_scene_to_file("res://scenes/level_list.tscn")


func _on_restart_pressed() -> void:
    if _restart_confirm == null:
        _perform_restart()
        return
    _restart_confirm.popup_centered()


func _perform_restart() -> void:
    if _graph_edit != null and _graph_edit.has_method("restart_graph"):
        _graph_edit.restart_graph()
    GameState.reset_task_progress()
    if _log_label:
        _log_label.text = ""
    _update_spend_label(0)
    EditorLog.info("已重新开始本关卡")


func _on_button_pressed() -> void:
    if _graph_edit == null:
        return
    if _graph_edit.has_method("run_all"):
        await _graph_edit.run_all()


func _on_help_pressed() -> void:
    if _help_dialog == null:
        _bind_help_dialog()
    if _help_dialog == null:
        push_error("HelpDialog not found")
        return

    await _help_dialog.show_help(
        GameState.get_current_level_help(),
        GameState.get_current_level_name()
    )
