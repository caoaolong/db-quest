class_name FunctionAdapterNode
extends BaseNode

"""
{
    "function_owner": "Database",
    "function_name": "ReadPage"
}
"""

const FIRST_SLOT := 2


func _ready() -> void:
    super._ready()
    _apply_bound_function()


func _can_add_prefab_functions() -> bool:
    return false


func apply_persisted_data(saved: Dictionary) -> void:
    if saved.is_empty():
        return
    var payload := saved.duplicate(true)
    payload.erase("rows")
    payload.erase("functions")
    apply_data(payload)
    _apply_bound_function()


func collect_persisted_data() -> Dictionary:
    _sync_data_from_controls()
    return data.duplicate(true)


func bind_function(owner: String, function_name: String) -> void:
    data["function_owner"] = owner.strip_edges()
    data["function_name"] = function_name.strip_edges()
    _apply_bound_function()
    schedule_save()


func _apply_bound_function() -> void:
    var owner := str(data.get("function_owner", "")).strip_edges()
    var function_name := str(data.get("function_name", "")).strip_edges()
    var prefab := GameState.get_node_function(owner, function_name)
    if prefab.is_empty():
        set_subtitle("适配器")
        _rebuild_slots({})
        return

    var label := str(prefab.get("label", function_name)).strip_edges()
    if label.is_empty():
        label = function_name
    set_subtitle(label)
    var graph_node := get_parent() as GraphNode
    if graph_node:
        graph_node.title = label
    _rebuild_slots(prefab)


func _rebuild_slots(prefab: Dictionary) -> void:
    var graph_node := get_parent() as GraphNode
    var graph_edit := get_graph_edit()
    if graph_node == null or graph_edit == null:
        return
    if not graph_edit.has_method("create_node_row") or not graph_edit.has_method("_parse_op_list"):
        return

    while graph_node.get_child_count() > FIRST_SLOT:
        graph_edit.remove_slot_row(graph_node, graph_node.get_child_count() - 1)

    var slot_index := FIRST_SLOT
    for param in prefab.get("params", []):
        if not param is Dictionary:
            continue
        var op_list: Array = graph_edit._parse_op_list([{
            "operation": str(param.get("type", "DATA")),
            "type": "INPUT",
        }])
        graph_edit.create_node_row(
            graph_node,
            slot_index,
            str(param.get("name", "")),
            op_list
        )
        slot_index += 1

    for ret in prefab.get("returns", []):
        if not ret is Dictionary:
            continue
        var op_list: Array = graph_edit._parse_op_list([{
            "operation": str(ret.get("type", "DATA")),
            "type": "OUTPUT",
        }])
        graph_edit.create_node_row(
            graph_node,
            slot_index,
            str(ret.get("name", "")),
            op_list
        )
        slot_index += 1

    _fit_graph_node_size(graph_node)


func _fit_graph_node_size(graph_node: GraphNode) -> void:
    if graph_node == null:
        return
    # GraphNode 不会在删减 slot 后自动收缩，需按最小尺寸重置
    graph_node.reset_size()
    var min_size := graph_node.get_combined_minimum_size()
    if graph_node.size.y > min_size.y or graph_node.size.x < min_size.x:
        graph_node.size = Vector2(
            maxf(graph_node.size.x, min_size.x),
            min_size.y
        )
