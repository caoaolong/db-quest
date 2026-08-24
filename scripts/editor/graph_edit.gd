extends GraphEdit

# 执行规范（画布 Run 走这三段，按依赖拓扑顺序跑全部节点）：
# pre   DataSplit / 队列源之前的上游（LoadFile / Number / Operation 等）
# queue 从队列源（DataSplit 等）起及其全部下游：按分片数 N 整段跑 N 次
# after 预留（当前为空；下游已并入 queue 波次）

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
# 端口两侧留白，避免点到 Label/输入框时抢走连线热区、误触发拖动节点
const ROW_PORT_SIDE_MARGIN := 28
const PORT_HOTZONE_INNER := 32
const PORT_HOTZONE_OUTER := 40
const SYSTEM_NODE_POSITIONS := {
    "LoadFile": Vector2(40, 80),
}

var _is_restoring := false
var _is_running := false
var _run_spend_ms := 0
var _save_timer: Timer

signal run_spend_changed(total_ms: int)


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

    add_theme_constant_override("port_hotzone_inner_extent", PORT_HOTZONE_INNER)
    add_theme_constant_override("port_hotzone_outer_extent", PORT_HOTZONE_OUTER)

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


# 自定义端口热区：加大可点范围，并不再被行内 Label 等控件抢走点击
func _is_in_output_hotzone(in_node: Variant, in_port: int, mouse_position: Vector2) -> bool:
    return _port_hotzone_contains(in_node as GraphNode, in_port, mouse_position, false)


func _is_in_input_hotzone(in_node: Variant, in_port: int, mouse_position: Vector2) -> bool:
    return _port_hotzone_contains(in_node as GraphNode, in_port, mouse_position, true)


func _port_hotzone_contains(
    graph_node: GraphNode,
    port_idx: int,
    mouse_position: Vector2,
    is_input: bool
) -> bool:
    if graph_node == null or not is_instance_valid(graph_node):
        return false

    var port_local: Vector2
    var slot_index: int
    if is_input:
        port_local = graph_node.get_input_port_position(port_idx)
        slot_index = graph_node.get_input_port_slot(port_idx)
    else:
        port_local = graph_node.get_output_port_position(port_idx)
        slot_index = graph_node.get_output_port_slot(port_idx)

    # 与 GraphEdit 引擎坐标一致：port + position / zoom
    var port_pos := port_local + graph_node.position / zoom
    var inner := float(get_theme_constant("port_hotzone_inner_extent"))
    var outer := float(get_theme_constant("port_hotzone_outer_extent"))

    var slot_height := 28.0
    if slot_index >= 0 and slot_index < graph_node.get_child_count():
        var slot_child := graph_node.get_child(slot_index) as Control
        if slot_child:
            slot_height = maxf(slot_height, slot_child.size.y)

    var hotzone := Rect2(
        port_pos.x - (outer if is_input else inner),
        port_pos.y - slot_height * 0.5,
        inner + outer,
        slot_height
    )
    return hotzone.has_point(mouse_position)


func run_all() -> void:
    if _is_running:
        return
    _is_running = true
    _set_run_spend(0)

    var all_nodes := _collect_enabled_graph_nodes()
    if all_nodes.is_empty():
        EditorLog.info("没有启用的节点可运行")
        _is_running = false
        return

    var order: Array = _compute_execution_order(all_nodes)
    var results: Dictionary = {}

    for graph_node in order:
        var node := _base_node_of(graph_node)
        if node:
            node.queue_index = 0
            node.queue_total = 1
            node.queue_length = 0

    _reset_run_status(_collect_all_graph_nodes())
    for graph_node in order:
        _set_graph_run_status(graph_node, QuestGraphNode.RunStatus.PENDING)

    # 全画布按 pre → queue → after 三段执行
    var phases := _classify_run_phases(order, all_nodes)
    await _run_phase(phases["pre"], results)
    await _run_queue_wave(phases["queue"], results)
    await _run_phase(phases["after"], results)

    _is_running = false


func get_run_spend_ms() -> int:
    return _run_spend_ms


func _set_run_spend(total_ms: int) -> void:
    _run_spend_ms = maxi(0, total_ms)
    run_spend_changed.emit(_run_spend_ms)


func _add_run_spend(delta_ms: int) -> void:
    if delta_ms <= 0:
        return
    _set_run_spend(_run_spend_ms + delta_ms)


func _collect_all_graph_nodes() -> Dictionary:
    var nodes: Dictionary = {}
    for child in get_children():
        if child is GraphNode:
            nodes[String(child.name)] = child
    return nodes


func _collect_enabled_graph_nodes() -> Dictionary:
    var nodes: Dictionary = {}
    for child in get_children():
        if not child is GraphNode:
            continue
        if child is QuestGraphNode and not (child as QuestGraphNode).is_run_enabled():
            continue
        nodes[String(child.name)] = child
    return nodes


func _is_graph_node_enabled(graph_node: GraphNode) -> bool:
    if graph_node is QuestGraphNode:
        return (graph_node as QuestGraphNode).is_run_enabled()
    return true


func _classify_run_phases(order: Array, upstream: Dictionary) -> Dictionary:
    # 队列源（如 DataSplit）及其全部下游都进入波次，按 N 次执行
    var wave_names := {}
    for graph_node in order:
        var node_name := String(graph_node.name)
        if not upstream.has(node_name):
            continue
        if not _is_queue_phase_node(graph_node):
            continue
        var downstream := _collect_downstream_closure(graph_node, upstream)
        for key in downstream.keys():
            wave_names[key] = true

    var pre_nodes: Array = []
    var queue_nodes: Array = []
    for graph_node in order:
        var node_name := String(graph_node.name)
        if not upstream.has(node_name):
            continue
        if wave_names.has(node_name):
            queue_nodes.append(graph_node)
        else:
            pre_nodes.append(graph_node)

    return {
        "pre": pre_nodes,
        "queue": queue_nodes,
        "after": [],
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
            # 仅队列源（DataSplit 等）用 queue_length 扩展波次数
            if node and _is_queue_phase_node(graph_node):
                total = maxi(total, maxi(1, node.queue_length))
        step += 1


func _is_queue_phase_node(graph_node: GraphNode) -> bool:
    var node_type := str(graph_node.get_meta("node_type", ""))
    # DataSplit 输出为 DATA，但仍是队列波次源
    if node_type == "Queue" or node_type == "DataSplit":
        return true
    return _has_queue_output(graph_node) or _has_queue_inbound(graph_node)


func _collect_downstream_closure(start: GraphNode, allowed: Dictionary) -> Dictionary:
    var closure: Dictionary = {}
    var stack: Array = [start]

    while not stack.is_empty():
        var node: GraphNode = stack.pop_back()
        var node_name := String(node.name)
        if closure.has(node_name):
            continue
        if not allowed.has(node_name):
            continue
        closure[node_name] = node

        for conn in get_connection_list():
            var from_name := String(conn.get("from_node", conn.get("from")))
            if from_name != node_name:
                continue
            var to_name := String(conn.get("to_node", conn.get("to")))
            if not allowed.has(to_name) or closure.has(to_name):
                continue
            stack.append(allowed[to_name])

    return closure


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
    if not _is_graph_node_enabled(graph_node):
        return null

    var content: Node = graph_node.get_child(0)
    if not content is BaseNode:
        return null

    _set_graph_run_status(graph_node, QuestGraphNode.RunStatus.RUNNING)
    var node: BaseNode = content as BaseNode
    var inputs: Dictionary = _collect_run_inputs(graph_node, results)
    var spend_ms := node.get_spend()
    await node.play_spend()
    _add_run_spend(spend_ms)
    if not is_instance_valid(graph_node) or not is_instance_valid(node):
        return null
    var result: Variant = await node.run(inputs)
    results[String(graph_node.name)] = result
    _set_graph_run_status(graph_node, QuestGraphNode.RunStatus.DONE)

    var node_type: String = str(graph_node.get_meta("node_type", ""))
    if node_type == "Disk":
        TaskTrigger.handle(TaskTrigger.AFTER_DISK_RUN, self)
    return result


func _reset_run_status(nodes: Dictionary) -> void:
    for graph_node in nodes.values():
        _set_graph_run_status(graph_node, QuestGraphNode.RunStatus.IDLE)


func _set_graph_run_status(graph_node: GraphNode, status: QuestGraphNode.RunStatus) -> void:
    if graph_node is QuestGraphNode:
        (graph_node as QuestGraphNode).set_run_status(status)


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
    return _compute_execution_order(closure)


func _compute_execution_order(closure: Dictionary) -> Array:
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
        EditorLog.warn("Graph cycle detected while computing execution order")
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
    node.run_enable_state_changed.connect(_on_node_run_enabled_changed)

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
    if attributes.has("subtitle"):
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
    var graph_enabled := bool(state.get("graph_enabled", true))
    var node_state := state.duplicate(true)
    node_state.erase("graph_enabled")
    _apply_graph_node_enabled(node, graph_enabled)
    _apply_node_state(content, node_state)
    schedule_save()
    return node


func _apply_graph_node_enabled(graph_node: GraphNode, enabled: bool) -> void:
    if graph_node is QuestGraphNode:
        (graph_node as QuestGraphNode).set_run_enabled(enabled)


func _on_node_run_enabled_changed(_enabled: bool) -> void:
    schedule_save()


func clear_run_data() -> void:
    GameState.read_buffer.clear()
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
        _set_graph_run_status(child as GraphNode, QuestGraphNode.RunStatus.IDLE)
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
    GameState.read_buffer.clear()
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
        var node_entry := {
            "instance_id": String(graph_node.name),
            "template_name": str(graph_node.get_meta("template_name", graph_node.name)),
            "position": {
                "x": graph_node.position_offset.x,
                "y": graph_node.position_offset.y,
            },
            "state": _export_node_state(content),
        }
        if graph_node is QuestGraphNode:
            node_entry["enabled"] = (graph_node as QuestGraphNode).is_run_enabled()
        nodes_data.append(node_entry)

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
            if node_data.has("enabled"):
                state["graph_enabled"] = bool(node_data.get("enabled", true))
            var created := create_node_from_config(
                item,
                str(node_data.get("instance_id", "")),
                node_position,
                state,
                GameState.is_system_node_name(template_name)
            )
            if created == null:
                continue

        for conn in snapshot.get("connections", []):
            if not conn is Dictionary:
                continue
            var from_name := StringName(conn.get("from_node", ""))
            var to_name := StringName(conn.get("to_node", ""))
            if get_node_or_null(NodePath(from_name)) == null:
                continue
            if get_node_or_null(NodePath(to_name)) == null:
                continue
            connect_node(
                from_name,
                int(conn.get("from_port", 0)),
                to_name,
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
    margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
    margin.add_theme_constant_override("margin_left", ROW_PORT_SIDE_MARGIN)
    margin.add_theme_constant_override("margin_right", ROW_PORT_SIDE_MARGIN)
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    if control is Label:
        control.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
