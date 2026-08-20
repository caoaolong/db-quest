class_name TaskProgress
extends RefCounted

const PROGRESS_DIR := "user://task_progress/"


static func get_path(level: int) -> String:
    return "%slevel_%d.json" % [PROGRESS_DIR, level]


static func save(level: int, completed_indices: Array[int]) -> void:
    _ensure_dir()

    var path := get_path(level)
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        push_error("Failed to save task progress: %s" % path)
        return

    var data: Array = []
    for index in completed_indices:
        data.append(index)

    file.store_string(JSON.stringify(data))
    file.close()


static func load(level: int) -> Array[int]:
    var path := get_path(level)
    if not FileAccess.file_exists(path):
        return []

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("Failed to open task progress: %s" % path)
        return []

    var parsed = JSON.parse_string(file.get_as_text())
    if not parsed is Array:
        push_error("Invalid task progress format: %s" % path)
        return []

    var result: Array[int] = []
    for item in parsed:
        result.append(int(item))
    return result


static func _ensure_dir() -> void:
    var dir := DirAccess.open("user://")
    if dir == null:
        return
    if not dir.dir_exists("task_progress"):
        dir.make_dir("task_progress")
