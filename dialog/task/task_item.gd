extends PanelContainer
class_name TaskItem

@onready var _title: Label = $VBoxContainer/TaskCard/Content/Title
@onready var _description: Label = $VBoxContainer/TaskCard/Content/Description
@onready var _status: Label = $VBoxContainer/TaskCard/Option/Status
@onready var _claim_button: Button = $VBoxContainer/TaskCard/Option/Claim
@onready var _reward_item: TaskRewardItem = $VBoxContainer/TaskRewardItem

var _task_data: Dictionary = {}


func setup(task_data: Dictionary) -> TaskItem:
    _task_data = task_data.duplicate(true)
    if is_node_ready():
        _apply_task_data()
    return self


func get_task_data() -> Dictionary:
    return _task_data.duplicate(true)


func _ready() -> void:
    if _task_data.is_empty():
        return
    _apply_task_data()


func _apply_task_data() -> void:
    _title.text = str(_task_data.get("title", ""))
    _description.text = str(_task_data.get("description", ""))
    _status.text = "[未完成]"
    _claim_button.disabled = true

    var reward: Variant = _task_data.get("reward", {})
    if reward is Dictionary:
        _reward_item.setup(int(reward.get("EXP", 0)), int(reward.get("COIN", 0)))
