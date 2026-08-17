class_name VirtualDisk
extends RefCounted

const PATH := "user://virtual_disk.bin"
const SIZE_BYTES := 64 * 1024 * 1024
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
