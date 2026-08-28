class_name GoalValidator
extends RefCounted

const OPERATORS := [">=", "<=", "!=", "==", ">", "<"]
const RULE_MARKER := " is "


static func evaluate_goal(goal: String, graph_edit: GraphEdit) -> bool:
    var expression: String = LevelVariables.expand_goal(goal.strip_edges())
    if expression.is_empty():
        return false

    var node_check := _parse_node_check(expression)
    if not node_check.is_empty():
        return _evaluate_node_check(node_check, graph_edit)

    var rule_check := _parse_rule_check(expression)
    if not rule_check.is_empty():
        return _evaluate_rule_check(rule_check, graph_edit)

    var parts := _split_comparison(expression)
    if parts.size() != 3:
        EditorLog.warn("无法解析任务目标: %s" % goal)
        return false

    var left_value: Variant = _resolve_operand(str(parts[0]), graph_edit)
    var right_value: Variant = _resolve_operand(str(parts[1]), graph_edit)
    return _compare_values(left_value, right_value, str(parts[2]))


static func evaluate_task(task: Dictionary, graph_edit: GraphEdit) -> bool:
    if not task is Dictionary:
        return false
    return evaluate_goal(str(task.get("goal", "")), graph_edit)


static func _parse_node_check(expression: String) -> Dictionary:
    var parts := expression.split(".", false, 1)
    if parts.size() != 2:
        return {}
    var node_type := str(parts[0]).strip_edges()
    var function_name := str(parts[1]).strip_edges()
    if node_type.is_empty() or function_name.to_lower() != "check":
        return {}
    return {
        "node_type": node_type,
    }


static func _evaluate_node_check(node_check: Dictionary, graph_edit: GraphEdit) -> bool:
    var node_type := str(node_check.get("node_type", "")).strip_edges()
    var nodes := _find_nodes_by_type(graph_edit, node_type)
    if nodes.is_empty():
        return false
    for node in nodes:
        if not node.check():
            return false
    return true


static func _parse_rule_check(expression: String) -> Dictionary:
    var index := expression.find(RULE_MARKER)
    if index == -1:
        return {}
    var target := expression.substr(0, index).strip_edges()
    var rule_name := expression.substr(index + RULE_MARKER.length()).strip_edges()
    if target.is_empty() or rule_name.is_empty():
        return {}
    return {
        "target": target,
        "rule": rule_name,
    }


static func _evaluate_rule_check(rule_check: Dictionary, graph_edit: GraphEdit) -> bool:
    var target := str(rule_check.get("target", ""))
    var rule_name := str(rule_check.get("rule", ""))
    var page_bytes := _resolve_page_bytes(target, graph_edit)
    if page_bytes.is_empty():
        return false
    return PageRule.validate_page(page_bytes, rule_name)


static func _resolve_page_bytes(operand: String, graph_edit: GraphEdit) -> PackedByteArray:
    var value: Variant = _resolve_operand(operand, graph_edit)
    if value is PackedByteArray:
        return value as PackedByteArray
    if value is String:
        return (value as String).to_utf8_buffer()
    return PackedByteArray()


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

    var buffer_spec := _parse_buffer_spec(operand)
    if not buffer_spec.is_empty():
        if buffer_spec.get("open_ended", false):
            return {
                "__kind": "byte_range",
                "source": str(buffer_spec.get("source", "")),
                "start": int(buffer_spec.get("start", 0)),
            }
        var source := str(buffer_spec.get("source", ""))
        var index := int(buffer_spec.get("start", 0))
        if source == "vf":
            return VirtualFile.read_page(GameState.virtual_file_path, index)
        return _resolve_buffer_sector(source, index)

    return _resolve_literal(operand)


## VD[n] / RB[n] 单扇区；VD[n:] / RB[n:] 从 n 扇区起按对比数据长度读取。
static func _parse_buffer_spec(operand: String) -> Dictionary:
    var source := ""
    if operand.begins_with("VD["):
        source = "vd"
    elif operand.begins_with("RB["):
        source = "rb"
    elif operand.begins_with("VF["):
        source = "vf"
    else:
        return {}
    if not operand.ends_with("]"):
        return {}

    var index_text := operand.substr(3, operand.length() - 4).strip_edges()
    if index_text.ends_with(":"):
        var start_text := index_text.substr(0, index_text.length() - 1).strip_edges()
        if not start_text.is_valid_int():
            return {}
        return {
            "source": source,
            "start": int(start_text),
            "open_ended": true,
        }

    if not index_text.is_valid_int():
        return {}
    return {
        "source": source,
        "start": int(index_text),
        "open_ended": false,
    }


static func _resolve_disk_size(graph_edit: GraphEdit) -> int:
    var disk_node := _find_node_by_type(graph_edit, "Disk")
    if disk_node is DiskNode:
        return int((disk_node as DiskNode).data.get("size", 0))
    return 0


static func _resolve_buffer_sector(source: String, sector_index: int) -> String:
    var sector := PackedByteArray()
    if source == "rb":
        if not GameState.read_buffer.has_sector(sector_index):
            return ""
        sector = GameState.read_buffer.read_sector(sector_index)
    else:
        sector = VirtualDisk.read_sector(GameState.virtual_disk_path, sector_index)
    return _bytes_to_compare_string(sector)


static func _find_node_by_type(graph_edit: GraphEdit, node_type: String) -> BaseNode:
    var nodes := _find_nodes_by_type(graph_edit, node_type)
    if nodes.is_empty():
        return null
    return nodes[0]


static func _find_nodes_by_type(graph_edit: GraphEdit, node_type: String) -> Array[BaseNode]:
    var result: Array[BaseNode] = []
    if graph_edit == null or node_type.is_empty():
        return result

    for child in graph_edit.get_children():
        if not child is GraphNode:
            continue

        var graph_node := child as GraphNode
        if str(graph_node.get_meta("node_type", "")) != node_type:
            continue
        for child_node in graph_node.get_children():
            if child_node is BaseNode:
                result.append(child_node as BaseNode)
                break

    return result


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
            return FileAccess.get_file_as_bytes(path)
    return value


static func _is_byte_range(value: Variant) -> bool:
    return value is Dictionary and str(value.get("__kind", "")) == "byte_range"


static func _to_compare_bytes(value: Variant) -> PackedByteArray:
    if value is PackedByteArray:
        return value as PackedByteArray
    return str(value).to_utf8_buffer()


static func _compare_byte_range(left: Variant, right: Variant) -> bool:
    var range_spec: Dictionary = {}
    var expected: Variant = null
    if _is_byte_range(left):
        range_spec = left as Dictionary
        expected = right
    else:
        range_spec = right as Dictionary
        expected = left

    var expected_bytes := _to_compare_bytes(expected)
    if expected_bytes.is_empty():
        return false

    var start_index := int(range_spec.get("start", 0))
    var page_size := VirtualFile.PAGE_SIZE if str(range_spec.get("source", "")) == "vf" else VirtualDisk.SECTOR_SIZE
    var byte_offset := start_index * page_size
    var actual := PackedByteArray()
    if str(range_spec.get("source", "")) == "rb":
        if not GameState.read_buffer.is_range_covered(byte_offset, expected_bytes.size()):
            return false
        actual = GameState.read_buffer.read_bytes(byte_offset, expected_bytes.size())
    elif str(range_spec.get("source", "")) == "vf":
        actual = VirtualFile.read_bytes(
            GameState.virtual_file_path,
            byte_offset,
            expected_bytes.size()
        )
    else:
        actual = VirtualDisk.read_bytes(
            GameState.virtual_disk_path,
            byte_offset,
            expected_bytes.size()
        )
    return actual == expected_bytes


static func _compare_packed_bytes(left: Variant, right: Variant) -> bool:
    var left_bytes := _to_compare_bytes(left)
    var right_bytes := _to_compare_bytes(right)
    if left_bytes.size() == VirtualFile.PAGE_SIZE and right_bytes.size() > VirtualFile.PAGE_SIZE:
        right_bytes = right_bytes.slice(0, VirtualFile.PAGE_SIZE)
    elif right_bytes.size() == VirtualFile.PAGE_SIZE and left_bytes.size() > VirtualFile.PAGE_SIZE:
        left_bytes = left_bytes.slice(0, VirtualFile.PAGE_SIZE)
    return left_bytes == right_bytes


static func _compare_values(left: Variant, right: Variant, operator: String) -> bool:
    if operator in ["==", "!="]:
        var equal: bool
        if _is_byte_range(left) or _is_byte_range(right):
            equal = _compare_byte_range(left, right)
        elif left is PackedByteArray or right is PackedByteArray:
            equal = _compare_packed_bytes(left, right)
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
