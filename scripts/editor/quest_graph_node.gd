class_name QuestGraphNode
extends GraphNode

const PORT_SIZE := Vector2(10.0, 10.0)


func _draw_port(slot_index: int, position: Vector2i, left: bool, color: Color) -> void:
    var center := Vector2(position)
    var half_width := PORT_SIZE.x * 0.5
    var half_height := PORT_SIZE.y * 0.5

    var points: PackedVector2Array
    if left:
        # 输入端口：三角形角朝内（指向节点内部）
        points = PackedVector2Array([
            center + Vector2(half_width, 0.0),
            center + Vector2(-half_width, half_height),
            center + Vector2(-half_width, -half_height),
        ])
    else:
        # 输出端口：三角形角朝外（指向节点外部）
        points = PackedVector2Array([
            center + Vector2(half_width, 0.0),
            center + Vector2(-half_width, half_height),
            center + Vector2(-half_width, -half_height),
        ])

    draw_colored_polygon(points, color)
