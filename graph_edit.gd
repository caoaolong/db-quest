extends GraphEdit

enum SlotType {
    INPUT,
    OUTPUT,
}

enum Slot {
    OPERATION_CODE,
    INT,
    ADDR,
    DATA,
}

const SLOT_COLORS: Dictionary = {
    Slot.OPERATION_CODE: "#F59E0B",
    Slot.INT: "#3B82F6",
    Slot.ADDR: "#8B5CF6",
    Slot.DATA: "#A855F7",
}

const node_style = preload("res://node/node_style.tres")
const ROW_HORIZONTAL_MARGIN := 12
const RUNTIME_DATA_PATH := "res://data/runtime/%d.data"

var _is_restoring := false
var _save_timer: Timer


func _ready() -> void:
    connection_request.connect(_on_connection_request)
    disconnection_request.connect(_on_disconnection_request)
    end_node_move.connect(_on_end_node_move)
    delete_nodes_request.connect(_on_delete_nodes_request)

    _save_timer = Timer.new()
    _save_timer.one_shot = true
    _save_timer.wait_time = 0.3
    _save_timer.timeout.connect(_save_snapshot)
    add_child(_save_timer)

    call_deferred("load_snapshot")


func is_restoring() -> bool:
    return _is_restoring


func schedule_save() -> void:
    if _is_restoring:
        return
    _save_timer.start()


func _on_end_node_move() -> void:
    schedule_save()


func _on_delete_nodes_request(node: Node) -> void:
    if node is GraphNode:
        node.queue_free()
        schedule_save()


func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
    if from_node == to_node:
        return

    var from_graph_node := get_node_or_null(NodePath(from_node)) as GraphNode
    var to_graph_node := get_node_or_null(NodePath(to_node)) as GraphNode
    if from_graph_node == null or to_graph_node == null:
        return
    if from_graph_node.get_output_port_type(from_port) != to_graph_node.get_input_port_type(to_port):
        return

    connect_node(from_node, from_port, to_node, to_port)
    schedule_save()


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
    disconnect_node(from_node, from_port, to_node, to_port)
    schedule_save()


func create_node_from_config(
    item: Dictionary,
    instance_id: String = "",
    position: Variant = null,
    state: Dictionary = {}
) -> GraphNode:
    var config := GameState.resolve_node_config(item)
    if config.is_empty():
        return null

    var template_name := str(config.get("name", ""))
    if not GameState.is_node_available(template_name):
        push_warning("Node is not available in current level: %s" % template_name)
        return null

    var scene_path := str(config.get("scene", ""))
    if scene_path.is_empty():
        push_error("Node config missing scene path")
        return null

    var scene := load(scene_path) as PackedScene
    if scene == null:
        push_error("Failed to load scene: %s" % scene_path)
        return null

    var attributes := config.get("attributes", {}) as Dictionary
    var node := GraphNode.new()
    if instance_id.is_empty():
        instance_id = _generate_instance_id(template_name)
    node.name = instance_id
    node.set_meta("template_name", template_name)
    node.add_theme_stylebox_override("panel", node_style)

    var content := scene.instantiate() as Control
    _apply_node_attributes(content, attributes, config, node)
    content.set_anchors_preset(Control.PRESET_FULL_RECT)
    content.offset_left = 0
    content.offset_top = 0
    content.offset_right = 0
    content.offset_bottom = 0
    node.add_child(content)
    if attributes.has("subtitle"):
        _set_subtitle(content, str(attributes["subtitle"]))
    node.set_slot_enabled_left(0, false)
    node.set_slot_enabled_right(0, false)

    _build_node_rows(node, attributes)

    if position is Vector2:
        node.position_offset = position
    else:
        var graph_node_count := 0
        for child in get_children():
            if child is GraphNode:
                graph_node_count += 1
        node.position_offset = Vector2(40 + graph_node_count * 24, 40 + graph_node_count * 24)

    add_child(node)
    _apply_node_state(content, state)
    schedule_save()
    return node


func clear_graph() -> void:
    for conn in get_connection_list():
        var from_name: StringName = conn.get("from_node", conn.get("from"))
        var to_name: StringName = conn.get("to_node", conn.get("to"))
        var from_port: int = conn.get("from_port", 0)
        var to_port: int = conn.get("to_port", 0)
        disconnect_node(from_name, from_port, to_name, to_port)

    for child in get_children():
        if child is GraphNode:
            remove_child(child)
            child.queue_free()


func export_snapshot() -> Dictionary:
    var nodes_data: Array = []
    for child in get_children():
        if not child is GraphNode:
            continue

        var graph_node := child as GraphNode
        var content := graph_node.get_child(0) as Control
        nodes_data.append({
            "instance_id": String(graph_node.name),
            "template_name": str(graph_node.get_meta("template_name", graph_node.name)),
            "position": {
                "x": graph_node.position_offset.x,
                "y": graph_node.position_offset.y,
            },
            "state": _export_node_state(content),
        })

    var connections_data: Array = []
    for conn in get_connection_list():
        connections_data.append({
            "from_node": String(conn.get("from_node", conn.get("from"))),
            "from_port": int(conn.get("from_port", 0)),
            "to_node": String(conn.get("to_node", conn.get("to"))),
            "to_port": int(conn.get("to_port", 0)),
        })

    return {
        "level": GameState.current_level,
        "nodes": nodes_data,
        "connections": connections_data,
    }


func load_snapshot() -> void:
    var snapshot := GraphSnapshot.load(GameState.current_level)
    if snapshot.is_empty():
        return

    _is_restoring = true
    clear_graph()

    for node_data in snapshot.get("nodes", []):
        if not node_data is Dictionary:
            continue

        var template_name := str(node_data.get("template_name", ""))
        var item := GameState.get_node_entry(template_name)
        if item.is_empty():
            continue

        var position_dict: Dictionary = node_data.get("position", {})
        var position := Vector2(
            float(position_dict.get("x", 0.0)),
            float(position_dict.get("y", 0.0))
        )
        var state: Dictionary = node_data.get("state", {})
        create_node_from_config(
            item,
            str(node_data.get("instance_id", "")),
            position,
            state
        )

    for conn in snapshot.get("connections", []):
        if not conn is Dictionary:
            continue
        connect_node(
            StringName(conn.get("from_node", "")),
            int(conn.get("from_port", 0)),
            StringName(conn.get("to_node", "")),
            int(conn.get("to_port", 0))
        )

    _is_restoring = false


func _exit_tree() -> void:
    _save_snapshot()


func _save_snapshot() -> void:
    if _is_restoring:
        return
    GraphSnapshot.save(GameState.current_level, export_snapshot())


func _generate_instance_id(template_name: String) -> String:
    var index := 1
    while has_node(NodePath("%s_%d" % [template_name, index])):
        index += 1
    return "%s_%d" % [template_name, index]


func _export_node_state(content: Control) -> Dictionary:
    if content is BaseNode:
        return (content as BaseNode).collect_persisted_data()
    return {}


func _apply_node_state(content: Control, state: Dictionary) -> void:
    if content is BaseNode:
        (content as BaseNode).apply_persisted_data(state)


func _load_runtime_data() -> String:
    var path := RUNTIME_DATA_PATH % GameState.current_level
    if not FileAccess.file_exists(path):
        push_error("Runtime data file not found: %s" % path)
        return ""

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("Failed to open runtime data file: %s" % path)
        return ""

    return file.get_as_text()


func _apply_node_attributes(content: Control, attributes: Dictionary, config: Dictionary, graph_node: GraphNode) -> void:
    if content is DiskNode:
        var disk_node := content as DiskNode
        if attributes.has("title"):
            disk_node.title = str(attributes["title"])
        graph_node.title = disk_node.title
    elif content is DataNode:
        (content as DataNode).runtime_data = _load_runtime_data()
        _set_graph_node_title(graph_node, attributes, config)
    else:
        _set_graph_node_title(graph_node, attributes, config)


func _set_subtitle(content: Control, subtitle: String) -> void:
    if content is BaseNode:
        (content as BaseNode).set_subtitle(subtitle)
        return

    var label := content.get_node_or_null("VBoxContainer/Label") as Label
    if label:
        label.text = subtitle


func _set_graph_node_title(graph_node: GraphNode, attributes: Dictionary, config: Dictionary) -> void:
    if attributes.has("title"):
        graph_node.title = str(attributes["title"])
    else:
        graph_node.title = str(config.get("label", graph_node.name))


func _build_node_rows(node: GraphNode, attributes: Dictionary) -> void:
    for row in attributes.get("slots", []):
        if row is Dictionary:
            _add_row_from_config(node, row)


func _add_row_from_config(node: GraphNode, row: Dictionary) -> void:
    create_node_row(
        node,
        int(row.get("row_number", 0)),
        str(row.get("row_name", "")),
        _parse_operation(str(row.get("operation", ""))),
        _parse_op_list(row.get("op_list", [])),
        row.get("row_options", []),
        str(row.get("row_number_input", ""))
    )


func create_node_row(
    node: GraphNode,
    row_number: int,
    row_name: String,
    operation: Slot,
    op_list: Array,
    row_options: Variant = [],
    row_number_input: String = ""
) -> int:
    var row_control := _create_row_control(row_name, row_options, row_number_input, operation)
    _bind_row_control_save(row_control)
    node.add_child(_wrap_row_control(row_control))
    var slot_index := node.get_child_count() - 1

    for op in op_list:
        var slot_color := _get_slot_color(op.operation)
        match op.type:
            SlotType.INPUT:
                node.set_slot_enabled_left(slot_index, true)
                node.set_slot_type_left(slot_index, op.operation)
                node.set_slot_color_left(slot_index, slot_color)
            SlotType.OUTPUT:
                node.set_slot_enabled_right(slot_index, true)
                node.set_slot_type_right(slot_index, op.operation)
                node.set_slot_color_right(slot_index, slot_color)
    return slot_index


func _bind_row_control_save(control: Control) -> void:
    if control is SpinBox:
        (control as SpinBox).value_changed.connect(func(_value: float) -> void:
            schedule_save()
        )
    elif control is OptionButton:
        (control as OptionButton).item_selected.connect(func(_index: int) -> void:
            schedule_save()
        )


func _wrap_row_control(control: Control) -> MarginContainer:
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", ROW_HORIZONTAL_MARGIN)
    margin.add_theme_constant_override("margin_right", ROW_HORIZONTAL_MARGIN)
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    margin.add_child(control)
    return margin


func _create_row_control(
    row_name: String,
    row_options: Variant,
    row_number_input: String,
    operation: Slot
) -> Control:
    if row_options is Array and not row_options.is_empty():
        var option_button := OptionButton.new()
        for i in row_options.size():
            option_button.add_item(str(row_options[i]), i)
        option_button.selected = 0
        return option_button

    if not row_number_input.is_empty():
        var spin_box := SpinBox.new()
        spin_box.min_value = 0
        match operation:
            Slot.INT, Slot.ADDR:
                spin_box.max_value = 9223372036854775807
            _:
                spin_box.max_value = 100
        var line_edit := spin_box.get_line_edit()
        line_edit.placeholder_text = row_number_input
        line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
        return spin_box

    var label := Label.new()
    label.text = row_name
    label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
    return label


func _get_slot_color(slot: Slot) -> Color:
    var hex := str(SLOT_COLORS.get(slot, "#FFFFFF"))
    return Color.html(hex)


func set_slot_operation(node: GraphNode, row_number: int, op_name: String, is_output: bool) -> void:
    var operation := _parse_operation(op_name)
    var slot_color := _get_slot_color(operation)
    _disconnect_slot(node, row_number, is_output)
    if is_output:
        node.set_slot_enabled_right(row_number, true)
        node.set_slot_type_right(row_number, operation)
        node.set_slot_color_right(row_number, slot_color)
    else:
        node.set_slot_enabled_left(row_number, true)
        node.set_slot_type_left(row_number, operation)
        node.set_slot_color_left(row_number, slot_color)


func _disconnect_slot(node: GraphNode, row_number: int, is_output: bool) -> void:
    var port_index := _port_index_for_slot(node, row_number, is_output)
    if port_index < 0:
        return

    var node_name := node.name
    for conn in get_connection_list():
        var from_name: StringName = conn.get("from_node", conn.get("from"))
        var to_name: StringName = conn.get("to_node", conn.get("to"))
        var from_port: int = conn.get("from_port", 0)
        var to_port: int = conn.get("to_port", 0)
        if is_output and from_name == node_name and from_port == port_index:
            disconnect_node(from_name, from_port, to_name, to_port)
        elif not is_output and to_name == node_name and to_port == port_index:
            disconnect_node(from_name, from_port, to_name, to_port)


func _port_index_for_slot(node: GraphNode, row_number: int, is_output: bool) -> int:
    if is_output:
        for i in node.get_output_port_count():
            if node.get_output_port_slot(i) == row_number:
                return i
    else:
        for i in node.get_input_port_count():
            if node.get_input_port_slot(i) == row_number:
                return i
    return -1


func _parse_operation(op_name: String) -> Slot:
    match op_name:
        "OPERATION_CODE":
            return Slot.OPERATION_CODE
        "INT":
            return Slot.INT
        "ADDR":
            return Slot.ADDR
        "DATA":
            return Slot.DATA
        _:
            push_warning("Unknown operation: %s" % op_name)
            return Slot.OPERATION_CODE


func _parse_op_list(raw_list: Variant) -> Array:
    var result: Array = []
    if raw_list is Array:
        for item in raw_list:
            if item is Dictionary:
                result.append({
                    "operation": _parse_operation(str(item.get("operation", ""))),
                    "type": _parse_slot_type(str(item.get("type", ""))),
                })
    return result


func _parse_slot_type(type_name: String) -> SlotType:
    match type_name.strip_edges():
        "INPUT":
            return SlotType.INPUT
        "OUTPUT":
            return SlotType.OUTPUT
        _:
            push_warning("Unknown slot type: %s" % type_name)
            return SlotType.OUTPUT
