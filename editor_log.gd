extends Node

signal message_logged(message: String, level: String)

const LEVEL_INFO := "info"
const LEVEL_WARN := "warn"
const LEVEL_ERROR := "error"

const MAX_MESSAGES := 50

var _messages: Array[String] = []


func info(message: String) -> void:
    _append(message, LEVEL_INFO)


func warn(message: String) -> void:
    push_warning(message)
    _append(message, LEVEL_WARN)


func error(message: String) -> void:
    push_error(message)
    _append(message, LEVEL_ERROR)


func get_latest_message() -> String:
    if _messages.is_empty():
        return ""
    return _messages[-1]


func _append(message: String, level: String) -> void:
    if message.is_empty():
        return

    _messages.append(message)
    if _messages.size() > MAX_MESSAGES:
        _messages.pop_front()

    message_logged.emit(message, level)
