class_name NumberNode
extends BaseNode

"""
{
    "value": 0
}
"""

@onready var value_input: SpinBox = $VBoxContainer/SpinBox


func _ready() -> void:
    super._ready()
    value_input.value_changed.connect(_on_value_changed)


func _sync_data_from_controls() -> void:
    data["value"] = int(value_input.value)


func _sync_controls_from_data() -> void:
    if data.has("value"):
        value_input.value = int(data["value"])


func _on_value_changed(_value: float) -> void:
    _sync_data_from_controls()
    schedule_save()


func run(_inputs: Dictionary = {}) -> Variant:
    return get_user_input()
