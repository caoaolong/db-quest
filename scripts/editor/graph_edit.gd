extends GraphEdit

enum SlotType {
    INPUT,
    OUTPUT,
}

enum Slot {
    OPERATION_CODE,
    INT,
    DATA,
}

const SLOT_COLORS: Dictionary = {
    Slot.OPERATION_CODE: "#F59E0B",
    Slot.INT: "#3B82F6",
    Slot.DATA: "#A855F7",
}

const node_style = preload("res://node/node_style.tres")
const ROW_HORIZONTAL_MARGIN := 12
const SYSTEM_CHECK_POSITION := Vector2(520, 280)

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


func run_node(target: GraphNode) -> void:
    var order: Array = compute_execution_order(target)
    if order.is_empty():
        order = [target]

    var results: Dictionary = {}
    print("开始执行（目标节点: %s）" % target.name)

    for index in order.size():
        var graph_node: GraphNode = order[index]
        print("[%d] %s (%s)" % [
            index + 1,
            graph_node.name,
            str(graph_node.get_meta("template_name", graph_node.name)),
        ])
        _execute_graph_node(graph_node, results)


func run_split_node(target: GraphNode) -> void:
    var split_content: DataSplitNode = target.get_child(0) as DataSplitNode
    if split_content == null:
        run_node(target)
        return

    var order: Array = compute_execution_order(target)
    var results: Dictionary = {}

    for graph_node in order:
        if graph_node == target:
            break
        _execute_graph_node(graph_node, results)

    var inputs: Dictionary = _collect_run_inputs(target, results)
    var source_data: Variant = _first_input_value(inputs)
    if source_data == null:
        EditorLog.warn("数据分割：未收到 DATA 输入")
        return

    var chunks: Array = DataSplitNode.split_data(source_data, split_content.get_chunk_size())
    if chunks.is_empty():
        EditorLog.warn("数据分割：无有效数据")
        return

    EditorLog.info("数据分割：共 %d 块" % chunks.size())
    for index in chunks.size():
        EditorLog.info("--- 执行第 %d/%d 块 ---" % [index + 1, chunks.size()])
        var batch_results: Dictionary = results.duplicate(true)
        batch_results[String(target.name)] = chunks[index]
        print("  %s: %s" % [target.name, chunks[index]])
        _execute_downstream_from(target, batch_results)


func _execute_graph_node(graph_node: GraphNode, results: Dictionary) -> Variant:
    var content: Node = graph_node.get_child(0)
    if not content is BaseNode:
        print("  结果: （未实现 run）")
        return null

    var node: BaseNode = content as BaseNode
    var inputs: Dictionary = _collect_run_inputs(graph_node, results)
    var result: Variant = node.run(inputs)
    results[String(graph_node.name)] = result
    print("  结果: %s" % result)

    var node_type: String = str(graph_node.get_meta("node_type", ""))
    if node_type == "Disk":
        TaskTrigger.handle(TaskTrigger.AFTER_DISK_RUN, self)
    return result


func _execute_downstream_from(source: GraphNode, results: Dictionary) -> void:
    var closure: Dictionary = _collect_downstream_closure(source)
    var order: Array = _topological_order_subset(closure)
    for graph_node in order:
        if graph_node == source:
            continue
        _execute_graph_node(graph_node, results)


func _collect_downstream_closure(source: GraphNode) -> Dictionary:
    var closure: Dictionary = {}
    var stack: Array[GraphNode] = [source]

    while not stack.is_empty():
        var node: GraphNode = stack.pop_back()
        var node_name := String(node.name)
        if closure.has(node_name):
            continue
        closure[node_name] = node

        for downstream in _get_direct_downstream_nodes(node):
            stack.append(downstream)

    return closure


func _get_direct_downstream_nodes(graph_node: GraphNode) -> Array:
    var result: Array = []
    var seen: Dictionary = {}
    var node_name := String(graph_node.name)

    for conn in get_connection_list():
        var from_name := String(conn.get("from_node", conn.get("from")))
        if from_name != node_name:
            continue

        var to_name := String(conn.get("to_node", conn.get("to")))
        if seen.has(to_name):
            continue
        seen[to_name] = true

        var to_node := get_node_or_null(NodePath(to_name)) as GraphNode
        if to_node:
            result.append(to_node)

    return result


func _topological_order_subset(closure: Dictionary) -> Array:
    var in_degree: Dictionary = {}
    var adjacency: Dictionary = {}
    for node_name in closure.keys():
        in_degree[node_name] = 0
        adjacency[node_name] = []

    for conn in get_connection_list():
        var from_name := String(conn.get("from_node", conn.get("from")))
        var to_name := String(conn.get("to_node", conn.get("to")))
        if not closure.has(from_name) or not closure.has(to_name):
            continue
        adjacency[from_name].append(to_name)
        in_degree[to_name] = int(in_degree[to_name]) + 1

    var ready_queue: Array[String] = []
    for node_name in closure.keys():
        if int(in_degree[node_name]) == 0:
            ready_queue.append(node_name)
    ready_queue.sort()

    var order: Array = []
    while not ready_queue.is_empty():
        var node_name: String = ready_queue.pop_front()
        order.append(closure[node_name])
        for next_name in adjacency[node_name]:
            in_degree[next_name] = int(in_degree[next_name]) - 1
            if int(in_degree[next_name]) == 0:
                ready_queue.append(next_name)
        ready_queue.sort()

    return order


func _first_input_value(inputs: Dictionary) -> Variant:
    if inputs.is_empty():
        return null
    var keys: Array = inputs.keys()
    keys.sort()
    return inputs[keys[0]]


func _collect_run_inputs(graph_node: GraphNode, results: Dictionary) -> Dictionary:
    var inputs := {}
    var node_name := String(graph_node.name)

    for conn in get_connection_list():
        var to_name := String(conn.get("to_node", conn.get("to")))
        if to_name != node_name:
            continue

        var from_name := String(conn.get("from_node", conn.get("from")))
        var to_port := int(conn.get("to_port", 0))
        if results.has(from_name):
            inputs[str(to_port)] = results[from_name]

    return inputs


func compute_execution_order(target: GraphNode) -> Array:
    var closure := _collect_upstream_closure(target)
    if closure.is_empty():
        return [target]

    var in_degree: Dictionary = {}
    var adjacency: Dictionary = {}
    for node_name in closure.keys():
        in_degree[node_name] = 0
        adjacency[node_name] = []

    for conn in get_connection_list():
        var from_name := String(conn.get("from_node", conn.get("from")))
        var to_name := String(conn.get("to_node", conn.get("to")))
        if not closure.has(from_name) or not closure.has(to_name):
            continue
        adjacency[from_name].append(to_name)
        in_degree[to_name] = int(in_degree[to_name]) + 1

    var ready_queue: Array[String] = []
    for node_name in closure.keys():
        if int(in_degree[node_name]) == 0:
            ready_queue.append(node_name)
    ready_queue.sort()

    var order: Array = []
    while not ready_queue.is_empty():
        var node_name: String = ready_queue.pop_front()
        order.append(closure[node_name])
        for next_name in adjacency[node_name]:
            in_degree[next_name] = int(in_degree[next_name]) - 1
            if int(in_degree[next_name]) == 0:
                ready_queue.append(next_name)
        ready_queue.sort()

    if order.size() != closure.size():
        EditorLog.warn("Graph cycle detected while computing execution order for: %s" % target.name)
        for node_name in closure.keys():
            var graph_node: GraphNode = closure[node_name]
            if not graph_node in order:
                order.append(graph_node)

    return order


func _collect_upstream_closure(target: GraphNode) -> Dictionary:
    var closure: Dictionary = {}
    var stack: Array[GraphNode] = [target]

    while not stack.is_empty():
        var node: GraphNode = stack.pop_back()
        var node_name := String(node.name)
        if closure.has(node_name):
            continue
        closure[node_name] = node

        for upstream in _get_direct_upstream_nodes(node):
            stack.append(upstream)

    return closure


func _get_direct_upstream_nodes(graph_node: GraphNode) -> Array:
    var result: Array = []
    var seen: Dictionary = {}
    var node_name := String(graph_node.name)

    for conn in get_connection_list():
        var to_name := String(conn.get("to_node", conn.get("to")))
        if to_name != node_name:
            continue

        var from_name := String(conn.get("from_node", conn.get("from")))
        if seen.has(from_name):
            continue
        seen[from_name] = true

        var from_node := get_node_or_null(NodePath(from_name)) as GraphNode
        if from_node:
            result.append(from_node)

    return result


func has_node_type(node_type: String) -> bool:
    if node_type.is_empty():
        return false

    for child in get_children():
        if not child is GraphNode:
            continue

        if str((child as GraphNode).get_meta("node_type", "")) == node_type:
            return true

    return false


func create_node_from_config(
    item: Dictionary,
    instance_id: String = "",
    node_position: Variant = null,
    state: Dictionary = {},
    allow_system: bool = false
) -> GraphNode:
    var config := GameState.resolve_node_config(item)
    if config.is_empty():
        return null

    var template_name := str(config.get("name", ""))
    var node_type := str(config.get("type", ""))
    var category := str(config.get("category", ""))

    if category == "System" and not allow_system:
        EditorLog.warn("系统节点不支持手动创建")
        return null

    if category != "System" and not GameState.is_node_available(template_name):
        EditorLog.warn("Node is not available in current level: %s" % template_name)
        return null

    if bool(config.get("unique", false)) and has_node_type(node_type):
        var node_label := str(config.get("label", node_type))
        EditorLog.warn("画布中只能存在一个 %s 节点" % node_label)
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
    var node := QuestGraphNode.new()
    if instance_id.is_empty():
        instance_id = _generate_instance_id(template_name)
    node.name = instance_id
    node.set_meta("template_name", template_name)
    node.set_meta("node_type", node_type)
    node.add_theme_stylebox_override("panel", node_style)

    var content := scene.instantiate() as Control
    if content is BaseNode:
        (content as BaseNode).category = str(config.get("category", ""))
    _apply_node_attributes(content, attributes, config, node)
    content.set_anchors_preset(Control.PRESET_FULL_RECT)
    content.offset_left = 0
    content.offset_top = 0
    content.offset_right = 0
    content.offset_bottom = 0
    node.add_child(content)
    if attributes.has("subtitle") and not content is CheckNode:
        _set_subtitle(content, str(attributes["subtitle"]))
    node.set_slot_enabled_left(0, false)
    node.set_slot_enabled_right(0, false)

    _build_node_rows(node, attributes)

    if content is CheckNode:
        (content as CheckNode).call_deferred("refresh_display")

    if node_position is Vector2:
        node.position_offset = node_position
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
    _is_restoring = true
    clear_graph()

    var snapshot := GraphSnapshot.load(GameState.current_level)
    if not snapshot.is_empty():
        for node_data in snapshot.get("nodes", []):
            if not node_data is Dictionary:
                continue

            var template_name := str(node_data.get("template_name", ""))
            var item := GameState.get_node_create_item(template_name)
            if item.is_empty():
                continue

            var position_dict: Dictionary = node_data.get("position", {})
            var node_position := Vector2(
                float(position_dict.get("x", 0.0)),
                float(position_dict.get("y", 0.0))
            )
            var state: Dictionary = node_data.get("state", {})
            create_node_from_config(
                item,
                str(node_data.get("instance_id", "")),
                node_position,
                state,
                GameState.is_system_node_name(template_name)
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

    _ensure_system_nodes()
    _is_restoring = false
    schedule_save()


func _ensure_system_nodes() -> void:
    if has_node_type("Check"):
        return

    var item := GameState.get_node_create_item("Check")
    if item.is_empty():
        return

    create_node_from_config(item, "Check", SYSTEM_CHECK_POSITION, {}, true)


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


func _apply_node_attributes(content: Control, attributes: Dictionary, config: Dictionary, graph_node: GraphNode) -> void:
    if content is DiskNode:
        var disk_node := content as DiskNode
        if attributes.has("title"):
            disk_node.title = str(attributes["title"])
        graph_node.title = disk_node.title
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
    var op_list := _parse_op_list(row.get("op_list", []))
    create_node_row(
        node,
        int(row.get("row_number", 0)),
        str(row.get("row_name", "")),
        op_list,
        row.get("row_options", []),
        str(row.get("row_number_input", ""))
    )


func create_node_row(
    node: GraphNode,
    _row_number: int,
    row_name: String,
    op_list: Array,
    row_options: Variant = [],
    row_number_input: String = ""
) -> int:
    var operation := _resolve_row_operation(op_list)
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
            Slot.INT:
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
        "DATA":
            return Slot.DATA
        _:
            EditorLog.warn("Unknown operation: %s" % op_name)
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


func _resolve_row_operation(op_list: Array) -> Slot:
    if op_list.is_empty():
        return Slot.OPERATION_CODE

    for op in op_list:
        if op.type == SlotType.INPUT:
            return op.operation

    return op_list[0].operation


func _parse_slot_type(type_name: String) -> SlotType:
    match type_name.strip_edges():
        "INPUT":
            return SlotType.INPUT
        "OUTPUT":
            return SlotType.OUTPUT
        _:
            EditorLog.warn("Unknown slot type: %s" % type_name)
            return SlotType.OUTPUT
