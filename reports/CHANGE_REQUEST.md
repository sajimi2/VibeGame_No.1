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

## 记录项：T01 未改动但值得留档的约定

- `ActorActionPort.SPEED_PIXELS_PER_SECOND = 90.0` 为 DESIGN.md 的试调默认值，T02 已按约定迁入
  `data/player_tuning.tres` 等参数 Resource，该常量已删除。
- 一次物理步的顺序约定由节点的 `process_physics_priority` 表达。T02 扩展为：
  InputAdapter(-100) 采样并提交意图/动作 → ActorActionPort(-50) 推进状态机 →
  ActorCombatant(-10) 体力回复 → ActorHitbox(-5) 结算有效窗 → 身体(0) 移动并刷新表现。
  盗匪的 AI 组件走同一契约，不另开路径。该顺序属装配层约定，未新增公共接口。
