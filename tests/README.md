# 当前 3D 回归测试

旧 T01–T07、2D Demo 截图/探针测试已移除；保留的测试覆盖现有行为，不按文件年龄决定删留。测试用 `tactical/testing=true` 禁用真实战术存档；背包保存测试仅写 `work/camp_progress_test.json`。

- `startup_smoke.gd`：实际加载配置的 F5 入口，验证装配、五名敌人、相机、默认武器和安全出生点。
- 核心 16 项：`pixel_weapon`（53；渲染时 70）、`weapon_choreography`（50；渲染时 52）、`atlas_pipeline`（55）、`arrow_attachment`（34；渲染时 40）、`character_art`（33）、`locomotion_art`（60；渲染时 62）、`rock_collision`（290）、`guard_reaction`（28）、`attack_motion`（15）、`battlefield`（17）、`guard_encounter`（28）、`mission`（29）、`short_level`（21）、`camp_loop`（22）、`space_combat`（27）、`combat_polish`（15）。共 777 项，渲染模式额外检查 27 项；这是套件规模，不代表每轮全跑。
- `weapon_choreography`：实际轻重疾跑限制及独立来源叠加、十二方向拖地/尘粒清理、交替出招、握点、真实前冲和撞墙、站蹲射击散布、新动作图集编辑回导与实际 Player 接入、守卫/弓手死亡渐隐和坡面贴合。覆盖资源写隔离 `work/weapon_test_*/overrides`；渲染模式输出三种出招的过程及十二方向图、尸体截图。自动断言不代替动作美感与手感验收。
- `atlas_pipeline`：原尺寸 PNG + JSON 导出/编辑/回导、多行裁片、重复替换、错误稿保护、握点、实际玩家/守卫/搭弓箭接入及通用界面。覆盖资源仅写独立 `work/atlas_test_*/overrides/`；不要将其作为正式素材应用。测试会记录隔离路径到 `work/atlas_last_test_root.txt`，新进程加 `-- verify <该路径>` 另查 2 项持久化读取。
- `arrow_attachment`：实际盾挡与身体命中、十二朝向移动/旋转、盾面/纸片嵌入、角色死亡/卸载与飞行箭寿命、垂直射击；玩家插箭停留 4 秒、淡出 0.8 秒、淡出中跟随、独立材质和无重复伤害；渲染时保存盾箭/身体箭十二方向，并比较墙前/墙后及半透明阶段的实际像素。
- `weapon_choreography` 另覆盖目录内全部近战型号的封闭实体、厚度与面朝向、重刀顶点居中；渲染输出正面/双侧举刀，并对照旧单面与实体宝剑的真实阴影。
- `character_art`：十二朝向蹲起不缩放、实际手心/剑柄投影、石材显示与射线碰撞一致；输出全朝向人物和蹲起预览，渲染模式额外保存战场与近景。
- `locomotion_art`：十二朝向疾跑/跳跃图集、真实 Shift 输入、步行/疾跑/蹲行速度、跳跃阶段、持械投影、动态剪影阴影和顶墙停步；身体/移动方向 12×12 组合下的双膝折向，以及实际鼠标事件驱动的后退跳和空中转向；渲染时比较墙前/墙后本体像素。
- `rock_collision`：240 条贴石进退轨迹、40 条真实守卫状态机绕石路线、10 次石面阻弹检查。修复前玩家轨迹 66/240 卡死，修复后全部通过。始终以无头固定 60Hz 加速模拟运行，避免数万物理帧超过单项超时。
- `guard_reaction`：三名守卫在各自出生点横斩/突刺的最终世界顶点、移动转身及父节点旋转缩放、刀光消退；实际远程箭盾挡后的调查、记忆、返回和重新追击。渲染模式可保存刀光截图供人工查看。
- 边界 7 项：`height_lab`、`height_edge`、`art_route`、`outpost_sample`、`letter_interaction`、`feedback_edges`、`tower_feedback`，覆盖坡道、净空、相机/投影、视野和任务输入。
- 23 个功能测试位于 `tactical/`。迁移路径和背包 view 归属已更新；`outpost_sample` 原本就有两项失败，已对照备份复现，并修正登台所需帧数与平台射线取样位置；该历史修正未改变几何、碰撞或断言阈值。
- `pixel_weapon_test.gd`：已加入 core，无头 53 项，实际渲染 70 项。覆盖三种刀剑各十二朝向九相位、离线导出缓存、屏外恢复、移动攻击/蹲/跳、五名敌人的剑盾/弓、弓弦与展示箭、死亡隐藏、武器/刀光真实遮挡和消退。新增五模型十二朝向 GPU 实际纹理与 CPU 输出的轮廓/颜色/深度对照，并断言正式刷新不再填充 CPU 图像缓存。运行引擎 `--path <工程目录> --disable-vsync --max-fps 120 --script res://tests/tactical/pixel_weapon_test.gd`，证据在 `work/weapon_pixels/`；渲染验证不要带 `--headless`。末尾加 `-- gpu-only` 可单查 GPU/CPU 一致性。

从工程根执行 `./scripts/check.ps1 -Suite core`；`-Suite all` 跑边界项目，`-Suite smoke -Rendered` 检查渲染启动。可加 `-GodotPath` 或设置 `GODOT_BIN`。

每项单独引擎进程，上限 300 秒（高度边缘测试约 190 秒）；日志在 `work/checks`。Godot 部分解析错误不返回非零退出码，因此脚本同时检查输出。历史个别无头测试退出有资源清理警告，脚本不忽略脚本错误或失败断言。无头通过不代表手感或图形验收。
