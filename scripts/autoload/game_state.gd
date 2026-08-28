extends Node

const LEVEL_LIST_PATH := "res://data/level_list.json"
const NODE_LIST_PATH := "res://data/node_list.json"
const EDITOR_SCENES := {
    "program_editor": "res://scenes/program_editor.tscn",
}
const DEFAULT_EDITOR := "program_editor"

# 当前的关卡
var current_level: int = 1
var current_editor: String = DEFAULT_EDITOR
var load_previous: bool = false
var available_nodes: Array[String] = []
var current_tasks: Array = []
var current_files: Dictionary = {}
var current_help: String = ""
var current_level_name: String = ""
var completed_task_indices: Array[int] = []
var node_list: Array = []
var virtual_disk_path: String = ""
var virtual_file_path: String = ""
var read_buffer: ReadBuffer = ReadBuffer.new()


func _ready() -> void:
    virtual_disk_path = VirtualDisk.ensure_exists()
    virtual_file_path = VirtualFile.ensure_exists()
    _load_node_list()
    _validate_all_level_entries()
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


func get_current_level_help() -> String:
    return current_help


func get_current_level_name() -> String:
    return current_level_name


func get_current_editor() -> String:
    return current_editor


func get_current_editor_scene() -> String:
    return EDITOR_SCENES.get(current_editor, EDITOR_SCENES[DEFAULT_EDITOR])


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
        _:
            return true


func set_current_level(level: int) -> bool:
    if level <= 0 or level > get_level_count():
        return false

    var previous_level := current_level
    current_level = level
    if not _load_level_config():
        current_level = previous_level
        return false
    return true


func get_level_count() -> int:
    return _read_level_list().size()


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
    var resolved_name := template_name
    if template_name == "Operation" or template_name == "LoadOperation":
        resolved_name = "LoadString"
    for item in node_list:
        if item is Dictionary and str(item.get("name", "")) == resolved_name:
            return item
    return {}


func get_node_functions(template_name: String) -> Array:
    var entry := get_node_entry(template_name)
    var raw: Variant = []
    if not entry.is_empty():
        var attributes: Variant = entry.get("attributes", {})
        if attributes is Dictionary and attributes.has("functions"):
            raw = attributes["functions"]
        elif entry.has("functions"):
            raw = entry["functions"]
    return _player_functions(_normalize_function_list(raw))


func get_node_function(template_name: String, function_name: String) -> Dictionary:
    var target := _capitalize_ident(function_name)
    if target.is_empty():
        return {}
    for item in get_node_functions(template_name):
        if str(item.get("name", "")) == target:
            return item
    return {}


func get_all_prefab_functions(available_only: bool = true) -> Array:
    var result: Array = []
    for item in node_list:
        if not item is Dictionary:
            continue
        var _owner := str(item.get("name", "")).strip_edges()
        if _owner.is_empty() or _owner == "Function":
            continue
        if available_only and not is_node_available(_owner):
            continue
        var owner_label := str(item.get("label", _owner)).strip_edges()
        if owner_label.is_empty():
            owner_label = _owner
        for function_def in get_node_functions(_owner):
            var entry: Dictionary = function_def.duplicate(true)
            entry["_owner"] = _owner
            entry["owner_label"] = owner_label
            result.append(entry)
    return result


func is_system_node_name(template_name: String) -> bool:
    var entry := get_node_entry(template_name)
    return str(entry.get("category", "")) == "System"


func get_node_create_item(template_name: String) -> Dictionary:
    var entry := get_node_entry(template_name)
    if entry.is_empty():
        return {}

    var item: Dictionary
    if is_system_node_name(template_name):
        item = _build_system_node_item(entry)
    else:
        item = entry.duplicate(true)

    return item


func get_level_entries() -> Array:
    var entries: Array = []

    for entry in _read_level_list():
        if not entry is Dictionary:
            continue
        entries.append(entry.duplicate(true))

    return entries


func _build_system_node_item(entry: Dictionary) -> Dictionary:
    var item := entry.duplicate(true)
    var template_name := str(entry.get("name", ""))

    if not item.has("attributes") or not item["attributes"] is Dictionary:
        item["attributes"] = {}

    match template_name:
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
    return type_name == "Queue" or node_name == "DataMerge"


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


func _load_level_config() -> bool:
    available_nodes.clear()
    current_tasks.clear()
    current_files.clear()
    current_help = ""
    current_level_name = ""
    current_editor = DEFAULT_EDITOR
    load_previous = false
    read_buffer.clear()
    _load_task_progress()

    var level_list := _read_level_list()
    if current_level <= 0 or current_level > level_list.size():
        push_warning("No node config found for level %d" % current_level)
        return false

    var entry: Variant = level_list[current_level - 1]
    if not entry is Dictionary:
        push_warning("Invalid level config at index %d" % current_level)
        return false

    var validation_error := _validate_level_entry(entry as Dictionary)
    if not validation_error.is_empty():
        push_error("Level %d config invalid: %s" % [current_level, validation_error])
        return false

    load_previous = bool(entry.get("load_previous", false))
    current_level_name = str(entry.get("name", "")).strip_edges()
    current_help = str(entry.get("help", "")).strip_edges()
    current_editor = _resolve_editor_type(str(entry.get("editor", DEFAULT_EDITOR)))

    for node_name in entry.get("nodes", []):
        available_nodes.append(str(node_name))

    var files: Variant = entry.get("files", {})
    if files is Dictionary:
        for key in files.keys():
            var file_name := str(key).strip_edges()
            var path := str(files[key]).strip_edges()
            if file_name.is_empty() or path.is_empty():
                continue
            current_files[file_name] = path

    var tasks: Variant = entry.get("tasks", [])
    if tasks is Array:
        current_tasks = tasks
    return true


func _validate_all_level_entries() -> void:
    var level_list := _read_level_list()
    for index in level_list.size():
        var entry: Variant = level_list[index]
        if not entry is Dictionary:
            push_error("Level %d config invalid: entry must be an object" % (index + 1))
            continue

        var validation_error := _validate_level_entry(entry as Dictionary)
        if not validation_error.is_empty():
            push_error("Level %d config invalid: %s" % [index + 1, validation_error])


func _validate_level_entry(_entry: Dictionary) -> String:
    return ""


func _resolve_editor_type(editor_type: String) -> String:
    var normalized := editor_type.strip_edges()
    if normalized.is_empty():
        return DEFAULT_EDITOR
    if EDITOR_SCENES.has(normalized):
        return normalized
    push_warning("Unknown editor type '%s', fallback to %s" % [normalized, DEFAULT_EDITOR])
    return DEFAULT_EDITOR


func _normalize_function_list(raw: Variant) -> Array:
    var result: Array = []
    if not raw is Array:
        return result
    for item in raw:
        var normalized := _normalize_function_entry(item)
        if not normalized.is_empty():
            result.append(normalized)
    return result


func _player_functions(functions: Array) -> Array:
    var result: Array = []
    for item in functions:
        if item is Dictionary and _is_hidden_prefab_function(str(item.get("name", ""))):
            continue
        result.append(item)
    return result


func _is_hidden_prefab_function(function_name: String) -> bool:
    return function_name.strip_edges().to_lower() == "check"


func _capitalize_ident(value: String) -> String:
    var trimmed := value.strip_edges()
    if trimmed.is_empty():
        return ""
    return trimmed.substr(0, 1).to_upper() + trimmed.substr(1)


func _normalize_function_entry(item: Variant) -> Dictionary:
    if item is String:
        var _name := _capitalize_ident(str(item))
        if _name.is_empty():
            return {}
        return {
            "name": _name,
            "label": _name,
            "params": [],
            "returns": [],
        }
    if not item is Dictionary:
        return {}

    var function_name := _capitalize_ident(str(item.get("name", "")))
    if function_name.is_empty():
        return {}
    var label := _capitalize_ident(str(item.get("label", function_name)))
    if label.is_empty():
        label = function_name
    return {
        "name": function_name,
        "label": label,
        "params": _normalize_function_ports(item.get("params", []), "arg"),
        "returns": _normalize_function_ports(_function_returns_raw(item), "ret"),
    }


func _function_returns_raw(item: Dictionary) -> Variant:
    if item.has("returns"):
        return item["returns"]
    if item.has("return"):
        return item["return"]
    if bool(item.get("has_return", false)):
        return ["DATA"]
    return []


func _normalize_function_ports(raw: Variant, fallback_prefix: String) -> Array:
    var result: Array = []
    if raw is String:
        var type_name := str(raw).strip_edges()
        if not type_name.is_empty():
            result.append({
                "name": fallback_prefix,
                "type": type_name.to_upper(),
            })
        return result
    if not raw is Array:
        return result

    var index := 1
    for item in raw:
        if item is String:
            var type_name := str(item).strip_edges()
            if type_name.is_empty():
                continue
            result.append({
                "name": "%s%d" % [fallback_prefix, index],
                "type": type_name.to_upper(),
            })
            index += 1
            continue
        if not item is Dictionary:
            continue
        var port_type := str(item.get("type", "DATA")).strip_edges()
        if port_type.is_empty():
            port_type = "DATA"
        var port_name := str(item.get("name", "")).strip_edges()
        if port_name.is_empty():
            port_name = "%s%d" % [fallback_prefix, index]
        result.append({
            "name": port_name,
            "type": port_type.to_upper(),
        })
        index += 1
    return result


func _merge_attributes(base: Dictionary, override: Dictionary) -> Dictionary:
    var merged: Dictionary = base.duplicate(true)
    for key in override.keys():
        var value: Variant = override[key]
        if merged.has(key) and merged[key] is Dictionary and value is Dictionary:
            merged[key] = _merge_attributes(merged[key], value)
        else:
            merged[key] = value
    return merged
