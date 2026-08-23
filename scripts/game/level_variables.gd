class_name LevelVariables
extends RefCounted


static func expand_text(text: String, variables: Dictionary = {}) -> String:
    if text.is_empty():
        return text

    var result := _expand_file_placeholders(text, false)
    for key in variables.keys():
        result = result.replace("${%s}" % key, str(variables[key]))
    return result


static func expand_goal(goal: String, variables: Dictionary = {}) -> String:
    if goal.is_empty():
        return goal

    var result := _expand_file_placeholders(goal, true)
    for key in variables.keys():
        result = result.replace("${%s}" % key, _format_goal_literal(variables[key]))
    return result


static func expand_text_for_current_level(text: String) -> String:
    return expand_text(text, GameState.get_current_level_variables())


static func expand_goal_for_current_level(goal: String) -> String:
    return expand_goal(goal, GameState.get_current_level_variables())


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
