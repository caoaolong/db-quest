class_name DiskNode
extends BaseNode

@export var title: String = "磁盘"

@onready var progress: ProgressBar = $VBoxContainer/ProgressBar


func _ready() -> void:
    super._ready()
    if not data.has("progress"):
        progress.value = 65


func _sync_data_from_controls() -> void:
    data["progress"] = progress.value


func _sync_controls_from_data() -> void:
    if data.has("progress"):
        progress.value = float(data["progress"])
