class_name OperationNode
extends BaseNode

"""
{
    "value": ""
}
"""

@onready var value_input: LineEdit = $VBoxContainer/LineEdit


func _ready() -> void:
    super._ready()
    value_input.text_changed.connect(_on_text_changed)


func _sync_data_from_controls() -> void:
    data["value"] = value_input.text


func _sync_controls_from_data() -> void:
    if data.has("value"):
        value_input.text = str(data["value"])


func _on_text_changed(_text: String) -> void:
    _sync_data_from_controls()
    schedule_save()


func run(inputs: Dictionary = {}) -> Variant:
    return get_user_input()
