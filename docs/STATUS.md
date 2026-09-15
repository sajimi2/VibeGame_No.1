# 状态

2026-09-14：Codex 已准备设计与接口骨架，验证记录见 reports/BASELINE.md。尚未派发 Harness。
2026-09-14：Harness 完成 T01 实现，等待 Codex 审查；实现记录见 reports/T01.md。T01 的真人键鼠手感项未验证，待用户试玩确认。
2026-09-14：Codex 审查 T01，结论 CHANGES_REQUESTED（R1 静止光标瞄准、R2 输入晚一帧、R3 渐变绑定），见 reports/T01_REVIEW_CODEX.md。
2026-09-14：Harness 完成第 1 轮返工：R1/R2/R3 已修复并经 Codex 原探针复测（角度误差 20.17→0.0 度，松键首步位移 1.5→0.0，渐变非 null）；新增 tests/t01_input_path_test.gd 28 项与迁入 tests/ 的窗口缩放测试（含绝对速度断言）；记录见 reports/T01_REVISION_1.md。真人键鼠手感仍未验证，待用户试玩确认。
2026-09-14：Harness 完成第 2 轮返工：R1b 已修复（光标按采样时缩放每物理步重算当前映射；首次点击也记录光标；焦点恢复重锚定缩放），Codex 缩放探针误差 3.11084→0.0 度、退出码 1→0；新增 tests/t01_cursor_resize_test.gd 7 项（正常物理调度）；无头断言合计 95 项 0 失败；记录见 reports/T01_REVISION_2.md。
2026-09-14：Harness 完成第 3 轮返工：R1c 已修复（删除 FOCUS_IN 的缩放重锚定，位置与缩放只在采样时成对写入；FOCUS_OUT 清空样本与待发动作），Codex 焦点探针误差 3.11084→0.0 度、退出码 1→0；新增 tests/t01_focus_test.gd 9 项；无头断言合计 104 项 0 失败；记录见 reports/T01_REVISION_3.md。

2026-09-14：Harness 完成 T02 最小剑盾战斗：参数集中到 ActorTuning/AttackSpec Resource；CombatantPort 与完整动作状态机（轻重击/闪避/方向格挡/受击/死亡）；一个近战盗匪；HUD 与 R 键死亡重试。check.ps1 退出 0，无头断言合计 183 项 0 失败；真实窗口实测盗匪从 440px 接近至 18.6px 并命中一次（100→88）、HUD 同步，截图 work/t02_fight_frame.png。记录见 reports/T02.md。真人键鼠手感未验证。

2026-09-14：用户试玩 T02：地图边界、墙壁碰撞与已开放功能均无 bug；用户裁定数值与游戏性设计留到后续阶段，不作为本轮验收项。T02 仍待 Codex 审查。

2026-09-14：Harness 完成 T03 敌人组合：弓箭手（瞄准提示/投射物/视线遮挡）、野兽（带位移的突进）、三组固定遭遇（木桩 / 盗匪+野兽 / 弓箭手×2+野兽），进入活动区生成、离开即清除、重试清空敌人与在飞箭矢。用户已指示跳过逐任务审查门，故 T03 在 T02 未标 ACCEPTED 时开始（见 reports/T03.md 第 7 节）。check.ps1 退出 0，无头断言合计 209 项 0 失败；真实窗口截图可见 3 敌人与 2 支在飞箭矢。记录见 reports/T03.md。

2026-09-14：用户试玩 T03 报三个缺陷，已全部复现并修复：①敌人莫名消失（活动半径 200px 超过可见半屏约 160px，边界几乎贴屏幕边）→ 半径收缩为 140/170/165；②敌人血条永远满血（HUD 硬绑已不存在的场景节点）→ 改为跟踪最近存活敌人，随伤害与死亡切换；③攻击无反馈（只有玩家有闪白）→ 新增共用 `ActorHitFeedback` 给全部敌人。另修：敌人尸体不清除会挡路 → 死后 1.1s 清除。新增 tests/t04_bugfix_test.gd 28 项回归，无头断言合计 237 项 0 失败。

2026-09-14：Harness 完成 T04 装备与背包：InventoryPort 实现（20 格背包 + weapon/head/body/accessory 四槽）、12 个物品定义、普通/优质 roll（RNG 可注入、不污染共享定义）、掉落物与掉落表、装备属性接入（护甲/攻击/生命体力上限/移速，基础值+装备重算不漂移）、按 I 打开的比较型背包 UI。新增 tests/t04_inventory_test.gd 131 项，覆盖满包拾取失败掉落仍在、重复拾取无复制、槽位不匹配零副作用、满包换装原子交换、穿脱十次无漂移、固定种子复现。8 个套件合计 368 项断言 0 失败，check.ps1 退出 0。记录见 reports/T04.md。

2026-09-14：Harness 完成 T05 经验与升级：ProgressionPort 实现（等级上限 5、需求 50*L、每级 1 点、跨级保留余量、满级不循环、加点原子且不治疗）、敌人自带经验奖励、升级面板（+5 生命 / +5 体力）。**契约方案由我提出待 Codex 裁定**（`enum Attribute` + `spend_point`，见 reports/CHANGE_REQUEST.md 变更 5）。新增 tests/t05_progression_test.gd 46 项。9 个套件合计 414 项断言 0 失败，check.ps1 退出 0。记录见 reports/T05.md。

2026-09-14：Harness 完成 T06 完整冒险：村庄（安全点、按 E 接/交契约）→ 林地 → 哨站下层（清空开启上层）→ 哨站上层头目 → 回村交付。契约四态且完成奖只发一次；关卡切换携带玩家状态、只有村庄补满；四关统一 32px 基准与受限色板（仍为几何占位）。新增 tests/t06_adventure_test.gd 38 项。修复实现期发现的引擎坑：连续 `change_scene_to_file` 会把场景树清空，改为显式换场景。10 个套件合计 452 项断言 0 失败，check.ps1 退出 0。记录见 reports/T06.md。

2026-09-14：Harness 完成 T07 存档部分：`SaveService`（schema v1 写入 `user://`、临时文件后替换、损坏/未知版本给可恢复反馈且不覆写原文件、加载回村庄安全点、不持久化弹丸与去重记录、完成奖不重复发放），F5 存 / F9 读；`ActorInventory` 与 `GameSession` 增加快照恢复。新增 tests/t07_save_test.gd 32 项，测试用独立存档文件不触碰用户正式存档。11 个套件合计 484 项断言 0 失败，check.ps1 退出 0。**Windows 导出明确阻塞**：导出模板目录不存在（`export_templates/4.7.2.stable` 缺失），实测 `--export-release` 退出码 1 并点名缺少 `windows_release_x86_64.exe`；已交付 `export_presets.cfg`，模板正在下载中，未成功导出前不声称完成。记录见 reports/T07.md。

| 任务 | 状态 | 备注 |
|---|---|---|
2026-09-14：Harness 完成 T07：存档（schema v1、临时文件+替换、损坏/未知版本不覆写、加载回村庄安全点、完成奖不重复、不持久化弹丸与去重记录）32 项断言全通过；**Windows 导出已完成并实际运行验证**——下载并安装匹配的导出模板（1222MB）后 `--export-release` 退出码 0，产出 `builds/windows/OutpostRPG.exe`（104.1MB）+ `.pck`；运行导出的 EXE 确认窗口 1280×720、中文正常显示、输入有响应。实际运行中暴露并修复了一个只在导出包出现的信号错误（Area2D 在信号回调中改 monitoring 被拒 → 改 `set_deferred`）。11 个套件合计 484 项断言 0 失败。记录见 reports/T07.md。

2026-09-15：T07 导出收尾：导出模板已安装（1222MB），`--export-release` 产出 `builds/windows/OutpostRPG.exe`（104.1MB）。**导出版内存档已端到端验证**——用默认关闭的启动自检（`LevelFlow.run_save_smoke_check`）实测：存档写入 `user://`（737 字节）、读档返回 OK、回到村庄、血量恢复。验证后开关设回 false 并重新导出，确认正式导出版启动时不自建存档、`godot.log` 为空。修掉一个只在导出包暴露的信号错误（Area2D 在信号回调中改 monitoring 被拒 → `set_deferred`）。全项目编码扫描干净。**11 个套件 484 项断言 0 失败**，check.ps1 退出 0。

| 任务 | 状态 | 备注 |
|---|---|---|
| T01 | ACCEPTED | 真人手感待确认 |
| T02 | READY_FOR_REVIEW | 剑盾战斗闭环；用户试玩无 bug |
| T03 | READY_FOR_REVIEW | 敌人组合与遭遇；试玩三缺陷已修复并加回归 |
| T04 | READY_FOR_REVIEW | 装备与背包 |
| T05 | READY_FOR_REVIEW | 经验与升级；spend_point 契约方案待 Codex 裁定 |
| T06 | READY_FOR_REVIEW | 完整冒险闭环；程序生成音效 |
| T07 | READY_FOR_REVIEW | 存档完成并在导出版内验证；Windows 导出已产出可运行 EXE |

| 里程碑 | 状态 | 备注 |
|---|---|---|
| v0.2 阶段 1 | 用户试玩通过 | Codex 实现；reports/V02_STAGE1.md |
| v0.2 阶段 2 | READY_FOR_REVIEW | Harness 实现；手感待试玩；reports/V02_STAGE2.md |
| v0.2 阶段 3 | TODO | 像素美术与完整音效 |
| v0.2 阶段 4 | TODO | 四关整体验证与独立交付 |

T03～T07 均已完成并自测通过，等待 Codex 一次性复审。

2026-09-15：用户让 Codex 直接修复试玩缺陷（村庄契约 E 无效、灰墙碰撞体积、弓箭手朝向与穿墙、遭遇越界消失），Codex 修复并导出 OutpostRPG_Codex.exe，另做 Git 管理与 v0.2 计划；记录见 reports/CODEX_PLAYTEST_FIX_20260915.md。

2026-09-15：用户确认 v0.2 阶段 1（装备与成长流程）无 bug，Codex 实现并导出 OutpostRPG_v02_Stage1.exe，本地 main 首个提交 + 标签 v0.2-stage1，并推送 GitHub；记录见 reports/V02_STAGE1.md。

2026-09-15：用户把后续开发交给 Harness。**Harness 完成 v0.2 阶段 2（两种近战）**：`AttackSpec` 增加移动模式/移速比/挥砍位移（默认值等价于旧行为，敌人零改动）；新增 `WeaponProfile` 与 `ItemDefinition.weapon_profile`，`ActorActionPort` 每次出招解析当前武器招式；小刀三阶段全速移动，大砍刀 60% 移速且伤害窗内前移 8/14 像素并受墙碰撞约束；开局默认猎刀、村庄武器架按 E 一次性领取大砍刀（`GameSession.claimed` 随存档保存）；HUD 新增当前武器行。新增 tests/v02_stage2_test.gd 92 项；**14 个套件 637 项断言 0 失败**，check.ps1 退出 0；真实窗口实测小刀 90.0 / 大砍刀 50.4 / 站立重击前移 87.5 px/s，截图 work/v02_stage2_{knife,cleaver,strike}.png 已目视检查；导出 OutpostRPG_v02_Stage2.exe 实跑退出 0。接口追加记录见 reports/CHANGE_REQUEST.md 变更 6～10，完整结果与未验证项见 reports/V02_STAGE2.md。**手感与数值平衡待用户试玩**；阶段 3 美术音效、阶段 4 整体验证未开始。


