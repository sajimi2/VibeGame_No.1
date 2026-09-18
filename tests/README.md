# 当前 3D 回归测试

旧 T01–T07、2D Demo 截图/探针测试已移除；保留的测试覆盖现有行为，不按文件年龄决定删留。测试用 `tactical/testing=true` 禁用真实战术存档；背包保存测试仅写 `work/camp_progress_test.json`。

- `startup_smoke.gd`：实际加载配置的 F5 入口，验证装配、五名敌人、相机、默认武器和安全出生点。
- 核心 9 项：`guard_reaction`（28）、`attack_motion`（15）、`battlefield`（17）、`guard_encounter`（28）、`mission`（29）、`short_level`（21）、`camp_loop`（22）、`space_combat`（27）、`combat_polish`（15）。括号为断言数，共 202。
- `guard_reaction`：三名守卫在各自出生点横斩/突刺的最终世界顶点、移动转身及父节点旋转缩放、刀光消退；实际远程箭盾挡后的调查、记忆、返回和重新追击。渲染模式可保存刀光截图供人工查看。
- 边界 7 项：`height_lab`、`height_edge`、`art_route`、`outpost_sample`、`letter_interaction`、`feedback_edges`、`tower_feedback`，覆盖坡道、净空、相机/投影、视野和任务输入。
- 16 个玩法测试位于 `tactical/`。迁移路径和背包 view 归属已更新；`outpost_sample` 原本就有两项失败，已对照备份复现，并修正登台所需帧数与平台射线取样位置；几何、碰撞和断言阈值不变。

从工程根执行 `./scripts/check.ps1 -Suite core`；`-Suite all` 跑边界项目，`-Suite smoke -Rendered` 检查渲染启动。可加 `-GodotPath` 或设置 `GODOT_BIN`。

每项单独引擎进程，上限 300 秒（高度边缘测试约 190 秒）；日志在 `work/checks`。Godot 部分解析错误不返回非零退出码，因此脚本同时检查输出。历史个别无头测试退出有资源清理警告，脚本不忽略脚本错误或失败断言。无头通过不代表手感或图形验收。
