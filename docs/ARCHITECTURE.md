# 当前 3D 架构

本文件描述现有代码，不规划新的框架。旧 2D 架构及任务派发文档在备份标签中。

## 装配与地图
`scenes/battlefield.tscn` 保存地面、19 个主要掩体及可编辑尺寸；根脚本 `world/battlefield.gd` 继承 `world/level.gd`。`world/height_sandbox.gd` 是同一基类的另一地图实现。

`level._ready()` 按原先次序：地形构建器 → 环境/光照 → 地图 → 效果 → 玩家 → 相机 → HUD → 战斗。`start_encounter()` 等待物理/普通帧后建立导航、敌人、任务、成长、结算。程序生成节点仍挂在原关卡根下，几何坐标和碰撞保持一致。

- `terrain_builder.gd`：输入关卡根与几何参数，输出 Mesh/Collision 节点，拥有材质缓存，不读取玩家/UI/任务。
- 地图通过 `spawn_point / objective_point / navigation_bounds / enemy_layout / _build_environment` 提供差异。
- `level.gd` 中的 `box/ramp/material/natural_ledge` 是薄的地图构造接口，具体实现统一委托给 terrain builder。
- `battle_prop.gd` 保留 `@tool` 编辑能力；`StoneVisual/StoneCollision` 可在编辑器阶段生成。巨石的 `StoneCollision` 只处理视线/阻弹，另有第六层的 `MovementBody` 凸包；角色与 `terrain_routes` 共用地形+移动代理掩码（`1 | 32`）。
- Autoload 仅为 Godot AI 的运行工具辅助；游戏没有新增全局管理器。

## 攻击调用链
`player_combat._unhandled_input → player.update_aim → attack（选择动作资源）→ _physics_process（动作窗口）→ strike → space_trace.trace → enemy.receive_strike`。

点击锁定方向；计时到有效窗口后按角度采样射线；`struck` 按实例 ID 去重。伤害由敌人按盾挡/身体/顶部决定。武器图形不是碰撞伤害源。弓箭先拉弓 0.14 秒，`arrow.gd` 连续检测飞行线段。

`data/weapons` 选择轻/中/重类别、待机动作与攻击序列；`data/actions` 中的 `action_profile` 提供身体/手臂/刀刃曲线、分段速度曲线、有效窗口与前冲速度。`action_library` 只负责查资源，不操作演员。战斗模块推进时间，`character_pose` 取同一相位生成关节，武器按同一资源旋转；玩家在移动前通过注入的 `combat_movement` 查询速度增量，统一走 `move_and_slide()`。重刀前冲没有直接改位置。

装备通过 `player.set_sprint_block("equipped_weapon", ...)` 登记疾跑限制；未来技能可用独立来源键叠加，换装只移除装备自己的限制。轻型的 `movement_scale()` 为 1.1，中/重型为 1.0，只乘主动步行/疾跑/蹲行速度；跳跃初速和前冲不乘此倍率。枚举显式保留 HEAVY=1，新增 MEDIUM=2，避免旧资源被误读。

`ground_drag` 是待机动作的接地能力，重刀接地角按握点、刀长和地面射线计算；`ground_impact` 在重击末端修正刀尖落点并发一次扬尘，空中和隔墙不触发。`drag_dust` 共用粒子寿命管理，分别接收轻微拖地和较大的重击喷散。

玩家用 `sword_*` 双手剑动作，守卫用 `shield_*` 剑盾变体：采样器、身体通道与中型模型共用，左手各自编排。守卫把原状态机前摇/挥出/收招映射到资源相位，不重写 AI 决策、伤害时刻或受击打断。盾的位置由左手握点反解，刀刃独立旋转。

`bow_accuracy` 是纯散布计算：发射时取站/蹲、移动/腾空状态，保留箭速和既有弹道解算。`death_visual` 只管理死亡表现：根据致命来向和地面法线倒地、停留、渐隐；`enemy` 的生命、碰撞关闭及击败统计仍在原流程中。隐藏尸体后保留敌人根节点，因此任务计数不丢失。

玩家移动独立在 `player._physics_process`；敌人每帧依次执行 `update_senses → choose_movement → move_and_slide → update_visuals`。这些是同一物理线程内的方法调用，不是多个并行任务。最后目击记忆只在真实看见玩家时更新；受到隐藏攻击时仅估计来袭方向。

人物表现由 `presentation/character_pose.gd` 提供关节和手心数据，`directional_art.gd` 绘制像素纸片；玩家战斗更新动作后同帧刷新纸片，并把世界武器握柄对齐该手心。刀光取实际模型端点，命中仍走原射线。石材像素纹理和 Shader 在 `stone_palette.gd` / `pixel_stone.gdshader`，与 `battle_prop.gd` 的几何、碰撞分开。资产入口和调研见 ART_PIPELINE.md。

`character_billboard.gd` 只接收 Sprite3D 与相机，统一直立纸片的深度/高度补偿并同步剪影投影，不读取战斗、UI 或存档。疾跑/跳跃状态由玩家物理过程产生，姿态生成器据此改变关节；阴影和武器握点均跟随同一帧。玩家 Shift 疾跑、Ctrl 精确射击；步行 4.2m/s、疾跑 6.8m/s、起跳 6.6m/s。

## 美术帧与命中附着

`data/art_sources/*.tres → atlas_source → atlas_document → tools/art_preview` 是工具侧数据流：来源提供动作/选项/帧，文档拼图并导出 PNG + JSON，界面只负责交互。`atlas_store` 按资产 ID 和规范帧键查询手绘覆盖，不依赖场景、UI 或战斗；回导通过校验后写自包含 `.res` 与 `catalog.tres`。角色运行时 `Art.frame()` 优先取覆盖，否则程序生成；纹理、握点、轮廓和阴影共用同一结果。详见 ART_PIPELINE.md。

`arrow → receive_strike/receive_damage → impact_attachment.bind → follow` 先按原规则结算，再保存目标提供的局部变换。角色根节点不旋转，所以身体附着框架从 `facing` 构造，盾挡则用盾节点；箭仍由关卡管理，无需改父子树或让敌人管理投射物。箭侧影与搭弓箭共用 `arrow_art`，正常三维深度遮挡。

玩家通过可选的 `projectile_attachment_duration()` 返回插箭停留时间 4 秒，附着记录保存该策略；`arrow` 在命中后计时，再经 `arrow_art.set_opacity()` 淡出 0.8 秒并释放，期间继续跟随。敌人没有该方法，沿用死亡/卸载清理；环境/飞行箭仍为五秒寿命。计时与表现不回调伤害入口。

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
- `data/weapons/knife.tres`：轻型、16 伤害、1.45m、0.38s 动作、0.42s 间隔；反持，上挥/下刺交替。
- `data/weapons/sword.tres`：中型、20 伤害、1.85m、0.56s 动作、0.64s 间隔；双手横斩/突刺。初始化在读档后按 `camp_sword` 唯一实例补入背包，不替换当前装备。
- `data/weapons/cleaver.tres`：重型、26 伤害、2.45m、0.80s 动作、0.90s 间隔；拖地待机、前劈，装备时禁用疾跑。
- 参数和背包说明从同一 Resource 读取；`apply_weapon` 由战斗模块设置自己的参数和模型比例。
- `inventory_panel` 只接收显示数据并发出换装意图，负责背包输入和暂停；不写存档或战斗内部字段。
- `tactical_save` 只负责 v1 JSON I/O；路径、字段和装备实例 ID 没有迁移。
- `run_screen.setup(player, objective, progression, hint_provider)` 接收明确依赖，负责结果/重试。任务状态每局重置，成长快照跨重试保存。

## 已知边界
- 导航每个 X/Z 网格仅一个行走表面，不支持桥上桥下并行路径。
- 敌人仍在一个脚本内维护状态和表现字段；此次先拆更新阶段，避免改动 AI 行为。
- 角色字段仍存在直接读写，碰撞层仍有数字掩码；新增交互前要核对所有调用者。
- 存档 I/O 已隔离，但异常 JSON 保护/原子写入仍是后续小修，不宣称此次已解决。
- 近战命中仍为按角度扫射线，而非逐刀刃骨骼碰撞；动作编排改变了时序和前冲，需结合实际试玩验收。未来技能可复用动作资源及限制来源，但尚未实现技能系统。
