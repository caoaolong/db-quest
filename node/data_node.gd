class_name DataNode
extends BaseNode

var runtime_data: String = ""


func _on_display_clicked() -> void:
    action.display_data(runtime_data)
