class_name DataSplitNode
extends BaseNode

"""
{
    "chunk_size": 512
}
"""

@onready var chunk_size_input: SpinBox = $VBoxContainer/SpinBox


func _ready() -> void:
    super._ready()
    chunk_size_input.min_value = 1
    chunk_size_input.max_value = 9223372036854775807
    chunk_size_input.value_changed.connect(_on_chunk_size_changed)
    if not data.has("chunk_size"):
        chunk_size_input.value = 512


func _configure_action_bar() -> void:
    if action == null:
        return
    action.set_run_visible(true)


func _sync_data_from_controls() -> void:
    data["chunk_size"] = int(chunk_size_input.value)


func _sync_controls_from_data() -> void:
    if data.has("chunk_size"):
        chunk_size_input.value = int(data["chunk_size"])


func get_chunk_size() -> int:
    _sync_data_from_controls()
    return maxi(1, int(data.get("chunk_size", 512)))


func _on_chunk_size_changed(_value: float) -> void:
    _sync_data_from_controls()
    schedule_save()


func _on_run_clicked() -> void:
    var graph_node := get_parent() as GraphNode
    var graph_edit := get_graph_edit()
    if graph_node == null or graph_edit == null:
        return
    if graph_edit.has_method("run_split_node"):
        graph_edit.run_split_node(graph_node)


func run(inputs: Dictionary = {}) -> Variant:
    var source: Variant = _first_input_value(inputs)
    if source == null:
        return []
    return split_data(source, get_chunk_size())


static func split_data(source: Variant, chunk_size: int) -> Array:
    if chunk_size <= 0:
        return []

    var bytes: PackedByteArray = _to_bytes(source)
    if bytes.is_empty():
        return []

    var chunks: Array = []
    var offset := 0
    while offset < bytes.size():
        var end := mini(offset + chunk_size, bytes.size())
        chunks.append(bytes.slice(offset, end).get_string_from_utf8())
        offset += chunk_size
    return chunks


static func _to_bytes(source: Variant) -> PackedByteArray:
    if source is PackedByteArray:
        return source
    return str(source).to_utf8_buffer()


func _first_input_value(inputs: Dictionary) -> Variant:
    if inputs.is_empty():
        return null
    var keys: Array = inputs.keys()
    keys.sort()
    return inputs[keys[0]]
