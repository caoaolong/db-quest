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


static func load(level: int) -> Dictionary:
    var path := get_path(level)
    if not FileAccess.file_exists(path):
        return {}

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("Failed to open graph snapshot: %s" % path)
        return {}

    var parsed = JSON.parse_string(file.get_as_text())
    if parsed is Dictionary:
        return parsed

    push_error("Invalid graph snapshot format: %s" % path)
    return {}


static func _ensure_dir() -> void:
    var dir := DirAccess.open("user://")
    if dir == null:
        return
    if not dir.dir_exists("snapshots"):
        dir.make_dir("snapshots")
