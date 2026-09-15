# Codex 试玩缺陷修复 · 2026-09-15

用户要求 Codex 直接修复以对比实现效果。本轮已修改生产代码，并导出独立试玩版本；无需 Harness 再执行上一轮修复任务。

## 修改
- 契约：LevelFlow 创建会话后显式调用 QuestGiver.bind_session，解决冷启动子节点先 ready 缓存空会话的问题。
- 村庄灰块：Well 使用独立 40×40 碰撞资源，房屋保持原尺寸。
- 弓箭手：提交瞄准方向后才开始攻击，预警线采用锁定朝向；有掩体时不发起攻击，发射时仍再次检测视线。
- 箭矢：top_level 隔离射手位移，保留父子归属以沿用重试/场景清理；检测枪口偏移段，射线启用 hit_from_inside，避免出生在墙内后穿出。
- 遭遇：半径只用于首次激活，当前关卡活敌人不因玩家越界删除；全灭同步结束 engaged，避免误发脱战。死亡、重试、场景释放仍清理。

## 验证
- tests/codex_playtest_regression.gd：26 项通过，覆盖正式村庄冷启动与物理 E 键事件、碰撞尺寸、左/上/斜向首次箭矢实际命中、预警方向、射手移动不拖箭、墙外/墙内箭和枪口薄墙、越界存活与实例保留、全灭提示状态、重试。
- 在隔离副本恢复修复前的七个生产文件，同一测试得到 26 项中 17 项失败；修复后 0 失败。失败计数包含同一根因引起的后续失败，不代表 17 个独立 bug。旧代码正常撞墙通过，但起点在墙内及枪口跨薄墙失败，因此穿墙不是“完全没碰撞检测”。
- 相关回归：t03_encounter_test 27 项、t03_bugfix_test 28 项、t06_adventure_test 38 项通过。旧“越界应删除”断言更新为当前玩法，其他伤害、血条、尸体、过关、任务奖励测试保留。合计本轮 119 项断言通过。
- 导入无脚本解析错误。Windows 导出生成 exe/pck；导出后 exe 用 --headless --quit-after 120 启动，进程退出 0，无游戏脚本错误。
- 环境日志仍报告无法读取 Windows 根证书仓库，以及编辑器无法写入受限的 AppData 设置文件；没有将这些日志隐瞒为“全程无 ERROR”。本地游戏测试和产物运行完成，不涉及联网功能。

## 产物与限制
- 新版：builds/windows/OutpostRPG_Codex.exe，与同目录 OutpostRPG_Codex.pck 配套。
- 原 OutpostRPG.exe/pck 未覆盖，可作试玩对照。源代码已是修复版，编辑器 F6/F5 会使用修复后的代码。
- 原始修改文件备份：work/codex_before_bugfix_20260915（带 .gdignore，避免扫描成重复全局类）。
- 日志：work/codex-regression.log、codex-t03.log、codex-t03-feedback.log、codex-t06.log、codex-export-console.log、codex-export-startup.log。
- 未进行真人键鼠试玩与图形观感确认，未声称整个游戏没有其他 bug。敌人当前会留在本关继续战斗，未增加归巢寻路系统。
