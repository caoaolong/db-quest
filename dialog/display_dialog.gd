extends PopupPanel
class_name DisplayDialog

@onready var text_edit: TextEdit = $VBoxContainer/TextEdit
@onready var display_size: Label = $VBoxContainer/HBoxContainer/Size

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
    pass


func load_data(data: String) -> void:
    text_edit.text = data
    display_size.text = "{size} Bytes".format({
        "size": len(data)
    })
    
func _on_close_pressed() -> void:
    hide()
