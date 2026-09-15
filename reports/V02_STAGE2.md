# v0.2 阶段 2：两种近战（小刀 / 大砍刀）

2026-09-15，Harness 实现，接续 Codex 在 AI_SYNC.md 与 docs/DEVELOPMENT_PLAN_V02.md 中的交接。
本轮只交付阶段 2；阶段 3 美术音效、阶段 4 整体验证仍待推进。

## 已实现

- **小刀（猎刀）**：轻刺/强刺。起手、有效、收招三个阶段都保持 100% 移速，出招方向仍在起手时锁定，
  所以可以边打边拉开距离。
- **大砍刀**：横斩/重劈。三个阶段移速 60%；伤害窗口（ACTIVE）内沿锁定方向前移，轻击 8 逻辑像素、
  重击 14，逻辑与 `docs/DEVELOPMENT_PLAN_V02.md` 一致。前移走 `move_and_slide`，照旧被墙挡住。
- **武器决定招式**：`ItemDefinition.weapon_profile` 指向 `WeaponProfile`（轻/重两个 `AttackSpec` 与一句
  HUD 说明）。`ActorActionPort` 每次出招前向 `ActorCombatant` 取当前装备的武器；武器槽为空时回落到
  `ActorTuning` 的拳击，没有武器的敌人也走同一条回落路径。
- **开局默认小刀**：新开一局时把 `hunting_knife` 直接装进武器槽，并在会话里记下 `starting_kit`。
- **村庄武器架**：新增一次性领取点，按 E 领取大砍刀（`village_cleaver` 标记），换下的武器进背包
  （满包且武器槽已占用时拒绝领取并保留武器架上的武器，不会吞掉）。
- **一次性领取随存档保存**：`GameSession.claimed` 进入快照，换图、重试、读档都不会重复发放；
  领取标记只在物品真的交到手上之后才写入。
- **HUD 当前武器行**：`武器：大砍刀 — 横斩与重劈，蓄势收招 60% 移速，挥砍前移`，由装备变更信号刷新。
- **出招期间禁止换装**：沿用既有规则（`ActionRules.allows_locomotion`），本轮补上回归断言。
- **敌人零改动**：`AttackSpec` 新字段的默认值是"原地不动、不前移"，野兽突进仍用原来的
  `charge_distance_pixels`，因此四个敌人的攻击行为与阶段 1 完全一致（有断言守着）。

## 接口

同步记录在 `reports/CHANGE_REQUEST.md` 变更 6～9。

- `AttackSpec`（`scripts/combat/attack_spec.gd`）新增：
  - `enum MoveMode { STATIONARY, FULL_SPEED, SCALED }` 与 `move_mode`（默认 `STATIONARY`）；
  - `move_speed_scale`（默认 1.0，仅 SCALED 使用）；
  - `strike_advance_pixels`（默认 0，只在 ACTIVE 生效）。
  默认值与旧行为逐项等价，因此既有攻击资源不需要改动。
- 新增 `scripts/combat/weapon_profile.gd`（`WeaponProfile`：`light_attack` / `heavy_attack` /
  `description` / `spec_for(is_heavy, fallback)`）。
- `ItemDefinition.weapon_profile`（新增可选字段）。
- `ActorInventory.equipped_weapon_profile()` 与 `weapon_profile_of(item)`；
  `ActorCombatant.equipped_weapon_profile()`；`ActorActionPort.is_action_in_progress()`。
- `GameSession.claimed` + `has_claimed(flag)` / `claim(flag)`，纳入 `snapshot()` 与
  `restore_from_snapshot()`。存档 schema 仍为 v1：新增键是追加式的，旧档缺该键时按空表处理。
- 新增 `scripts/world/weapon_rack.gd`（数据驱动的一次性领取交互节点：
  `item_definition_id` / `claim_flag` / `equip_directly`），村庄场景新增 `WeaponRack` 节点。
- 物品目录 12 → 14：新增 `data/items/hunting_knife.tres`、`data/items/great_cleaver.tres`。
  既有武器接上配置：`bandit_cleaver`、`woodcutter_axe` → 砍刀配置；`rusty_pick` → 小刀配置。
- `data/attack_light.tres`、`data/attack_heavy.tres` 删除（它们是 v0.1 剑盾的招式），玩家默认招式
  移到 `data/attack_fist_light.tres` / `data/attack_fist_heavy.tres`。`reports/T02.md` 里对这两个
  旧文件的引用自此只作历史记录。

## 验证

- 新 `tests/v02_stage2_test.gd`，**92 项断言 0 失败**：
  - 招式数据：小刀两招 `FULL_SPEED`、大砍刀两招 `SCALED` 0.6、小刀不前移、大砍刀重击位移大于轻击；
  - 敌人默认值未变（四个敌人攻击资源仍是 `STATIONARY`、无前移、无缩放），野兽突进仍有 charge 距离；
  - 小刀攻击三阶段实测 90.0 px/s（`player_tuning.move_speed`）；
  - 大砍刀攻击三阶段 50.4 px/s = (90 − 6) × 0.6，装备自带的 −6 移速只生效一次；
  - 站立不动时 WINDUP/RECOVERY 速度为 0，只有 ACTIVE 沿锁定方向前移（轻 57.1、重 87.5 px/s）；
  - 前移撞墙：从 x=44 向左重击停在 x=40（墙面 32 + 身体半径 8），没有穿墙；
  - 真实命中：重击对木桩造成 47 = 38（大砍刀重击）+ 9（装备攻击加成）；
  - 换武器后下一次出招即使用新招式；卸下武器后回落拳击（7 伤害）；
  - 武器架：一次领取、二次按 E 无副本、被换下的猎刀仍在背包、提示变为"已取走"；
  - 换图往返与存读档后领取标记、装备与物品数量都保持；
  - 出招中打开背包按装备被拒，武器不变。
- 真实窗口（NVIDIA OpenGL 3.3，1280×720，`tests/stage2_capture.tscn`）实测：
  小刀攻击 90.0 px/s、大砍刀攻击 50.4 px/s、站立重击前移 87.5 px/s。
  截图 `work/v02_stage2_knife.png`（开局猎刀 + 武器架提示 + HUD 武器行）、
  `work/v02_stage2_cleaver.png`（领取后 HUD 换成大砍刀）、`work/v02_stage2_strike.png`
  （重击有效窗内命中木桩）已逐张目视检查。
- `scripts/check.ps1` 退出 0（导入、无头启动、7 个契约解析）。
- 回归 14 个套件 **637 项断言 0 失败**：
  t01 57/28/7/9、t02 82、t03 27、t03 bugfix 28、t04 137、t05 46、t06 38、t07 32、
  codex_playtest_regression 26、v02_gameplay 28、v02_stage2 92。
  两处旧断言按新事实改写（不是放宽）：
  - `t02_combat_test` 的体力原子性与单次命中断言改为从当前招式读取代价与伤害，不再写死 16/18；
  - `v02_gameplay_test` 的"选中不立即装备"改为对比装备前后，因为现在开局武器槽里就是猎刀。
- 视觉整理（本轮截图发现）：世界空间提示文字加描边、契约提示从标记上方移到下方，
  修掉"提示压在左上角 HUD 上导致两行字互相盖住"。同一改动应用到四个关卡。
- 顺手清掉一个导出残留临时文件 `OutpostRPG.exe~RF9cf546.TMP`。

## 未验证 / 遗留

- **手感未验证**：两种武器的节奏、8/14 像素前移是否够"沉"、60% 移速是否拖沓，都需要用户实际试玩。
  数值（小刀 13/22、大砍刀 22/38、体力 9/20/18/32、前摇 0.10/0.24/0.30/0.48）是试调默认值，未做平衡。
- 拳头数值同样是试调默认值；"空手明显弱于小刀"只有 7 vs 13 的伤害差，未做体感确认。
- 未做正式美术与正式音效（阶段 3）。武器架、大砍刀都还是几何占位。
- 已知非阻塞：只要本进程播放过任意提示音，退出时 Godot 会报 `2 ObjectDB instances were leaked at exit`
  （AudioStreamWAV + 其 playback）。我用一个最小探针复现过：只有这个类播一个音就会触发，停播、
  清空 stream、提前 free 节点都不能消除，属于音频层在退出时保留了 playback，与玩法无关。
  开局发放武器时**不**播音，所以无头启动检查保持干净。结论写在 `scripts/ui/sfx_player.gd` 顶部注释。
- `LevelUpPanel` 常驻显示（阶段 1 既有表现，0 点时按钮置灰），本轮未动。
- 未做四关完整跑通与 Boss 复测（阶段 4）。

## 阶段产物

- `builds/windows/OutpostRPG_v02_Stage2.exe` + 同名 `.pck`：导出退出 0，导出后用
  `--headless --quit-after 120` 实跑，进程退出 0，`godot.log` 无脚本错误。
- 旧产物 `OutpostRPG.exe`、`OutpostRPG_Codex.exe`、`OutpostRPG_v02_Stage1.exe` 全部保留对照。
- 试玩建议：双击 `builds/windows/OutpostRPG_v02_Stage2.exe`；改代码后要看效果用 `play.bat dev`。
