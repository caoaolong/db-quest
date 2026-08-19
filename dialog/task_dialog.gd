extends PopupDialog
class_name TaskDialog

const TASK_ITEM_SCENE := preload("res://dialog/task/task_item.tscn")

@onready var _task_list: VBoxContainer = $VBoxContainer/TaskList
@onready var _task_count: Label = $VBoxContainer/HBoxContainer/Count


func _ready() -> void:
    super._ready()
    _build_task_list()


func show_dialog() -> void:
    _build_task_list()
    await get_tree().process_frame
    _fit_task_list_panel()
    await refresh_popup_size()
    popup_centered()


func _fit_task_list_panel() -> void:
    var separation := _task_list.get_theme_constant("separation")
    var content_width := 320.0
    var content_height := 0.0
    var child_count := _task_list.get_child_count()

    for child in _task_list.get_children():
        if child is not Control:
            continue
        var _min_size := (child as Control).get_combined_minimum_size()
        content_width = maxf(content_width, _min_size.x)
        content_height += _min_size.y

    if child_count > 1:
        content_height += separation * (child_count - 1)

    set_clamped_content_size(_task_list, Vector2(content_width, maxf(content_height, 80.0)))


func _build_task_list() -> void:
    for child in _task_list.get_children():
        child.free()

    var task_count := 0
    var tasks := GameState.get_current_level_tasks()
    for index in tasks.size():
        var task: Variant = tasks[index]
        if not task is Dictionary:
            continue

        task_count += 1
        var item := TASK_ITEM_SCENE.instantiate() as TaskItem
        _task_list.add_child(item)
        item.setup(task as Dictionary, GameState.is_task_completed(index))

    _task_count.text = "%d 项任务" % task_count


func _on_close_pressed() -> void:
    close_dialog()
