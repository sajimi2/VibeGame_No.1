# DeepSeek Harness 交接入口

## 当前交付
这是经过引擎检查的架构骨架，尚无角色、战斗、装备或存档实现。
项目：D:\vibe coding\OutpostRPG
引擎：D:\vibe coding\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
已实测版本：4.7.2.stable.official.ed1daf0bf。

## 将下面整段作为 Harness 的首条任务

```text
请在 D:\vibe coding\OutpostRPG 工作，先明确读取 AGENTS.md、HANDOFF.md、docs/DESIGN.md、docs/ARCHITECTURE.md、docs/TASKS.md、docs/STATUS.md、docs/REVIEW.md 和 scripts/contracts 下的代码。
Codex 负责设计与审查，你负责按契约实现。此次只执行 T01，不实现后续战斗、装备或升级。先检查现有文件和工作区变更，再按 T01 的步骤完成角色移动、相机、输入适配和碰撞测试场。
保持现有公共接口签名，必要的协议调整写 reports/CHANGE_REQUEST.md。运行 scripts/check.ps1，按 T01 验收条目逐项记录结果；不能验证的内容明确标记未验证。
完成后创建 reports/T01.md，更新 docs/STATUS.md 为 READY_FOR_REVIEW，列出如何运行、实际验证结果和需要 Codex 审查的事项，然后停止推进，等待审查。
```

此提示不依赖 Harness 是否自动加载 AGENTS.md。请把会话工作目录设为上述项目路径。
本次只准备交接材料，未向 Harness 发送任务，未改动其凭据或配置。

## 审查循环
1. Harness 实现一个任务，更新报告及状态。
2. 用户回到 Codex 说“审查 T01”（后续换任务编号）。
3. Codex 查看实际文件/差异、重跑关键检查，给出缺陷位置、复现和修复验收标准。
4. 需要修改则标记 CHANGES_REQUESTED，Harness 修复；通过后 Codex 标记 ACCEPTED，并指明下一任务。
5. 用户试玩确认手感。主观手感未确认可单独挂起，不伪装成已验收。

## 环境
开发和语法检查只需要 Godot；VS Code 可选。Git 建议使用但本次未初始化或提交。
Windows 导出需要匹配 4.7.2 的导出模板，在 T07 检查并安装；当前未核实是否已安装。
Harness 的 Node/API 配置由其本地环境管理，与游戏运行时无关。

## 开发命令（PowerShell）
```powershell
Set-Location -LiteralPath 'D:\vibe coding\OutpostRPG'
.\scripts\check.ps1
& 'D:\vibe coding\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path 'D:\vibe coding\OutpostRPG' --editor
```

可在 Godot 编辑器中运行主场景；当前仅显示骨架状态页。

## 官方参考
- https://github.com/deepseek-ai/deepseek-harness （Harness 官方入口；其文档确认 npm 启动方式，本包不假定自动读规则能力）
- https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html
- https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html
