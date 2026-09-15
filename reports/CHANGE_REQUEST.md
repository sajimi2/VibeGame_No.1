# 公共协议变更请求

提出者：DeepSeek Harness。日期：2026-09-14。关联任务：T01。
裁决：**已由 Codex 在 reports/T01_REVIEW_CODEX.md 第 38-40 行批准**（含语义定义与追加要求）。本文件用于补齐记录，非待批请求。

## 变更 1：ActorCommandPort.get_facing() -> Vector2

- 类型：向抽象契约追加方法（追加式，不修改既有签名、信号或数据对象）。
- 现状：已在 `scripts/contracts/actor_command_port.gd` 声明，由 `scripts/actors/actor_action_port.gd` 实现。
- 原因：`set_intent` 的契约规定“零方向保留上一次非零朝向”，因此朝向是端口的内部状态，但契约没有读取口。T01 需要它驱动朝向箭头；T02 的命中框与格挡弧必须从端口取朝向，而不是从视觉节点取。
- 批准语义：当前世界空间单位朝向；默认 `Vector2.RIGHT`；`set_intent` 收到零 aim 时保留上一方向。
- 调用方影响：仅新增可调用方法，既有实现与调用方无需改动。（范围限定：同上，仅适用于本次已具备该方法的实现类。）
- 迁移方案：无（无可迁移内容）。

## 变更 2：ActorCommandPort.get_velocity() -> Vector2

- 类型：向抽象契约追加方法（追加式）。
- 现状：已在 `scripts/contracts/actor_command_port.gd` 声明；`ActorActionPort` 原本就提供同名方法，本次补上契约声明。
- 原因：`PlayerController` 声明依赖 `ActorCommandPort`，却调用该契约未声明的 `get_velocity()`。具体类能运行，但公共接口不完整。
- 批准语义：返回本物理步要交给身体的期望速度，单位为逻辑像素/秒；纯读取，不在 getter 内消费体力、推进计时或发信号；实际碰撞速度仍由 `CharacterBody2D` 管理。T02 按动作状态提供允许的速度，DEAD 为零。
- 调用方影响：仅新增可调用方法；`ActorActionPort` 既有实现已符合语义，未改行为。（范围限定：该结论只适用于本次已具备同名方法的具体实现；向抽象契约追加方法会要求**所有**实现类提供该方法，不得泛化为“既有实现都无需改动”。）
- 迁移方案：无。

## 变更 3（T02）：ActorCommandPort.get_state_elapsed() / get_attack_id()

- 类型：向抽象契约追加两个读方法（追加式，不修改既有签名、信号或数据对象）。
- 现状：已在 `scripts/contracts/actor_command_port.gd` 声明；`ActorActionPort` 实现，
  `tests/recording_command_port.gd` 测试替身同步补齐。
- 原因：两者都有 T01 契约未覆盖的真实调用方——
  `get_state_elapsed()`：身体在 DODGE 期间需要按已用时间移动；`ActorCombatant` 需要它判定
  无敌窗 `[start, end)`；HUD 需要它显示蓄力。若不在契约声明，调用方只能对自己声明的
  依赖做 `has_method` 猜测或强制转型到具体类，这正是 T01 复审要求避免的“接口不完整”。
  `get_attack_id()`：命中去重键是 `(source_id, attack_id)`，攻击者必须能对外报出当前挥击 id；
  否则 `ActorHitbox` 无法为每个 `DamageEvent` 标注去重键，重复命中保护就只能靠目标猜测。
- 语义：`get_state_elapsed()` 返回当前状态按物理 delta 累积的秒数，纯读取，不推进计时；
  不累积时间的状态返回 0。`get_attack_id()` 每次**被接受的**攻击递增一次，无攻击时为 0。
- 调用方影响：追加抽象方法会要求所有实现类提供这两个方法。本仓库内实现类为
  `ActorActionPort`（已实现）与测试用 `RecordingCommandPort`（已补齐，返回 0）。
  不改任何既有调用方行为。
- 迁移方案：无。

## 变更 4（T03）：ActorCommandPort.Action 追加 DASH

- 类型：向契约枚举追加取值（追加式，不改变既有取值顺序）。
- 现状：`enum Action { LIGHT_ATTACK, HEAVY_ATTACK, DODGE, DASH }`。
- 原因：野兽的短距离突进需要一种"带位移的攻击"，而 DODGE 语义是无敌位移、LIGHT/HEAVY 是原地攻击。
  追加一个动作取值让突进复用既有规则（起手锁定方向、只有 ACTIVE 有判定、收招不可取消），
  比新建一套并行状态更小且更一致。
- 语义：`DASH` 表示"按当前朝向发起一次带 `AttackSpec.charge_distance_pixels` 的攻击"。
  没有配置 `ActorTuning.dash_attack` 的 actor 一律拒绝（`request_action` 返回 false，无副作用）。
- 调用方影响：既有调用方不受影响（新增枚举值，不改变原值）。实现类无需改动即可编译；
  未配置 `dash_attack` 的 actor 行为与之前完全相同（仍拒绝该请求）。
- 迁移方案：无。

## 变更 5（T05）：ProgressionPort 追加 spend_point() 与 Attribute 枚举

- 类型：向抽象契约追加一个枚举与一个方法（追加式；`grant_experience` / `get_snapshot` 签名未动）。
- 现状：已在 `scripts/contracts/progression_port.gd` 声明；`ActorProgression` 实现。
- 原因：TASKS.md 的 T05 写明「Codex 先补定 spend_point 接口和加点枚举，再由 Harness 实现」。
  用户当前目标指令要求连续完成 T03→T07。为避免整条链路因等待设计而停摆，我**提出一个最小方案**并实现，
  同时在本文件与 `reports/T05.md`、`AI_SYNC.md` 槽位 A 标注为「待 Codex 裁定」。
- 方案（尽量小）：
  - `enum Attribute { MAX_HEALTH, MAX_STAMINA }` —— DESIGN 明确 v0.1 只有这两种加点选择；
  - `func spend_point(attribute: Attribute) -> bool` —— 只加一个方法，返回值表达成功/拒绝。
- 语义：无未分配点、超出等级上限、未知枚举值 → 返回 false 且**不改变任何状态**；成功则消耗 1 点并向对应属性加 5；
  **加点不治疗**（提高上限只抬高天花板，当前值由 `ActorCombatant` 钳制而不回填）；
  成功时发 `attribute_increased(attribute, amount)`，由拥有属性的一方重算派生值。
- 新增信号：`points_changed(unspent_points)`、`attribute_increased(attribute, amount)`。
- `get_snapshot()` 允许实现追加只读键（`bonus_max_health` / `bonus_max_stamina`），既有键不变。
- 调用方影响：追加抽象方法会要求所有实现类提供它。仓库内实现类为新增的 `ActorProgression`。
- 迁移方案：无。若 Codex 采用不同命名/签名，改动集中在契约文件与一个实现文件。

## 变更 6（v0.2 阶段 2）：AttackSpec 追加移动模式、移速比与挥砍位移

- 类型：向既有数据 Resource 追加字段（追加式；不改既有字段名、含义或默认行为）。
- 现状：已在 `scripts/combat/attack_spec.gd` 声明，六个玩家招式资源与既有敌人招式资源均已可读。
- 原因：`docs/DEVELOPMENT_PLAN_V02.md` 阶段 2 要求"攻击资源增加移动模式、移速比、挥砍位移，
  默认兼容敌人"。小刀要在整个出招过程保持全速移动，大砍刀要 60% 移速并在伤害窗内前移。
- 语义：
  - `enum MoveMode { STATIONARY, FULL_SPEED, SCALED }` 与 `move_mode`（默认 `STATIONARY` =
    出招期间身体完全由招式接管，与阶段 1 行为一致）；
  - `move_speed_scale`（默认 1.0，只在 `SCALED` 下生效）；
  - `strike_advance_pixels`（默认 0，只在 ACTIVE 生效；速度由"距离 ÷ 有效时长"推导，距离是调参口）。
- 调用方影响：`ActorActionPort._attack_velocity()` 是唯一读取方；默认值使既有敌人招式行为逐项不变，
  有 `tests/v02_stage2_test.gd` 的默认值断言守着。数据文件未加字段者按默认值读取。
- 迁移方案：无。

## 变更 7（v0.2 阶段 2）：新增 WeaponProfile，武器行为与物品定义分离

- 类型：新增文件与追加字段。
- 现状：新增 `scripts/combat/weapon_profile.gd`（`class_name WeaponProfile extends Resource`：
  `light_attack`、`heavy_attack`、`description`、`spec_for(is_heavy, fallback)`）；
  `ItemDefinition` 追加可选字段 `weapon_profile`。
- 原因：玩家会在运行中换武器，招式必须跟着换；把招式挂在物品定义上比在 `ActorActionPort` 里写
  武器分支更小，也让"武器外观/动作从定义读取，不写入存档"这条阶段 2 约束自然成立。
- 语义：装备武器时 `ActorActionPort` 每次出招前取 `ActorCombatant.equipped_weapon_profile()`；
  为 null（空手、或没有背包的敌人）时使用 `ActorTuning` 自带的招式；武器槽为空是正常状态，不是错误。
- 调用方影响：`ActorInventory`、`ActorCombatant` 各追加一个只读查询方法；既有物品定义不填新字段时
  行为与之前完全相同。
- 迁移方案：无。

## 变更 8（v0.2 阶段 2）：GameSession 追加一次性领取标记

- 类型：向具体类追加状态与方法（不是 `scripts/contracts` 下的公共协议）。
- 现状：`GameSession.claimed: Dictionary` + `has_claimed(flag)` / `claim(flag)`，纳入
  `snapshot()` / `restore_from_snapshot()`。
- 原因：开局的刀和村庄武器架的大砍刀都只能拿一次。标记放在会话而不是发放节点上，换图、重试、
  读档才不会重复发放；这与既有 `reward_paid`（契约奖励只发一次）同一思路。
- 语义：`claim()` 已领取过则返回 false 且不改变状态；调用方必须在物品真的交到手上之后才调用它。
- 存档影响：`session` 里多一个可选键 `claimed`；schema 仍为 v1，旧档缺该键时按空表处理。
- 调用方影响：`LevelFlow`（开局装备、HUD 刷新）、`WeaponRack`。
- 迁移方案：无。

## 变更 9（v0.2 阶段 2）：新增 WeaponRack 一次性领取交互节点

- 类型：新增具体节点脚本 `scripts/world/weapon_rack.gd`（不是公共协议）。
- 现状：村庄场景新增 `WeaponRack` 节点，`LevelFlow` 新增可选 `weapon_rack_path` 并在 `_ready()` 里
  `bind_session` + `set_player`（与 `QuestGiver` 相同的显式绑定，避免子节点先 ready 拿到空会话）。
- 原因：阶段 2 要求"村庄一次性领取大砍刀"。做成数据驱动节点后，后续再发武器只需要场景加一个节点与
  一份物品定义，不需要新代码。
- 语义：按 E 领取；物品先交付成功、再写领取标记（满包时拒绝领取且不消耗武器）；领取后提示变为"已取走"。
- 调用方影响：仅村庄场景；其他关卡不挂该节点时为 null，逻辑跳过。
- 迁移方案：无。

## 变更 10（v0.2 阶段 2）：物品目录 12 → 14，玩家默认招式改名

- 类型：数据变更（追加入口 + 替换两个旧资源）。
- 现状：新增 `hunting_knife`、`great_cleaver` 两个定义与对应的武器配置资源；
  `data/attack_light.tres` / `data/attack_heavy.tres`（v0.1 剑盾招式）删除，
  `data/player_tuning.tres` 改指 `data/attack_fist_light.tres` / `data/attack_fist_heavy.tres`。
- 原因：阶段 2 明确"新游戏默认小刀；村庄一次性领取大砍刀""空手基础拳击；法杖留待后续"，
  剑盾不在 v0.2 计划内；`ItemCatalog.default_ids()` 的注释与尺寸说明同步更新。
- 调用方影响：`ItemCatalog.default_ids()` 顺序变化；`tests/t04_inventory_test.gd` 的定义数断言从
  写死 12 改为按 `default_ids().size()` 读取。
- 迁移方案：旧存档里的物品 ID 未变、未被删除，仍能加载；只是不再有新的剑盾招式资源。

## 记录项：T01 未改动但值得留档的约定

- `ActorActionPort.SPEED_PIXELS_PER_SECOND = 90.0` 为 DESIGN.md 的试调默认值，T02 已按约定迁入
  `data/player_tuning.tres` 等参数 Resource，该常量已删除。
- 一次物理步的顺序约定由节点的 `process_physics_priority` 表达。T02 扩展为：
  InputAdapter(-100) 采样并提交意图/动作 → ActorActionPort(-50) 推进状态机 →
  ActorCombatant(-10) 体力回复 → ActorHitbox(-5) 结算有效窗 → 身体(0) 移动并刷新表现。
  盗匪的 AI 组件走同一契约，不另开路径。该顺序属装配层约定，未新增公共接口。
