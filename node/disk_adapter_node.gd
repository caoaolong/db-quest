class_name DiskAdapterNode
extends BaseNode


func run(inputs: Dictionary = {}) -> Variant:
    var graph_node := get_parent() as GraphNode
    var rows := {}
    if graph_node:
        rows = _collect_row_data(graph_node)
    return {
        "inputs": inputs,
        "rows": rows,
    }
