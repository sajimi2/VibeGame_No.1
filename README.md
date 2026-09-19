# Outpost RPG

Godot 4.7.2 / GDScript / Compatibility。当前游戏是固定斜角正交的 3D 荒堡战场：十二朝向、移动中攻击、三名守卫和两名弓手，取信后返回营地交付。

## 运行
- 在 Godot 打开 `project.godot`，**F5 直接运行最新战场**；`play.bat dev` / `play_battlefield.bat dev` 同样运行源码。
- 驿站混合遭遇：打开 `scenes/waystation_blockout.tscn` 按 **F6**，或双击 `play_waystation.bat`。78×78m 灰盒含西侧野地、1.8m 高台与室内渐隐屋顶；两名哥布林、两只史莱姆、一名石头人、两名守卫和三名弓手分组驻守。哥布林锁向突刺后撤；石头人预告砸地，跳跃/离开圈可躲、重刀可打断；史莱姆蓄势直线冲撞、撞墙停下。I 切换三把现有近战武器，返回出生营地恢复生命，R 重开；无任务奖励，不读写真实进度。根节点关闭 `Combat Enabled` 可恢复无战斗勘察（M 全图、1–5 区域跳转）。
- `scenes/tactical_height.tscn` 是保留的 3D 高度/布帘/坡道试验场，F6 或 `play_height.bat dev`。
- 不带 `dev` 的批处理运行 `builds/windows` 中的导出包；修改源码后须重新导出。EXE 与同名 PCK 必须配套。
- WASD 移动，Shift 疾跑，Space 跳跃，C 下蹲，左键近战，右键弓箭，E 交互，I 背包，Ctrl 暂停辅瞄，R 重试。
- 近战分工：匕首单体；宝剑横斩最多扫三人、突刺单体；大砍刀下砸在落点周围 1.25m 产生冲击，连同刀刃最多四人并强化击退。同一刀不重复扣血，盾牌仍减伤，墙体/高差仍阻隔。
- 图集工作台：打开 `tools/art_preview.tscn`，按 **F6**。查看七种角色与箭矢，导出原尺寸 PNG + JSON；编辑 PNG 后载入 JSON、应用，再重新运行查看。类人支持分层补色与握点；哥布林/石头人/史莱姆使用整身帧，无额外握点选项。使用与扩展说明见 [美术资产](docs/ART_PIPELINE.md)。
- F5 已启用玩家匕首/宝剑/大砍刀/弓、守卫剑盾、弓手弓及刀光的像素表现。模型对照工具：打开 `tools/weapon_pixel_lab.tscn`，按 **F6**；1 宝剑、2 大砍刀、3 匕首、Tab 原版/像素对照、V 导出当前帧。工具场景不读写进度，说明见 [武器像素化](docs/WEAPON_PIXEL_EXPERIMENT.md)。

## 阅读代码
先读 [当前架构](docs/ARCHITECTURE.md)。生命周期入口是 `scripts/world/level.gd`，地图参数是 `scripts/world/battlefield.gd`。

| 目录 | 职责 |
|---|---|
| `scripts/world/` | 关卡装配、战场/驿站/高度试验场、地形生成、导航、任务 |
| `scripts/actors/` | 玩家移动/姿态；敌人感知、状态机、移动和攻击 |
| `scripts/combat/` | 玩家输入和攻击时序、命中检测、弹道、武器参数类型 |
| `scripts/presentation/` | 程序美术、武器模型、刀光、声音与投影 |
| `scripts/art/`、`data/art_sources/` | 资产来源协议、稳定帧键、图集拼装、校验和手绘覆盖持久化 |
| `scripts/items/`、`scripts/contracts/` | 库存、物品定义和快照结构 |
| `scripts/progression/`、`scripts/persistence/` | 装备/首通成长与 JSON 存档 I/O |
| `scripts/ui/` | HUD、背包、结算界面 |
| `data/weapons/` | 当前 3D 武器的伤害、米制距离、秒制时序和显示比例 |
| `data/encounters/` | 关卡敌人难度参数；驿站强化不修改原战场默认值 |
| `data/enemies/` | 新物种的体型、血量、速度、攻击距离与分段时序 |
| `tests/` | 当前功能回归；不是早期 Demo 业务代码 |

## 验证与导出
在 PowerShell 中运行：
```powershell
./scripts/check.ps1 -Suite smoke   # 导入及隔离进度的 F5 入口
./scripts/check.ps1 -Suite core    # 当前战斗/任务/装备核心回归
./scripts/check.ps1 -Suite all     # 加上高度、视野、投影等边界回归
./scripts/check.ps1 -Suite smoke -Rendered
./scripts/export_height.ps1       # 导出荒堡战场
./scripts/export_height.ps1 -Sandbox
```
可用 `-GodotPath` 或 `GODOT_BIN` 指定引擎。测试说明见 [tests/README.md](tests/README.md)。日志/截图在 `work/`，导出包在 `builds/`，两者均不提交。

## 保存和历史
- 存档仍是 `user://tactical_progress_v1.json`，v1 JSON、物品 ID、20 格库存快照保持兼容。
- 编辑器运行的项目名仍为 `Outpost RPG`；导出包保留原 `Outpost RPG Height Lab` 身份，因此不搬动既有存档目录。战场和试验场在同一种运行方式下共享成长。
- 旧 2D 四关、T01–T07 报告和旧测试已从活跃工程移除；完整回退节点是 [9c4dc82](https://github.com/sajimi2/VibeGame_No.1/commit/9c4dc82ef5445503f2a7511232f8dd6f8a86a38c)，标签 `backup/pre-3d-cleanup-20260917`。不要在有未提交工作的目录中直接覆盖恢复。
- 第三方 Godot AI 工具保持原样，使用见 [GODOT_AI_SETUP.md](GODOT_AI_SETUP.md)；个人 `.codex/` 配置不提交。
## 角色三维源模型与离线图集

七种角色统一采用 **Blender → GLB → Godot 离线烘焙 96×96**，十二朝向，显示大小沿用已确认的 1.2 倍观察基准。可编辑源集中在 `assets/characters/blender/`；工作台同时查看 3D 源模型和像素图集。导出入口 `tools/blender/export_characters.py`，烘焙入口 `tools/bake_characters.gd`。编辑、补色回导与限制见 [美术流程](docs/ART_PIPELINE.md)。
