# OutpostRPG 接手说明

更新：2026-09-17。本文件替换早期 Harness/T01 骨架交接入口。用户已在新对话“验证 Godot MCP 连接”完成连接实测；接下来先建立项目理解，不自动接续加功能。

## 先明确接手什么

- 工程：`D:\vibe coding\OutpostRPG`。独立学习工程 `D:\vibe coding\test project` 与旧 `OutpostRPG_AgentLab` 不在本次接手范围。
- 阶段：已可玩的战斗原型，正在验证动作/敌人/地形与美术表现。不是只有骨架，也不是已经完成正式美术和完整内容的成品。
- 阅读顺序：`AGENTS.md` → 本文件 → `AI_SYNC.md` → `docs/TACTICAL_HEIGHT_PLAN.md`；MCP 用法另读 `GODOT_AI_SETUP.md`。
- 当前分支：`tactical-height-prototype`，本次核对 HEAD 为 `94bfb57`。最新荒堡战场、动作改动及 Godot AI 接入有已修改/未跟踪文件，尚未包含在该提交中。不要把“已有 Git 节点”误认为“当前所有文件已备份到 GitHub”。先查看自己的实时 Git 状态；本轮没有 commit/push。
- 用户原则：AI 高效实现，用户理解核心流程并保留最终控制权。现在最需补齐的是理解/review 能力，不是继续累加功能。

## 开发过程与已定方向

1. 原 2D 四关（村庄、林地、哨站、Boss）完成过战斗、物品、成长、存档和美术/声音雏形。中间让 DeepSeek Harness 接续过一个阶段，此后回到 Codex；旧 T01～T07 派发审查约定不再是当前流程。
2. 新建真实高度的 3D 战术试验场，以像素纸片人物/树木配地形碰撞；验证过坡道、低洼、高台、瞭望塔、遮挡与弹道。反复比较透视后，用户最终明确选择固定斜角正交。相机可跟随平移，不做可转镜头。
3. 形成取密函并返回的短关卡，加入守卫/弓手、追踪记忆、装备与重试。用户否定了在很小地图中堆砌“帘后小径/密函高地”等探索命名的做法：地图和掩体服务战斗。
4. 当前保留试验场，另有 48×56 的荒堡战场，3 守卫 + 2 弓手；新增可编辑的断壁、巨石，提升攻击动作连续性。之后用户转向掌握代码与接入 Godot AI；没有授权新会话立即扩充敌人/地图。

具体取舍：
- 十二朝向、移动中攻击、脚步着地与世界统一投影是已认可方向。像素树获得用户认可；地形、人物和武器仍为可改进的程序美术雏形。
- 身体/顶部做粗粒度命中，追求玩家能理解并利用的战术，不细分关节。真实高度不等于必须透视渲染。
- 墙阻挡弹道；布帘遮挡视野但可穿行/穿箭并破损。真实视野与最后目击记忆决定追击，不允许丢目标后读取隐藏玩家的最新位置。
- 高处弓手侦察范围更大但仍受遮挡；辅瞄仅在鼠标附近并有视线时微调，有提示圈，不能变成自动追踪。
- 跳跃早期搁置，后来已获用户同意并实现短跳；“不加跳跃”是过期决策。现版本无二段跳、跳跃无敌或跳斩。
- 换装备已允许营地外操作，但死亡/攻击期间禁止。配色、人物比例未定死，不照抄《饥荒》或《皓白初晓》。

## 三个入口不要混淆

| 入口 | 当前用途 | 源码运行 |
|---|---|---|
| `scenes/battlefield.tscn` | 最新荒堡战场，当前主线 | 打开此场景后 F6，或 `play_battlefield.bat dev` |
| `scenes/tactical_height.tscn` | 保留的高度/战术试验场 | F6，或 `play_height.bat dev` |
| `scenes/level_village.tscn` | 原 2D 四关入口 | 当前 `project.godot` 的 main_scene，F5 仍会进入这里 |

批处理不带 `dev` 会运行已导出的 EXE，不会自动反映新源码。不要因 F5 打开旧入口而误判最新地图丢失，也不要擅自改默认主场景。

## 当前代码地图（已对照源码）

以下均为 `scripts/tactical/` 下文件，另列公共物品组件。名称带 lab 不代表可删除的临时代码。

| 文件/模块 | 目前职责与关系 |
|---|---|
| `battlefield.gd` | 继承 `height_lab.gd`，提供地图环境、出生点、敌人布局、任务点、导航范围。`battlefield.tscn` 写入主要静态掩体。 |
| `height_lab.gd` | 场景装配入口：创建环境/光照、玩家、相机、HUD、战斗组件；延迟构建路径、敌人、任务、成长及结果界面。也包含地形构造工具。 |
| `height_actor.gd` | `CharacterBody3D` 玩家：移动、重力/跳跃、下蹲净空、瞄准、生命/受伤、朝向和遮挡表现。 |
| `lab_combat.gd` | 接收鼠标攻击输入，管理出招/冷却/输入缓冲、近战轨迹与命中去重、弓箭拉弓和发射、辅助瞄准及提示圈。通过装配传入的 actor/effects/notify 合作。 |
| `outpost_guard.gd` | 近战守卫和弓手共用的 `CharacterBody3D` 行为脚本，通过 `ranged` 区分。集中处理视野、最后目击、追击/调查/搜索/返回、攻击状态、盾挡、生命/表现；没有独立 outpost_archer.gd。 |
| `terrain_routes.gd` | 采样地面高度、净空与连接，建立路径。导航静态采样排除同伴身体，实际移动仍发生角色碰撞。 |
| `space_trace.gd` / `space_arrow.gd` | 空间检测和箭的连续运动/碰撞；阻挡材质与身体/顶部命中。 |
| `combat_motion.gd` / `directional_art.gd` / `weapon_art.gd` / `swing_trail.gd` | 动作曲线、十二朝向人物图、武器几何、短刀光；表现与实际伤害结算要分别核对。 |
| `outpost_objective.gd` / `outpost_run.gd` | E 交互的接任务/取信/交付，以及死亡、结算、重试、暂停界面。 |
| `camp_progress.gd` + `ActorInventory` / `ItemInstance` / `ItemCatalog` | 复用原公共物品结构，管理两种近战武器、20 格背包、首通奖励、成长和战术存档；目前也负责背包 UI。 |
| `battle_prop.gd` / `outpost_sample.gd` / `world_lighting.gd` / `encounter_effects.gd` | 编辑器可摆放断墙/巨石、场景样例资产、光照投影/分段明暗、音效与受击反馈。 |

编辑器中的 Battlefield 场景树以 Ground/Cover 为主。玩家、敌人、HUD 等很多节点在 `_ready()` / `start_encounter()` 里生成，因此需要运行游戏才能在运行时树中看到它们。

## 三条优先理解的数据流

1. **一次玩家近战**：鼠标输入 → `lab_combat._unhandled_input()` → `attack()` 锁方向、设置冷却并清命中记录 → `_physics_process()` 取 `combat_motion` 姿态、推进武器 → `strike()` 空间检测/去重 → 敌人 `receive_strike()` 处理盾挡/伤害/受击。玩家移动仍由 `height_actor._physics_process()` 负责。
2. **敌人如何追人**：`height_lab.start_encounter()` 注入 player/camera/routes/effects → `outpost_guard.can_see_target()` 判断范围/方向/遮挡 → `_physics_process()` 更新行为状态和最后目击记忆 → `terrain_routes` 求路径 → `move_and_slide()` 真实碰撞移动 → 攻击/玩家 `receive_damage()`。弓手也走同一脚本的 ranged 分支。
3. **换装到保存**：背包按钮 → `camp_progress.equip()` 检查死亡/攻击 → `ActorInventory.try_equip()` → `inventory_changed` 信号 → `camp_progress.changed()` 更新武器参数、生命上限、背包显示，并保存可序列化快照。任务交付通过 `grant_reward()` 控制首通奖励只发一次。

战术存档为 `user://tactical_progress_v1.json`，独立于旧四关存档；战场/试验场共享战术成长。任务密函的当局状态不会跨重试保留。不要为了验证奖励而删除或覆盖玩家真实存档。

## 已知限制与技术债：先理解，按需修

- 原 2D 四关和新战术层并存，有意识复用了物品结构，其余不是统一运行架构。旧 docs/ARCHITECTURE.md 的端口设计不能直接套在全部战术代码上。
- `height_lab.gd` 同时负责装配、地形和部分 HUD；`outpost_guard.gd` 集中 AI/战斗/表现；`camp_progress.gd` 混合存档、装备适配与 UI。这是目前明确的职责耦合，不要宣称已经彻底组件化。
- 多处使用 Node 类型的 lab/actor 引用和直接字段赋值，是隐式接口；攻击/装备等参数也有代码硬编码。边界与依赖须在修改前看清；还不需要全面引入事件总线、ECS 或大 GameManager。
- 导航每个水平采样格仅有一个行走表面，不支持复杂桥上桥下并行路径。复杂隧道、趴下、多层导航、自动昼夜尚非完整实现。
- 局部纸片/武器穿插仍待处理，优先级低于动作和战斗反馈。现在没有经过全量代码审计，不代表除以上条目之外没有问题。

## 验证证据与下一步

- `AI_SYNC.md` 记录过最新阶段 174 项相关检查通过，含实际移动中攻击/出箭、守卫追坡、战场路线等；这是上一实现阶段的记录，交接这一轮没有重跑，不能对外称本轮全部测试通过。
- 本次接入已验证两个工程 Godot 4.7.2 导入、MCP 认证及编辑器/场景树读取。接手新对话也实际读取成功；当时 Battlefield 返回 62 个节点。节点数和会话 ID 都是当时快照，不要硬编码。
- 修改玩家/武器动作重点看 `tests/attack_motion_test.gd`；地图/碰撞看 `battlefield_test.gd`；敌人/任务/装备分别看 `guard_encounter_test.gd`、`mission_test.gd`、`camp_loop_test.gd`。先读测试的隔离方式及适用入口，再运行相关项。
- 例如：`& 'D:\vibe coding\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'D:\vibe coding\OutpostRPG' --script res://tests/attack_motion_test.gd`。无头检查不能代替画面、音效与手感验收。

下一会话的第一轮只做：读取规则/文档和 Git 差异；沿一次近战实际调用链阅读；用 MCP 对照当前工程和节点；用用户熟悉的 C/模块/状态变量概念解释“节点如何组装、谁调用谁、数据放在哪”。列出不超过 3 个真实风险和一个可独立验证的小改进建议，不自动落地重构。

随后按“用户能指出调用入口/关键状态 → 一处小修改 → 专项验证 → 用户试玩”的节奏并行开发与学习。功能优先级仍是动作流畅度和敌人可读性，之后才按战术缺口决定新敌人或地图内容。

这份文档传递的是可核对的工程状态和用户决策，不代表新对话继承了完整聊天历史。遇到未记录的设计选择，先查源码/最新反馈，不补造历史承诺。
