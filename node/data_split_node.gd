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
    chunk_size_input.max_value = 1_000_000_000
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


func run(inputs: Dictionary = {}) -> Variant:
    var source: Variant = _first_input_value(inputs)
    if source == null:
        remember_split(PackedByteArray(), [])
        queue_length = 0
        set_queue_progress(0, 0)
        return PackedByteArray()

    var chunks: Array = split_data(source, get_chunk_size())
    remember_split(source, chunks)
    queue_length = chunks.size()
    if chunks.is_empty():
        EditorLog.warn("数据分割：无有效数据")
        set_queue_progress(0, 0)
        return PackedByteArray()

    var index := clampi(queue_index, 0, chunks.size() - 1)
    var chunk := chunks[index] as PackedByteArray
    set_queue_progress(index + 1, chunks.size())
    EditorLog.info("数据分割：投递 %d / %d（%d 字节）" % [index + 1, chunks.size(), chunk.size()])
    return chunk


func remember_split(source: Variant, chunks: Array) -> void:
    data["source"] = _to_bytes(source)
    data["chunks"] = chunks
    schedule_save()


func clear_run_data() -> void:
    data.erase("source")
    data.erase("chunks")
    queue_length = 0
    reset_queue_progress()


func _on_display_clicked() -> void:
    var bytes := _to_bytes(data.get("source", PackedByteArray()))
    if bytes.is_empty():
        var chunks: Variant = data.get("chunks", [])
        if chunks is Array:
            for chunk in chunks:
                bytes.append_array(_to_bytes(chunk))

    if bytes.is_empty():
        EditorLog.warn("数据分割：暂无数据，请先运行")
        return

    action.display_data(bytes, DisplayDialog.DataType.BINARY)


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
        chunks.append(bytes.slice(offset, end))
        offset += chunk_size
    return chunks


static func _to_bytes(source: Variant) -> PackedByteArray:
    if source is PackedByteArray:
        return source
    if source is Array:
        var bytes := PackedByteArray()
        for item in source:
            bytes.append_array(_to_bytes(item))
        return bytes
    return str(source).to_utf8_buffer()


func _first_input_value(inputs: Dictionary) -> Variant:
    if inputs.is_empty():
        return null
    var keys: Array = inputs.keys()
    keys.sort()
    return inputs[keys[0]]
