class_name FilePageNode
extends BaseNode

"""
{
    "page": 0,
    "input_count": 1,
    "input_types": ["DATA"]
}
"""

const MIN_INPUTS := 1
const MAX_INPUTS := 16
const FIRST_INPUT_SLOT := 2

const INPUT_TYPE_OPTIONS := [
    "UINT8",
    "UINT16",
    "UINT32",
    "UINT64",
    "DATA",
]

@export var title: String = "文件页"

@onready var page_input: SpinBox = $VBoxContainer/PageRow/PageSpinBox
@onready var input_count_spin: SpinBox = $VBoxContainer/InputsRow/InputCountSpinBox


func _ready() -> void:
    super._ready()
    page_input.min_value = 0
    page_input.max_value = maxi(0, VirtualFile.get_page_count() - 1)
    page_input.value_changed.connect(_on_page_changed)

    input_count_spin.min_value = MIN_INPUTS
    input_count_spin.max_value = MAX_INPUTS
    input_count_spin.step = 1
    input_count_spin.value_changed.connect(_on_input_count_changed)

    _ensure_input_types()
    _sync_controls_from_data()
    call_deferred("_rebuild_input_slots")


func apply_persisted_data(saved: Dictionary) -> void:
    if saved.is_empty():
        return
    var payload := saved.duplicate(true)
    var rows: Variant = payload.get("rows", {})
    payload.erase("rows")
    apply_data(payload)
    _ensure_input_types()
    _rebuild_input_slots()
    var graph_node := get_parent() as GraphNode
    if graph_node and rows is Dictionary:
        _apply_input_row_data(graph_node, rows as Dictionary)
    _restore_function_slots()


func _sync_data_from_controls() -> void:
    data["page"] = int(page_input.value)
    data["input_count"] = clampi(int(input_count_spin.value), MIN_INPUTS, MAX_INPUTS)
    _ensure_input_types()
    _sync_input_types_from_rows()


func _sync_controls_from_data() -> void:
    if data.has("page"):
        page_input.value = float(int(data["page"]))
    var count := clampi(int(data.get("input_count", MIN_INPUTS)), MIN_INPUTS, MAX_INPUTS)
    data["input_count"] = count
    input_count_spin.set_block_signals(true)
    input_count_spin.value = float(count)
    input_count_spin.set_block_signals(false)
    _ensure_input_types()
    _update_subtitle()


func _ensure_input_types() -> void:
    var count := clampi(int(data.get("input_count", MIN_INPUTS)), MIN_INPUTS, MAX_INPUTS)
    var types: Array = []
    if data.get("input_types") is Array:
        for item in data["input_types"]:
            types.append(_normalize_type_name(str(item)))

    while types.size() < count:
        types.append("DATA")
    while types.size() > count:
        types.pop_back()

    data["input_types"] = types
    data.erase("input_offsets")


func _normalize_type_name(type_name: String) -> String:
    var normalized := type_name.strip_edges().to_upper()
    if normalized == "PAGE_DATA":
        return "DATA"
    if INPUT_TYPE_OPTIONS.has(normalized):
        return normalized
    return "DATA"


func _sync_input_types_from_rows() -> void:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return

    var count := clampi(int(data.get("input_count", MIN_INPUTS)), MIN_INPUTS, MAX_INPUTS)
    var types: Array = []
    for i in count:
        var slot_index := FIRST_INPUT_SLOT + i
        types.append(_row_input_type(slot_index))
    data["input_types"] = types


func _apply_input_row_data(graph_node: GraphNode, rows: Dictionary) -> void:
    for key in rows.keys():
        var slot_index := int(key)
        var option := _row_option(graph_node, slot_index)
        if option == null:
            continue
        option.set_block_signals(true)
        option.selected = int(rows[key])
        option.set_block_signals(false)
        _sync_slot_type(slot_index, _row_input_type(slot_index))


func collect_persisted_data() -> Dictionary:
    _sync_data_from_controls()
    var result := data.duplicate(true)
    var graph_node := get_parent() as GraphNode
    if graph_node:
        var rows := _collect_input_row_data(graph_node)
        if not rows.is_empty():
            result["rows"] = rows
    return result


func _collect_input_row_data(graph_node: GraphNode) -> Dictionary:
    var rows := {}
    var count := clampi(int(data.get("input_count", MIN_INPUTS)), MIN_INPUTS, MAX_INPUTS)
    for i in count:
        var slot_index := FIRST_INPUT_SLOT + i
        var option := _row_option(graph_node, slot_index)
        if option != null:
            rows[str(slot_index)] = option.selected
    return rows


func _on_page_changed(_value: float) -> void:
    _sync_data_from_controls()
    _update_subtitle()
    schedule_save()


func _on_input_count_changed(_value: float) -> void:
    _sync_data_from_controls()
    _rebuild_input_slots()
    _update_subtitle()
    schedule_save()


func clear_run_data() -> void:
    _update_subtitle()


func _update_subtitle() -> void:
    var page := int(data.get("page", 0))
    var count := int(data.get("input_count", MIN_INPUTS))
    set_subtitle("page %d · inputs %d" % [page, count])


func _on_display_clicked() -> void:
    var page := int(page_input.value)
    var page_data := VirtualFile.read_page(GameState.virtual_file_path, page)
    var schema_name := "meta" if page == 0 else ""
    var rows := PageSchema.describe_page(page_data, schema_name)
    if rows.is_empty():
        action.display_data(page_data, DisplayDialog.DataType.BINARY)
        return
    action.display_data({
        "title": "文件页 %d" % page,
        "rows": rows,
    }, DisplayDialog.DataType.TABLE)


func run(inputs: Dictionary = {}) -> Variant:
    _sync_data_from_controls()
    var page := int(data.get("page", 0))
    var slot_inputs: Dictionary = _get_slot_inputs(inputs)
    var ops: Array = _collect_write_ops(slot_inputs)
    if ops.is_empty():
        EditorLog.warn("文件页没有有效的输入")
        return {"error": "Missing input"}

    var page_bytes := VirtualFile.read_page(GameState.virtual_file_path, page)
    for op in ops:
        var offset := int(op.get("offset", 0))
        var length := int(op.get("length", 0))
        var payload: PackedByteArray = op.get("data", PackedByteArray()) as PackedByteArray
        if length <= 0:
            length = payload.size()
        if length <= 0:
            continue
        if not _validate_range(offset, length):
            return {"error": "Invalid range"}
        var clipped: PackedByteArray = VirtualFile.clip_to_length(payload, length)
        for i in length:
            page_bytes[offset + i] = clipped[i]

    var success := VirtualFile.write_page(GameState.virtual_file_path, page, page_bytes)
    if not success:
        return {"error": "Write failed"}

    EditorLog.info("文件页写入 page=%d，合并 %d 段输入" % [page, ops.size()])
    var graph_edit := get_graph_edit()
    if graph_edit != null:
        TaskTrigger.handle(TaskTrigger.AFTER_VF_WRITE, graph_edit)
    _update_subtitle()
    schedule_save()
    return page_bytes


func _collect_write_ops(slot_inputs: Dictionary) -> Array:
    var ops: Array = []
    var count := clampi(int(data.get("input_count", MIN_INPUTS)), MIN_INPUTS, MAX_INPUTS)
    for i in count:
        var slot_index := FIRST_INPUT_SLOT + i
        if not slot_inputs.has(slot_index):
            continue
        var normalized: Dictionary = _normalize_input(slot_inputs[slot_index])
        if normalized.is_empty():
            continue
        ops.append(normalized)
    return ops


func _normalize_input(value: Variant) -> Dictionary:
    if value is Dictionary:
        return _normalize_page_data(value as Dictionary)
    var payload := _to_byte_array(value)
    if payload.is_empty():
        return {}
    EditorLog.warn("文件页输入缺少 offset 信息，已跳过")
    return {}


func _normalize_page_data(value: Dictionary) -> Dictionary:
    var raw_data: Variant = value.get("data", null)
    var payload := _to_byte_array(raw_data)
    var offset := int(value.get("offset", 0))
    var length := int(value.get("length", 0))
    if length <= 0:
        length = payload.size()
    if length <= 0:
        return {}
    return {
        "data": payload,
        "offset": maxi(0, offset),
        "length": maxi(0, length),
    }


func _rebuild_input_slots() -> void:
    var graph_node := get_parent() as GraphNode
    var graph_edit := get_graph_edit()
    if graph_node == null or graph_edit == null:
        return
    if not graph_edit.has_method("create_node_row") or not graph_edit.has_method("_parse_op_list"):
        return

    var count := clampi(int(data.get("input_count", MIN_INPUTS)), MIN_INPUTS, MAX_INPUTS)
    data["input_count"] = count
    _ensure_input_types()

    while graph_node.get_child_count() > count + FIRST_INPUT_SLOT:
        var slot_index := graph_node.get_child_count() - 1
        graph_edit.remove_slot_row(graph_node, slot_index)

    for i in count:
        var slot_index := FIRST_INPUT_SLOT + i
        var type_name := _stored_input_type(i)
        var op_list: Array = graph_edit._parse_op_list([{
            "operation": type_name,
            "type": "INPUT",
        }])
        if slot_index >= graph_node.get_child_count() or _row_option(graph_node, slot_index) == null:
            graph_edit.create_node_row(
                graph_node,
                slot_index,
                "In %d" % (i + 1),
                op_list,
                INPUT_TYPE_OPTIONS
            )
        _configure_input_row(graph_node, slot_index, i)

    _restore_function_slots()
    _fit_graph_node_size(graph_node)


func _configure_input_row(graph_node: GraphNode, slot_index: int, input_index: int) -> void:
    var type_name := _stored_input_type(input_index)
    var option := _row_option(graph_node, slot_index)
    if option != null:
        var type_index := INPUT_TYPE_OPTIONS.find(type_name)
        if type_index < 0:
            type_index = 0
        option.set_block_signals(true)
        option.selected = type_index
        option.set_block_signals(false)
        option.set_meta("file_page_input_index", input_index)
        var type_callable := func(_selected: int) -> void:
            _on_input_type_selected(int(option.get_meta("file_page_input_index")))
        if option.has_meta("file_page_type_callable"):
            var old_callable: Callable = option.get_meta("file_page_type_callable")
            if option.item_selected.is_connected(old_callable):
                option.item_selected.disconnect(old_callable)
        option.set_meta("file_page_type_callable", type_callable)
        option.item_selected.connect(type_callable)

    _sync_slot_type(slot_index, type_name)


func _on_input_type_selected(input_index: int) -> void:
    var slot_index := FIRST_INPUT_SLOT + input_index
    _sync_slot_type(slot_index, _row_input_type(slot_index))
    _sync_data_from_controls()
    schedule_save()


func _sync_slot_type(slot_index: int, type_name: String) -> void:
    var graph_node := get_parent() as GraphNode
    var graph_edit := get_graph_edit()
    if graph_node == null or graph_edit == null:
        return
    if not graph_edit.has_method("set_slot_operation"):
        return
    graph_edit.set_slot_operation(graph_node, slot_index, type_name, false)


func _stored_input_type(input_index: int) -> String:
    var types: Variant = data.get("input_types", [])
    if types is Array and input_index < (types as Array).size():
        return _normalize_type_name(str((types as Array)[input_index]))
    return "DATA"


func _row_input_type(slot_index: int) -> String:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return _stored_input_type(slot_index - FIRST_INPUT_SLOT)
    var option := _row_option(graph_node, slot_index)
    if option == null or option.selected < 0:
        return _stored_input_type(slot_index - FIRST_INPUT_SLOT)
    return _normalize_type_name(option.get_item_text(option.selected))


func _row_option(graph_node: GraphNode, slot_index: int) -> OptionButton:
    var row := _get_row_hbox(graph_node, slot_index)
    if row == null:
        return null
    for child in row.get_children():
        if child is OptionButton:
            return child as OptionButton
    return null


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


func _validate_range(offset: int, length: int) -> bool:
    if offset < 0 or length < 0:
        EditorLog.warn("文件页偏移/长度非法: offset=%d length=%d" % [offset, length])
        return false
    if offset + length > VirtualFile.PAGE_SIZE:
        EditorLog.warn(
            "文件页超出页大小 %d: offset=%d length=%d" % [VirtualFile.PAGE_SIZE, offset, length]
        )
        return false
    return true


func _get_slot_inputs(inputs: Dictionary) -> Dictionary:
    var graph_node := get_parent() as GraphNode
    if graph_node == null:
        return {}
    var by_slot := {}
    for port_key in inputs.keys():
        var port_index := int(port_key)
        var slot_index := graph_node.get_input_port_slot(port_index)
        by_slot[slot_index] = inputs[port_key]
    return by_slot


func _to_byte_array(value: Variant) -> PackedByteArray:
    if value == null:
        return PackedByteArray()
    if value is PackedByteArray:
        return value as PackedByteArray
    if value is Array:
        var bytes := PackedByteArray()
        for item in value:
            bytes.append_array(_to_byte_array(item))
        return bytes
    if value is Dictionary:
        return _to_byte_array((value as Dictionary).get("data", null))
    return str(value).to_utf8_buffer()
