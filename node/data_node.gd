class_name DataNode
extends BaseNode

"""
{
    "value": ""
}
"""

@onready var value_input: TextEdit = $VBoxContainer/TextEdit


func _ready() -> void:
    super._ready()
    value_input.text_changed.connect(_on_text_changed)


func _sync_data_from_controls() -> void:
    data["value"] = value_input.text


func _sync_controls_from_data() -> void:
    if data.has("value"):
        value_input.text = str(data["value"])


func run(_inputs: Dictionary = {}) -> Variant:
    return get_user_input()


func _on_text_changed() -> void:
    _sync_data_from_controls()
    schedule_save()


func _on_display_clicked() -> void:
    _sync_data_from_controls()
    action.display_data(str(data.get("value", "")))
