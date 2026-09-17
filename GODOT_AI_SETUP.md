# Godot AI 接入说明

安装版本：4.1.0（2026-09-17）。来源：https://github.com/hi-godot/godot-ai/releases/tag/v4.1.0
安装目录：`addons/godot_ai`。本次只接入编辑器工具，没有更改游戏脚本、场景或主场景选择。

## 使用
1. 打开本工程，确认“项目 → 项目设置 → 插件”中的 Godot AI 已启用。
2. Godot AI 面板负责 MCP 连接，不是 Godex 那样的内嵌聊天窗口。等面板连接成功。
3. 在 Codex 中打开本工程目录，使用本地工程模式新建对话。连接配置已写在 `.codex/config.toml`，会话必须信任并加载这个工程。旧对话可能需要重新开启才能加载 MCP。
4. 首次让 Agent 只读调用 `session_manage(op="list")`，按完整项目路径 `D:/vibe coding/OutpostRPG` 找到 session_id，再调用 `editor_state` 和 `scene_get_hierarchy`。每次操作显式带该 session_id，避免两个编辑器之间串工程。
5. 本配置默认逐次确认 MCP 工具调用，未配置自动批准写操作。学习阶段先要求解释/只读，修改前说明影响范围。

本机依赖 uv/uvx 位于 `%USERPROFILE%/.local/bin`，MCP 服务固定使用 godot-ai==4.1.0；HTTP 8000、WebSocket 9500，两个编辑器共用服务并按 session_id 区分。
已经配置好本工程，不必再次点击插件 Configure（该按钮的 Codex 配置会写入用户全局配置）。
插件启用时会自动登记 `_mcp_game_helper` Autoload，用于运行时状态/调试通信；这是插件配套组件。Godot AI 导出插件会将其从发布包中移除。

## 回退
在 Godot 的插件设置里禁用 Godot AI，关闭编辑器，然后可移走 `addons/godot_ai` 和本次新建的 `.codex/config.toml`。
安装前 project.godot 备份：`C:\Users\21775\Documents\Codex\2026-09-14\inn\work\godot-ai-setup\backups-20260917-214358\OutpostRPG\project.godot`。日后若已修改输入、场景等设置，不要直接用旧备份覆盖，应仅撤销插件项。
原 AgentLab 测试副本不在此次安装范围；未改 Codex 全局配置、登录信息和游戏存档。

## 本次实际验证
- 两工程均已通过 Godot 4.7.2 导入，MCP 成功认证。
- 两个编辑器同时连接，分别按 session_id 读取状态和场景树：OutpostRPG → Battlefield，test project → CodeTest。
- 原有 170 / 5 个脚本、场景、资源文件哈希未变；插件 293 个文件与签名发布清单一致。
- 未调用修改节点/脚本的 MCP 工具，未进行全套游戏回归。
- 更新（2026-09-17）：用户已在本工程新对话“验证 Godot MCP 连接”完成实际 MCP 调用，读取 Battlefield 状态和场景树成功。此前首次信任/加载配置的阻碍已解决。后续新会话先读 AGENTS.md、HANDOFF.md，再按工程路径重新匹配 session_id。
