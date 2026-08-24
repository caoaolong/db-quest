class_name DataMergeNode
extends BaseNode

"""
{
    "merged": ""
}
"""


func _sync_data_from_controls() -> void:
    pass


func _sync_controls_from_data() -> void:
    pass


func run(inputs: Dictionary = {}) -> Variant:
    var chunk := _item_to_bytes(_first_input_value(inputs))
    var merged := PackedByteArray()
    if queue_index > 0:
        merged = _to_bytes(data.get("merged", PackedByteArray()))
    merged.append_array(chunk)

    var total := maxi(1, queue_total)
    queue_length = total
    remember_merge(merged)
    set_queue_progress(queue_index + 1, total)
    EditorLog.info("数据合并：接收 %d / %d，累计 %d 字节" % [queue_index + 1, total, merged.size()])
    return merged


func remember_merge(merged: PackedByteArray) -> void:
    data["merged"] = merged
    schedule_save()


func clear_run_data() -> void:
    data.erase("merged")
    queue_length = 0
    reset_queue_progress()


func _on_display_clicked() -> void:
    var bytes := _to_bytes(data.get("merged", PackedByteArray()))
    if bytes.is_empty():
        EditorLog.warn("数据合并：暂无数据，请先运行")
        return
    action.display_data(bytes, DisplayDialog.DataType.BINARY)


static func merge_data(source: Variant) -> PackedByteArray:
    return _item_to_bytes(source)


static func _item_to_bytes(item: Variant) -> PackedByteArray:
    if item == null:
        return PackedByteArray()
    if item is PackedByteArray:
        return item as PackedByteArray
    if item is Dictionary:
        var payload := item as Dictionary
        if payload.has("data"):
            return _item_to_bytes(payload["data"])
    if item is Array:
        var bytes := PackedByteArray()
        for nested in item:
            bytes.append_array(_item_to_bytes(nested))
        return bytes
    return str(item).to_utf8_buffer()


static func _to_bytes(source: Variant) -> PackedByteArray:
    return _item_to_bytes(source)


func _first_input_value(inputs: Dictionary) -> Variant:
    if inputs.is_empty():
        return null
    var keys: Array = inputs.keys()
    keys.sort()
    return inputs[keys[0]]
