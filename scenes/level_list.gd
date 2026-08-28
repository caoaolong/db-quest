extends Control
class_name LevelList

const LEVEL_CARD_SCENE := preload("res://scenes/level_list/level_card.tscn")
const GRID_COLUMNS := 4
const CHAPTER_TITLE_FONT_SIZE := 24
const CHAPTER_SPACING := 24

@onready var _content: VBoxContainer = $PanelContainer/MarginContainer/ScrollContainer/ContentVBox


func _ready() -> void:
    _build_level_list()


func _build_level_list() -> void:
    for child in _content.get_children():
        child.free()

    var chapters := _group_levels_by_chapter()
    for section in chapters:
        _content.add_child(_create_chapter_title(str(section.get("chapter", ""))))

        var grid := GridContainer.new()
        grid.columns = GRID_COLUMNS
        grid.add_theme_constant_override("h_separation", 16)
        grid.add_theme_constant_override("v_separation", 16)
        grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _content.add_child(grid)

        for level_item in section.get("levels", []):
            if not level_item is Dictionary:
                continue

            var card := LEVEL_CARD_SCENE.instantiate() as LevelCard
            grid.add_child(card)
            card.setup(
                int(level_item.get("index", 0)),
                level_item.get("entry", {}) as Dictionary
            )


func _group_levels_by_chapter() -> Array:
    var chapters: Array = []
    var chapter_map: Dictionary = {}

    var entries := GameState.get_level_entries()
    for index in entries.size():
        var entry: Dictionary = entries[index]
        var chapter := str(entry.get("chapter", "")).strip_edges()
        if chapter.is_empty():
            chapter = "未分类"

        if not chapter_map.has(chapter):
            var section := {
                "chapter": chapter,
                "levels": [],
            }
            chapter_map[chapter] = section
            chapters.append(section)

        chapter_map[chapter]["levels"].append({
            "index": index + 1,
            "entry": entry,
        })

    return chapters


func _create_chapter_title(title: String) -> Label:
    var label := Label.new()
    label.text = title
    label.add_theme_font_size_override("font_size", CHAPTER_TITLE_FONT_SIZE)
    label.add_theme_constant_override("margin_bottom", CHAPTER_SPACING)
    return label
