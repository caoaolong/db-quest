extends GraphEdit

enum SlotType {
    INPUT,
    OUTPUT,
}

enum Slot {
    OPERATION_CODE,
    INT32,
    INT64,
    DATA,
}

const SLOT_COLORS: Dictionary = {
    Slot.OPERATION_CODE: "#F59E0B",
    Slot.INT32: "#10B981",
    Slot.INT64: "#3B82F6",
    Slot.DATA: "#A855F7",
}

const node_style = preload("res://node/node_style.tres")
const ROW_HORIZONTAL_MARGIN := 12
const RUNTIME_DATA_PATH := "res://data/runtime/%d.data"


func _ready() -> void:
    connection_request.connect(_on_connection_request)
    disconnection_request.connect(_on_disconnection_request)


func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
    if from_node == to_node:
        return
    connect_node(from_node, from_port, to_node, to_port)


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
    disconnect_node(from_node, from_port, to_node, to_port)


func create_node_from_config(item: Dictionary) -> void:
    var config := GameState.resolve_node_config(item)
    if config.is_empty():
        return

    var node_name := str(config.get("name", ""))
    if not GameState.is_node_available(node_name):
        push_warning("Node is not available in current level: %s" % node_name)
        return

    var scene_path := str(config.get("scene", ""))
    if scene_path.is_empty():
        push_error("Node config missing scene path")
        return

    var scene := load(scene_path) as PackedScene
    if scene == null:
        push_error("Failed to load scene: %s" % scene_path)
        return

    var attributes := config.get("attributes", {}) as Dictionary
    var node := GraphNode.new()
    node.name = str(config.get("name", "GraphNode"))
    node.add_theme_stylebox_override("panel", node_style)

    var content := scene.instantiate() as Control
    if content is DiskNode:
        var disk_node := content as DiskNode
        if attributes.has("title"):
            disk_node.title = str(attributes["title"])
        if attributes.has("subtitle"):
            disk_node.subtitle = str(attributes["subtitle"])
        node.title = disk_node.title
    elif content is DataNode:
        var data_node := content as DataNode
        if attributes.has("subtitle"):
            data_node.subtitle = str(attributes["subtitle"])
        data_node.data = _load_runtime_data()
        if attributes.has("title"):
            node.title = str(attributes["title"])
        else:
            node.title = str(config.get("label", node.name))
    elif attributes.has("title"):
        node.title = str(attributes["title"])
    else:
        node.title = str(config.get("label", node.name))
    content.set_anchors_preset(Control.PRESET_FULL_RECT)
    content.offset_left = 0
    content.offset_top = 0
    content.offset_right = 0
    content.offset_bottom = 0
    node.add_child(content)

    _build_node_rows(node, attributes)

    var graph_node_count := 0
    for child in get_children():
        if child is GraphNode:
            graph_node_count += 1
    node.position_offset = Vector2(40 + graph_node_count * 24, 40 + graph_node_count * 24)
    add_child(node)


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
) -> void:
    var row_control := _create_row_control(row_name, row_options, row_number_input, operation)

    for op in op_list:
        var slot_color := _get_slot_color(op.operation)
        match op.type:
            SlotType.INPUT:
                node.set_slot_enabled_left(row_number, true)
                node.set_slot_type_left(row_number, op.operation)
                node.set_slot_color_left(row_number, slot_color)
            SlotType.OUTPUT:
                node.set_slot_enabled_right(row_number, true)
                node.set_slot_type_right(row_number, op.operation)
                node.set_slot_color_right(row_number, slot_color)
    node.add_child(_wrap_row_control(row_control))


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
            Slot.INT32:
                spin_box.max_value = 2147483647
            Slot.INT64:
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


func _parse_operation(op_name: String) -> Slot:
    match op_name:
        "OPERATION_CODE":
            return Slot.OPERATION_CODE
        "INT32":
            return Slot.INT32
        "INT64":
            return Slot.INT64
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
