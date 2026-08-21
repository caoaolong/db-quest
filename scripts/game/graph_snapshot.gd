class_name GraphSnapshot
extends RefCounted

const SNAPSHOT_DIR := "user://snapshots/"


static func get_path(level: int) -> String:
    return "%slevel_%d.json" % [SNAPSHOT_DIR, level]


static func save(level: int, data: Dictionary) -> void:
    _ensure_dir()

    var path := get_path(level)
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        push_error("Failed to save graph snapshot: %s" % path)
        return

    file.store_string(JSON.stringify(data, "\t"))
    file.close()


static func exists(level: int) -> bool:
    return FileAccess.file_exists(get_path(level))


static func load_snapshot(level: int) -> Dictionary:
    var path := get_path(level)
    if not exists(level):
        return {}

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("Failed to open graph snapshot: %s" % path)
        return {}

    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if parsed is Dictionary:
        return parsed

    push_error("Invalid graph snapshot format: %s" % path)
    return {}


## 本关没有自己的图（或只有系统节点）时，复制上一关快照作为初始结构。
static func load_or_inherit(level: int) -> Dictionary:
    if level <= 1:
        return GraphSnapshot.load_snapshot(level)

    var current := GraphSnapshot.load_snapshot(level)
    if _has_user_nodes(current):
        return current

    var previous := GraphSnapshot.load_snapshot(level - 1)
    if previous.is_empty():
        return current

    var inherited := previous.duplicate(true)
    inherited["level"] = level
    save(level, inherited)
    return inherited


static func _has_user_nodes(snapshot: Dictionary) -> bool:
    if snapshot.is_empty():
        return false

    for node_data in snapshot.get("nodes", []):
        if not node_data is Dictionary:
            continue
        var template_name := str(node_data.get("template_name", ""))
        if template_name.is_empty():
            continue
        if GameState.is_system_node_name(template_name):
            continue
        return true

    return false


static func _ensure_dir() -> void:
    var dir := DirAccess.open("user://")
    if dir == null:
        return
    if not dir.dir_exists("snapshots"):
        dir.make_dir("snapshots")
