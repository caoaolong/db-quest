extends Control
class_name LevelList

const LEVEL_CARD_SCENE := preload("res://scenes/level_list/level_card.tscn")

@onready var _grid: GridContainer = $PanelContainer/MarginContainer/GridContainer


func _ready() -> void:
    _build_level_list()


func _build_level_list() -> void:
    for child in _grid.get_children():
        child.free()

    for entry in GameState.get_level_entries():
        if not entry is Dictionary:
            continue

        var card := LEVEL_CARD_SCENE.instantiate() as LevelCard
        _grid.add_child(card)
        card.setup(entry as Dictionary)
