class_name DataNode
extends PanelContainer

@export var subtitle: String = ""

@onready var label: Label = $VBoxContainer/Label

func _ready() -> void:
    label.text = subtitle
