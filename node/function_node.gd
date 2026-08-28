class_name FunctionNode
extends BaseNode

"""
{
    "function_owner": "Database",
    "function_name": "open"
}
"""

const FIRST_SLOT := 2

@onready var function_option: OptionButton = $VBoxContainer/FunctionRow/FunctionOption


func _ready() -> void:
    super._ready()
    _populate_function_option()
    if function_option:
        function_option.item_selected.connect(_on_function_selected)
    _apply_selected_function()


func _can_add_prefab_functions() -> bool:
    return false


func apply_persisted_data(saved: Dictionary) -> void:
    if saved.is_empty():
        return
    var payload := saved.duplicate(true)
    payload.erase("rows")
    payload.erase("functions")
    apply_data(payload)
    _populate_function_option()
    _apply_selected_function()


func collect_persisted_data() -> Dictionary:
    _sync_data_from_controls()
    return data.duplicate(true)


func _sync_data_from_controls() -> void:
    if function_option == null:
        return
    var meta := _selected_function_meta()
    data["function_owner"] = str(meta.get("owner", ""))
    data["function_name"] = str(meta.get("name", ""))


func _sync_controls_from_data() -> void:
    _select_current_function()


func _populate_function_option() -> void:
    if function_option == null:
        return

    var current_owner := str(data.get("function_owner", ""))
    var current_name := str(data.get("function_name", ""))
    function_option.clear()
    function_option.add_item("选择函数")
    function_option.set_item_metadata(0, {})

    for function_def in GameState.get_all_prefab_functions():
        var owner := str(function_def.get("owner", ""))
        var function_name := str(function_def.get("name", ""))
        var owner_label := str(function_def.get("owner_label", owner))
        var function_label := str(function_def.get("label", function_name))
        function_option.add_item("%s.%s" % [owner_label, function_label])
        function_option.set_item_metadata(function_option.item_count - 1, {
            "owner": owner,
            "name": function_name,
        })

    _select_function(current_owner, current_name)


func _select_current_function() -> void:
    _select_function(str(data.get("function_owner", "")), str(data.get("function_name", "")))


func _select_function(owner: String, function_name: String) -> void:
    if function_option == null:
        return
    var selected := 0
    if not owner.is_empty() and not function_name.is_empty():
        for i in function_option.item_count:
            var meta: Variant = function_option.get_item_metadata(i)
            if meta is Dictionary \
                    and str(meta.get("owner", "")) == owner \
                    and str(meta.get("name", "")) == function_name:
                selected = i
                break
    function_option.set_block_signals(true)
    function_option.selected = selected
    function_option.set_block_signals(false)


func _selected_function_meta() -> Dictionary:
    if function_option == null or function_option.selected < 0:
        return {}
    var meta: Variant = function_option.get_item_metadata(function_option.selected)
    if meta is Dictionary:
        return meta
    return {}


func _on_function_selected(_index: int) -> void:
    _sync_data_from_controls()
    _apply_selected_function()
    schedule_save()


func _apply_selected_function() -> void:
    var owner := str(data.get("function_owner", "")).strip_edges()
    var function_name := str(data.get("function_name", "")).strip_edges()
    var prefab := GameState.get_node_function(owner, function_name)
    if prefab.is_empty():
        set_subtitle("函数签名")
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
