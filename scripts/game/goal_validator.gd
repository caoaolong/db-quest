class_name GoalValidator
extends RefCounted

const OPERATORS := [">=", "<=", "!=", "==", ">", "<"]


static func evaluate_goal(goal: String, graph_edit: GraphEdit, variables: Dictionary = {}) -> bool:
    var expression: String = LevelVariables.expand_goal(goal.strip_edges(), variables)
    if expression.is_empty():
        return false

    var parts := _split_comparison(expression)
    if parts.size() != 3:
        EditorLog.warn("无法解析任务目标: %s" % goal)
        return false

    var left_value: Variant = _resolve_operand(str(parts[0]), graph_edit)
    var right_value: Variant = _resolve_operand(str(parts[1]), graph_edit)
    return _compare_values(left_value, right_value, str(parts[2]))


static func evaluate_task(task: Dictionary, graph_edit: GraphEdit, variables: Dictionary = {}) -> bool:
    if not task is Dictionary:
        return false
    return evaluate_goal(str(task.get("goal", "")), graph_edit, variables)


static func evaluate_check_row(graph_edit: GraphEdit, row_index: int) -> bool:
    var needle := "Check.rows[%d]" % row_index
    var variables := GameState.get_current_level_variables()
    var found := false

    for task in GameState.get_current_level_tasks():
        if not task is Dictionary:
            continue
        var goal := str(task.get("goal", ""))
        if not goal.contains(needle):
            continue
        found = true
        if not evaluate_goal(goal, graph_edit, variables):
            return false

    return found


static func _split_comparison(expression: String) -> Array:
    for operator in OPERATORS:
        var index := expression.find(operator)
        if index == -1:
            continue
        return [
            expression.substr(0, index).strip_edges(),
            expression.substr(index + operator.length()).strip_edges(),
            operator,
        ]
    return []


static func _resolve_operand(operand: String, graph_edit: GraphEdit) -> Variant:
    operand = operand.strip_edges()
    if operand.is_empty():
        return ""

    if operand.begins_with("\"") and operand.ends_with("\""):
        return _resolve_literal(operand.substr(1, operand.length() - 2))

    if operand.is_valid_int():
        return int(operand)
    if operand.is_valid_float():
        return float(operand)

    if operand == "Disk.size":
        return _resolve_disk_size(graph_edit)

    var vd_spec := _parse_vd_spec(operand)
    if not vd_spec.is_empty():
        if vd_spec.get("open_ended", false):
            return {
                "__kind": "vd_range",
                "start": int(vd_spec.get("start", 0)),
            }
        return _resolve_vd_sector(int(vd_spec.get("start", 0)))

    var check_row_index := _parse_check_rows_operand(operand)
    if check_row_index >= 0:
        return _resolve_check_row(graph_edit, check_row_index)

    return _resolve_literal(operand)


## VD[n] 单扇区；VD[n:] 从 n 扇区起按对比数据长度读取。
static func _parse_vd_spec(operand: String) -> Dictionary:
    if not operand.begins_with("VD["):
        return {}
    if not operand.ends_with("]"):
        return {}

    var index_text := operand.substr(3, operand.length() - 4).strip_edges()
    if index_text.ends_with(":"):
        var start_text := index_text.substr(0, index_text.length() - 1).strip_edges()
        if not start_text.is_valid_int():
            return {}
        return {
            "start": int(start_text),
            "open_ended": true,
        }

    if not index_text.is_valid_int():
        return {}
    return {
        "start": int(index_text),
        "open_ended": false,
    }


static func _parse_check_rows_operand(operand: String) -> int:
    const PREFIX := "Check.rows["
    if not operand.begins_with(PREFIX):
        return -1
    if not operand.ends_with("]"):
        return -1

    var index_text := operand.substr(PREFIX.length(), operand.length() - PREFIX.length() - 1)
    if not index_text.is_valid_int():
        return -1
    return int(index_text)


static func _resolve_disk_size(graph_edit: GraphEdit) -> int:
    var disk_node := _find_node_by_type(graph_edit, "Disk")
    if disk_node is DiskNode:
        return int((disk_node as DiskNode).data.get("size", 0))
    return 0


static func _resolve_vd_sector(sector_index: int) -> String:
    var sector := VirtualDisk.read_sector(GameState.virtual_disk_path, sector_index)
    return _bytes_to_compare_string(sector)


static func _resolve_check_row(graph_edit: GraphEdit, row_index: int) -> String:
    var check_node := _find_node_by_type(graph_edit, "Check")
    if check_node is CheckNode:
        return (check_node as CheckNode).get_check_value(row_index)
    return ""


static func _find_node_by_type(graph_edit: GraphEdit, node_type: String) -> BaseNode:
    if graph_edit == null or node_type.is_empty():
        return null

    for child in graph_edit.get_children():
        if not child is GraphNode:
            continue

        var graph_node := child as GraphNode
        if str(graph_node.get_meta("node_type", "")) != node_type:
            continue
        if graph_node.get_child_count() == 0:
            continue

        var content := graph_node.get_child(0)
        if content is BaseNode:
            return content as BaseNode

    return null


static func _bytes_to_compare_string(data: PackedByteArray) -> String:
    var end := data.size()
    while end > 0 and data[end - 1] == 0:
        end -= 1
    if end == 0:
        return ""
    return data.slice(0, end).get_string_from_utf8()


static func _resolve_literal(value: String) -> Variant:
    var path := value.strip_edges()
    if path.begins_with("res://") or path.begins_with("user://"):
        if FileAccess.file_exists(path):
            return FileAccess.get_file_as_string(path)
    return value


static func _is_vd_range(value: Variant) -> bool:
    return value is Dictionary and str(value.get("__kind", "")) == "vd_range"


static func _to_compare_bytes(value: Variant) -> PackedByteArray:
    if value is PackedByteArray:
        return value as PackedByteArray
    return str(value).to_utf8_buffer()


static func _compare_vd_range(left: Variant, right: Variant) -> bool:
    var range_spec: Dictionary = {}
    var expected: Variant = null
    if _is_vd_range(left):
        range_spec = left as Dictionary
        expected = right
    else:
        range_spec = right as Dictionary
        expected = left

    var expected_bytes := _to_compare_bytes(expected)
    if expected_bytes.is_empty():
        return false

    var start_sector := int(range_spec.get("start", 0))
    var actual := VirtualDisk.read_bytes(
        GameState.virtual_disk_path,
        start_sector * VirtualDisk.SECTOR_SIZE,
        expected_bytes.size()
    )
    return actual == expected_bytes


static func _compare_values(left: Variant, right: Variant, operator: String) -> bool:
    if operator in ["==", "!="]:
        var equal: bool
        if _is_vd_range(left) or _is_vd_range(right):
            equal = _compare_vd_range(left, right)
        else:
            equal = str(left) == str(right)
        return equal if operator == "==" else not equal

    var left_number := _to_number(left)
    var right_number := _to_number(right)
    match operator:
        ">":
            return left_number > right_number
        "<":
            return left_number < right_number
        ">=":
            return left_number >= right_number
        "<=":
            return left_number <= right_number
        _:
            return false


static func _to_number(value: Variant) -> float:
    if value is int or value is float:
        return float(value)
    if str(value).is_valid_int():
        return float(int(str(value)))
    if str(value).is_valid_float():
        return float(str(value))
    return 0.0
