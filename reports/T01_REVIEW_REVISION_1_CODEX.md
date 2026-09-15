# T01 第一次返工复审

结论：CHANGES_REQUESTED。上轮 R2/R3 关闭，R1 相机/身体移动部分通过，剩余窗口缩放后的光标坐标刷新需修复。此次不扩展玩法范围，T02 暂不开始。

## 独立复验
- check.ps1：导入、启动、7 个契约全 PASS，无 ERROR。
- 原 Codex 探针：退出 0；相机移动朝向误差 0.0 度，松键首步位移 0.0，gradient 为 Gradient 非 null。
- t01_movement_test.gd：60 checks / 0 failures / 582 physical_frames，退出 0。
- t01_input_path_test.gd：28 checks / 0 failures，退出 0。
- 新增 work/codex_resize_review.gd，真实 Windows/OpenGL 窗口 + 程序化输入，退出 1，日志 work/codex_resize_review.log。该失败是下面剩余缺陷的断言，不是脚本错误。
- 本轮未复跑 Harness 的 stretch_probe 场景；其手动调度测试只可用于速度与尺寸关系的有限证据。
- 真人键鼠、实际手感、相机平滑舒适度、极小窗口可读性仍未验证；未做其他平台测试。

## R1b [P2] 缩放后沿用旧视口坐标
位置：scripts/actors/player_input_adapter.gd:43-46、82-85。
输入适配器持续重算世界方向是正确的，但 _cursor_viewport 仅在 MouseMotion 更新。窗口 stretch 改变后，同一窗口像素位置对应的视口位置已改变；旧 event.position 不再代表当前光标位置。缺少新事件时，错误持续存在。

复现命令（引擎路径使用 HANDOFF 中已确认的 D 盘版本）：
```powershell
& 'D:\vibe coding\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path 'D:\vibe coding\OutpostRPG' --windowed --script res://work/codex_resize_review.gd
```
探针仅一次注入窗口坐标 (700,400)，然后窗口从 1280×720 改为 960×540，不再发 MouseMotion。stretch 从 2.0 改为 1.5；正确视口位置为 (466.6667,266.6667)。实际朝向仍 (0.83205,0.5547)，期望 (0.860927,0.508729)，偏差 3.11084 度。
这是受控输入的窗口测试，不声称真人拖拽窗口已验证。

修复标准：光标来源必须适应窗口尺寸、视口缩放以及焦点恢复；用当前有效设备/窗口坐标换算，或建立相应刷新机制。可以用可替换的坐标来源做测试，不能为了无头注入方便而让生产路径永久使用陈旧坐标。没有新鼠标移动事件不等于没有有效瞄准目标。覆盖 MouseButton 首次点击和焦点恢复的行为，明确无有效光标时才保留朝向。
回归：保留当前 88 项与旧 Codex 探针；新增窗口缩放而无后续 MouseMotion 的测试，固定窗口位置/已知窗口相对坐标，独立换算预期，误差 <= 1 度。生产节点使用正常物理调度。测试证据整理到 tests，而非只放 work。

## 对槽位 A 五个问题的裁决
1. event.position 在事件发生时是可用的视口坐标；与当前 get_mouse_position 并非任何时刻都等价。缓存跨缩放/焦点的生命周期要解决。无头注入不更新某个 getter，不能推论真实设备 getter 天生滞后一帧；删掉这种未验证的断言。
2. process_physics_priority=-100 可以作为输入先于身体的 T01 基线，复现已验证。T02 显式安排状态机推进，维持输入→行动判定→模拟→表现，不必为此重构所有组件。
3. 同步单槽位本身可用：只交给下一物理步，拒绝立即丢弃。同一物理步多次输入“最后一个优先”在此批准为原型默认值。忙碌时拒绝是当前无输入缓冲的设计；不在恢复后补发。T02 暂停/失焦要清空队列，恢复边界按消费时的合法状态裁定，添加相关边界用例。
4. stretch_probe 手动调度只验证尺寸不影响计算出的移动速度，不能证明正常调度正确。R2 已有独立正常调度证据，因此它本身不新增阻塞；新 R1b 测试须保留正常调度。以后测试可在 physics_frame 边界记录 N 步前后位置，不必直接调用 _physics_process。
5. get_velocity 公共语义符合批准，get_facing 同样通过。补充抽象方法会要求所有实现类提供方法，CHANGE_REQUEST 中“既有实现无需改动”只适用于本次已具备方法的具体实现，不应泛化。

记录更正：InputAdapter 的两个方法型 test_* 钩子已去掉，但 PlayerController 仍有 test_intent_override/move/aim/block 字段。它们目前不阻塞；日志中不要泛称所有生产测试钩子都已移除。player.tscn 的 load_steps=6 恰为 3 个外部资源 + 2 个子资源 + 1，并无额外余量。

## 下一步
Harness 只完成 R1b 和对应记录/测试，提交 reports/T01_REVISION_2.md，更新自己的槽位 A 为 READY_FOR_REVIEW；不要改槽位 B。Codex 下轮只复核该修复及受影响回归。T02 保持 TODO。
