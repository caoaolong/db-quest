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
    return int(SIZE_BYTES / (1024 * 1024))


static func read_sector(path: String, sector_index: int) -> PackedByteArray:
    if path.is_empty():
        push_error("Virtual disk path is empty")
        return PackedByteArray()

    var offset := sector_index * SECTOR_SIZE
    if offset < 0 or offset + SECTOR_SIZE > SIZE_BYTES:
        push_error("Sector out of range: %d" % sector_index)
        return PackedByteArray()

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("Failed to open virtual disk for read: %s" % path)
        return PackedByteArray()

    file.seek(offset)
    return file.get_buffer(SECTOR_SIZE)


static func write_sector(path: String, sector_index: int, data: PackedByteArray) -> bool:
    if path.is_empty():
        push_error("Virtual disk path is empty")
        return false

    var offset := sector_index * SECTOR_SIZE
    if offset < 0 or offset + SECTOR_SIZE > SIZE_BYTES:
        push_error("Sector out of range: %d" % sector_index)
        return false

    var file := FileAccess.open(path, FileAccess.READ_WRITE)
    if file == null:
        push_error("Failed to open virtual disk for write: %s" % path)
        return false

    # 每次只写入一个扇区，超出部分在调用方截断
    var sector_data := clip_to_sector(data)

    file.seek(offset)
    file.store_buffer(sector_data)
    file.close()
    return true


static func clip_to_sector(data: PackedByteArray) -> PackedByteArray:
    var sector_data := data.duplicate()
    if sector_data.size() < SECTOR_SIZE:
        sector_data.resize(SECTOR_SIZE) # 不足 512 字节时用 0 补齐
    elif sector_data.size() > SECTOR_SIZE:
        sector_data = sector_data.slice(0, SECTOR_SIZE)
    return sector_data
