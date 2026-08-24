class_name ReadBuffer
extends RefCounted

## 玩家从 Disk 读出的缓存，按虚拟磁盘扇区位置对齐。
## 未读过的扇区不参与比对；任务用 RB[n] / RB[n:] 检查本缓存，而不是 Check 节点。

var _sectors: Dictionary = {}


func clear() -> void:
    _sectors.clear()


func record(start_sector: int, data: PackedByteArray) -> void:
    if start_sector < 0 or data.is_empty():
        return

    var offset := 0
    var sector_index := start_sector
    while offset < data.size():
        var chunk := data.slice(offset, mini(offset + VirtualDisk.SECTOR_SIZE, data.size()))
        if chunk.size() < VirtualDisk.SECTOR_SIZE:
            chunk.resize(VirtualDisk.SECTOR_SIZE)
        _sectors[sector_index] = chunk
        offset += VirtualDisk.SECTOR_SIZE
        sector_index += 1


func has_sector(sector_index: int) -> bool:
    return _sectors.has(sector_index)


func is_range_covered(byte_offset: int, length: int) -> bool:
    if byte_offset < 0 or length <= 0:
        return false

    var start_sector := floori(float(byte_offset) / float(VirtualDisk.SECTOR_SIZE))
    var end_sector := floori(float(byte_offset + length - 1) / float(VirtualDisk.SECTOR_SIZE))
    for sector_index in range(start_sector, end_sector + 1):
        if not _sectors.has(sector_index):
            return false
    return true


func read_sector(sector_index: int) -> PackedByteArray:
    if not _sectors.has(sector_index):
        return PackedByteArray()
    return (_sectors[sector_index] as PackedByteArray).duplicate()


func read_bytes(byte_offset: int, length: int) -> PackedByteArray:
    if not is_range_covered(byte_offset, length):
        return PackedByteArray()

    var result := PackedByteArray()
    result.resize(length)
    var copied := 0
    while copied < length:
        var abs_offset := byte_offset + copied
        var sector_index := floori(float(abs_offset) / float(VirtualDisk.SECTOR_SIZE))
        var within := abs_offset % VirtualDisk.SECTOR_SIZE
        var sector: PackedByteArray = _sectors[sector_index]
        var take := mini(VirtualDisk.SECTOR_SIZE - within, length - copied)
        for i in take:
            result[copied + i] = sector[within + i]
        copied += take
    return result
