# T01 修复报告（第 3 轮返工）

- 状态：READY_FOR_REVIEW
- 实现者与日期：DeepSeek Harness，2026-09-14
- 对应审查：reports/T01_REVIEW_REVISION_2_CODEX.md（结论 CHANGES_REQUESTED，仅剩 R1c）
- 接口是否改变：否。本轮未增删任何公共协议，也未新增生产脚本的测试钩子。

## 1. R1c [P2] 焦点恢复破坏光标位置与采样缩放的配对 — 已修复

### 缺陷确认

第 2 轮我在 `NOTIFICATION_APPLICATION_FOCUS_IN` 里只重写 `_cursor_scale`，而 `_cursor_viewport` 仍是旧映射下采样的坐标。这等于把一个旧坐标当成新映射下的坐标使用，恰好重新引入了 R1b 的偏移。

用你的探针（未改动 `work/codex_focus_review.gd`）复现：

```
AFTER   stretch=(1.5) actual=(0.860927,0.508729) expected=(0.860927,0.508729) error=0.0
FOCUS_AFTER_RESIZE actual=(0.83205,0.5547) expected=(0.860927,0.508729) error_degrees=3.11083847
退出码 1
```

### 修法

采用复审第 25 行的方案二（失焦清空样本），并删除重锚定：

- **删除** FOCUS_IN 下的 `_cursor_scale = _current_window_scale()`。位置与缩放只在 `_remember_cursor()` 中**成对**写入，任何路径都不再单独改动其中一半。
- **FOCUS_OUT** 时清空 `_has_cursor` 与 `_queued_action`：失焦后窗口可能已移动、被改缩放，或光标已不在本窗口上，旧样本不再可信；已排队但尚未提交的动作边缘也一并丢弃，恢复焦点不得重放。
- 无有效样本时 `_read_aim_direction()` 返回零向量，端口按契约保留上一朝向；焦点恢复本身不是输入事件，不重建样本。首个**新的** MouseMotion 或 MouseButton 会同时写入位置与缩放，恢复完整样本。

未采用方案三（恢复焦点时立即读设备光标）：那需要同时更新位置与缩放并引入可替换坐标来源，超出本轮“只修焦点分支”的范围；若你要求，我可以另做。

### 修复后复验（你的探针，未改动）

```
FOCUS_AFTER_RESIZE actual=(0.860927,0.508729) expected=(0.860927,0.508729) error_degrees=0.0
退出码 0
```

## 2. 新增回归测试

`tests/t01_focus_test.gd`（9 项断言，退出码语义同上），全部无头可跑、全部在**正常物理调度**下（只在 `physics_frame` 边界读状态，不手动调用任何节点的 `_physics_process`），期望值只由引擎自身的 stretch / canvas 变换算出：

1. **缩放 → FOCUS_IN、无新采样**：有效样本不得被扰动（此项即 R1c 的锁定）。
2. **FOCUS_OUT → FOCUS_IN → 首次点击**：无样本时保持原朝向；点击后重建方向并符合当前映射。
3. **聚焦前排队、聚焦后不得送达**：FOCUS_OUT 丢弃已排队动作；FOCUS_IN 不重放；聚焦后的新按下仍恰好送达一次（用 `tests/recording_command_port.gd` 观察提交时刻）。

**有效性验证**：临时把 FOCUS_IN 重锚定加回去再跑，该测试确实失败并报出与你一致的 3.11084 度——

```
WITH_DEFECT_EXIT=1
  [FAIL] focus-in alone must not move the aim (... error=3.11084 deg)
RESTORED_EXIT=0
```

## 3. 执行命令、退出码与日志

| 命令 | 退出码 | 日志 |
|---|---|---|
| `.\scripts\check.ps1` | 0 | `work/*-console.log`、`work/*-parse.log` |
| `--headless --script res://work/codex_focus_review.gd` | 0 | `work/codex_focus_review.log`（1 → 0） |
| `--headless --script res://work/codex_t01_review_probe.gd` | 0 | `work/codex_t01_review_probe.log` |
| `--headless --script res://tests/t01_movement_test.gd` | 0 | `work/t01-tests.log`（checks=60） |
| `--headless --script res://tests/t01_input_path_test.gd` | 0 | `work/t01-input-path-tests.log`（checks=28） |
| `--headless --script res://tests/t01_cursor_resize_test.gd` | 0 | `work/t01-cursor-resize-tests.log`（checks=7） |
| `--headless --script res://tests/t01_focus_test.gd` | 0 | `work/t01-focus-tests.log`（checks=9） |

合计无头断言 60+28+7+9 = **104 项 0 失败**；两个 Codex 复现探针退出码均为 0。R2/R3 未触碰，保持关闭。

## 4. 未验证内容及原因

1. **真实失焦/聚焦**：本轮与你的探针都用 `Node.notification(NOTIFICATION_APPLICATION_FOCUS_OUT/IN)` 做受控通知复现，不是真人切换窗口。真实焦点事件的内容与顺序（是否伴随光标移动、是否跨显示器）未验证。
2. 真人键鼠、真实拖拽缩放窗口。
3. **DPI / 多显示器 / 窗口位移 / letterbox 偏移**：按你的裁决，`capture/current` 比例法只在本轮测试范围（固定窗口原点、无旋转、无额外偏移、仅缩放）内成立；`get_screen_transform().get_scale()` 只覆盖缩放，**不声称**已支持窗口位移与跨 DPI。
4. 无头 0×0 窗口的退化回退分支只用于让无头测试可跑，不构成真实屏幕映射的验证。
5. 相机平滑舒适度、贴墙滑行偏好、160×90 可读性；未在 macOS/Linux 运行。

## 5. Codex 复审建议关注点

- FOCUS_OUT 清空 `_queued_action` 是否符合你对“忙碌状态拒发、不跨状态缓存”的预期；T02 是否需要额外的动作边界用例。
- 无有效样本时保持原朝向（而非回到默认 RIGHT）是否是你要的原型行为。
- 是否需要我现在补方案三（恢复焦点时同时读设备光标位置与缩放）作为后续任务，而不是留在原型限制里。

## 6. 用户手感反馈（无则写待确认）

待确认，同前。
