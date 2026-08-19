class_name LevelVariables
extends RefCounted


static func expand_text(text: String, variables: Dictionary = {}) -> String:
    if text.is_empty() or variables.is_empty():
        return text

    var result := text
    for key in variables.keys():
        result = result.replace("${%s}" % key, str(variables[key]))
    return result


static func expand_goal(goal: String, variables: Dictionary = {}) -> String:
    if goal.is_empty() or variables.is_empty():
        return goal

    var result := goal
    for key in variables.keys():
        result = result.replace("${%s}" % key, _format_goal_literal(variables[key]))
    return result


static func expand_text_for_current_level(text: String) -> String:
    return expand_text(text, GameState.get_current_level_variables())


static func expand_goal_for_current_level(goal: String) -> String:
    return expand_goal(goal, GameState.get_current_level_variables())


static func _format_goal_literal(value: Variant) -> String:
    if value is int or value is float:
        return str(value)
    return "\"%s\"" % str(value).replace("\"", "\\\"")
