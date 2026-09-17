# OutpostRPG 接手入口

1. 读 `AGENTS.md`、`README.md`、`AI_SYNC.md`；架构看 `docs/ARCHITECTURE.md`，方向看 `docs/TACTICAL_HEIGHT_PLAN.md`。
2. 先查看 Git 工作区；保留他人未提交修改。当前重构分支为 `codex/3d-maintainability`。
3. 最新入口为 `scenes/battlefield.tscn`，F5 已对齐；3D 试验场 `scenes/tactical_height.tscn` 仍可 F6。旧 2D 已经用户明确同意从工作区移除。
4. 清理前完整快照 `9c4dc82` 已推送 GitHub，标签 `backup/pre-3d-cleanup-20260917`；该节点包含原 2D、最新 3D、旧报告和插件。个人配置与构建缓存不在 Git 中。
5. 新代码路径按职责组织，原 `scripts/tactical/` 已迁移；见架构文档。不可按已删除的 T01–T07 顺序推进。
6. 战术 v1 存档、项目身份和物品实例 ID 保持兼容。测试必须隔离玩家存档；使用 `scripts/check.ps1`。
7. 默认任务以用户当前请求为准；不自动新增敌人、地图或大框架。技术通过与主观试玩通过分开报告。
8. MCP 每次通过 `session_manage(op="list")` 匹配完整工程路径，显式传 `session_id`。另一个学习工程和 AgentLab 均不属于本工程。
