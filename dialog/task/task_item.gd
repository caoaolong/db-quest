extends PanelContainer
class_name TaskItem

const LevelVariables := preload("res://level_variables.gd")

@onready var _title: Label = $VBoxContainer/TaskCard/Content/Title
@onready var _description: Label = $VBoxContainer/TaskCard/Content/Description
@onready var _status: Label = $VBoxContainer/TaskCard/Option/Status
@onready var _claim_button: Button = $VBoxContainer/TaskCard/Option/Claim
@onready var _reward_item: TaskRewardItem = $VBoxContainer/TaskRewardItem

var _task_data: Dictionary = {}
var _completed := false


func setup(task_data: Dictionary, completed: bool = false) -> TaskItem:
    _task_data = task_data.duplicate(true)
    _completed = completed
    if is_node_ready():
        _apply_task_data()
    return self


func get_task_data() -> Dictionary:
    return _task_data.duplicate(true)


func is_completed() -> bool:
    return _completed


func _ready() -> void:
    if _task_data.is_empty():
        return
    _apply_task_data()


func _apply_task_data() -> void:
    var variables := GameState.get_current_level_variables()
    _title.text = LevelVariables.expand_text(str(_task_data.get("title", "")), variables)
    _description.text = LevelVariables.expand_text(str(_task_data.get("description", "")), variables)
    _status.text = "[已完成]" if _completed else "[未完成]"
    _claim_button.disabled = not _completed

    var reward: Variant = _task_data.get("reward", {})
    if reward is Dictionary:
        _reward_item.setup(int(reward.get("EXP", 0)), int(reward.get("COIN", 0)))
