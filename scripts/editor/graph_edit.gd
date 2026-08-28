extends GraphEdit

# 执行规范（画布 Run 走这三段，按依赖拓扑顺序跑全部节点）：
# pre   DataSplit / 队列源之前的上游（LoadFile / Number / LoadString 等）
# queue 从队列源（DataSplit 等）起及其全部下游：按分片数 N 整段跑 N 次
# after 预留（当前为空；下游已并入 queue 波次）

enum SlotType {
    INPUT,
    OUTPUT,
}

enum Slot {
    OPERATION_CODE,
    DATA,
    QUEUE,
    UNION,
    UINT8,
    UINT16,
    UINT32,
    UINT64,
    PAGE_DATA,
    FUNCTION,
    REFER,
}

const SLOT_COLORS: Dictionary = {
    Slot.OPERATION_CODE: "#F59E0B",
    Slot.DATA: "#A855F7",
    Slot.QUEUE: "#14B8A6",
    Slot.UNION: "#EC4899",
    Slot.UINT8: "#86EFAC",
    Slot.UINT16: "#38BDF8",
    Slot.UINT32: "#818CF8",
    Slot.UINT64: "#3B82F6",
    Slot.PAGE_DATA: "#F97316",
    Slot.FUNCTION: "#22D3EE",
    Slot.REFER: "#FBBF24",
}

const UINT_SLOT_WIDTHS: Dictionary = {
    Slot.UINT8: 1,
    Slot.UINT16: 2,
    Slot.UINT32: 4,
    Slot.UINT64: 8,
}

const node_style = preload("res://node/node_style.tres")
# 端口两侧留白，避免点到 Label/输入框时抢走连线热区、误触发拖动节点
const ROW_PORT_SIDE_MARGIN := 28 # 与 BaseNode.BODY_SIDE_MARGIN 保持一致
const ROW_LABEL_MIN_WIDTH := 72
const SELF_REFER_SLOT := 0
const CONTENT_SLOT := 1
const FIRST_DATA_SLOT := 2
const REFER_COLORS := [
    "#38BDF8",
    "#A855F7",
    "#34D399",
    "#F97316",
    "#F43F5E",
    "#818CF8",
    "#14B8A6",
    "#EAB308",
]
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
    connection_from_empty.connect(_on_connection_from_empty)
    connection_to_empty.connect(_on_connection_to_empty)
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
    add_valid_connection_type(Slot.FUNCTION, Slot.REFER)
    add_valid_connection_type(Slot.REFER, Slot.FUNCTION)
    _register_uint_widening_connections()
    _register_uint_to_data_connections()
    _register_union_connections()

    add_theme_constant_override("port_hotzone_inner_extent", PORT_HOTZONE_INNER)
    add_theme_constant_override("port_hotzone_outer_extent", PORT_HOTZONE_OUTER)

    call_deferred("load_snapshot")


func _register_uint_widening_connections() -> void:
    var uint_slots: Array = [Slot.UINT8, Slot.UINT16, Slot.UINT32, Slot.UINT64]
    for from_slot in uint_slots:
        for to_slot in uint_slots:
            if int(UINT_SLOT_WIDTHS.get(from_slot, 0)) < int(UINT_SLOT_WIDTHS.get(to_slot, 0)):
                add_valid_connection_type(from_slot, to_slot)


func _register_uint_to_data_connections() -> void:
    for from_slot in [Slot.UINT8, Slot.UINT16, Slot.UINT32, Slot.UINT64]:
        add_valid_connection_type(from_slot, Slot.DATA)
    add_valid_connection_type(Slot.OPERATION_CODE, Slot.DATA)


func _register_union_connections() -> void:
    for from_slot in [
        Slot.DATA,
        Slot.OPERATION_CODE,
        Slot.PAGE_DATA,
        Slot.UINT8,
        Slot.UINT16,
        Slot.UINT32,
        Slot.UINT64,
    ]:
        add_valid_connection_type(from_slot, Slot.UNION)


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
        var template_name := str(graph_node.get_meta("template_name", ""))
        if GameState.is_system_node_name(template_name):
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
    if _can_connect_function_bind(from_graph_node, from_port, to_graph_node, to_port):
        connect_node(from_node, from_port, to_node, to_port)
        _sync_adapter_from_function_bind(from_graph_node, from_port, to_graph_node, to_port)
        schedule_save()
        return
    if not _can_connect_refer(from_graph_node, from_port, to_graph_node, to_port, from_type, to_type):
        return

    connect_node(from_node, from_port, to_node, to_port)
    schedule_save()


func _on_connection_from_empty(to_node: StringName, to_port: int, release_position: Vector2) -> void:
    var host := get_node_or_null(NodePath(to_node)) as GraphNode
    if host == null:
        return
    var slot_index := host.get_input_port_slot(to_port)
    if not is_function_member_slot(host, slot_index):
        return
    _spawn_function_adapter(host, slot_index, to_port, release_position)


func _on_connection_to_empty(from_node: StringName, from_port: int, release_position: Vector2) -> void:
    var host := get_node_or_null(NodePath(from_node)) as GraphNode
    if host == null:
        return
    var slot_index := host.get_output_port_slot(from_port)
    if not is_function_member_slot(host, slot_index):
        return
    var input_port := _function_slot_input_port(host, slot_index)
    if input_port < 0:
        return
    _spawn_function_adapter(host, slot_index, input_port, release_position)


func _spawn_function_adapter(
    host: GraphNode,
    host_slot: int,
    host_input_port: int,
    release_position: Vector2
) -> void:
    var info := _function_slot_info(host, host_slot)
    if info.is_empty():
        return

    var item := GameState.get_node_create_item("FunctionAdapter")
    if item.is_empty():
        return

    var created := create_node_from_config(
        item,
        "",
        _graph_position_from_local(release_position),
        {
            "function_owner": str(info.get("owner", "")),
            "function_name": str(info.get("name", "")),
        },
        false,
        true
    )
    if created == null:
        return

    var adapter_port := _self_refer_output_port(created)
    if adapter_port < 0 or host_input_port < 0:
        return
    if not _can_connect_function_bind(created, adapter_port, host, host_input_port):
        return
    connect_node(created.name, adapter_port, host.name, host_input_port)
    schedule_save()


func _graph_position_from_local(local_position: Vector2) -> Vector2:
    return (local_position + scroll_offset) / zoom


func _function_slot_info(node: GraphNode, slot_index: int) -> Dictionary:
    if not is_function_member_slot(node, slot_index):
        return {}
    var child := node.get_child(slot_index)
    var function_name := str(child.get_meta("function_name", "")).strip_edges()
    if function_name.is_empty():
        return {}
    return {
        "owner": str(node.get_meta("template_name", "")).strip_edges(),
        "name": function_name,
    }


func _function_slot_input_port(node: GraphNode, slot_index: int) -> int:
    if node == null:
        return -1
    for port_index in node.get_input_port_count():
        if node.get_input_port_slot(port_index) == slot_index:
            return port_index
    return -1


func _self_refer_output_port(node: GraphNode) -> int:
    if node == null:
        return -1
    for port_index in node.get_output_port_count():
        if node.get_output_port_slot(port_index) == SELF_REFER_SLOT:
            return port_index
    return -1


func _sync_adapter_from_function_bind(
    from_node: GraphNode,
    from_port: int,
    to_node: GraphNode,
    to_port: int
) -> void:
    var from_slot := from_node.get_output_port_slot(from_port)
    var to_slot := to_node.get_input_port_slot(to_port)
    if is_function_adapter(from_node) and is_function_member_slot(to_node, to_slot):
        _apply_adapter_function(from_node, to_node, to_slot)
    elif is_function_adapter(to_node) and is_function_member_slot(from_node, from_slot):
        _apply_adapter_function(to_node, from_node, from_slot)


func _apply_adapter_function(adapter_node: GraphNode, host: GraphNode, host_slot: int) -> void:
    var info := _function_slot_info(host, host_slot)
    if info.is_empty():
        return
    var adapter := _base_node_of(adapter_node)
    if adapter is FunctionAdapterNode:
        (adapter as FunctionAdapterNode).bind_function(
            str(info.get("owner", "")),
            str(info.get("name", ""))
        )


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

    TaskTrigger.handle(TaskTrigger.AFTER_RUN, self)
    TaskTrigger.reevaluate([
        TaskTrigger.AFTER_VD_READ,
        TaskTrigger.AFTER_VF_READ,
        TaskTrigger.AFTER_VF_WRITE,
    ], self)

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
            var pair := _execution_pair_for_connection(conn)
            var from_name := str(pair.get("from", ""))
            if from_name != node_name:
                continue
            var to_name := str(pair.get("to", ""))
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
    if graph_node == null:
        return null
    for child in graph_node.get_children():
        if child is BaseNode:
            return child as BaseNode
    return null


func _execute_graph_node(graph_node: GraphNode, results: Dictionary) -> Variant:
    if not is_instance_valid(graph_node):
        return null
    if not _is_graph_node_enabled(graph_node):
        return null

    var content := _base_node_of(graph_node)
    if content == null:
        return null

    _set_graph_run_status(graph_node, QuestGraphNode.RunStatus.RUNNING)
    var node: BaseNode = content as BaseNode
    var inputs: Dictionary = _collect_run_inputs(graph_node, results)
    var node_type := str(graph_node.get_meta("node_type", ""))
    var spend_ms := node.get_spend()
    await node.play_spend()
    _add_run_spend(spend_ms)
    if not is_instance_valid(graph_node) or not is_instance_valid(node):
        return null
    var result: Variant = await node.run(inputs)
    results[String(graph_node.name)] = result
    _set_graph_run_status(graph_node, QuestGraphNode.RunStatus.DONE)

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
        var pair := _execution_pair_for_connection(conn)
        var from_name := str(pair.get("from", ""))
        var to_name := str(pair.get("to", ""))
        if from_name.is_empty() or to_name.is_empty():
            continue
        if not closure.has(from_name) or not closure.has(to_name):
            continue
        adjacency[from_name].append(to_name)
        in_degree[to_name] = int(in_degree[to_name]) + 1

    _apply_file_page_input_order_constraints(closure, in_degree, adjacency)

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


## 同一 FilePage 的上游节点按 In 1 → In 2 → … 顺序串行执行。
func _apply_file_page_input_order_constraints(
    closure: Dictionary,
    in_degree: Dictionary,
    adjacency: Dictionary
) -> void:
    for node_name in closure.keys():
        var graph_node: GraphNode = closure[node_name]
        if str(graph_node.get_meta("node_type", "")) != "FilePage":
            continue

        var base := _base_node_of(graph_node)
        if base == null:
            continue

        var count := clampi(int(base.data.get("input_count", 1)), 1, 16)
        var prev_source := ""
        for input_index in count:
            var slot_index := FilePageNode.FIRST_INPUT_SLOT + input_index
            var source_name := _find_connected_source_for_slot(graph_node, slot_index)
            if source_name.is_empty() or not closure.has(source_name):
                continue
            if not prev_source.is_empty() and prev_source != source_name:
                _add_execution_edge(prev_source, source_name, in_degree, adjacency)
            prev_source = source_name


func _find_connected_source_for_slot(file_page: GraphNode, slot_index: int) -> String:
    var target_port := -1
    for port in file_page.get_input_port_count():
        if file_page.get_input_port_slot(port) == slot_index:
            target_port = port
            break
    if target_port == -1:
        return ""

    var file_page_name := String(file_page.name)
    for conn in get_connection_list():
        if String(conn.get("to_node", conn.get("to"))) != file_page_name:
            continue
        if int(conn.get("to_port", 0)) != target_port:
            continue
        return String(conn.get("from_node", conn.get("from")))
    return ""


func _add_execution_edge(
    from_name: String,
    to_name: String,
    in_degree: Dictionary,
    adjacency: Dictionary
) -> void:
    if from_name == to_name:
        return
    if to_name in adjacency[from_name]:
        return
    adjacency[from_name].append(to_name)
    in_degree[to_name] = int(in_degree[to_name]) + 1


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
        var pair := _execution_pair_for_connection(conn)
        var to_name := str(pair.get("to", ""))
        if to_name != node_name:
            continue

        var from_name := str(pair.get("from", ""))
        if from_name.is_empty() or seen.has(from_name):
            continue
        seen[from_name] = true

        var from_node := get_node_or_null(NodePath(from_name)) as GraphNode
        if from_node:
            result.append(from_node)

    return result


## A 持有 REFER(B) 字段时，无论连线方向如何，B 都先于 A 执行。
func _execution_pair_for_connection(conn: Dictionary) -> Dictionary:
    var from_name := String(conn.get("from_node", conn.get("from")))
    var to_name := String(conn.get("to_node", conn.get("to")))
    var from_port := int(conn.get("from_port", 0))
    var to_port := int(conn.get("to_port", 0))
    var from_node := get_node_or_null(NodePath(from_name)) as GraphNode
    var to_node := get_node_or_null(NodePath(to_name)) as GraphNode
    if from_node == null or to_node == null:
        return {"from": from_name, "to": to_name}

    var from_slot := from_node.get_output_port_slot(from_port)
    var to_slot := to_node.get_input_port_slot(to_port)
    var from_is_member := _is_member_refer_slot(from_node, from_slot)
    var to_is_member := _is_member_refer_slot(to_node, to_slot)
    if from_is_member and not to_is_member:
        return {"from": to_name, "to": from_name}
    return {"from": from_name, "to": to_name}


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
    allow_system: bool = false,
    force: bool = false
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

    if category != "System" and not GameState.is_node_available(template_name) and not force:
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
    var self_row := _create_self_refer_row(template_name)
    node.add_child(self_row)
    _apply_self_refer_slot(node, template_name)

    node.add_child(content)
    node.set_slot_enabled_left(CONTENT_SLOT, false)
    node.set_slot_enabled_right(CONTENT_SLOT, false)
    if attributes.has("subtitle"):
        _set_subtitle(content, str(attributes["subtitle"]))

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
        var content := _base_node_of(child as GraphNode)
        if content != null:
            content.clear_run_data()
            if content.action:
                content.action.reset_progress()
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
        var content := _base_node_of(graph_node)
        var node_entry := {
            "instance_id": String(graph_node.name),
            "template_name": str(graph_node.get_meta("template_name", graph_node.name)),
            "display_title": graph_node.title,
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
            if node_data.has("display_title"):
                created.title = str(node_data.get("display_title", ""))

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


func _find_node_by_template(template_name: String) -> GraphNode:
    for child in get_children():
        if not child is GraphNode:
            continue
        if str((child as GraphNode).get_meta("template_name", "")) == template_name:
            return child as GraphNode
    return null


func is_function_slot_type(slot_type: int) -> bool:
    return slot_type == Slot.FUNCTION


func is_refer_slot_type(slot_type: int) -> bool:
    return slot_type == Slot.REFER


func is_self_refer_slot(node: GraphNode, slot_index: int) -> bool:
    if node == null:
        return false
    return int(node.get_meta("self_refer_slot", -1)) == slot_index


func _is_member_refer_slot(node: GraphNode, slot_index: int) -> bool:
    if node == null or slot_index < 0:
        return false
    if is_self_refer_slot(node, slot_index):
        return false
    if is_function_member_slot(node, slot_index):
        return false
    return not get_slot_refer_target(node, slot_index).is_empty()


func get_slot_refer_target(node: GraphNode, slot_index: int) -> String:
    if node == null:
        return ""
    var targets: Variant = node.get_meta("refer_targets", {})
    if not targets is Dictionary:
        return ""
    return str((targets as Dictionary).get(str(slot_index), "")).strip_edges()


func _set_slot_refer_target(node: GraphNode, slot_index: int, refer_target: String) -> void:
    if node == null:
        return
    var targets: Dictionary = {}
    var raw: Variant = node.get_meta("refer_targets", {})
    if raw is Dictionary:
        targets = (raw as Dictionary).duplicate()
    var normalized := refer_target.strip_edges()
    if normalized.is_empty():
        targets.erase(str(slot_index))
    else:
        targets[str(slot_index)] = normalized
    node.set_meta("refer_targets", targets)


func _apply_self_refer_slot(node: GraphNode, template_name: String) -> void:
    var refer_target := template_name.strip_edges()
    if refer_target.is_empty():
        return

    node.set_meta("self_refer_slot", SELF_REFER_SLOT)
    _apply_refer_ports(node, SELF_REFER_SLOT, refer_target)


func _create_self_refer_row(template_name: String) -> Control:
    var wrapper := _wrap_labeled_row(template_name, null)
    wrapper.custom_minimum_size = Vector2(0, 28)
    wrapper.set_meta("self_refer_row", true)
    return wrapper


func is_function_node(node: GraphNode) -> bool:
    if node == null:
        return false
    var template_name := str(node.get_meta("template_name", ""))
    var node_type := str(node.get_meta("node_type", ""))
    return template_name == "Function" or node_type == "Function"


func is_function_adapter(node: GraphNode) -> bool:
    if node == null:
        return false
    var template_name := str(node.get_meta("template_name", ""))
    var node_type := str(node.get_meta("node_type", ""))
    return template_name == "FunctionAdapter" or node_type == "FunctionAdapter"


func is_function_member_slot(node: GraphNode, slot_index: int) -> bool:
    if node == null or slot_index < 0 or slot_index >= node.get_child_count():
        return false
    var child := node.get_child(slot_index)
    return child != null and child.has_meta("function_slot")


func _is_function_node_refer_slot(node: GraphNode, slot_index: int) -> bool:
    if not is_self_refer_slot(node, slot_index):
        return false
    return is_function_node(node) or is_function_adapter(node)


func _can_connect_function_bind(
    from_node: GraphNode,
    from_port: int,
    to_node: GraphNode,
    to_port: int
) -> bool:
    var from_slot := from_node.get_output_port_slot(from_port)
    var to_slot := to_node.get_input_port_slot(to_port)
    if is_function_member_slot(from_node, from_slot) and _is_function_node_refer_slot(to_node, to_slot):
        return true
    if _is_function_node_refer_slot(from_node, from_slot) and is_function_member_slot(to_node, to_slot):
        return true
    return false


func _can_connect_refer(
    from_node: GraphNode,
    from_port: int,
    to_node: GraphNode,
    to_port: int,
    from_type: int,
    to_type: int
) -> bool:
    var from_is_refer := is_refer_slot_type(from_type)
    var to_is_refer := is_refer_slot_type(to_type)
    if not from_is_refer and not to_is_refer:
        return true
    if not from_is_refer or not to_is_refer:
        return false

    var from_target := get_slot_refer_target(from_node, from_node.get_output_port_slot(from_port))
    var to_target := get_slot_refer_target(to_node, to_node.get_input_port_slot(to_port))
    if from_target.is_empty() or to_target.is_empty() or from_target != to_target:
        EditorLog.warn("引用类型不匹配：REFER(%s) → REFER(%s)" % [from_target, to_target])
        return false
    return true


func add_function_slot(node: GraphNode, function_name: String, has_return: bool) -> int:
    if node == null:
        return -1

    var slot_index := node.get_child_count()
    var op_list := [ {
        "operation": Slot.FUNCTION,
        "type": SlotType.INPUT,
    }]
    if has_return:
        op_list.append({
            "operation": Slot.FUNCTION,
            "type": SlotType.OUTPUT,
        })

    var created := create_node_row(node, slot_index, function_name, op_list)
    var wrapper := node.get_child(created) as Control
    if wrapper:
        wrapper.set_meta("function_slot", true)
        wrapper.set_meta("function_name", function_name)
        wrapper.set_meta("has_return", has_return)
        _attach_function_slot_delete(wrapper, function_name)
    return created


func _attach_function_slot_delete(wrapper: Control, function_name: String) -> void:
    if wrapper == null or wrapper.get_child_count() == 0:
        return
    var row := wrapper.get_child(0) as HBoxContainer
    if row == null:
        return

    for child in row.get_children():
        if child.has_meta("row_field"):
            row.remove_child(child)
            child.free()

    var button := Button.new()
    button.text = "删除"
    button.focus_mode = Control.FOCUS_NONE
    button.custom_minimum_size = Vector2(48, 0)
    button.pressed.connect(func() -> void:
        var graph_node := wrapper.get_parent() as GraphNode
        var base := _base_node_of(graph_node)
        if base != null:
            base.remove_function(function_name)
    )
    row.add_child(button)


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
    if content == null:
        return {}
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
    var slots: Array = []
    for row in attributes.get("slots", []):
        if row is Dictionary:
            slots.append(row)
    slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return int(a.get("row_number", 0)) < int(b.get("row_number", 0))
    )
    for row in slots:
        _add_row_from_config(node, row)


func _add_row_from_config(node: GraphNode, row: Dictionary) -> void:
    var op_list := _parse_op_list(row.get("op_list", []))
    create_node_row(
        node,
        _config_row_to_slot(int(row.get("row_number", 0))),
        str(row.get("row_name", "")),
        op_list,
        row.get("row_options", []),
        str(row.get("row_number_input", "")),
        str(row.get("row_text_input", ""))
    )


func _config_row_to_slot(row_number: int) -> int:
    return maxi(FIRST_DATA_SLOT, row_number + (FIRST_DATA_SLOT - 1))


func create_node_row(
    node: GraphNode,
    row_number: int,
    row_name: String,
    op_list: Array,
    row_options: Variant = [],
    row_number_input: String = "",
    row_text_input: String = ""
) -> int:
    var operation := _resolve_row_operation(op_list)
    var label_text := _resolve_row_label_text(
        row_name,
        row_options,
        row_number_input,
        row_text_input
    )
    var row_field := _create_row_field(
        row_options,
        row_number_input,
        row_text_input,
        operation
    )
    if row_field != null:
        _bind_row_control_save(row_field)
    var wrapper := _wrap_labeled_row(label_text, row_field)
    var slot_index := maxi(FIRST_DATA_SLOT, row_number)

    while node.get_child_count() < slot_index:
        var placeholder := _wrap_labeled_row("", null)
        node.add_child(placeholder)
        var placeholder_index := node.get_child_count() - 1
        node.set_slot_enabled_left(placeholder_index, false)
        node.set_slot_enabled_right(placeholder_index, false)

    if slot_index < node.get_child_count():
        var existing := node.get_child(slot_index)
        if existing:
            _clear_slot_ports(node, slot_index)
            node.remove_child(existing)
            existing.free()

    if slot_index == node.get_child_count():
        node.add_child(wrapper)
    else:
        node.add_child(wrapper)
        node.move_child(wrapper, slot_index)

    var refer_target := ""
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
        if slot_operation == Slot.REFER:
            refer_target = str(op.get("refer", "")).strip_edges()

    if not refer_target.is_empty():
        _apply_refer_ports(node, slot_index, refer_target)
        wrapper.set_meta("refer_target", refer_target)
    elif _row_has_refer_operation(op_list):
        EditorLog.warn("REFER slot 缺少引用类型")
    return slot_index


func _row_has_refer_operation(op_list: Array) -> bool:
    for op in op_list:
        if op is Dictionary and op.get("operation", -1) == Slot.REFER:
            return true
    return false


func _apply_refer_ports(node: GraphNode, slot_index: int, refer_target: String) -> void:
    var color := _get_refer_color(refer_target)
    node.set_slot_enabled_left(slot_index, true)
    node.set_slot_type_left(slot_index, Slot.REFER)
    node.set_slot_color_left(slot_index, color)
    node.set_slot_enabled_right(slot_index, true)
    node.set_slot_type_right(slot_index, Slot.REFER)
    node.set_slot_color_right(slot_index, color)
    _set_slot_refer_target(node, slot_index, refer_target)


func _get_refer_color(refer_target: String) -> Color:
    var key := refer_target.strip_edges()
    if key.is_empty():
        return _get_slot_color(Slot.REFER)
    var hash_value := 0
    for i in key.length():
        hash_value = (hash_value * 31 + key.unicode_at(i)) & 0x7fffffff
    var hex := str(REFER_COLORS[hash_value % REFER_COLORS.size()])
    return Color.html(hex)


func remove_slot_row(node: GraphNode, slot_index: int) -> void:
    if node == null or slot_index < FIRST_DATA_SLOT or slot_index >= node.get_child_count():
        return
    _clear_slot_ports(node, slot_index)
    var child := node.get_child(slot_index)
    node.remove_child(child)
    child.free()


func _clear_slot_ports(node: GraphNode, slot_index: int) -> void:
    _disconnect_slot(node, slot_index, false)
    _disconnect_slot(node, slot_index, true)
    node.set_slot_enabled_left(slot_index, false)
    node.set_slot_enabled_right(slot_index, false)
    _set_slot_refer_target(node, slot_index, "")


func _bind_row_control_save(control: Control) -> void:
    if control is HBoxContainer:
        for child in control.get_children():
            if child is Control:
                _bind_row_control_save(child as Control)
        return
    if control is SpinBox:
        (control as SpinBox).value_changed.connect(func(_value: float) -> void:
            schedule_save()
        )
    elif control is OptionButton:
        (control as OptionButton).item_selected.connect(func(_index: int) -> void:
            schedule_save()
        )
    elif control is LineEdit:
        (control as LineEdit).text_changed.connect(func(_text: String) -> void:
            schedule_save()
        )


func _resolve_row_label_text(
    row_name: String,
    row_options: Variant,
    row_number_input: String,
    row_text_input: String
) -> String:
    if not row_name.is_empty():
        return row_name
    if not row_number_input.is_empty():
        return row_number_input
    if not row_text_input.is_empty():
        return row_text_input
    if row_options is Array and not (row_options as Array).is_empty():
        return "Op"
    return ""


## Slot 行：左 Label、右表单；左右留白与内容区 BaseNode.BODY_SIDE_MARGIN 对齐。
func _wrap_labeled_row(label_text: String, field: Control) -> MarginContainer:
    var margin := MarginContainer.new()
    margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
    margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    margin.add_theme_constant_override("margin_left", ROW_PORT_SIDE_MARGIN)
    margin.add_theme_constant_override("margin_right", ROW_PORT_SIDE_MARGIN)

    var row := HBoxContainer.new()
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_theme_constant_override("separation", 8)

    var name_label := Label.new()
    name_label.text = label_text
    name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    name_label.custom_minimum_size = Vector2(ROW_LABEL_MIN_WIDTH, 0)
    name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    name_label.set_meta("row_name_label", true)
    row.add_child(name_label)

    if field != null:
        field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        field.set_meta("row_field", true)
        row.add_child(field)
    else:
        var value_label := Label.new()
        value_label.text = ""
        value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        value_label.set_meta("row_field", true)
        row.add_child(value_label)

    margin.add_child(row)
    return margin


func _create_row_field(
    row_options: Variant,
    row_number_input: String,
    row_text_input: String,
    operation: Slot
) -> Control:
    var has_options := row_options is Array and not (row_options as Array).is_empty()
    var has_number := not row_number_input.is_empty()

    if has_options and has_number:
        var container := HBoxContainer.new()
        container.add_theme_constant_override("separation", 6)
        container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

        var option_button := OptionButton.new()
        for i in (row_options as Array).size():
            option_button.add_item(str(row_options[i]), i)
        option_button.selected = 0
        option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        container.add_child(option_button)

        var spin_box := SpinBox.new()
        spin_box.min_value = 0
        spin_box.max_value = 65535.0
        spin_box.custom_minimum_size = Vector2(72, 0)
        spin_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var spin_line_edit := spin_box.get_line_edit()
        spin_line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
        container.add_child(spin_box)

        container.set_meta("row_field", true)
        return container

    if has_options:
        var option_button := OptionButton.new()
        for i in (row_options as Array).size():
            option_button.add_item(str(row_options[i]), i)
        option_button.selected = 0
        return option_button

    if not row_number_input.is_empty():
        var spin_box := SpinBox.new()
        spin_box.min_value = 0
        match operation:
            Slot.UINT8, Slot.UINT16, Slot.UINT32, Slot.UINT64:
                spin_box.max_value = float(UintCodec.max_value(_slot_to_type_name(operation)))
            _:
                spin_box.max_value = 100
        var line_edit := spin_box.get_line_edit()
        line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
        return spin_box

    if not row_text_input.is_empty():
        var text_input := LineEdit.new()
        text_input.alignment = HORIZONTAL_ALIGNMENT_LEFT
        text_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        return text_input

    return null


func _get_slot_color(slot: Slot) -> Color:
    var hex := str(SLOT_COLORS.get(slot, "#FFFFFF"))
    return Color.html(hex)


func set_slot_operation(node: GraphNode, row_number: int, op_name: String, is_output: bool) -> void:
    var operation := _parse_operation(op_name)
    var slot_color := _get_slot_color(operation)
    var type_changed := true
    if is_output:
        type_changed = not node.is_slot_enabled_right(row_number) or node.get_slot_type_right(row_number) != operation
    else:
        type_changed = not node.is_slot_enabled_left(row_number) or node.get_slot_type_left(row_number) != operation
    if type_changed:
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
    var normalized := op_name.strip_edges()
    if _is_refer_operation(normalized):
        return Slot.REFER

    match normalized.to_upper():
        "OPERATION_CODE":
            return Slot.OPERATION_CODE
        "DATA":
            return Slot.DATA
        "QUEUE":
            return Slot.QUEUE
        "UNION":
            return Slot.UNION
        "UINT8":
            return Slot.UINT8
        "UINT16":
            return Slot.UINT16
        "UINT32":
            return Slot.UINT32
        "UINT64", "INT":
            return Slot.UINT64
        "PAGE_DATA":
            return Slot.PAGE_DATA
        "FUNCTION":
            return Slot.FUNCTION
        _:
            EditorLog.warn("Unknown operation: %s" % op_name)
            return Slot.OPERATION_CODE


func _is_refer_operation(op_name: String) -> bool:
    return op_name.strip_edges().to_upper().begins_with("REFER")


func _parse_refer_target(op_name: String) -> String:
    var normalized := op_name.strip_edges()
    var start := normalized.find("(")
    var end := normalized.rfind(")")
    if start < 0 or end <= start:
        return ""
    return normalized.substr(start + 1, end - start - 1).strip_edges()


func _slot_to_type_name(slot: Slot) -> String:
    match slot:
        Slot.UINT8:
            return UintCodec.TYPE_UINT8
        Slot.UINT16:
            return UintCodec.TYPE_UINT16
        Slot.UINT32:
            return UintCodec.TYPE_UINT32
        Slot.UINT64:
            return UintCodec.TYPE_UINT64
        _:
            return UintCodec.TYPE_UINT64


func _parse_op_list(raw_list: Variant) -> Array:
    var result: Array = []
    if raw_list is Array:
        for item in raw_list:
            if item is Dictionary:
                var operation_name := str(item.get("operation", ""))
                var parsed := {
                    "operation": _parse_operation(operation_name),
                    "type": _parse_slot_type(str(item.get("type", ""))),
                }
                if parsed["operation"] == Slot.REFER:
                    parsed["refer"] = _parse_refer_target(operation_name)
                result.append(parsed)
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
