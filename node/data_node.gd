class_name DataNode
extends BaseNode

var data: String


func _on_display_clicked() -> void:
    action.display_data(data)
