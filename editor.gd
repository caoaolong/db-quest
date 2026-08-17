extends Control

@onready var _tab_bar: TabBar = $VBoxContainer/TabBar


func _ready() -> void:
    _build_tab_bar()


func _build_tab_bar() -> void:
    while _tab_bar.tab_count > 0:
        _tab_bar.remove_tab(0)

    for category in GameState.get_categories():
        _tab_bar.add_tab(category)
