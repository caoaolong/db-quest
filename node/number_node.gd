class_name NumberNode
extends BaseNode

"""
{
    "value": 0,
    "int_type": "UINT64"
}
"""

const OUTPUT_SLOT := 1
const TYPE_OPTIONS := [
    UintCodec.TYPE_UINT8,
    UintCodec.TYPE_UINT16,
    UintCodec.TYPE_UINT32,
    UintCodec.TYPE_UINT64,
]

@onready var value_input: SpinBox = $VBoxContainer/ValueRow/SpinBox
@onready var type_input: OptionButton = $VBoxContainer/TypeRow/TypeOption


func _ready() -> void:
    super._ready()
    _setup_type_options()
    value_input.value_changed.connect(_on_value_changed)
    type_input.item_selected.connect(_on_type_selected)
    _apply_type_constraints(false)
    _sync_output_slot()


func _setup_type_options() -> void:
    type_input.clear()
    for type_name in TYPE_OPTIONS:
        type_input.add_item(type_name)
    _select_type(_stored_type(), false)


func _sync_data_from_controls() -> void:
    data["int_type"] = _selected_type_name()
    data["value"] = int(value_input.value)


func _sync_controls_from_data() -> void:
    var type_name := _stored_type()
    _select_type(type_name, false)
    _apply_type_constraints(false)
    if data.has("value") and value_input != null:
        value_input.value = float(clampi(int(data["value"]), 0, UintCodec.max_value(type_name)))
    _sync_output_slot()


func _on_value_changed(_value: float) -> void:
    _sync_data_from_controls()
    schedule_save()


func _on_type_selected(_index: int) -> void:
    _apply_type_constraints(true)
    _sync_data_from_controls()
    _sync_output_slot()
    schedule_save()


func _apply_type_constraints(clamp_value: bool) -> void:
    var type_name := _selected_type_name()
    var max_v := UintCodec.max_value(type_name)
    value_input.min_value = 0
    value_input.max_value = float(max_v)
    if clamp_value and int(value_input.value) > max_v:
        value_input.value = float(max_v)


func _stored_type() -> String:
    return UintCodec.normalize_type(str(data.get("int_type", UintCodec.TYPE_UINT64)))


func _selected_type_name() -> String:
    if type_input == null or type_input.item_count <= 0 or type_input.selected < 0:
        return _stored_type()
    return UintCodec.normalize_type(type_input.get_item_text(type_input.selected))


func _select_type(type_name: String, should_emit: bool) -> void:
    if type_input == null:
        return
    var normalized := UintCodec.normalize_type(type_name)
    var index := TYPE_OPTIONS.find(normalized)
    if index < 0:
        index = TYPE_OPTIONS.size() - 1
    if should_emit:
        type_input.selected = index
    else:
        type_input.set_block_signals(true)
        type_input.selected = index
        type_input.set_block_signals(false)
    data["int_type"] = TYPE_OPTIONS[index]


func _sync_output_slot() -> void:
    var graph_node := get_parent() as GraphNode
    var graph_edit := get_graph_edit()
    if graph_node == null or graph_edit == null:
        return
    if not graph_edit.has_method("set_slot_operation"):
        return
    graph_edit.set_slot_operation(graph_node, OUTPUT_SLOT, _selected_type_name(), true)


func get_user_input() -> Variant:
    _sync_data_from_controls()
    return UintCodec.encode(int(data.get("value", 0)), _selected_type_name())


func run(_inputs: Dictionary = {}) -> Variant:
    return get_user_input()
