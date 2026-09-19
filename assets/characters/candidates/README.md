# 待选敌人模型

保留哥布林 `goblin.blend`、史莱姆 `slime.blend`、石头人 `golem.blend`，及各自正面/背面/三分之四预览。它们是未绑定、未接入游戏的静态候选，不能当作已完成敌人。

骷髅已完成选择与接入，当前制作源在 `../blender/skeleton_rig.blend`；旧骷髅初稿和四角色旧总览已退出活跃工程。初稿生成器不再保留，精修以保存的 Blender 文件为准。

Blender 4.2 打开：Outliner 中 `MODEL_*` 为可编辑角色，`STUDIO__not_part_of_model` 为摄影环境。各角色预览独立取景，不可用于比较身高。`goblin_concept_reference.png` 是已确认概念参考，不是实际烘焙图。

坐标为米、Z 向上、面向 -Y；导出 GLB 时转换为 Godot 坐标。目录的 `.gdignore` 阻止 Godot 自动导入 `.blend`。选定后再整理拓扑、骨骼、权重与动作，并验证十二朝向；不要把软体、石头人硬套类人骨架。
