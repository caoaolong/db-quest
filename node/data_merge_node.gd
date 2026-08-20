class_name DataMergeNode
extends BaseNode

"""
{
    "separator": ""
}
"""

@onready var separator_input: LineEdit = $VBoxContainer/LineEdit


func _ready() -> void:
    super._ready()
    separator_input.text_changed.connect(_on_separator_changed)


func _configure_action_bar() -> void:
    if action == null:
        return
    action.set_run_visible(true)


func _sync_data_from_controls() -> void:
    data["separator"] = separator_input.text


func _sync_controls_from_data() -> void:
    if data.has("separator"):
        separator_input.text = str(data["separator"])


func _on_separator_changed(_text: String) -> void:
    _sync_data_from_controls()
    schedule_save()


func run(inputs: Dictionary = {}) -> Variant:
    _sync_data_from_controls()
    var separator: String = str(data.get("separator", ""))
    var parts: PackedStringArray = []
    var keys: Array = inputs.keys()
    keys.sort()
    for key in keys:
        var value: Variant = inputs[key]
        if value == null:
            continue
        parts.append(str(value))
    return separator.join(parts)
