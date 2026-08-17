class_name DiskNode
extends BaseNode

@export var title: String = "磁盘"

@onready var progress: ProgressBar = $VBoxContainer/ProgressBar


func _ready() -> void:
    super._ready()
    progress.value = 65
