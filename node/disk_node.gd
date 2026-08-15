class_name DiskNode
extends PanelContainer

@export var title: String = "磁盘"
@export var subtitle: String = "当前用量"

@onready var label: Label = $VBoxContainer/Label
@onready var progress: ProgressBar = $VBoxContainer/ProgressBar

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    label.text = subtitle
    progress.value = 65