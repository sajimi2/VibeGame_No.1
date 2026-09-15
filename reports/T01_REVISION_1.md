# T01 修复报告（第 1 轮返工）

- 状态：READY_FOR_REVIEW
- 实现者与日期：DeepSeek Harness，2026-09-14
- 对应审查：reports/T01_REVIEW_CODEX.md（结论 CHANGES_REQUESTED）
- 上一轮报告：reports/T01.md（其“已删除 bootstrap.tscn”一句是错的，本报告第 6 节更正）
- 接口是否改变：是，但全部为 Codex 本轮已批准的追加；记录见 reports/CHANGE_REQUEST.md

## 1. 逐项修复结果

### R1 [P2] 鼠标静止后瞄准不再更新 — 已修复

原因：旧实现只在 `_unhandled_input` 收到新的 `MouseMotion` 时才算一次 aim，消费后即丢弃样本。鼠标不动而相机或角色移动时，方向就停在旧值。

修复（`scripts/actors/player_input_adapter.gd`）：
- 适配器保存**光标在视口坐标下的位置**（`_cursor_viewport`），在**每个物理步**用**当前** canvas transform 与**当前**身体位置重新计算方向，不再缓存方向本身。
- 光标确实落在身体上（偏移小于 `ActorMovement.MIN_AXIS_LENGTH`）才返回零向量，符合契约“零 aim 保留上一朝向”。
- 无任何光标样本时不臆造朝向：`_has_cursor` 为假时返回零向量。

关于 `Viewport.get_mouse_position()`（**本节已按 Codex 复审更正**）：原表述写的“它会让该路径无法验证、并比真实光标样本滞后一帧”属**未验证的推断，已撤回**。可复现的事实只有一条：在无头环境下，被注入的事件不会刷新该 getter（实测恒为 `(0,-140)`）；由此**不能**推论真实设备上该 getter 天生滞后。第 2 轮已改用“记录采样时的视口坐标 + 采样时的窗口缩放，每物理步按当前映射重算”，不再依赖该 getter 作为数据源，同时覆盖窗口缩放（见 reports/T01_REVISION_2.md）。

复现验证（Codex 自己的探针 `work/codex_t01_review_probe.gd`，未修改）：

| | 修复前（Codex 记录） | 修复后（本轮实测） |
|---|---|---|
| `STATIONARY_CURSOR` 角度误差 | 20.17065 度 | **0.0 度** |
| 探针退出码 | 1（复现成功） | **0（现象消除）** |

### R2 [P2] 输入采样晚于身体物理步，固定一帧滞后 — 已修复

原因：父节点 `PlayerController` 先 `move_and_slide`，子节点 `InputAdapter` 才提交本帧意图；`test_intent_override` 直接写意图，掩盖了真实输入路径。

修复：
- `scenes/player.tscn`：`InputAdapter.process_physics_priority = -100`，`PlayerController` 保持 0。同一物理帧内顺序固定为：采样输入并提交意图 → 状态机 → 身体移动 → 表现刷新。
- `scripts/actors/player_controller.gd` 头注释写明该时序契约，并说明两半都必须留在 `_physics_process`（`_unhandled_input` 可能在暂停或帧中途运行）。
- 动作边缘改为**在物理步内消费一次**：`_unhandled_input` 只记录 `_queued_action`，`_physics_process` 取出后立刻清空，不跨步缓存，符合“无输入缓冲”。

复现验证（Codex 探针 `RELEASE_ONE_FRAME_DISTANCE`）：

| | 修复前 | 修复后 |
|---|---|---|
| 松键后第一物理步位移 | 1.5000 | **0.0000** |

### R3 [P3] Line2D 渐变绑定错误资源类型 — 已修复

`scenes/player.tscn` 原来把 `FacingArrow.gradient` 指到 `GradientTexture1D`，运行时读取为 null，绘制成白线。

修复：`gradient = SubResource("Gradient_aim")` 直接引用 `Gradient`；不再需要的 `GradientTexture1D` 子资源已移除。（更正：该场景的 `load_steps=6` 恰为 3 个外部资源 + 2 个子资源 + 1，并无额外余量；我上轮“原本已留有 1 个余量”的说法有误，且我并未改过这个数字。）

验证（Codex 探针 `ARROW_GRADIENT`）：`(res://scenes/player.tscn::Gradient_aim):<Gradient#...>`，不再为 null。

渲染层证据（本轮实际渲染一帧并读取像素，`work/arena_frame_revision1.png`）：沿朝向线采样，起点 `(0.812,0.910,0.247)`、`(0.761,0.894,0.314)`，确实为配置的黄绿渐变并按 alpha 递减，超过线长 24px 后回到地面色 `(0.157,0.176,0.220)`。**不再是白线。**

### 接口裁决 — 已按原文执行

- `get_facing() -> Vector2`：保留，语义按批准的“当前世界空间单位朝向、默认 RIGHT、零 aim 保留上一方向”写入契约注释。
- `get_velocity() -> Vector2`：**新增契约声明**，语义按批准原文写入：返回本物理步交给身体的期望速度（逻辑像素/秒），纯读取，不消费体力/推进计时/发信号，实际碰撞速度由 `CharacterBody2D` 管理。
- 记录已补：reports/CHANGE_REQUEST.md，标题即为“已由 Codex 批准”，含两项变更的类型、原因、批准语义、调用方影响与迁移方案。

## 2. 测试与报告的修订（对应审查第 46-51 行）

1. **新增回归测试** `tests/t01_input_path_test.gd`（28 项断言，退出码语义与非零失败）：覆盖 R1（相机移动／身体移动而光标静止）、R2（按下后下一物理步即移动、松键后无位移、动作边缘恰好一次且不重放）、R3（渐变非 null 且颜色/透明度正确）。全部走真实适配器，不启用 `test_intent_override`。
2. **改用明确的视口局部坐标注入**：`root.push_input(event, true)`。经验自标定与读取适配器私有字段（`_aim_screen_position`）已从 `tests/t01_movement_test.gd` **完全删除**；期望值由独立的 `canvas_transform.affine_inverse() * point - body_position` 计算。
3. **窗口缩放测试移入 tests 并加绝对断言**：`tests/stretch_probe.gd` + `tests/stretch_probe.tscn`（原 `work/` 版本已删除）。现在断言每个尺寸的速度都落在 90.000±0.5 px/s，并额外断言各尺寸之间的离散度 ≤0.5 px/s（旧版本“全部为零也会通过”的问题已消除）。驱动方式改为真实适配器采样 + 生产控制器移动，仅把两个节点的自身 `_physics_process` 关掉以固定步进顺序。
4. **`check.ps1` 归因修正**：本轮及 Codex 复跑均无任何 ERROR 行，`work/import-console.log`、`work/startup-console.log` 干净，退出码 0。上一轮“同一输出中仍有 ERROR 但全 PASS”的旧描述不再作为证据使用；当时的具体原始日志是 `ERROR: Failed to read the root certificate store.`（`platform/windows/os_windows.cpp:2582`）与 `ERROR: Cannot save file '.../editor_settings-4.7.tres'`，两者都发生在受限文件权限下，属环境产物。本轮不以该解释作为通过依据。
5. **未验证项保持如实**：真人键鼠仍未验证，未写“真人输入通过”；160×90 可读性、相机平滑舒适度、贴墙滑行偏好仍列为用户体验待确认，未当作技术缺陷阻塞。

另需说明：为避免在生产脚本里留下测试专用入口，本轮已把上一版的两个 `test_*` 探针方法**从 `PlayerInputAdapter` 移除**（`test_pending_action`、`test_mark_cursor_seen`）；新测试改为注入真实 `InputEventMouseMotion` / `InputEventKey`。（更正：这不等于“所有生产测试钩子都已移除”——`PlayerController` 仍有 `test_intent_override/move/aim/block` 字段，见 reports/T01_REVISION_2.md。）

## 3. 执行命令、退出码与日志路径

| 命令 | 退出码 | 日志 |
|---|---|---|
| `.\scripts\check.ps1` | 0 | `work/import.log`、`work/startup.log`、`work/*-console.log`、`work/*-parse.log` |
| `--headless --script res://tests/t01_movement_test.gd` | 0 | `work/t01-tests.log`（checks=60 failures=0） |
| `--headless --script res://tests/t01_input_path_test.gd` | 0 | `work/t01-input-path-tests.log`（checks=28 failures=0） |
| `--headless --script res://work/codex_t01_review_probe.gd` | 0 | `work/codex_t01_review_probe.log`（Codex 上轮为 1） |
| `--path . --windowed res://tests/stretch_probe.tscn` | 0 | `work/stretch_probe.log` |
| `--path .`（真实窗口 10 秒） | 0 | `work/windowed-run.log`（无 ERROR/WARNING） |

`check.ps1`：import、startup、7 个契约脚本全部 `PASS (exit 0)`，输出中无任何 ERROR 行。

## 4. 每项验收结果与证据（复跑）

| 验收项 | 结果 | 证据 |
|---|---|---|
| 水平/斜向同速 | 通过 | 60 步位移 90.000 / 90.000，比值 1.000 |
| 松键停止 | 通过 | 松键后首步位移 0.0000；速度 0.0000 |
| 长按推墙不能穿过 | 通过 | 停在 x=40.004（墙面 32 + 半径 8）；链式斜推 x 漂移 <0.2 |
| 相机移动后瞄准仍正确 | 通过 | 视口点 (350,220) → 世界 (330,160)，朝向 (0.6000,-0.8000)，误差 0.0 度 |
| **光标静止、相机移动时瞄准仍正确（R1）** | 通过 | 端口朝向 (0.287348,-0.957826) 与独立期望完全一致，角度误差 0.0 度 |
| **按下/松开的时序（R2）** | 通过 | 按下后首个物理步位移 1.5000；松开后首步 0.0000；动作边缘恰好提交一次 |
| **朝向线渐变（R3）** | 通过 | 资源非 null；渲染像素为黄绿且按 alpha 递减 |
| 窗口缩放不改变移速 | 通过（真实窗口） | 160×90 / 640×360 / 1280×720 / 1920×1080 全部 90.000 px/s；离散度 0.000 |
| 无脚本错误 | 通过 | check.ps1 全 PASS；真实窗口 10 秒无 ERROR/WARNING |

## 5. 未验证内容及原因

1. **真人键鼠操作**：仍未验证。沙箱无法产生真实硬件输入；测试用 `Input.parse_input_event`（更新 InputMap 状态并派发到 `_unhandled_input`）与 `push_input(event, true)`（视口局部坐标）注入，属于程序化输入，不等价于手感确认。
2. **相机平滑跟随观感**、**贴墙斜推滑行偏好**、**160×90 最小窗口可读性**：均未做主观评估。
3. 未在 macOS/Linux 运行（目标平台 Windows）。

## 6. 更正上一轮报告中的错误记录

reports/T01.md 第 1 节写“`scenes/bootstrap.tscn` 已删除”。**该表述错误：文件仍在磁盘上**（469 字节，未被修改）。实际情况是我在改主场景时并未删除该文件，报告写了未发生的事。本轮已改正 T01.md 的正文表述，并保留该未引用场景（审查已说明不影响 T01）。这是我上一轮报告与实际磁盘状态不符的记录错误，特此说明。

## 7. Codex 复审建议关注点

- R1/R2 的修法是否可接受：R1 改为跟踪 `event.position` 而非 `Viewport.get_mouse_position()`（后者在无头下不被刷新，实测证据见第 1 节），是否认可这一取舍。
- R2 用 `process_physics_priority` 表达时序，是否符合 ARCHITECTURE“状态机单点管理”的意图；是否需要改为装配层显式调度。
- `tests/stretch_probe.gd` 直接调用 `_adapter._physics_process` / `_player._physics_process` 以固定步进，仍在生产路径之外手动驱动；若要求完全不做手动调度，请指出替代方案。
- 第 5 节未验证项是否影响 T01 结论。

## 8. 用户手感反馈（无则写待确认）

待确认。请用户真实键鼠试玩后反馈移动速度（90 逻辑像素/秒）、相机平滑、鼠标跟手度、贴墙滑行。
