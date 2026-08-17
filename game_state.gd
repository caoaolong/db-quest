extends Node

const LEVEL_LIST_PATH := "res://data/level_list.json"
const NODE_TYPE_LIST_PATH := "res://data/node_type_list.json"

# 当前的关卡
var current_level: int = 1
var available_nodes: Array[String] = []
var node_types: Dictionary = {}


func _ready() -> void:
    _load_node_types()
    _load_level_config()


func is_node_available(node_name: String) -> bool:
    return node_name in available_nodes


func get_node_tab(type_name: String) -> String:
    match type_name:
        "DiskAdapter":
            return "Disk"
        _:
            return type_name


func resolve_node_config(item: Dictionary) -> Dictionary:
    var type_name := str(item.get("type", ""))
    if not node_types.has(type_name):
        push_error("Unknown node type: %s" % type_name)
        return {}

    var resolved: Dictionary = node_types[type_name].duplicate(true)
    resolved["name"] = str(item.get("name", ""))
    resolved["type"] = type_name
    resolved["label"] = str(item.get("label", ""))

    if item.has("scene"):
        resolved["scene"] = str(item["scene"])

    if item.has("attributes") and item["attributes"] is Dictionary:
        var base_attributes: Dictionary = resolved.get("attributes", {})
        resolved["attributes"] = _merge_attributes(base_attributes, item["attributes"])

    return resolved


func _load_node_types() -> void:
    node_types.clear()

    if not FileAccess.file_exists(NODE_TYPE_LIST_PATH):
        push_error("Node type list file not found: %s" % NODE_TYPE_LIST_PATH)
        return

    var file := FileAccess.open(NODE_TYPE_LIST_PATH, FileAccess.READ)
    if file == null:
        push_error("Failed to open node type list: %s" % NODE_TYPE_LIST_PATH)
        return

    var parsed = JSON.parse_string(file.get_as_text())
    if parsed == null:
        push_error("Failed to parse node type list JSON: %s" % NODE_TYPE_LIST_PATH)
        return

    if not parsed is Dictionary:
        push_error("Unexpected node type list JSON format: %s" % NODE_TYPE_LIST_PATH)
        return

    node_types = parsed


func _load_level_config() -> void:
    available_nodes.clear()

    if not FileAccess.file_exists(LEVEL_LIST_PATH):
        push_error("Level list file not found: %s" % LEVEL_LIST_PATH)
        return

    var file := FileAccess.open(LEVEL_LIST_PATH, FileAccess.READ)
    if file == null:
        push_error("Failed to open level list: %s" % LEVEL_LIST_PATH)
        return

    var parsed = JSON.parse_string(file.get_as_text())
    if parsed == null:
        push_error("Failed to parse level list JSON: %s" % LEVEL_LIST_PATH)
        return

    if not parsed is Array:
        push_error("Unexpected level list JSON format: %s" % LEVEL_LIST_PATH)
        return

    for entry in parsed:
        if not entry is Dictionary:
            continue
        if int(entry.get("level", 0)) != current_level:
            continue

        for node_name in entry.get("nodes", []):
            available_nodes.append(str(node_name))
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
