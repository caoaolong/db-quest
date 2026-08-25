extends PopupDialog
class_name HelpDialog

const DEFAULT_SIZE := Vector2(720, 480)

@onready var _title: Label = $VBoxContainer/Title
@onready var _text_edit: TextEdit = $VBoxContainer/TextEdit


func _ready() -> void:
    super._ready()
    if _text_edit:
        _text_edit.editable = false
        _text_edit.wrap_mode = TextEdit.LINE_WRAPPING_NONE


func show_help(path: String, level_name: String = "") -> void:
    var content := _load_help_text(path)
    if content.is_empty() and not path.is_empty():
        EditorLog.warn("无法加载帮助文档: %s" % path)
        content = "暂无帮助内容。"
    elif path.is_empty():
        content = "本关卡暂未配置帮助文档。"

    if _title:
        if level_name.is_empty():
            _title.text = "帮助"
        else:
            _title.text = "帮助 · %s" % level_name

    if _text_edit:
        _text_edit.text = content
        set_clamped_content_size(_text_edit, DEFAULT_SIZE)

    await refresh_popup_size()
    popup_centered()


func _load_help_text(path: String) -> String:
    var help_path := path.strip_edges()
    if help_path.is_empty():
        return ""
    if not FileAccess.file_exists(help_path):
        return ""
    var file := FileAccess.open(help_path, FileAccess.READ)
    if file == null:
        return ""
    return file.get_as_text()


func _on_close_pressed() -> void:
    close_dialog()
