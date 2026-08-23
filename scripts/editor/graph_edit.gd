extends GraphEdit

# 执行规范（任意节点点 Run 都走这三段，只跑目标及其上游）：
# pre   普通上游，不参与队列投递（LoadFile / Number / Operation / Data 等）
# queue 队列波次：Queue 类型，或带 QUEUE 口 / 从 QUEUE 取数的节点（Split / Merge / 接队列的 Disk）
# after 队列收敛之后的下游（Merge 之后的 Check 等）

enum SlotType {
    INPUT,
    OUTPUT,
}

enum Slot {
    OPERATION_CODE,
    INT,
    DATA,
    QUEUE,
}

const SLOT_COLORS: Dictionary = {
    Slot.OPERATION_CODE: "#F59E0B",
    Slot.INT: "#3B82F6",
    Slot.DATA: "#A855F7",
    Slot.QUEUE: "#14B8A6",
}

const node_style = preload("res://node/node_style.tres")
const ROW_HORIZONTAL_MARGIN := 12
const SYSTEM_NODE_POSITIONS := {
    "Check": Vector2(520, 280),
    "LoadFile": Vector2(40, 80),
}

var _is_restoring := false
var _is_running := false
var _save_timer: Timer


func _ready() -> void:
    connection_request.connect(_on_connection_request)
    disconnection_request.connect(_on_disconnection_request)
    popup_request.connect(_on_popup_request)
    end_node_move.connect(_on_end_node_move)
    delete_nodes_request.connect(_on_delete_nodes_request)

    _save_timer = Timer.new()
    _save_timer.one_shot = true
    _save_timer.wait_time = 0.3
    _save_timer.timeout.connect(_save_snapshot)
    add_child(_save_timer)

    add_valid_connection_type(Slot.QUEUE, Slot.DATA)
    add_valid_connection_type(Slot.DATA, Slot.QUEUE)

    call_deferred("load_snapshot")


func is_restoring() -> bool:
    return _is_restoring


func schedule_save() -> void:
    if _is_restoring:
        return
    _save_timer.start()


func _on_end_node_move() -> void:
    schedule_save()


func _on_delete_nodes_request(nodes: Array) -> void:
    for node_name in nodes:
        var graph_node := get_node_or_null(NodePath(str(node_name))) as GraphNode
        if graph_node == null:
            continue
        if GameState.is_system_node_name(str(graph_node.get_meta("template_name", ""))):
            continue
        graph_node.queue_free()
    schedule_save()


func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
    if from_node == to_node:
        return

    var from_graph_node := get_node_or_null(NodePath(from_node)) as GraphNode
    var to_graph_node := get_node_or_null(NodePath(to_node)) as GraphNode
    if from_graph_node == null or to_graph_node == null:
        return
    var from_type := from_graph_node.get_output_port_type(from_port)
    var to_type := to_graph_node.get_input_port_type(to_port)
    if from_type != to_type and not is_valid_connection_type(from_type, to_type):
        return

    connect_node(from_node, from_port, to_node, to_port)
    schedule_save()


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
    disconnect_node(from_node, from_port, to_node, to_port)
    schedule_save()


func _on_popup_request(at_position: Vector2) -> void:
    var conn := get_closest_connection_at_point(at_position, 12.0)
    if conn.is_empty():
        return

    disconnect_node(
        conn.get("from_node"),
        int(conn.get("from_port", 0)),
        conn.get("to_node"),
        int(conn.get("to_port", 0))
    )
    schedule_save()


func run_node(target: GraphNode) -> void:
    if _is_running:
        return
    _is_running = true

    var upstream := _collect_upstream_closure(target)
    if upstream.is_empty():
        upstream[String(target.name)] = target

    var order: Array = compute_execution_order(target)
    var results: Dictionary = {}

    for graph_node in order:
        var node := _base_node_of(graph_node)
        if node:
            node.queue_index = 0
            node.queue_total = 1
            node.queue_length = 0

    # 任意节点点 Run 都按 pre → queue → after 三段执行
    var phases := _classify_run_phases(order, upstream)
    await _run_phase(phases["pre"], results)
    await _run_queue_wave(phases["queue"], results)
    await _run_phase(phases["after"], results)

    _is_running = false


func _classify_run_phases(order: Array, upstream: Dictionary) -> Dictionary:
    var queue_nodes: Array = []
    var queue_names := {}
    for graph_node in order:
        var node_name := String(graph_node.name)
        if not upstream.has(node_name):
            continue
        if _is_queue_phase_node(graph_node):
            queue_nodes.append(graph_node)
            queue_names[node_name] = true

    var after_names := _collect_nodes_after_queue(queue_nodes, upstream)
    var pre_nodes: Array = []
    var after_nodes: Array = []
    for graph_node in order:
        var node_name := String(graph_node.name)
        if not upstream.has(node_name) or queue_names.has(node_name):
            continue
        if after_names.has(node_name):
            after_nodes.append(graph_node)
        else:
            pre_nodes.append(graph_node)

    return {
        "pre": pre_nodes,
        "queue": queue_nodes,
        "after": after_nodes,
    }


func _run_phase(graph_nodes: Array, results: Dictionary) -> void:
    for graph_node in graph_nodes:
        if not is_instance_valid(graph_node):
            continue
        await _execute_graph_node(graph_node, results)


func _run_queue_wave(queue_nodes: Array, results: Dictionary) -> void:
    if queue_nodes.is_empty():
        return

    var total := 1
    var step := 0
    while step < total:
        for graph_node in queue_nodes:
            if not is_instance_valid(graph_node):
                continue
            var node := _base_node_of(graph_node)
            if node:
                node.queue_index = step
                node.queue_total = total
            await _execute_graph_node(graph_node, results)
            if node and _is_queue_phase_node(graph_node):
                total = maxi(total, maxi(1, node.queue_length))
        step += 1


func _is_queue_phase_node(graph_node: GraphNode) -> bool:
    if str(graph_node.get_meta("node_type", "")) == "Queue":
        return true
    return _has_queue_output(graph_node) or _has_queue_inbound(graph_node)


func _collect_nodes_after_queue(queue_nodes: Array, allowed: Dictionary) -> Dictionary:
    var after_names := {}
    if queue_nodes.is_empty():
        return after_names

    var visited := {}
    var stack: Array = []
    for graph_node in queue_nodes:
        stack.append(graph_node)
        visited[String(graph_node.name)] = true

    while not stack.is_empty():
        var node: GraphNode = stack.pop_back()
        var node_name := String(node.name)
        for conn in get_connection_list():
            var from_name := String(conn.get("from_node", conn.get("from")))
            if from_name != node_name:
                continue
            var to_name := String(conn.get("to_node", conn.get("to")))
            if not allowed.has(to_name) or visited.has(to_name):
                continue
            visited[to_name] = true
            var to_node: GraphNode = allowed[to_name]
            stack.append(to_node)
            if not _is_queue_phase_node(to_node):
                after_names[to_name] = true

    return after_names


func _has_queue_output(graph_node: GraphNode) -> bool:
    for port_index in graph_node.get_output_port_count():
        if graph_node.get_output_port_type(port_index) == int(Slot.QUEUE):
            return true
    return false


func _has_queue_inbound(graph_node: GraphNode) -> bool:
    var node_name := String(graph_node.name)
    for conn in get_connection_list():
        var to_name := String(conn.get("to_node", conn.get("to")))
        if to_name != node_name:
            continue
        var from_name := String(conn.get("from_node", conn.get("from")))
        var from_port := int(conn.get("from_port", 0))
        var from_node := get_node_or_null(NodePath(from_name)) as GraphNode
        if from_node and from_node.get_output_port_type(from_port) == int(Slot.QUEUE):
            return true
    return false


func _base_node_of(graph_node: GraphNode) -> BaseNode:
    if graph_node == null or graph_node.get_child_count() == 0:
        return null
    return graph_node.get_child(0) as BaseNode


func _execute_graph_node(graph_node: GraphNode, results: Dictionary) -> Variant:
    if not is_instance_valid(graph_node):
        return null

    var content: Node = graph_node.get_child(0)
    if not content is BaseNode:
        return null

    var node: BaseNode = content as BaseNode
    var inputs: Dictionary = _collect_run_inputs(graph_node, results)
    await node.play_spend()
    if not is_instance_valid(graph_node) or not is_instance_valid(node):
        return null
    var result: Variant = await node.run(inputs)
    results[String(graph_node.name)] = result

    var node_type: String = str(graph_node.get_meta("node_type", ""))
    if node_type == "Disk":
        TaskTrigger.handle(TaskTrigger.AFTER_DISK_RUN, self)
    return result


func _collect_run_inputs(graph_node: GraphNode, results: Dictionary) -> Dictionary:
    var inputs := {}
    var node_name := String(graph_node.name)

    for conn in get_connection_list():
        var to_name := String(conn.get("to_node", conn.get("to")))
        if to_name != node_name:
            continue

        var from_name := String(conn.get("from_node", conn.get("from")))
        var from_port := int(conn.get("from_port", 0))
        var to_port := int(conn.get("to_port", 0))
        if results.has(from_name):
            inputs[str(to_port)] = _pick_output_value(results[from_name], from_port)

    return inputs


func compute_execution_order(target: GraphNode) -> Array:
    # 执行顺序只包含目标节点及其上游，不包含下游
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
        if not _is_restoring:
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
        (content as BaseNode).spend = int(config.get("spend", 0))
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

    if content.has_method("refresh_display"):
        content.call_deferred("refresh_display")

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


func clear_run_data() -> void:
    for child in get_children():
        if not child is GraphNode:
            continue
        if child.get_child_count() == 0:
            continue
        var content := child.get_child(0)
        if content is BaseNode:
            var base_node := content as BaseNode
            base_node.clear_run_data()
            if base_node.action:
                base_node.action.reset_progress()
    schedule_save()


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


func restart_graph() -> void:
    _is_restoring = true
    if _save_timer:
        _save_timer.stop()
    clear_graph()
    _ensure_system_nodes()
    _is_restoring = false
    _save_snapshot()


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

    var snapshot := GraphSnapshot.load_or_inherit(GameState.current_level)
    if not snapshot.is_empty():
        for node_data in snapshot.get("nodes", []):
            if not node_data is Dictionary:
                continue

            var template_name := str(node_data.get("template_name", ""))
            if not GameState.should_spawn_system_node(template_name):
                continue

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


func _pick_output_value(result: Variant, from_port: int) -> Variant:
    if result is Dictionary and result.has("__outputs"):
        var outputs: Variant = result["__outputs"]
        if outputs is Dictionary:
            return (outputs as Dictionary).get(str(from_port), null)
    return result


func _ensure_system_nodes() -> void:
    for item in GameState.get_node_list():
        if not item is Dictionary:
            continue
        if str(item.get("category", "")) != "System":
            continue

        var template_name := str(item.get("name", ""))
        if not GameState.should_spawn_system_node(template_name):
            continue

        var node_type := str(item.get("type", template_name))
        if has_node_type(node_type):
            continue

        var create_item := GameState.get_node_create_item(template_name)
        if create_item.is_empty():
            continue

        var _position: Vector2 = SYSTEM_NODE_POSITIONS.get(template_name, Vector2(40, 280))
        create_node_from_config(create_item, template_name, _position, {}, true)


func _exit_tree() -> void:
    _save_snapshot()


func _save_snapshot() -> void:
    if _is_restoring:
        return
    GraphSnapshot.save(GameState.current_level, export_snapshot())


func _generate_instance_id(template_name: String) -> String:
    var index := 1
    while has_node(NodePath("%s_%d"% [template_name, index])):
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
        if not op is Dictionary:
            continue
        var slot_operation: Slot = op["operation"] as Slot
        var port_kind: SlotType = op["type"] as SlotType
        var slot_color := _get_slot_color(slot_operation)
        match port_kind:
            SlotType.INPUT:
                node.set_slot_enabled_left(slot_index, true)
                node.set_slot_type_left(slot_index, slot_operation)
                node.set_slot_color_left(slot_index, slot_color)
            SlotType.OUTPUT:
                node.set_slot_enabled_right(slot_index, true)
                node.set_slot_type_right(slot_index, slot_operation)
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
                spin_box.max_value = 1_000_000_000
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
        "QUEUE":
            return Slot.QUEUE
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
        if not op is Dictionary:
            continue
        var port_kind: SlotType = op["type"] as SlotType
        if port_kind == SlotType.INPUT:
            return op["operation"] as Slot

    var first: Variant = op_list[0]
    if first is Dictionary:
        return first["operation"] as Slot
    return Slot.OPERATION_CODE


func _parse_slot_type(type_name: String) -> SlotType:
    match type_name.strip_edges():
        "INPUT":
            return SlotType.INPUT
        "OUTPUT":
            return SlotType.OUTPUT
        _:
            EditorLog.warn("Unknown slot type: %s" % type_name)
            return SlotType.OUTPUT
