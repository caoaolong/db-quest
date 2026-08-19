extends HBoxContainer
class_name TaskRewardItem

@onready var _exp_label: Label = $Exp/Value
@onready var _coin_label: Label = $Coin/Value

var _exp_value: int = 0
var _coin_value: int = 0


func setup(exp_value: int, coin_value: int) -> void:
    _exp_value = exp_value
    _coin_value = coin_value
    if is_node_ready():
        _update_labels()


func _ready() -> void:
    _update_labels()


func _update_labels() -> void:
    _exp_label.text = str(_exp_value)
    _coin_label.text = str(_coin_value)
