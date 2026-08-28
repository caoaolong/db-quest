class_name ComponentNode
extends BaseNode

"""
类节点：成员变量为普通 slots，成员函数从 node_list 预制列表中添加。
"""


func _ready() -> void:
    super._ready()
    if subtitle.is_empty():
        set_subtitle("类")
