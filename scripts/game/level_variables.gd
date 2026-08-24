class_name LevelVariables
extends RefCounted


static func expand_text(text: String) -> String:
    if text.is_empty():
        return text
    return _expand_file_placeholders(text, false)


static func expand_goal(goal: String) -> String:
    if goal.is_empty():
        return goal
    return _expand_file_placeholders(goal, true)


static func _expand_file_placeholders(text: String, as_goal_literal: bool) -> String:
    var files := GameState.get_level_files()
    var result := text
    for key in files.keys():
        var file_name := str(key)
        var value := str(files[key])
        var tokens := [
            "${files.%s}" % file_name,
            "${files[%s]}" % file_name,
        ]
        for token in tokens:
            if as_goal_literal:
                result = result.replace(token, _format_goal_literal(value))
            else:
                result = result.replace(token, value)
    return result


static func _format_goal_literal(value: Variant) -> String:
    if value is int or value is float:
        return str(value)
    return "\"%s\"" % str(value).replace("\"", "\\\"")
