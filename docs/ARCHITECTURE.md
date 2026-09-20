# 当前 3D 架构

本文件描述现有代码，不规划新的框架。旧 2D 架构及任务派发文档在备份标签中。

## 装配与地图

固定视角插画实验在原小屋遮挡注册后装配 `painted_cottage`。外墙/屋顶由 `registration.json` 配准四片，内景由 `interior_registration.json` 配准后墙/左墙/地板三片，直接写入空间深度。原 GLB 保留碰撞、独立阴影与遮挡几何，原墙和地板颜色通过 `layers=0` 退出，仍保持 visible 供采样；V 恢复原渲染层。`painted_environment` 复用墙圆和屋顶覆盖率，地板显式 `is_support`，不另建遮挡状态机。源图、配准与固定光照/方向限制见 `assets/environment/experiments/painted_cottage/README.md`，这条实验路线尚未替换正式地图。

`warehouse_art_slice.tscn` 继承驿站简模，以独立子类提供三人遭遇和桥前出生点。`warehouse_art_layer` 只读取资产 `bindings.json` 装配外观；`surface_projection` Resource 提供图片、局部 UV 轴和朝向筛选，小屋也复用这一计算器。投影只改 UV/UV2/COLOR，不改顶点或碰撞：UV2.x 标识外侧、COLOR.rg 保留原网格 UV 供土路边缘判断。装配必须早于 wall_occlusion 注册；V 同步源材质的 `art_projection_enabled` 到显示副本，不能直接换回原材质丢掉透视变体。新增箱桶独立显式碰撞，原仓库门洞、高台、桥和承托标记保持。资产原点/映射资源是维护入口，详见 `assets/environment/warehouse_slice/README.md`。

`tools/cottage_art_lab.tscn` 独立实验使用简单 Blender 网格配生成表面图，不替换正式地图。`cottage.gd` 从保存的 GLB 装配显示和碰撞，前墙门两侧/门楣/山墙归同一个物理父节点，门洞几何仍独立；侧墙/后墙/屋顶各自管理遮挡。资产局部位置生成 UV，UV2.x 是外侧贴图掩码；共用 `art_surface.gdshaderinc` 只替换颜色，不改几何深度或透明管线。默认关闭该功能，旧材质照常。屋顶可注入 `surface_material`，控制器复制表面参数后仍拥有透视状态；灰模对比仅修改颜色参数，wall_occlusion 同步到材质副本，不能重新挂原材质绕过透视变体。尺寸映射与生产约束见资产目录 README，回归入口 `cottage_art_lab_test.gd`。

普通墙圆先按真实遮挡筛选构件，再做圆内柔边：`wall_occlusion.measure` 收集相机到身体采样点之间命中的所有构件，身体覆盖并集决定是否开圆，命中集合决定哪些构件可以淡化。不能只取最近命中，否则前墙透开后仍漏掉第二堵墙。最近的 `CollisionObject3D` 为分组边界（当前建筑为独立 StaticBody3D 墙段）；无物理父节点时归到美术 `architecture_piece`，散放网格独立。墙身/压顶/窗框共组，独立墙段不因共用材质一起消失。材质副本按“组＋原材质”隔离，Shader 仍共享；组状态有 0.16s 退出缓冲和 0.28s 渐变，未激活的组跳过圆心等参数更新。`selective_wall` 验证同材质旁墙、近后墙、重叠前墙和真实仓库走道；不可用扩大/缩小深度余量代替对象筛选。

环境的承托角色由场景/构件声明 `metadata/occlusion_role="support"`，`wall_occlusion` 注册时向祖先查找并排除整组承托网格，直接注册某个子节点也不能绕过保护。驿站高台/地板/坡桥、程序生成高台/坡道与桥构件已标记。不能按材质或网格厚度推断：石台和墙共用材质，墙帽比地板还薄；薄装饰仍须和墙身一起透视。此合同只改变显示注册，不改碰撞/导航，专项 `occlusion_support` 必须核对高台、地板和桥在开关透视时画面不变，以及薄墙帽没有孤立残留。

透视深度边界由 `occlusion_depth.gdshaderinc` 共用：0.85m 身体/厚墙余量加 1m 柔边。不能用经过角色中心的硬平面逐像素决定透视，否则贴墙与斜屋面会切出折角。两圆默认半径 3.375m；墙圆中心 27% 半径全透、向外渐变至 22% 覆盖率，再淡回正常表面；屋顶原先的中心全透和室内整顶淡化保持。`near_wall_reveal` 检查斜墙/斜屋面穿过角色深度、核心无残留及远背景不受影响。

`level` 注入玩家/相机并延迟调用 `wall_occlusion.register_branch`，等环境构件生成后接管实心墙柱/巨石的显示材质。`body_occlusion_probe` 只读当前身体帧，按相机平面采样颜色 alpha/深度、合并上下身最前表面；`wall_occlusion` 每秒 10 次与原三角面求交，拥有普通遮挡比例及 90% 开启/80% 退出状态。这里使用**淡化前的几何**，不能改为淡化后的屏幕深度，否则自反馈会反复闪烁。Shader 仅在玩家前方的圆内降低墙面覆盖率；灰色身体随后依据淡化后的真实深度提示剩余遮挡。两圆共用 `occlusion_style` 默认值；遇到具体屋顶时同步其实际设置。原材质独立投影，物理/导航/敌人感知不变。静态图页读入缓存，不做实时屏幕读回；透明树和未适配的新材质不参与比例。新增动态构件需显式注册子树，重建既有网格后应重新注册其新节点。验证入口 `wall_occlusion_test.gd`。

`scenes/battlefield.tscn` 保存地面、19 个主要掩体及可编辑尺寸；根脚本 `world/battlefield.gd` 继承 `world/level.gd`。`world/height_sandbox.gd` 是同一基类的另一地图实现。

`level._ready()` 按原先次序：地形构建器 → 环境/光照 → 地图 → 效果 → 玩家 → 相机 → HUD → 战斗。`start_encounter()` 等待物理/普通帧后建立导航、敌人、任务、成长、结算。程序生成节点仍挂在原关卡根下，几何坐标和碰撞保持一致。

`scenes/waystation_blockout.tscn` 是独立 F6 驿站试玩场景：静态建筑、地面、坡道及其碰撞直接保存在场景，可由编辑器调整。`world/waystation_blockout.gd` 继承关卡装配，默认提供十名既有敌人的站位与难度资源，装配完成后补入隔离的临时装备。任务、奖励和进度持久化关闭；出生营地恢复生命。`combat_enabled=false` 恢复无战斗空间勘察及 M/1–5 快捷键，战斗模式禁用这些跳转/冻结入口。路线以土路连接，勘察红柱战斗时隐藏，捷径门尚未实现开关。

`enemy_layout()` 每条站位可传只读 `enemy_tuning` 资源；`level.start_encounter()` 在敌人入树前应用血量与参数，`enemy` 状态机统一读取追击速度、前摇/收招/冷却倍率和伤害倍率，敌方箭在发射时复制最终伤害。未提供资源时保持旧默认值。驿站使用 `data/encounters/waystation_hard.tres`；其 18m 离岗半径及玩家回营地触发归队，回到岗位附近再解除锁定，不改变视线检测、受击打断或盾挡规则。

`presentation/interior_roof.gd` 由关卡注入玩家，检查相机到玩家脚、胸、头的视线与当前盒形屋面是否相交；建筑地面 AABB 不限制开孔，因此屋檐外也能正确透视。`interior/can_enter` 另控制整组屋面淡到 `indoor_opacity=0.22`，圆孔覆盖率再与整体覆盖率相乘。两个渐变通道约 0.28 秒、退出缓冲 0.13 秒；室外只有圆孔。覆盖率采用世界锚定的像素裁切，保留深度和独立阴影代理。屋顶不增加移动/阻弹碰撞；墙后身体走逐像素灰色提示。西侧野地复用 `battle_prop` 的断墙/巨石及移动凸包，树冠体块仅显示、树干阻挡移动。

`environment_library` 缓存 `assets/environment` 中的磁盘材质；`architecture_piece` 输入类型/尺寸，只生成并按材质合并视觉网格，不操作碰撞或关卡状态。驿站墙体挂 `ArtFinish`，原静态身体继续负责碰撞；`terrain_builder.ramp` 用相同木架桥构件贴合原连续斜坡。纹理离线生成、运行时只读取。预制件、编辑入口与屋顶盒形约束见 [ENVIRONMENT_ART.md](ENVIRONMENT_ART.md)。

环境粗像素只有一个入口：`level` 在相机下创建 `environment_pixel_pass`，F2 切换、无存档依赖。隐藏约定是**不透明/像素裁切环境 → 优先级 -128 的环境颜色合成 → 灰色被挡身体（-1）→ 原精度演员/武器（0）→ 界面**。环境屏幕副本不含后续透明阶段的纸片；身体和武器 Shader 用 `ALPHA=1` 进入后续阶段，同时 `depth_draw_always` 写入已有图集的真实表面深度，不能删掉它而仅靠绘制顺序叠放。灰色变体仅绘环境深度前方确实有遮挡的身体像素，不写深度；正常身体随后覆盖露出的部分；箭矢优先级 1、独立裁剪阴影。角色太阳阴影继续由代理投到环境，因此随环境粗化。整个流程复用同一世界和原始深度，没有低分辨率世界副本；这是颜色后处理，非光栅化性能优化。新增透明环境/特效不会自动进入背景副本，应明确选择绘制阶段，并运行 `environment_resolution`、角色/武器深度及屋顶专项。

- `terrain_builder.gd`：输入关卡根与几何参数，输出 Mesh/Collision 节点，拥有材质缓存，不读取玩家/UI/任务。
- 地图通过 `spawn_point / objective_point / navigation_bounds / enemy_layout / _build_environment` 提供差异。
- `level.gd` 中的 `box/ramp/material/natural_ledge` 是薄的地图构造接口，具体实现统一委托给 terrain builder。
- `battle_prop.gd` 保留 `@tool` 编辑能力；`StoneVisual/StoneCollision` 可在编辑器阶段生成。巨石的 `StoneCollision` 只处理视线/阻弹，另有第六层的 `MovementBody` 凸包；角色与 `terrain_routes` 共用地形+移动代理掩码（`1 | 32`）。
- Autoload 仅为 Godot AI 的运行工具辅助；游戏没有新增全局管理器。

## 攻击调用链
`player_combat._unhandled_input → player.update_aim → attack（选择动作资源）→ _physics_process（动作窗口）→ strike → melee_query.sweep → space_trace.trace → enemy.receive_strike`。

点击锁定方向；计时到有效窗口后按角度采样射线，经 `melee_query.sweep` 逐个收集身体，墙/石材仍截断。`struck` 按实例 ID 去重，`attack_hits` 统计整次动作的目标数，格挡也占名额。伤害由敌人按盾挡/身体/顶部决定。武器图形不是碰撞伤害源。弓箭继续沿用首个不可穿透命中，先拉弓 0.14 秒，`arrow.gd` 连续检测飞行线段。

群攻按 `action_profile` 的 `max_targets/knockback_strength/impact_radius` 配置：宝剑横斩 100°/最多三人，突刺和匕首默认一人；重刀正面窄劈后，`align_impact` 确认真正接地，再由 `melee_query.impact` 查落点 1.25m 内、脚底高度差不超过 0.55m 且未隔墙的敌人，近者优先。刀刃与冲击合计最多四人，直接命中者不叠加冲击伤害。角色胶囊不参与落点/墙体查询，避免把敌人头顶当成地面。冲击调用相同受击接口，因此逐人保留盾挡、打断和碰撞击退；`receive_strike` 新增可选击退力度，旧调用仍默认 2m/s。

`data/weapons` 选择轻/中/重类别、待机动作与攻击序列；`data/actions` 中的 `action_profile` 提供刀刃曲线、分段速度曲线、有效窗口与前冲速度；身体动作保存于 Blender。`action_library` 只负责查资源，不操作演员。战斗模块推进时间，`baked_human` 按同一动作相位播放已烘焙的身体帧，武器按动作资源旋转；玩家在移动前通过注入的 `combat_movement` 查询速度增量，统一走 `move_and_slide()`。重刀前冲没有直接改位置。

装备通过 `player.set_sprint_block("equipped_weapon", ...)` 登记疾跑限制；未来技能可用独立来源键叠加，换装只移除装备自己的限制。轻型的 `movement_scale()` 为 1.1，中/重型为 1.0，只乘主动步行/疾跑/蹲行速度；跳跃初速和前冲不乘此倍率。枚举显式保留 HEAVY=1，新增 MEDIUM=2，避免旧资源被误读。

`ground_drag` 是待机动作的接地能力，重刀接地角按握点、刀长和地面射线计算；`ground_impact` 在重击末端修正刀尖落点并发一次扬尘，空中和隔墙不触发。`drag_dust` 共用粒子寿命管理，分别接收轻微拖地和较大的重击喷散。

玩家用 `sword_*` 双手剑动作，守卫用 `shield_*` 剑盾变体：采样器、身体通道与中型模型共用，左手各自编排。守卫把原状态机前摇/挥出/收招映射到资源相位，不重写 AI 决策、伤害时刻或受击打断。盾的位置由左手握点反解，刀刃独立旋转。

`bow_accuracy` 是纯散布计算：发射时取站/蹲、移动/腾空状态，保留箭速和既有弹道解算。`death_visual` 只管理死亡表现：根据致命来向和地面法线倒地、停留、渐隐；`enemy` 的生命、碰撞关闭及击败统计仍在原流程中。隐藏尸体后保留敌人根节点，因此任务计数不丢失。

玩家移动独立在 `player._physics_process`；敌人每帧依次执行 `update_senses → choose_movement → move_and_slide → update_visuals`。这些是同一物理线程内的方法调用，不是多个并行任务。最后目击记忆只在真实看见玩家时更新；受到隐藏攻击时仅估计来袭方向。

人物表现统一由 `presentation/baked_human.gd` 读取颜色、深度和双手握点，组合上下身；玩家战斗更新动作后同帧刷新图集帧，武器直接使用 `last_grip` / `last_support` 世界坐标，不再绕行二维像素握点转换。刀光取实际模型端点，命中仍走原射线。石材像素纹理和 Shader 在 `stone_palette.gd` / `pixel_stone.gdshader`，与 `battle_prop.gd` 的几何、碰撞分开。资产入口和调研见 ART_PIPELINE.md。

玩家换装/建弓、敌人建剑盾/弓时调用 `PixelWeaponVisual.attach(model,camera,sun)`；它随模型释放，读取最终变换，交给 `pixel_frame_gpu` 在独立小尺寸 SubViewport 输出颜色/深度，原模型仅投影。屏外、隐藏和同姿态停止出图。`weapon_sprite_baker` 只负责几何采集及显式 `capture_frame()` 离线导出，CPU 图像缓存不进入游戏刷新。弓以 `pixel_revision` 更新弦形，已有像素箭通过 `pixel_bake_ignore` 排除重复烘焙。`swing_trail` 复用 GPU 后端把世界轨迹转为像素刀光并逐块消退。二者不参与伤害计算，详见 WEAPON_PIXEL_EXPERIMENT.md。

`baked_human` 拥有上下身、逐像素深度、局部灰色提示和剪影阴影；演员通过 `apply_frame` 和 `refresh_occlusion_visibility` 更新表现。灰色变体读取环境深度，仅绘实际被挡像素，不再用中心物理射线开关全身描边。`layers.occlusion` 替代旧 `layers.outline`，两种身体显示共用深度解码与同一帧。疾跑/跳跃状态由玩家物理过程产生，阴影和世界武器握点均跟随同一帧。玩家 Shift 疾跑、Ctrl 精确射击；步行 4.2m/s、疾跑 6.8m/s、起跳 6.6m/s。

## 美术帧与命中附着

新物种由关卡出生数据中的 `creature` 选择 `data/enemies` 配置，`level` 仍只负责装配玩家、相机、效果和导航依赖。`actors/creature` 继承敌人的感知、路径、受击和死亡接口，独立推进蓄势/有效/收招/后撤；旧守卫和弓手的出招仍走 `enemy`。生命与碰撞尺寸由物种配置提供，关卡伤害倍率继续来自 `enemy_tuning`。`attack_warning` 只画已锁定的方向/落点，伤害由实体射线、范围遮挡或真实碰撞结算。

哥布林矛与身体一起烘焙；石头人、史莱姆不装备用剑盾。三者清单声明 `parts=["full"]`，播放器复用同一深度/阴影路径；`creature_rig` 在制作端按保存的整身动作采样，史莱姆允许缩放骨骼轨道。现有四种类人仍用上/下身分层与外置武器，不强迫软体提供人形握点。哥布林短矛暂未作为玩家可装备或掉落物。

`data/art_sources/*.tres → atlas_source → atlas_document → tools/art_preview` 是工具侧数据流：来源提供动作/选项/帧，文档拼图并导出 PNG + JSON，界面只负责交互。`atlas_store` 按资产 ID 和规范帧键查询手绘覆盖，不依赖场景、UI 或战斗；回导通过校验后写自包含 `.res` 与 `catalog.tres`。角色工作台与运行时按同一帧键优先取补色覆盖，否则读取已烘焙图页；纹理、握点、轮廓和阴影共用同一结果。覆盖必须匹配资产与格子尺寸，旧 32×48/64² 稿不会被错误套入 96²。详见 ART_PIPELINE.md。

`arrow → receive_strike/receive_damage → impact_attachment.bind → follow` 先按原规则结算，再保存目标提供的局部变换。角色根节点不旋转，所以身体附着框架从 `facing` 构造，盾挡则用盾节点；箭仍由关卡管理，无需改父子树或让敌人管理投射物。箭侧影与搭弓箭共用 `arrow_art`，正常三维深度遮挡。

玩家通过可选的 `projectile_attachment_duration()` 返回插箭停留时间 4 秒，附着记录保存该策略；`arrow` 在命中后计时，再经 `arrow_art.set_opacity()` 淡出 0.8 秒并释放，期间继续跟随。敌人没有该方法，沿用死亡/卸载清理；环境/飞行箭仍为五秒寿命。计时与表现不回调伤害入口。

## 装备、显示与存档
`ui/window_mode` 挂在游戏 Window 下，接收 F11 / Alt＋Enter，记录并恢复窗口大小/位置/最大化状态；暂停和关卡重开不影响它。它不持有玩家、存档或关卡，`level` 只负责一次性装配。窗口切换保持 1280×720 逻辑画布，以保持宽高比的小数倍率尽量铺满屏幕；玩家每帧从 Viewport 读取已转换的鼠标坐标，屋顶使用同一逻辑画布投影，避免把屏幕像素直接当世界瞄准坐标。

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

独立小院实验 `tools/painted_courtyard_lab` 只编排原小屋、玩家与测试快捷键；`painted_courtyard` 按资产 `catalog.json` 与 `layout.json` 装配。`illustrated_prop` 接收图片/显示尺寸/锚点/碰撞/深度范围，分别创建绘画平面与隐藏盒或柱。普通实物写近似盒深度，树用树干竖直深度面，不能用树冠最前面遮挡树前人物。花草走独立 `ground_decoration`：不写遮挡深度、无墙圆、先于人物显示。实物从注册后的代理材质读取已有墙圆参数，不拥有第二套遮挡状态。阴影由 `illustration_shadow` 根据 `shadow_profiles.json` 编排体量；`shadow_style.tres` 是方向/颜色/覆盖率/柔边/晃动上限的唯一来源。小院房屋显式启用共享投影，停用旧实时代理且退出其颜色层，V 对比恢复；人物太阳方向与强度从同一样式应用。物件先入树再 `setup`，无专属 profile 时按深度尺寸生成默认形体。固定朝向的平地平移由变换通知同步锚点；`set_visual_sway` 同步画稿上部和影子，脚点/碰撞不动，调用者持有动画时钟，不自动开启风摆、不逐帧重建。不同物件影子仍普通透明混合，夜间和坡面未接入。`courtyard_ambience` 只更新无碰撞装饰，与战斗/存档无依赖。小院默认关闭环境降采样、保留 F2，正式地图默认值不变。完整源图不导入，离线降采样记录在 `baked.json`，详见小院资产 README。

七种角色均采用 Blender 保存的模型/骨骼/动作，经 GLB 和开发期 GPU 烘焙后，输出 96×96 颜色/深度，四种类人另有双手握点；`baked_human` 只按清单播放整身或分层帧。制作步骤见 [ART_PIPELINE.md](ART_PIPELINE.md)。关卡总控不管理图集，运行时不实例化角色骨架、模型生成器或角色烘焙视口。守卫盾使用副手，弓使用左手，死亡模块读同一倒地图集。可装备武器与刀光仍有独立实时 GPU 像素化，不能混称为全离线。

- 导航每个 X/Z 网格仅一个行走表面，不支持桥上桥下并行路径。
- 旧守卫/弓手仍在 `enemy` 内维护状态和表现；新物种的 `creature` 复用其基础字段与公共方法。继承关系仍有耦合，新增不同生命周期时需核对死亡、装备占位与受击接口。
- 角色字段仍存在直接读写，碰撞层仍有数字掩码；新增交互前要核对所有调用者。
- 存档 I/O 已隔离，但异常 JSON 保护/原子写入仍是后续小修，不宣称此次已解决。
- 近战命中仍为按角度扫射线，而非逐刀刃骨骼碰撞；动作编排改变了时序和前冲，需结合实际试玩验收。未来技能可复用动作资源及限制来源，但尚未实现技能系统。
## 制作端与运行端的接口

`imported_humanoid_rig` 继承已有动作采样/上下身组合协议，读取标准 GLB 的 Skeleton3D、Skin 和材质，离线计算变形表面；仅被工作台和烘焙工具使用。`baked_human_spec` 集中声明 96²、2.56m 采样范围及资产/动作映射，`baked_human` 读取清单中的格子尺寸和像素比例；战斗仍通过原世界握点接口连接。关卡布局的可选 `art_id` 选择外观，不改变敌人种类和状态机。
