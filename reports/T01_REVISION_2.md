# T01 修复报告（第 2 轮返工）

- 状态：READY_FOR_REVIEW
- 实现者与日期：DeepSeek Harness，2026-09-14
- 对应审查：reports/T01_REVIEW_REVISION_1_CODEX.md（结论 CHANGES_REQUESTED，仅剩 R1b）
- 接口是否改变：否。本轮未增删任何公共协议；`get_facing` / `get_velocity` 沿用已批准状态。

## 1. R1b [P2] 缩放后沿用失效视口坐标 — 已修复

### 缺陷确认

第 1 轮我把光标以**视口坐标**缓存（`_cursor_viewport = event.position`）。窗口 stretch 改变后，同一物理光标位置对应的视口坐标随之改变，而缓存值不会更新；没有新的 MouseMotion 时错误就会一直存在。

修复前用你的探针实测（未改动该文件）：

```
BEFORE stretch=(2.0) facing=(0.83205, 0.5547)
AFTER  stretch=(1.5) viewport=(466.6667, 266.6667) actual=(0.83205, 0.5547)
                     expected=(0.860927, 0.508729) error_degrees=3.11083847
退出码 1
```

### 修法

`scripts/actors/player_input_adapter.gd`：

- 采样光标时**连同当时的窗口→视口缩放一起记录**：`_cursor_viewport` + `_cursor_scale = _current_window_scale()`。
- 每个物理步重算方向前，先按**当前**缩放把缓存点换算到当前映射：
  `viewport_now = cursor_viewport * (capture_scale / current_scale)`。
  物理位置 = 视口位置 × 缩放，所以反向换算乘的是 `capture/current`。
- 缩放在**每次**使用时从 `Viewport.get_screen_transform().get_scale()` 现取，不缓存；无头 0×0 窗口的三次变换退化为 (0,0)，此时按“位置已可视口化”处理（项目视口固定 640×360，缩放为 1）。
- 首次点击：`InputEventMouseButton` 同样携带光标位置，现已一并记录。实测确认此前**只处理 MouseMotion**，导致“开局先点一下鼠标”在移动鼠标前无法建立朝向。
- 焦点恢复：收到 `NOTIFICATION_APPLICATION_FOCUS_IN` 时用当前缩放重新锚定 `_cursor_scale`，避免窗口被移到别的显示器/改过缩放后仍按旧映射投影。

### 修复后复验（你的探针，未改动）

```
BEFORE stretch=(2.0) facing=(0.83205, 0.5547)
AFTER  stretch=(1.5) viewport=(466.6667, 266.6667) actual=(0.860927, 0.508729)
                     expected=(0.860927, 0.508729) error_degrees=0.0
退出码 0
```

### 回归测试（按你的要求：正常物理调度、整理到 tests/）

新增 `tests/t01_cursor_resize_test.gd`（7 项断言，退出码语义同上）：

1. 窗口缩小后光标静止，朝向须跟随新映射（容差 ≤1 度）。
2. 窗口放大后同理（1280×720 → 1600×900）。
3. 缩小再复原，朝向须回到原值（同时覆盖无漂移）。
4. 首次 MouseButton 点击即可建立朝向。

全部只用 `await physics_frame` 观察步边界，**不调用任何节点的 `_physics_process`**；期望值由引擎自身的 `get_stretch_transform().affine_inverse()` 与 canvas transform 独立算出，不读适配器私有状态。注入用 `Viewport.push_input(event, false)`（窗口坐标经真实 stretch 变换）。

**有效性验证**：我临时把修复还原成缺陷版本再跑该测试，确认它能抓住缺陷——

```
WITH_DEFECT_EXIT=1
  [FAIL] 缩小: error=3.11084 deg（与你探针数值一致）
  [FAIL] 放大: error=172.87498 deg
RESTORED_EXIT=0
```

无头环境（窗口 0×0）下该文件仍会充分执行：root viewport 的 size 可设，stretch 仍为 2.0/1.5，因此 4 个用例都在无头下真实跑过并通过；仅在检测到“改窗口尺寸不影响映射”时才会打印 SKIPPED，避免空过。

## 2. 按复审要求撤回的错误断言

- **撤回**“`Viewport.get_mouse_position()` 比真实光标样本滞后一帧”。可复现的只有“无头下注入事件不刷新该 getter”，由此推论真实设备行为属未验证，已从 reports/T01_REVISION_1.md 与我的槽位记录中删除。本轮修复也**不再以该 getter 为数据源**。
- **更正** `load_steps`：`player.tscn` 的 6 = 3 外部资源 + 2 子资源 + 1，**没有余量**；我上轮“原本已留有 1 个余量”的说法有误，且我并未改过该数字。
- **更正**测试钩子范围：`PlayerInputAdapter` 的两个方法型钩子已移除，但 `PlayerController` 仍保留 `test_intent_override/move/aim/block` 字段。它们是测试驱动入口，目前不阻塞；如需一并去掉，我可以把测试改为注入真实键鼠事件后删除这些字段——请指示。
- `reports/CHANGE_REQUEST.md` 已限定：追加抽象方法会要求**所有**实现类提供该方法，“既有实现无需改动”只适用于本次已具备同名方法的实现，不得泛化。

## 3. 执行命令、退出码与日志

| 命令 | 退出码 | 日志 |
|---|---|---|
| `.\scripts\check.ps1` | 0 | `work/*-console.log`、`work/*-parse.log` |
| `--headless --script res://tests/t01_movement_test.gd` | 0 | `work/t01-tests.log`（checks=60） |
| `--headless --script res://tests/t01_input_path_test.gd` | 0 | `work/t01-input-path-tests.log`（checks=28） |
| `--headless --script res://tests/t01_cursor_resize_test.gd` | 0 | `work/t01-cursor-resize-tests.log`（checks=7） |
| `--headless --script res://work/codex_t01_review_probe.gd` | 0 | `work/codex_t01_review_probe.log` |
| `--windowed --script res://work/codex_resize_review.gd` | 0 | `work/codex_resize_review.log`（误差 0.0 度） |

合计无头断言 60+28+7 = 95 项，0 失败。

## 4. 未验证内容及原因

1. 真人键鼠操作（含真实鼠标拖拽缩放窗口）：仍未验证。缩放回归用的是程序化注入 + 程序化改窗口尺寸，属受控输入，不等于真人拖拽。
2. 相机平滑舒适度、贴墙滑行偏好、160×90 最小窗口可读性。
3. 焦点恢复路径只做了代码级处理与 `NOTIFICATION_APPLICATION_FOCUS_IN` 重锚定，**未在真实失焦/聚焦操作下验证**（沙箱无法切窗口）。
4. 未在 macOS/Linux 运行。

## 5. Codex 复审建议关注点

- `capture_scale / current_scale` 的换算是否认可；缩放取自 `get_screen_transform()` 是否合适（而非事先存窗口尺寸）。
- “无头 0×0 窗口缩放退化为 (0,0) 时按位置已可视口化处理”这一分支是否可接受。
- 是否要求一并移除 `PlayerController` 的 `test_intent_*` 字段。
- DPI/多显示器切换只有代码路径，无实测证据，请判定是否需要额外验证手段。

## 6. 用户手感反馈（无则写待确认）

待确认，同前。
