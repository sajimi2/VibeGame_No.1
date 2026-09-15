# T01 第二次返工复审

结论：CHANGES_REQUESTED。仅修复新增焦点恢复分支；缩放补偿主体、R2/R3、现有接口不再返工。

## 本轮独立证据
- check.ps1：导入、启动和契约全 PASS，无 ERROR。
- t01_cursor_resize_test.gd：7 项全部通过，输出明确显示 stretch 2.0→1.5，未走 SKIPPED。
- t01_input_path_test.gd：28 项全部通过。
- 旧 Codex 无头探针：朝向误差 0.0、松键首步位移 0.0、Gradient 非 null，退出 0。
- 此次未重跑不受修改影响的 60 项移动套件，不将 Harness 报告的 95 项表述为本轮全量独立复测。
- 真实窗口原缩放探针此次曾出现 33.20 度偏差，但窗口接收真实设备/焦点事件，未隔离事件干扰，不能归因为同一个确定缺陷，也不作为新增阻塞项。以以下可重复的受控复现为裁决依据。

## R1c [P2] 焦点恢复破坏光标位置与采样缩放的配对
位置：scripts/actors/player_input_adapter.gd 的 _notification，条件 NOTIFICATION_APPLICATION_FOCUS_IN 下赋值 _cursor_scale。

该方案的前提是 _cursor_viewport 与 _cursor_scale 属于同一次采样。窗口缩放后，恢复焦点仅替换 _cursor_scale，会把旧坐标当作新映射下的坐标，重新引入已修复的方向偏移。

独立复现文件：work/codex_focus_review.gd；日志：work/codex_focus_review.log。
命令：使用已确认的 Godot，--headless --path <项目> --script res://work/codex_focus_review.gd。
步骤：窗口从 1280×720 改为 960×540，一次采样窗口坐标 (700,400)，缩放后不发新 MouseMotion，再通过 Node.notification 发送应用恢复焦点通知。
实测：通知前 actual=expected=(0.860927,0.508729)，误差 0.0；通知后 actual=(0.83205,0.5547)，误差 3.11084 度，退出 1。这是受控通知测试，不是真人切换窗口。

## 本轮明确修复方向
1. 删除只更新 _cursor_scale 的恢复焦点“重锚定”。不重新采样时必须保持位置与采样缩放成对；仅收到 FOCUS_IN 不得改坏一个有效样本。
2. 如处理真实失焦时样本已失效，允许在 FOCUS_OUT 清空 _has_cursor 和 _queued_action；随后无有效样本保持现有朝向，收到新的 MouseMotion 或 MouseButton 再完整更新位置与缩放。此方案作为原型默认行为获批，不要求实现全平台光标服务。
3. 若选择恢复焦点时立即读设备光标，必须同时更新位置和缩放，并通过可替换输入来源测试；不为了无头注入而牺牲生产坐标语义。
4. 回归至少覆盖“缩放→FOCUS_IN、无新采样”不能破坏有效方向，以及“FOCUS_OUT→FOCUS_IN→首次鼠标点击”建立新方向。若采用失焦清空，明确无样本时保持朝向的断言。恢复焦点不能重放已清空的动作。
5. 保留现有 7+28 项及旧 Codex 探针；新测试放 tests 中。无需再次扩展大范围功能或重写移动架构。

## 对槽位 A 的其余裁决
- capture_scale/current_scale 在当前根视口、无旋转、固定窗口原点与无新增偏移的测试范围内成立。get_screen_transform().get_scale() 只覆盖缩放，不代表处理了窗口位移、letterbox 偏移或跨 DPI；不宣传成这些场景已支持。
- 退化映射回退 ONE 可用于当前无头测试，但不能把该分支当真实屏幕映射验证。新测试的映射变化探测是有价值的。
- 不要求本轮移除 PlayerController 的 test_intent_* 字段；保留且默认关闭即可，避免无关返工。
- DPI/多显示器、真实拖拽、真人键鼠、真实失焦/聚焦、平滑与贴墙主观手感未验证，暂列原型限制，不要求本轮引入额外平台设施。
- 本次仅处理新增错误的焦点分支，R2/R3 保持关闭。T02 在 T01 ACCEPTED 后开展。

提交：reports/T01_REVISION_3.md，更新自己的槽位 A 和日志；不改 Codex 槽位 B。后续复审只围绕这个修复和相关回归。
