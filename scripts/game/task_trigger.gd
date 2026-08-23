class_name TaskTrigger
extends RefCounted

const AFTER_DISK_RUN := "after(Disk->run)"
const AFTER_VD_WRITE := "after(VD->write)"
const AFTER_VD_READ := "after(VD->read)"
const AFTER_FILE_RUN := "after(File->run)"
const AFTER_VF_WRITE := "after(VF->write)"


static func handle(signature: String, graph_edit: GraphEdit) -> void:
    if graph_edit == null or signature.is_empty():
        return

    var variables := GameState.get_current_level_variables()
    var tasks := GameState.get_current_level_tasks()
    for index in tasks.size():
        var task: Variant = tasks[index]
        if not task is Dictionary:
            continue
        if GameState.is_task_completed(index):
            continue
        if str(task.get("trigger", "")) != signature:
            continue

        var title := str(task.get("title", ""))
        if GoalValidator.evaluate_task(task as Dictionary, graph_edit, variables):
            GameState.mark_task_completed(index)
            EditorLog.info("任务完成: %s" % title)
        else:
            EditorLog.warn("任务未完成: %s" % title)


static func parse(signature: String) -> Dictionary:
    var trimmed := signature.strip_edges()
    if trimmed.begins_with("after(") and trimmed.ends_with(")"):
        return _parse_arrow_event(trimmed.substr(6, trimmed.length() - 7), "after")
    if trimmed.begins_with("on(") and trimmed.ends_with(")"):
        return _parse_arrow_event(trimmed.substr(3, trimmed.length() - 4), "on")
    return {}


static func _parse_arrow_event(body: String, mode: String) -> Dictionary:
    var parts := body.split("->", false, 1)
    if parts.size() != 2:
        return {}

    return {
        "mode": mode,
        "target": parts[0].strip_edges(),
        "event": parts[1].strip_edges(),
    }
