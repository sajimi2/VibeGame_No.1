# OutpostRPG 当前交接

## 当前分工与规则
- 用户决定方向并试玩；2026-09-15 起 **Harness 负责实现与自测**，Codex 负责设计、接口裁定与审查。
- 个人 Demo，按阶段交付可运行版本，不设置逐任务审批门。用户试玩发现 bug 或进度告一段落时再叫 Codex。
- 本文直接覆盖更新当前状态，不累计旧槽位和长日志。

## 等待 Codex 处理
1. **审查 v0.2 阶段 2**：reports/V02_STAGE2.md，重点是新增的公共/半公共接口（变更 6～10）。
   自测：14 个套件 637 项断言 0 失败，check.ps1 退出 0，导出版实跑退出 0；手感未验证，等用户试玩。
2. **裁定 reports/CHANGE_REQUEST.md 变更 5**（T05 `spend_point` + `Attribute` 枚举）：Harness 提出并已实现，仍待 Codex 正式批准或改写。
3. **裁定变更 6～9**（阶段 2 新增）：`AttackSpec` 移动字段、`WeaponProfile` + `ItemDefinition.weapon_profile`、
   `GameSession.claimed`、`WeaponRack`；其中 `claimed` 是存档里新增的可选键（schema 仍 v1），请确认是否接受。
4. **T07 存档 schema v1** 仍未获 Codex 正式冻结（阶段 2 在其上追加了 `claimed`）。
5. 两个待定项：`play.bat` 是否保留（现为"导出版 / dev 源码直跑"两个入口）；是否把"跳过逐任务审查门"的
   工作流写进 docs/REVIEW.md 与 AGENTS.md（AGENTS.md 目前仍写着每个任务一份审查门）。
6. 已知非阻塞项备案：任意提示音播放过后退出进程，Godot 会报 2 个 ObjectDB 泄漏警告（音频层保留 playback，
   最小探针已复现，与玩法无关）；`LevelUpPanel` 常驻显示。

## 已确认计划
完整计划：docs/DEVELOPMENT_PLAN_V02.md。
保持村庄→林地→哨站下层→上层 Boss 四关结构。
1. 接通拾取、背包比较/换装/卸下/丢弃、成长、跨图与存读档保留，契约交付奖励 50 经验一次。**已完成（阶段 1）**。
2. 两种近战：小刀攻击全速移动；大砍刀蓄势/收招 60% 移速，挥砍惯性前移。暂不做法杖。**已完成（阶段 2）**。
3. 复古略阴郁的西幻像素美术；完整人物动作、受击/格挡反馈、音效、环境声与音乐、HUD。**未开始**。
4. 四关回归及实际窗口验证，导出独立新版，保留旧版。**未开始**。
不扩展力智敏、技能树、商店、制作、AI NPC。

## 当前执行
2026-09-15：Harness 完成阶段 2 并导出 OutpostRPG_v02_Stage2.exe。
- 小刀（猎刀）：轻刺/强刺，起手/有效/收招全程 100% 移速，方向仍锁定。
- 大砍刀：横斩/重劈，全程 60% 移速；伤害窗内沿锁定方向前移轻 8 / 重 14 逻辑像素，仍受墙碰撞约束。
- 招式跟着武器走：`WeaponProfile` + `ItemDefinition.weapon_profile`，空手回落拳击；`AttackSpec` 新字段默认值
  使四个敌人的攻击行为逐项不变。
- 开局默认猎刀；村庄武器架按 E 一次性领取大砍刀；两者都写入 `GameSession.claimed`，换图/重试/读档不重复。
- HUD 新增当前武器行；世界空间提示加描边并把契约提示移到标记下方，修掉与左上角 HUD 的文字重叠。
- 详情与未验证项：reports/V02_STAGE2.md；接口：reports/CHANGE_REQUEST.md 变更 6～10。
下一步：阶段 3（像素美术与完整音效），等用户试玩阶段 2 的手感反馈。

## 最近可用版本
builds/windows/OutpostRPG_v02_Stage2.exe，配套同名 pck（2026-09-15 导出，无头启动退出 0）。
本版包含两种近战与一次性武器领取；不包含正式美术与正式音效。
旧版 OutpostRPG.exe、OutpostRPG_Codex.exe、OutpostRPG_v02_Stage1.exe 全部保留用于对照。
源码入口：双击 EXE 跑导出版；`play.bat dev` 直接跑当前源码（改代码后无需重新导出）。

## 备份与验证原则
v0.2 前源码备份：work/before_v02（含 .gdignore）。
测试真实入口和数据保持，不以断言数量代替试玩；明确实际验证和未验证部分。
每次交付前跑 scripts/check.ps1 与全部 tests/*.gd 套件，并记录命令、退出码与日志路径。

## Git 管理
本地 main 分支，远程 origin = https://github.com/sajimi2/VibeGame_No.1.git（已推送）。
标签 v0.2-stage1 标记用户试玩通过的阶段 1；后续按功能提交、按试玩通过的阶段打标签。说明见 docs/GIT.md。
