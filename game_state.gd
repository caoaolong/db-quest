extends Node

const LEVEL_LIST_PATH := "res://data/level_list.json"

# 当前的关卡
var current_level: int = 1
var available_nodes: Array[String] = []


func _ready() -> void:
    _load_level_config()


func is_node_available(node_name: String) -> bool:
    return node_name in available_nodes


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
