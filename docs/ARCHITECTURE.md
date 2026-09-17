# 当前 3D 架构

本文件描述现有代码，不规划新的框架。旧 2D 架构及任务派发文档在备份标签中。

## 装配与地图
`scenes/battlefield.tscn` 保存地面、19 个主要掩体及可编辑尺寸；根脚本 `world/battlefield.gd` 继承 `world/level.gd`。`world/height_sandbox.gd` 是同一基类的另一地图实现。

`level._ready()` 按原先次序：地形构建器 → 环境/光照 → 地图 → 效果 → 玩家 → 相机 → HUD → 战斗。`start_encounter()` 等待物理/普通帧后建立导航、敌人、任务、成长、结算。程序生成节点仍挂在原关卡根下，几何坐标和碰撞保持一致。

- `terrain_builder.gd`：输入关卡根与几何参数，输出 Mesh/Collision 节点，拥有材质缓存，不读取玩家/UI/任务。
- 地图通过 `spawn_point / objective_point / navigation_bounds / enemy_layout / _build_environment` 提供差异。
- `level.gd` 中的 `box/ramp/material/natural_ledge` 是薄的地图构造接口，具体实现统一委托给 terrain builder。
- `battle_prop.gd` 保留 `@tool` 编辑能力；`StoneVisual/StoneCollision` 可在编辑器阶段生成。
- Autoload 仅为 Godot AI 的运行工具辅助；游戏没有新增全局管理器。

## 攻击调用链
`player_combat._unhandled_input → player.update_aim → attack → _physics_process → motion.melee → strike → space_trace.trace → enemy.receive_strike`。

点击锁定方向；计时到有效窗口后按角度采样射线；`struck` 按实例 ID 去重。伤害由敌人按盾挡/身体/顶部决定。武器图形不是碰撞伤害源。弓箭先拉弓 0.14 秒，`arrow.gd` 连续检测飞行线段。

玩家移动独立在 `player._physics_process`；敌人每帧依次执行 `update_senses → choose_movement → move_and_slide → update_visuals`。这些是同一物理线程内的方法调用，不是多个并行任务。最后目击记忆只在真实看见玩家时更新；受到隐藏攻击时仅估计来袭方向。

## 装备、显示与存档
`camp_progress.setup(player, combat)` 只接收需要的系统；不再持有整个关卡。

```text
背包按钮 --equip_requested(id)--> camp_progress.equip
ActorInventory.try_equip --inventory_changed--> camp_progress.changed
                                              ├─ combat.apply_weapon(Resource)
                                              ├─ player.max_hp
                                              ├─ tactical_save.write_snapshot
                                              └─ inventory_panel.refresh(显示数据)
```

- `ItemInstance` / `ItemDefinition` 是 Resource 数据；库存拥有深拷贝，快照无活对象引用。
- `data/weapons/knife.tres`：16 伤害、1.45m、0.24s 动作、0.29s 间隔。
- `data/weapons/cleaver.tres`：26 伤害、2.45m、0.48s 动作、0.62s 间隔。
- 参数和背包说明从同一 Resource 读取；`apply_weapon` 由战斗模块设置自己的参数和模型比例。
- `inventory_panel` 只接收显示数据并发出换装意图，负责背包输入和暂停；不写存档或战斗内部字段。
- `tactical_save` 只负责 v1 JSON I/O；路径、字段和装备实例 ID 没有迁移。
- `run_screen.setup(player, objective, progression, hint_provider)` 接收明确依赖，负责结果/重试。任务状态每局重置，成长快照跨重试保存。

## 已知边界
- 导航每个 X/Z 网格仅一个行走表面，不支持桥上桥下并行路径。
- 敌人仍在一个脚本内维护状态和表现字段；此次先拆更新阶段，避免改动 AI 行为。
- 角色字段仍存在直接读写，碰撞层仍有数字掩码；新增交互前要核对所有调用者。
- 存档 I/O 已隔离，但异常 JSON 保护/原子写入仍是后续小修，不宣称此次已解决。
- 近战视觉与射线命中需一起验证；本轮不改变时序、命中规则或武器手感。
