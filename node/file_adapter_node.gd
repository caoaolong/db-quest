class_name FileAdapterNode
extends BaseNode

"""
{
    "rows": {
        "1": 0,
        "2": 0,
        "3": 0
    }
}
"""


func run(inputs: Dictionary = {}) -> Variant:
    var graph_node := get_parent() as GraphNode
    var rows := {}
    var outputs := {}
    if graph_node:
        rows = _collect_row_data(graph_node)
        var output_port := 0
        for slot_index in range(1, graph_node.get_child_count()):
            if not graph_node.is_slot_enabled_right(slot_index):
                continue
            var value: Variant = _connected_input_for_slot(graph_node, inputs, slot_index)
            if value == null:
                value = _row_output_value(graph_node, slot_index)
            outputs[str(output_port)] = value
            output_port += 1

    return {
        "__outputs": outputs,
        "inputs": inputs,
        "rows": rows,
    }


func _connected_input_for_slot(graph_node: GraphNode, inputs: Dictionary, slot_index: int) -> Variant:
    for port_index in graph_node.get_input_port_count():
        if graph_node.get_input_port_slot(port_index) != slot_index:
            continue
        var key := str(port_index)
        if inputs.has(key):
            return inputs[key]
        return null
    return null


func _row_output_value(graph_node: GraphNode, slot_index: int) -> Variant:
    var row_control := _get_row_control(graph_node, slot_index)
    if row_control is OptionButton:
        var option := row_control as OptionButton
        var selected := option.selected
        if selected < 0:
            return ""
        return option.get_item_text(selected)
    if row_control is SpinBox:
        return int((row_control as SpinBox).value)
    return null
