class_name VirtualDisk
extends RefCounted

const PATH := "user://virtual_disk.bin"
const SIZE_BYTES := 64 * 1024 * 1024
const SECTOR_SIZE := 512
const CHUNK_SIZE := 1024 * 1024


static func ensure_exists() -> String:
    if FileAccess.file_exists(PATH):
        return PATH

    var file := FileAccess.open(PATH, FileAccess.WRITE)
    if file == null:
        push_error("Failed to create virtual disk: %s" % PATH)
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


static func get_size_mb() -> int:
    return int(SIZE_BYTES / (1024.0 * 1024.0))


static func read_sector(path: String, sector_index: int) -> PackedByteArray:
    return read_bytes(path, sector_index * SECTOR_SIZE, SECTOR_SIZE)


static func read_bytes(path: String, byte_offset: int, length: int) -> PackedByteArray:
    if path.is_empty():
        push_error("Virtual disk path is empty")
        return PackedByteArray()
    if length <= 0:
        return PackedByteArray()

    if byte_offset < 0 or byte_offset + length > SIZE_BYTES:
        push_error("Byte range out of disk: offset=%d length=%d" % [byte_offset, length])
        return PackedByteArray()

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("Failed to open virtual disk for read: %s" % path)
        return PackedByteArray()

    file.seek(byte_offset)
    return file.get_buffer(length)


static func write_sector(path: String, sector_index: int, data: PackedByteArray) -> bool:
    return write_sectors(path, sector_index, 1, data)


static func write_sectors(path: String, start_sector: int, count: int, data: PackedByteArray) -> bool:
    if path.is_empty():
        push_error("Virtual disk path is empty")
        return false
    if count <= 0:
        return false

    var length := count * SECTOR_SIZE
    var offset := start_sector * SECTOR_SIZE
    if offset < 0 or offset + length > SIZE_BYTES:
        push_error("Sector range out of disk: start=%d count=%d" % [start_sector, count])
        return false

    var file := FileAccess.open(path, FileAccess.READ_WRITE)
    if file == null:
        push_error("Failed to open virtual disk for write: %s" % path)
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


static func clip_to_sector(data: PackedByteArray) -> PackedByteArray:
    return clip_to_length(data, SECTOR_SIZE)
