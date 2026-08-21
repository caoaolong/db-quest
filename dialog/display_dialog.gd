extends PopupDialog
class_name DisplayDialog

enum DataType {
    STRING,
    BINARY,
}

const BINARY_PAGE_SIZE := 512
const BINARY_BYTES_PER_LINE := 32
const HEX_CELL_WIDTH := 20
const ASCII_CELL_WIDTH := 12
const BINARY_LINE_HEIGHT := 24
const BINARY_CONTENT_WIDTH := HEX_CELL_WIDTH * 4 + 12 + BINARY_BYTES_PER_LINE * HEX_CELL_WIDTH + ASCII_CELL_WIDTH + BINARY_BYTES_PER_LINE * ASCII_CELL_WIDTH + 16

@onready var tab_container: TabContainer = $VBoxContainer/TabContainer
@onready var text_edit: TextEdit = $VBoxContainer/TabContainer/StringPanel/TextEdit
@onready var binary_lines: VBoxContainer = $VBoxContainer/TabContainer/BinaryPanel/VBoxContainer/BinaryLines
@onready var binary_page_info: Label = $VBoxContainer/TabContainer/BinaryPanel/VBoxContainer/Pager/PageInfo
@onready var binary_prev_button: Button = $VBoxContainer/TabContainer/BinaryPanel/VBoxContainer/Pager/Prev
@onready var binary_next_button: Button = $VBoxContainer/TabContainer/BinaryPanel/VBoxContainer/Pager/Next
@onready var display_size: Label = $VBoxContainer/HBoxContainer/Size

var _mono_font: Font = preload("res://fonts/cjk.ttf")

var _binary_page: int = 0
var _binary_total_bytes: int = 0
var _binary_page_size: int = BINARY_PAGE_SIZE
var _binary_disk_path: String = ""
var _binary_data: PackedByteArray = PackedByteArray()


func load_data(data: Variant, data_type: DataType = DataType.STRING) -> void:
    tab_container.current_tab = data_type
    match data_type:
        DataType.STRING:
            _load_string_data(str(data))
        DataType.BINARY:
            _load_binary_data(data)


func _load_string_data(data: String) -> void:
    text_edit.text = data
    display_size.text = _format_byte_size(data.to_utf8_buffer().size())
    _fit_string_panel(data)


func _load_binary_data(data: Variant) -> void:
    _reset_binary_state()
    if data is Dictionary:
        var source := data as Dictionary
        _binary_disk_path = str(source.get("disk_path", ""))
        _binary_total_bytes = int(source.get("total_bytes", 0))
        _binary_page_size = int(source.get("page_size", BINARY_PAGE_SIZE))
        if _binary_total_bytes <= 0:
            _binary_total_bytes = VirtualDisk.get_size_bytes()
    elif data is PackedByteArray:
        _binary_data = data as PackedByteArray
        _binary_total_bytes = _binary_data.size()
    else:
        push_warning("Unsupported binary display data: %s" % type_string(typeof(data)))
        return

    _render_binary_page()


func _reset_binary_state() -> void:
    _binary_page = 0
    _binary_disk_path = ""
    _binary_data = PackedByteArray()
    _binary_page_size = BINARY_PAGE_SIZE
    _binary_total_bytes = 0


func _render_binary_page() -> void:
    var page_data := _read_binary_page_data()
    for child in binary_lines.get_children():
        child.free()

    var line_count := _fill_binary_lines(page_data)
    set_clamped_content_size(binary_lines, Vector2(BINARY_CONTENT_WIDTH, _binary_content_height(line_count)))
    _update_binary_pager()

    if visible:
        await refresh_popup_size()


func _read_binary_page_data() -> PackedByteArray:
    if not _binary_disk_path.is_empty():
        return VirtualDisk.read_sector(_binary_disk_path, _binary_page)

    var start := _binary_page * _binary_page_size
    if start >= _binary_data.size():
        return PackedByteArray()

    return _binary_data.slice(start, mini(start + _binary_page_size, _binary_data.size()))


func _fill_binary_lines(page_data: PackedByteArray) -> int:
    var line_count := ceili(page_data.size() / float(BINARY_BYTES_PER_LINE))
    var page_offset := _binary_page * _binary_page_size

    for line_index in range(line_count):
        var line_start := line_index * BINARY_BYTES_PER_LINE
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 12)
        binary_lines.add_child(row)
        row.add_child(_create_mono_label("%08X" % (page_offset + line_start), HEX_CELL_WIDTH * 4))
        row.add_child(_create_byte_grid(page_data, line_start, false))
        row.add_child(_create_mono_label("|", ASCII_CELL_WIDTH))
        row.add_child(_create_byte_grid(page_data, line_start, true))

    return line_count


func _create_byte_grid(page_data: PackedByteArray, line_start: int, as_ascii: bool) -> GridContainer:
    var grid := GridContainer.new()
    grid.columns = BINARY_BYTES_PER_LINE
    grid.add_theme_constant_override("h_separation", 0 if as_ascii else 8)
    grid.add_theme_constant_override("v_separation", 0)

    for byte_index in range(BINARY_BYTES_PER_LINE):
        var data_index := line_start + byte_index
        var text := " " if as_ascii else "  "
        if data_index < page_data.size():
            var byte := page_data[data_index]
            text = _byte_to_ascii_char(byte) if as_ascii else "%02X" % byte

        var alignment := HORIZONTAL_ALIGNMENT_CENTER if as_ascii else HORIZONTAL_ALIGNMENT_LEFT
        var width := ASCII_CELL_WIDTH if as_ascii else HEX_CELL_WIDTH
        grid.add_child(_create_mono_label(text, width, alignment))

    return grid


func _fit_string_panel(data: String) -> void:
    var font := text_edit.get_theme_font(&"font") if text_edit.get_theme_font(&"font") else ThemeDB.fallback_font
    var font_size := text_edit.get_theme_font_size(&"font_size")
    if font_size <= 0:
        font_size = ThemeDB.fallback_font_size

    var line_height := font.get_height(font_size) + 2.0
    var lines := data.split("\n")
    var max_width := 0.0
    for line in lines:
        max_width = maxf(max_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)

    set_clamped_content_size(
        text_edit,
        Vector2(max_width + 24.0, maxi(1, lines.size()) * line_height + 16.0)
    )


func _binary_content_height(line_count: int) -> float:
    var safe_line_count := maxi(line_count, 1)
    return float(safe_line_count * BINARY_LINE_HEIGHT + maxi(safe_line_count - 1, 0) * 4)


func _create_mono_label(
    text: String,
    cell_width: int,
    alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
    var label := Label.new()
    label.text = text
    label.horizontal_alignment = alignment
    label.add_theme_font_override("font", _mono_font)
    label.custom_minimum_size = Vector2(cell_width, 0)
    return label


func _byte_to_ascii_char(byte: int) -> String:
    return char(byte) if byte >= 32 and byte <= 126 else "."


func _format_byte_size(bytes: int) -> String:
    bytes = maxi(bytes, 0)
    const UNITS := ["B", "KB", "MB", "GB"]
    var value := float(bytes)
    var unit_index := 0

    while value >= 1024.0 and unit_index < UNITS.size() - 1:
        value /= 1024.0
        unit_index += 1

    if unit_index == 0:
        return "%d B" % bytes
    return "%s %s" % ["%.1f" % value if value >= 100.0 else "%.2f" % value, UNITS[unit_index]]


func _get_binary_total_pages() -> int:
    if _binary_total_bytes <= 0 or _binary_page_size <= 0:
        return 1
    return ceili(_binary_total_bytes / float(_binary_page_size))


func _update_binary_pager() -> void:
    var total_pages := _get_binary_total_pages()
    display_size.text = _format_byte_size(_binary_total_bytes)
    binary_page_info.text = "第 {current} / {total} 页  偏移 {offset}".format({
        "current": _binary_page + 1,
        "total": total_pages,
        "offset": "%08X" % (_binary_page * _binary_page_size),
    })
    binary_prev_button.disabled = _binary_page <= 0
    binary_next_button.disabled = _binary_page >= total_pages - 1


func _on_binary_prev_pressed() -> void:
    _change_binary_page(-1)


func _on_binary_next_pressed() -> void:
    _change_binary_page(1)


func _change_binary_page(delta: int) -> void:
    var next_page := _binary_page + delta
    if next_page < 0 or next_page >= _get_binary_total_pages():
        return
    _binary_page = next_page
    _render_binary_page()


func _on_close_pressed() -> void:
    close_dialog()
