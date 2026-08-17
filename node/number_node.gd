class_name NumberNode
extends BaseNode

const OUTPUT_ROW := 1

@onready var type_option: OptionButton = $VBoxContainer/HBoxContainer/OptionButton
@onready var signed_check: CheckBox = $VBoxContainer/HBoxContainer/CheckBox


func _ready() -> void:
    super._ready()
    type_option.item_selected.connect(_on_type_selected)
    signed_check.toggled.connect(_on_signed_toggled)
    call_deferred("_apply_output_type")


func _on_type_selected(_index: int) -> void:
    _apply_output_type()


func _on_signed_toggled(_pressed: bool) -> void:
    _apply_output_type()


func _apply_output_type() -> void:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return

    var graph_edit := graph_node.get_parent() as GraphEdit
    if graph_edit == null:
        return

    graph_edit.set_slot_operation(graph_node, OUTPUT_ROW, _current_operation_name(), true)


func _current_operation_name() -> String:
    var type_name := type_option.get_item_text(type_option.selected)
    if signed_check.button_pressed:
        return type_name
    return type_name.replace("INT", "UINT")
