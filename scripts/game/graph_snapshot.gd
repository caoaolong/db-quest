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


## 本关尚无快照，且关卡配置 load_previous 为 true 时，复制上一关快照作为初始结构。
static func load_or_inherit(level: int) -> Dictionary:
    if exists(level):
        return GraphSnapshot.load_snapshot(level)

    if not GameState.load_previous or level <= 1:
        return {}

    var previous := GraphSnapshot.load_snapshot(level - 1)
    if previous.is_empty():
        return {}

    var inherited := previous.duplicate(true)
    inherited["level"] = level
    save(level, inherited)
    return inherited


static func _ensure_dir() -> void:
    var dir := DirAccess.open("user://")
    if dir == null:
        return
    if not dir.dir_exists("snapshots"):
        dir.make_dir("snapshots")
