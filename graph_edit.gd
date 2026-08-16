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

const SLOT_NAMES: Dictionary = {
	Slot.OPERATION_CODE: "OP",
	Slot.INT32: "INT32",
	Slot.INT64: "INT64",
	Slot.DATA: "DATA",
}

var _flow_overlay: ConnectionOverlay


func _ready() -> void:
	connection_request.connect(_on_connection_request)
	disconnection_request.connect(_on_disconnection_request)
	_flow_overlay = ConnectionOverlay.new()
	_flow_overlay.slot_colors = SLOT_COLORS
	_flow_overlay.slot_names = SLOT_NAMES
	add_child(_flow_overlay)


func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if from_node == to_node:
		return
	connect_node(from_node, from_port, to_node, to_port)


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	disconnect_node(from_node, from_port, to_node, to_port)


func create_node_from_config(item: Dictionary) -> void:
	var scene_path := str(item.get("scene", ""))
	if scene_path.is_empty():
		push_error("Node config missing scene path")
		return

	var scene := load(scene_path) as PackedScene
	if scene == null:
		push_error("Failed to load scene: %s" % scene_path)
		return

	var attributes := item.get("attributes", {}) as Dictionary
	var node := GraphNode.new()
	node.name = str(item.get("name", "GraphNode"))
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
		if attributes.has("title"):
			node.title = str(attributes["title"])
		else:
			node.title = str(item.get("label", node.name))
	elif attributes.has("title"):
		node.title = str(attributes["title"])
	else:
		node.title = str(item.get("label", node.name))
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


class ConnectionOverlay extends Control:
	const ARROW_LENGTH := 11.0
	const ARROW_WIDTH := 9.0
	const ARROW_OUTLINE := 2.5
	const TEXT_GAP := 7.0
	const DOT_COUNT := 3
	const DOT_RADIUS := 3.5
	const DOT_SPEED := 0.35

	var slot_colors: Dictionary = {}
	var slot_names: Dictionary = {}
	var _time := 0.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var graph := get_parent() as GraphEdit
		if graph == null:
			return
		var font := get_theme_default_font()
		var font_size := get_theme_default_font_size()
		var index := 0
		for conn in graph.get_connection_list():
            # 4.4+ 键名为 from_node/to_node，旧版本为 from/to
            var from_name: StringName = conn.get("from_node", conn.get("from"))
            var to_name: StringName = conn.get("to_node", conn.get("to"))
            var from_port: int = conn.get("from_port", 0)
            var to_port: int = conn.get("to_port", 0)
            var from_node := graph.get_node_or_null(NodePath(from_name)) as GraphNode
            var to_node := graph.get_node_or_null(NodePath(to_name)) as GraphNode
            if from_node == null or to_node == null:
                continue
            var p_from: Vector2 = from_node.position_offset \
                + from_node.get_connection_output_position(from_port)
            var p_to: Vector2 = to_node.position_offset \
                + to_node.get_connection_input_position(to_port)
            var slot_type: int = from_node.get_slot_type_right(from_port)
			var color := _color_for(slot_type)

			# 复刻 GraphEdit 默认连线贝塞尔：控制点水平偏移 |dx| * curvature
			var curvature := absf(p_to.x - p_from.x) * float(graph.connection_curvature)
			var c1 := p_from + Vector2(curvature, 0)
			var c2 := p_to - Vector2(curvature, 0)

			# 中点方向箭头（切线方向 = (dx - c, dy)）+ 类型文字
			var mid_draw := _to_draw(graph, (p_from + p_to) * 0.5)
			var tangent := Vector2(p_to.x - p_from.x - curvature, p_to.y - p_from.y)
			if tangent == Vector2.ZERO:
				tangent = Vector2.RIGHT
			_draw_arrow(mid_draw, tangent.angle(), color)
			if font != null:
				var label := str(slot_names.get(slot_type, ""))
				if not label.is_empty():
					_draw_label(font, font_size, mid_draw, label)

			# 输入端口处的箭头（贝塞尔终点处切线恒为水平向右）
			var tip_draw := _to_draw(graph, p_to - Vector2(3.0 / graph.zoom, 0))
			_draw_arrow(tip_draw, 0.0, color)

			# 沿曲线流动的圆点
			var base_phase := fmod(_time * DOT_SPEED + float(index) * 0.17, 1.0)
			for k in DOT_COUNT:
				var t := clampf(fmod(base_phase + float(k) / float(DOT_COUNT), 1.0), 0.04, 0.96)
				var dot := _to_draw(graph, _bezier(p_from, c1, c2, p_to, t))
				draw_circle(dot, DOT_RADIUS + 2.0, Color(0, 0, 0, 0.55))
				draw_circle(dot, DOT_RADIUS, color)
			index += 1

	func _color_for(slot_type: int) -> Color:
		return Color.html(str(slot_colors.get(slot_type, "#FFFFFF")))

	func _to_draw(graph: GraphEdit, point: Vector2) -> Vector2:
		return (point - graph.scroll_offset) * graph.zoom

	func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
		var u := 1.0 - t
		return p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t)

	func _draw_arrow(tip_pos: Vector2, angle: float, color: Color) -> void:
		var dir := Vector2.from_angle(angle)
		var perp := Vector2(-dir.y, dir.x)
		var back := tip_pos - dir * ARROW_LENGTH
		var outline_back := tip_pos - dir * (ARROW_LENGTH + ARROW_OUTLINE)
		draw_colored_polygon(PackedVector2Array([
			tip_pos + dir * ARROW_OUTLINE * 0.5,
			outline_back + perp * (ARROW_WIDTH * 0.5 + ARROW_OUTLINE),
			outline_back - perp * (ARROW_WIDTH * 0.5 + ARROW_OUTLINE),
		]), Color(0, 0, 0, 0.7))
		draw_colored_polygon(PackedVector2Array([
			tip_pos,
			back + perp * (ARROW_WIDTH * 0.5),
			back - perp * (ARROW_WIDTH * 0.5),
		]), color)

	func _draw_label(font: Font, font_size: int, mid: Vector2, label: String) -> void:
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var origin := Vector2(
			mid.x - text_size.x * 0.5,
			mid.y + ARROW_WIDTH * 0.5 + TEXT_GAP + font.get_ascent(font_size)
		)
		draw_string_outline(font, origin, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0, 0, 0, 0.85))
		draw_string(font, origin, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
