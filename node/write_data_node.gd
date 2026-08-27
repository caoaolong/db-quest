class_name WriteDataNode
extends BaseNode

"""
{
    "value": 0,
    "data_type": "DATA",
    "rows": {
        "data": "",
        "offset": 0
    }
}
"""

const TYPE_OPTIONS := [
    "DATA",
    UintCodec.TYPE_UINT8,
    UintCodec.TYPE_UINT16,
    UintCodec.TYPE_UINT32,
    UintCodec.TYPE_UINT64,
]

@export var title: String = "页写数据"

@onready var type_input: OptionButton = $VBoxContainer/TypeRow/TypeOption
@onready var value_row: HBoxContainer = $VBoxContainer/ValueRow
@onready var value_input: SpinBox = $VBoxContainer/ValueRow/SpinBox


func _ready() -> void:
    super._ready()
    _setup_type_options()
    value_input.value_changed.connect(_on_value_changed)
    type_input.item_selected.connect(_on_type_selected)
    _sync_controls_from_data()
    call_deferred("_rebuild_slots")


func apply_persisted_data(saved: Dictionary) -> void:
    if saved.is_empty():
        return
    var payload := saved.duplicate(true)
    var rows: Variant = payload.get("rows", {})
    payload.erase("rows")
    apply_data(payload)
    _rebuild_slots()
    var graph_node := get_parent() as GraphNode
    if graph_node and rows is Dictionary:
        _apply_role_row_data(graph_node, rows as Dictionary)


func collect_persisted_data() -> Dictionary:
    _sync_data_from_controls()
    var result := data.duplicate(true)
    var graph_node := get_parent() as GraphNode
    if graph_node:
        var rows := _collect_role_row_data(graph_node)
        if not rows.is_empty():
            result["rows"] = rows
    return result


func _setup_type_options() -> void:
    type_input.clear()
    for type_name in TYPE_OPTIONS:
        type_input.add_item(type_name)
    _select_type(_stored_type(), false)


func _sync_data_from_controls() -> void:
    data["data_type"] = _selected_type_name()
    data["value"] = int(value_input.value)


func _sync_controls_from_data() -> void:
    var type_name := _stored_type()
    _select_type(type_name, false)
    _apply_type_constraints(false)
    if data.has("value") and value_input != null and type_name != "DATA":
        value_input.value = float(clampi(int(data["value"]), 0, UintCodec.max_value(type_name)))
    _update_subtitle()
    _update_mode_layout()


func _on_value_changed(_value: float) -> void:
    _sync_data_from_controls()
    schedule_save()


func _on_type_selected(_index: int) -> void:
    _apply_type_constraints(true)
    _sync_data_from_controls()
    _rebuild_slots()
    schedule_save()


func _apply_type_constraints(clamp_value: bool) -> void:
    var type_name := _selected_type_name()
    if type_name == "DATA":
        return
    var max_v := UintCodec.max_value(type_name)
    value_input.min_value = 0
    value_input.max_value = float(max_v)
    if clamp_value and int(value_input.value) > max_v:
        value_input.value = float(max_v)


func _stored_type() -> String:
    var raw := str(data.get("data_type", data.get("int_type", "DATA")))
    if raw == "DATA":
        return "DATA"
    return UintCodec.normalize_type(raw)


func _selected_type_name() -> String:
    if type_input == null or type_input.item_count <= 0 or type_input.selected < 0:
        return _stored_type()
    return str(type_input.get_item_text(type_input.selected))


func _select_type(type_name: String, should_emit: bool) -> void:
    if type_input == null:
        return
    var normalized := "DATA"
    if type_name != "DATA":
        normalized = UintCodec.normalize_type(type_name)
    var index := TYPE_OPTIONS.find(normalized)
    if index < 0:
        index = 0
    if should_emit:
        type_input.selected = index
    else:
        type_input.set_block_signals(true)
        type_input.selected = index
        type_input.set_block_signals(false)
    data["data_type"] = TYPE_OPTIONS[index]


func _update_subtitle() -> void:
    set_subtitle(_selected_type_name())


func _update_mode_layout() -> void:
    value_row.visible = _selected_type_name() != "DATA"


func _rebuild_slots() -> void:
    var graph_node := get_parent() as GraphNode
    var graph_edit := get_graph_edit()
    if graph_node == null or graph_edit == null:
        return
    if not graph_edit.has_method("create_node_row") or not graph_edit.has_method("_parse_op_list"):
        return

    var is_data := _selected_type_name() == "DATA"
    var output_type := _selected_type_name()
    var saved_rows := _collect_role_row_data(graph_node)
    var saved_connections := _snapshot_connections(graph_node, graph_edit)

    while graph_node.get_child_count() > 1:
        graph_edit.remove_slot_row(graph_node, graph_node.get_child_count() - 1)

    var offset_op_list: Array = graph_edit._parse_op_list([{
        "operation": "UINT16",
        "type": "INPUT",
    }])
    var output_op_list: Array = graph_edit._parse_op_list([{
        "operation": output_type,
        "type": "OUTPUT",
    }])

    var slot_index := 1
    if is_data:
        var data_op_list: Array = graph_edit._parse_op_list([{
            "operation": "DATA",
            "type": "INPUT",
        }])
        graph_edit.create_node_row(
            graph_node,
            slot_index,
            "Data",
            data_op_list,
            [],
            "",
            "Data"
        )
        slot_index += 1

    graph_edit.create_node_row(
        graph_node,
        slot_index,
        "Offset",
        offset_op_list,
        [],
        "Offset"
    )
    slot_index += 1

    graph_edit.create_node_row(
        graph_node,
        slot_index,
        "Out",
        output_op_list
    )
    graph_edit.set_slot_operation(graph_node, slot_index, output_type, true)

    _apply_role_row_data(graph_node, saved_rows)
    if _restore_connections(graph_node, graph_edit, saved_connections):
        schedule_save()
    _update_mode_layout()
    _fit_graph_node_size(graph_node)


func _collect_role_row_data(graph_node: GraphNode) -> Dictionary:
    var rows := {}
    for slot_index in range(1, graph_node.get_child_count()):
        var role := _slot_role_for_index(graph_node, slot_index)
        if role.is_empty():
            continue
        var row_control := _get_row_control(graph_node, slot_index)
        if row_control is SpinBox:
            rows[role] = int((row_control as SpinBox).value)
        elif row_control is LineEdit:
            rows[role] = (row_control as LineEdit).text
    return rows


func _apply_role_row_data(graph_node: GraphNode, rows: Dictionary) -> void:
    for key in rows.keys():
        var role := str(key)
        var slot_index := -1
        if role.is_valid_int():
            slot_index = int(role)
        else:
            slot_index = _slot_index_for_role(graph_node, role)
        if slot_index < 0:
            continue
        var row_control := _get_row_control(graph_node, slot_index)
        if row_control is SpinBox:
            (row_control as SpinBox).value = int(rows[key])
        elif row_control is LineEdit:
            (row_control as LineEdit).text = str(rows[key])


func _fit_graph_node_size(graph_node: GraphNode) -> void:
    if graph_node == null:
        return
    graph_node.reset_size()
    var min_size := graph_node.get_combined_minimum_size()
    if graph_node.size.y > min_size.y or graph_node.size.x < min_size.x:
        graph_node.size = Vector2(
            maxf(graph_node.size.x, min_size.x),
            min_size.y
        )


func _data_slot_index(graph_node: GraphNode) -> int:
    return _slot_index_for_role(graph_node, "data")


func _offset_slot_index(graph_node: GraphNode) -> int:
    return _slot_index_for_role(graph_node, "offset")


func _snapshot_connections(graph_node: GraphNode, graph_edit: GraphEdit) -> Array:
    var records: Array = []
    var node_name := String(graph_node.name)
    for conn in graph_edit.get_connection_list():
        var from_name := String(conn.get("from_node", conn.get("from")))
        var to_name := String(conn.get("to_node", conn.get("to")))
        var from_port := int(conn.get("from_port", 0))
        var to_port := int(conn.get("to_port", 0))
        if to_name == node_name:
            var slot_index := graph_node.get_input_port_slot(to_port)
            var role := _slot_role_for_index(graph_node, slot_index)
            if role.is_empty():
                continue
            records.append({
                "direction": "in",
                "peer": from_name,
                "peer_port": from_port,
                "role": role,
            })
        elif from_name == node_name:
            var slot_index := graph_node.get_output_port_slot(from_port)
            var role := _slot_role_for_index(graph_node, slot_index)
            if role.is_empty():
                continue
            records.append({
                "direction": "out",
                "peer": to_name,
                "peer_port": to_port,
                "role": role,
            })
    return records


func _restore_connections(graph_node: GraphNode, graph_edit: GraphEdit, records: Array) -> bool:
    if records.is_empty():
        return false
    var node_name := String(graph_node.name)
    var restored := false
    for rec in records:
        if not rec is Dictionary:
            continue
        var role := str(rec.get("role", ""))
        var slot_index := _slot_index_for_role(graph_node, role)
        if slot_index < 0:
            continue
        if str(rec.get("direction", "")) == "in":
            var to_port := _port_for_input_slot(graph_node, slot_index)
            if to_port < 0:
                continue
            var err := graph_edit.connect_node(
                StringName(rec.get("peer", "")),
                int(rec.get("peer_port", 0)),
                node_name,
                to_port
            )
            restored = restored or err == OK
        else:
            var from_port := _port_for_output_slot(graph_node, slot_index)
            if from_port < 0:
                continue
            var err := graph_edit.connect_node(
                node_name,
                from_port,
                StringName(rec.get("peer", "")),
                int(rec.get("peer_port", 0))
            )
            restored = restored or err == OK
    return restored


func _slot_role_for_index(graph_node: GraphNode, slot_index: int) -> String:
    if slot_index < 1 or slot_index >= graph_node.get_child_count():
        return ""
    var label := _get_row_label(graph_node, slot_index)
    if label == null:
        return ""
    return label.text.strip_edges().to_lower()


func _slot_index_for_role(graph_node: GraphNode, role: String) -> int:
    var normalized := role.strip_edges().to_lower()
    for slot_index in range(1, graph_node.get_child_count()):
        if _slot_role_for_index(graph_node, slot_index) == normalized:
            return slot_index
    return -1


func _port_for_input_slot(graph_node: GraphNode, slot_index: int) -> int:
    for port_index in graph_node.get_input_port_count():
        if graph_node.get_input_port_slot(port_index) == slot_index:
            return port_index
    return -1


func _port_for_output_slot(graph_node: GraphNode, slot_index: int) -> int:
    for port_index in graph_node.get_output_port_count():
        if graph_node.get_output_port_slot(port_index) == slot_index:
            return port_index
    return -1


func run(inputs: Dictionary = {}) -> Variant:
    _sync_data_from_controls()
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return {"error": "No graph node"}
    var slot_inputs: Dictionary = _get_slot_inputs(inputs)
    var data_slot := _data_slot_index(graph_node)
    var offset_slot := _offset_slot_index(graph_node)
    var offset := _resolve_uint16(slot_inputs, offset_slot, 0)
    var type_name := _selected_type_name()
    var payload: PackedByteArray
    var length: int

    if type_name == "DATA":
        payload = _resolve_data_bytes(slot_inputs, data_slot)
        length = payload.size()
        EditorLog.info(
            "页写数据: type=DATA offset=%d bytes=%d" % [offset, length]
        )
    else:
        payload = UintCodec.encode(int(data.get("value", 0)), type_name)
        length = payload.size()
        EditorLog.info(
            "页写数据: type=%s value=%d offset=%d bytes=%d" % [
                type_name,
                int(data.get("value", 0)),
                offset,
                length,
            ]
        )

    var page_data: Dictionary = {
        "data": payload,
        "offset": offset,
        "length": length,
    }
    return {
        "__outputs": {
            "0": page_data,
        },
    }


func _resolve_data_bytes(slot_inputs: Dictionary, data_slot: int) -> PackedByteArray:
    if data_slot >= 0 and slot_inputs.has(data_slot) and _has_input_connection(data_slot):
        return _encode_data_bytes(slot_inputs[data_slot])
    var text := _row_text(data_slot)
    if not text.is_empty():
        return _string_to_bytes(text)
    if data_slot >= 0 and slot_inputs.has(data_slot):
        return _encode_data_bytes(slot_inputs[data_slot])
    return PackedByteArray()


func _has_input_connection(data_slot: int) -> bool:
    var graph_node := get_parent() as GraphNode
    var graph_edit := get_graph_edit()
    if graph_node == null or graph_edit == null or data_slot < 0:
        return false
    var node_name := String(graph_node.name)
    for conn in graph_edit.get_connection_list():
        if String(conn.get("to_node", conn.get("to"))) != node_name:
            continue
        var to_port := int(conn.get("to_port", 0))
        if graph_node.get_input_port_slot(to_port) == data_slot:
            return true
    return false


func _encode_data_bytes(value: Variant) -> PackedByteArray:
    if value == null:
        return PackedByteArray()
    if value is String:
        return _string_to_bytes(value as String)
    if value is PackedByteArray:
        return _strip_trailing_nulls(value as PackedByteArray)
    if value is Array:
        var bytes := PackedByteArray()
        for item in value:
            bytes.append_array(_encode_data_bytes(item))
        return bytes
    if value is Dictionary:
        return _encode_data_bytes((value as Dictionary).get("data", null))
    return PackedByteArray()


func _string_to_bytes(text: String) -> PackedByteArray:
    if text.is_empty():
        return PackedByteArray()
    return text.to_utf8_buffer()


func _strip_trailing_nulls(bytes: PackedByteArray) -> PackedByteArray:
    var end := bytes.size()
    while end > 0 and bytes[end - 1] == 0:
        end -= 1
    if end <= 0:
        return PackedByteArray()
    if end == bytes.size():
        return bytes
    return bytes.slice(0, end)


func _resolve_uint16(slot_inputs: Dictionary, slot_index: int, fallback: int) -> int:
    if slot_index >= 0 and slot_inputs.has(slot_index):
        return maxi(0, UintCodec.decode(slot_inputs[slot_index], UintCodec.TYPE_UINT16))
    var spin := _row_spin(slot_index)
    if spin != null:
        return maxi(0, int(spin.value))
    return maxi(0, fallback)


func _row_text(slot_index: int) -> String:
    if slot_index < 0:
        return ""
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return ""
    var control := _get_row_control(graph_node, slot_index)
    if control is LineEdit:
        return (control as LineEdit).text
    return ""


func _row_spin(slot_index: int) -> SpinBox:
    if slot_index < 0:
        return null
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return null
    return _get_row_control(graph_node, slot_index) as SpinBox


func _get_slot_inputs(inputs: Dictionary) -> Dictionary:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return {}
    var by_slot := {}
    for port_key in inputs.keys():
        var port_index := int(port_key)
        var slot_index := graph_node.get_input_port_slot(port_index)
        by_slot[slot_index] = inputs[port_key]
    return by_slot


func _on_display_clicked() -> void:
    var result: Variant = run({})
    if result is Dictionary and result.has("__outputs"):
        action.display_data((result as Dictionary)["__outputs"]["0"])
    else:
        action.display_data(result)
