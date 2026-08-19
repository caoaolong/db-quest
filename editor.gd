extends PanelContainer

@onready var _tab_bar: TabBar = $VBoxContainer/HBoxContainer/VBoxContainer/TabBar

var _task_dialog: TaskDialog = null


func _ready() -> void:
    _build_tab_bar()
    _bind_task_dialog()


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
