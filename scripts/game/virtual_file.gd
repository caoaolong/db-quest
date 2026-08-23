class_name VirtualFile
extends RefCounted

const PATH := "user://virtual_file.bin"
const SIZE_BYTES := 16 * 1024 * 1024
const PAGE_SIZE := 4096
const CHUNK_SIZE := 1024 * 1024


static func ensure_exists() -> String:
    if FileAccess.file_exists(PATH):
        return PATH

    var file := FileAccess.open(PATH, FileAccess.WRITE)
    if file == null:
        push_error("Failed to create virtual file: %s" % PATH)
        return ""

    var chunk := PackedByteArray()
    chunk.resize(CHUNK_SIZE)

    var remaining := SIZE_BYTES
    while remaining > 0:
        var write_size := mini(remaining, CHUNK_SIZE)
        if write_size == CHUNK_SIZE:
            file.store_buffer(chunk)
        else:
            var tail := PackedByteArray()
            tail.resize(write_size)
            file.store_buffer(tail)
        remaining -= write_size

    file.close()
    return PATH


static func get_size_bytes() -> int:
    return SIZE_BYTES


static func get_page_count() -> int:
    return int(SIZE_BYTES / float(PAGE_SIZE))


static func read_page(path: String, page_index: int) -> PackedByteArray:
    return read_bytes(path, page_index * PAGE_SIZE, PAGE_SIZE)


static func read_bytes(path: String, byte_offset: int, length: int) -> PackedByteArray:
    if path.is_empty():
        push_error("Virtual file path is empty")
        return PackedByteArray()
    if length <= 0:
        return PackedByteArray()

    if byte_offset < 0 or byte_offset + length > SIZE_BYTES:
        push_error("Byte range out of file: offset=%d length=%d" % [byte_offset, length])
        return PackedByteArray()

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("Failed to open virtual file for read: %s" % path)
        return PackedByteArray()

    file.seek(byte_offset)
    return file.get_buffer(length)


static func write_page(path: String, page_index: int, data: PackedByteArray) -> bool:
    return write_pages(path, page_index, 1, data)


static func write_pages(path: String, start_page: int, count: int, data: PackedByteArray) -> bool:
    if path.is_empty():
        push_error("Virtual file path is empty")
        return false
    if count <= 0:
        return false

    var length := count * PAGE_SIZE
    var offset := start_page * PAGE_SIZE
    if offset < 0 or offset + length > SIZE_BYTES:
        push_error("Page range out of file: start=%d count=%d" % [start_page, count])
        return false

    var file := FileAccess.open(path, FileAccess.READ_WRITE)
    if file == null:
        push_error("Failed to open virtual file for write: %s" % path)
        return false

    var payload := clip_to_length(data, length)
    file.seek(offset)
    file.store_buffer(payload)
    file.close()
    return true


static func clip_to_length(data: PackedByteArray, length: int) -> PackedByteArray:
    var payload := data.duplicate()
    if payload.size() < length:
        payload.resize(length) # 不足时用 0 补齐
    elif payload.size() > length:
        payload = payload.slice(0, length)
    return payload


static func clip_to_page(data: PackedByteArray) -> PackedByteArray:
    return clip_to_length(data, PAGE_SIZE)
