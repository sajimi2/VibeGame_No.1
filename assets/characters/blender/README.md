# 角色制作源

玩家 `player_rig.blend`、守卫 `guard_rig.blend`、弓箭手 `archer_rig.blend`、骷髅 `skeleton_rig.blend` 是当前可编辑源。使用 Blender 4.2 打开；Godot 不直接导入此目录。

身体网格按 `art_part` 分为 upper/lower，保留 `bound_bone` 和 15 骨名称。Action Editor 选择动作；动作存在文件中，修改后保存，不再运行旧的程序模型生成器。

统一导出入口为 `tools/blender/export_characters.py`，再由 `tools/bake_characters.gd` 离线烘焙 96×96、十二朝向。操作步骤、补色回导和边界见 [美术流程](../../../docs/ART_PIPELINE.md)。导出和验证不会写回 `.blend`。
