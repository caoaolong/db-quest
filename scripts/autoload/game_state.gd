extends Node

const LEVEL_LIST_PATH := "res://data/level_list.json"
const NODE_LIST_PATH := "res://data/node_list.json"

# 当前的关卡
var current_level: int = 1
var load_previous: bool = false
var available_nodes: Array[String] = []
var current_tasks: Array = []
var current_variables: Dictionary = {}
var current_files: Dictionary = {}
var completed_task_indices: Array[int] = []
var level_check_config: Dictionary = {}
var has_level_check: bool = false
var node_list: Array = []
var virtual_disk_path: String = ""
var virtual_file_path: String = ""


func _ready() -> void:
    virtual_disk_path = VirtualDisk.ensure_exists()
    virtual_file_path = VirtualFile.ensure_exists()
    _load_node_list()
    _load_level_config()


func get_node_list() -> Array:
    return node_list


func get_categories() -> Array[String]:
    var categories: Array[String] = []
    var seen: Dictionary = {}

    for item in node_list:
        if not item is Dictionary:
            continue

        var category := str(item.get("category", ""))
        if category.is_empty() or category == "System" or seen.has(category):
            continue
        if not is_node_available(str(item.get("name", ""))):
            continue

        seen[category] = true
        categories.append(category)

    return categories


func is_node_available(node_name: String) -> bool:
    return node_name in available_nodes


func get_current_level_tasks() -> Array:
    return current_tasks.duplicate(true)


func get_current_level_variables() -> Dictionary:
    return current_variables.duplicate(true)


func get_level_files() -> Dictionary:
    return current_files.duplicate()


func get_level_file_entries() -> Array:
    var entries: Array = []
    for key in current_files.keys():
        var file_name := str(key).strip_edges()
        var path := str(current_files[key]).strip_edges()
        if file_name.is_empty() or path.is_empty():
            continue
        entries.append({
            "name": file_name,
            "path": path,
        })
    return entries


func has_level_files() -> bool:
    return not get_level_file_entries().is_empty()


func should_spawn_system_node(template_name: String) -> bool:
    match template_name:
        "LoadFile":
            return has_level_files()
        "Check":
            return has_level_check
        _:
            return true


func set_current_level(level: int) -> void:
    if level <= 0:
        return
    current_level = level
    _load_level_config()


func is_task_completed(task_index: int) -> bool:
    return task_index in completed_task_indices


func mark_task_completed(task_index: int) -> void:
    if task_index < 0 or task_index in completed_task_indices:
        return
    completed_task_indices.append(task_index)
    _save_task_progress()


func reset_task_progress() -> void:
    completed_task_indices.clear()
    _save_task_progress()


func _load_task_progress() -> void:
    completed_task_indices = TaskProgress.load_progress(current_level)


func _save_task_progress() -> void:
    TaskProgress.save(current_level, completed_task_indices)


func get_node_entry(template_name: String) -> Dictionary:
    for item in node_list:
        if item is Dictionary and str(item.get("name", "")) == template_name:
            return item
    return {}


func is_system_node_name(template_name: String) -> bool:
    var entry := get_node_entry(template_name)
    return str(entry.get("category", "")) == "System"


func get_node_create_item(template_name: String) -> Dictionary:
    var entry := get_node_entry(template_name)
    if entry.is_empty():
        return {}

    if not is_system_node_name(template_name):
        return entry.duplicate(true)

    return _build_system_node_item(entry)


func get_level_check_config() -> Dictionary:
    return level_check_config.duplicate(true)


func get_level_entries() -> Array:
    var entries: Array = []
    var seen_levels: Dictionary = {}

    for entry in _read_level_list():
        if not entry is Dictionary:
            continue

        var level_num := int(entry.get("level", 0))
        if level_num <= 0 or seen_levels.has(level_num):
            continue

        seen_levels[level_num] = true
        entries.append(entry.duplicate(true))

    entries.sort_custom(func(a, b): return int(a.get("level", 0)) < int(b.get("level", 0)))
    return entries


func _build_system_node_item(entry: Dictionary) -> Dictionary:
    var item := entry.duplicate(true)
    var template_name := str(entry.get("name", ""))

    if not item.has("attributes") or not item["attributes"] is Dictionary:
        item["attributes"] = {}

    match template_name:
        "Check":
            if not level_check_config.is_empty():
                item["attributes"] = _merge_attributes(item["attributes"], level_check_config)
        "LoadFile":
            item["attributes"] = _merge_attributes(item["attributes"], {
                "slots": _build_load_file_slots(),
            })

    return item


func _build_load_file_slots() -> Array:
    var slots: Array = []
    var entries := get_level_file_entries()
    for index in entries.size():
        var entry: Dictionary = entries[index]
        slots.append({
            "row_number": float(index + 1),
            "row_name": str(entry.get("name", "")),
            "op_list": [
                {
                    "operation": "DATA",
                    "type": "OUTPUT",
                }
            ],
        })
    return slots


func resolve_node_config(item: Dictionary) -> Dictionary:
    if item.is_empty():
        return {}

    var resolved: Dictionary = item.duplicate(true)
    var type_name := str(item.get("type", item.get("name", "")))
    resolved["name"] = str(item.get("name", ""))
    resolved["type"] = type_name
    resolved["label"] = str(item.get("label", ""))
    resolved["category"] = str(item.get("category", ""))

    if str(resolved.get("scene", "")).is_empty():
        push_error("Node config missing scene path: %s" % resolved.get("name", ""))
        return {}

    if item.has("spend"):
        resolved["spend"] = int(item["spend"])
    elif not resolved.has("spend"):
        resolved["spend"] = 0

    if not resolved.has("attributes") or not resolved["attributes"] is Dictionary:
        resolved["attributes"] = {}

    var attributes: Dictionary = resolved["attributes"]
    if attributes.has("spend"):
        resolved["spend"] = int(attributes["spend"])
    if not attributes.has("title"):
        var label := str(item.get("label", ""))
        if not label.is_empty():
            attributes["title"] = label
            resolved["attributes"] = attributes

    if _node_requires_queue_port(resolved) and not _slots_have_queue_port(attributes.get("slots", [])):
        push_error("Queue 节点必须至少包含一个 QUEUE 输入或输出 slot: %s" % resolved.get("name", ""))
        return {}

    return resolved


func _node_requires_queue_port(resolved: Dictionary) -> bool:
    var type_name := str(resolved.get("type", ""))
    var node_name := str(resolved.get("name", ""))
    return type_name == "Queue" or node_name == "DataSplit" or node_name == "DataMerge"


func _slots_have_queue_port(slots: Variant) -> bool:
    if not slots is Array:
        return false

    for slot in slots:
        if not slot is Dictionary:
            continue
        var op_list: Variant = slot.get("op_list", [])
        if not op_list is Array:
            continue
        for op in op_list:
            if not op is Dictionary:
                continue
            if str(op.get("operation", "")) != "QUEUE":
                continue
            var port_type := str(op.get("type", "")).strip_edges()
            if port_type == "INPUT" or port_type == "OUTPUT":
                return true
    return false


func _load_node_list() -> void:
    node_list.clear()

    if not FileAccess.file_exists(NODE_LIST_PATH):
        push_error("Node list file not found: %s" % NODE_LIST_PATH)
        return

    var file := FileAccess.open(NODE_LIST_PATH, FileAccess.READ)
    if file == null:
        push_error("Failed to open node list: %s" % NODE_LIST_PATH)
        return

    var parsed = JSON.parse_string(file.get_as_text())
    if parsed == null:
        push_error("Failed to parse node list JSON: %s" % NODE_LIST_PATH)
        return

    if parsed is Array:
        node_list = parsed
        return

    if parsed is Dictionary and parsed.has("items") and parsed["items"] is Array:
        node_list = parsed["items"]
        return

    push_error("Unexpected node list JSON format: %s" % NODE_LIST_PATH)


func _read_level_list() -> Array:
    if not FileAccess.file_exists(LEVEL_LIST_PATH):
        push_error("Level list file not found: %s" % LEVEL_LIST_PATH)
        return []

    var file := FileAccess.open(LEVEL_LIST_PATH, FileAccess.READ)
    if file == null:
        push_error("Failed to open level list: %s" % LEVEL_LIST_PATH)
        return []

    var parsed = JSON.parse_string(file.get_as_text())
    if parsed == null:
        push_error("Failed to parse level list JSON: %s" % LEVEL_LIST_PATH)
        return []

    if not parsed is Array:
        push_error("Unexpected level list JSON format: %s" % LEVEL_LIST_PATH)
        return []

    return parsed


func _load_level_config() -> void:
    available_nodes.clear()
    current_tasks.clear()
    current_variables.clear()
    current_files.clear()
    level_check_config.clear()
    has_level_check = false
    load_previous = false
    _load_task_progress()

    for entry in _read_level_list():
        if not entry is Dictionary:
            continue
        if int(entry.get("level", 0)) != current_level:
            continue

        load_previous = bool(entry.get("load_previous", false))

        for node_name in entry.get("nodes", []):
            available_nodes.append(str(node_name))

        var variables: Variant = entry.get("variables", {})
        if variables is Dictionary:
            current_variables = variables.duplicate(true)

        var files: Variant = entry.get("files", {})
        if files is Dictionary:
            for key in files.keys():
                var file_name := str(key).strip_edges()
                var path := str(files[key]).strip_edges()
                if file_name.is_empty() or path.is_empty():
                    continue
                current_files[file_name] = path

        if entry.has("check") and entry["check"] is Dictionary:
            has_level_check = true
            level_check_config = (entry["check"] as Dictionary).duplicate(true)

        var tasks: Variant = entry.get("tasks", [])
        if tasks is Array:
            current_tasks = tasks
        return

    push_warning("No node config found for level %d" % current_level)


func _merge_attributes(base: Dictionary, override: Dictionary) -> Dictionary:
    var merged: Dictionary = base.duplicate(true)
    for key in override.keys():
        var value: Variant = override[key]
        if merged.has(key) and merged[key] is Dictionary and value is Dictionary:
            merged[key] = _merge_attributes(merged[key], value)
        else:
            merged[key] = value
    return merged
