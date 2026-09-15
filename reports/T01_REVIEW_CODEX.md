# T01 审查结果与修复任务

审查者：Codex。日期：2026-09-14。结论：**CHANGES_REQUESTED**。
先修复本报告并重新提交 T01，暂不进入 T02。未修改 Harness 的业务实现。

## 独立验证
- 重跑 scripts/check.ps1：import、startup、7 个契约全部 PASS，退出 0。本轮未观察到根证书或权限报错。
- 重跑 tests/t01_movement_test.gd：checks=60、failures=0、physical_frames=588，退出 0。
- 新增审查复现 work/codex_t01_review_probe.gd，并使用 Godot --headless --path <project> --script res://work/codex_t01_review_probe.gd 执行：退出 1，表示成功复现下述瞄准偏差，不是解析失败。日志 work/codex_t01_review_probe.log。
- 检查已有 work/arena_frame.png：文字可读，朝向线实际为白色。该图片是 DS 提供的既有帧，非本轮重新渲染。
- 本轮没有真人键鼠操作、图形窗口缩放复测或主观手感验证，不对这些作通过声明。
- 项目没有可用基线 diff，本轮基于当前文件、上轮已知骨架和重新执行的证据审查。

## R1 [P2] 鼠标静止后，玩家/相机移动不再更新瞄准
位置：scripts/actors/player_input_adapter.gd:54-58。
原因：只有收到新的 MouseMotion 才计算 aim；消费后把 _has_aim_sample 清掉。没有鼠标事件不代表世界方向为零，角色位置与 canvas transform 仍可能改变。
复现：玩家置 (300,200)，相机 (300,120)，向视口点 (350,220) 注入一次 MouseMotion；随后只把相机移到 (300,60)，不再注入鼠标。
实测：初始实际/期望均 (0.6,-0.8)。移动相机后实际仍 (0.6,-0.8)，期望 (0.287348,-0.957826)，偏差 20.17065 度。
影响：边移动边瞄准、平滑相机尚未稳定和缩放后，箭头可能不再指向屏幕光标；T02 将把错误方向传到攻击和格挡。
修复目标：每物理步使用当前有效的视口光标坐标、当前 canvas transform 和身体位置计算 aim。鼠标没有新事件时仍应重新计算；确实重合/无有效目标才传零向量。处理首次输入、窗口缩放及焦点切换后的坐标有效性。
回归：鼠标只注入一次，随后移动相机/角色，朝向匹配独立计算的期望；覆盖默认平滑相机和实际窗口缩放后的静止光标。不要为了通过用例再补发 MouseMotion。

## R2 [P2] 输入采样晚于身体物理步，造成固定一帧滞后
位置：scripts/actors/player_controller.gd:30-38；scripts/actors/player_input_adapter.gd:51-58；scenes/player.tscn 的父子默认处理顺序。
原因：父节点 Player 先用旧端口意图 move_and_slide，子节点 InputAdapter 随后才提交本帧意图。test_intent_override 在父节点直接设置意图，掩盖了实际输入路径的滞后。
复现：独立探针通过 Input.action_press/release 走真实适配器（不是硬件输入），在物理步边界释放 move_right 后观察下一物理步。
实测：松键后的第一物理步仍前进 1.5 逻辑像素；60Hz、90px/s 下正好是一帧。
影响：移动起停和朝向显示使用上一帧输入；下一阶段即时格挡/出招容易进一步出现顺序问题。
修复目标：明确一次物理步的顺序为输入采样/动作意图→状态机→身体移动→表现。可设物理处理优先级，或由装配层明确调度；避免两套路径双重处理。T02 的按键边缘也应按约定时序消费一次，不跨忙碌状态缓存出招。
回归：通过 InputMap 的 press/release 或输入事件驱动适配器，不启用 test_intent_override；按下后的首个物理步开始移动，释放后的首个物理步无位移。断言应在对应物理步完成后读取。

## R3 [P3] Line2D 渐变绑定了错误资源类型
位置：scenes/player.tscn:38。
现象：gradient 被赋为 GradientTexture1D；运行时读取 FacingArrow.gradient 为 null，既有截图也显示白线而非配置的黄绿渐变。
修复目标：gradient 引用现有 Gradient_aim；不需要的纹理资源可移除，并调整场景资源计数。
验证：实例化后 gradient 非 null，检查实际渲染颜色。此项是小缺陷，可随 R1/R2 一起修复。

## 接口与实现范围裁决
- **批准 get_facing() -> Vector2**，语义是当前世界空间单位朝向，默认 RIGHT，零 aim 保留上一方向。应补 reports/CHANGE_REQUEST.md 记录“已由 Codex 本次批准”；添加抽象方法也属于协议更改，不能据“纯追加”跳过记录。
- PlayerController 声明依赖 ActorCommandPort，却调用该契约未声明的 get_velocity()。当前具体类能运行，但公共接口不完整。**批准在 ActorCommandPort 追加 @abstract func get_velocity() -> Vector2**：返回本物理步要交给身体的期望速度，单位为逻辑像素/秒，不在 getter 内消费体力/推进计时/发信号；实际碰撞速度由 CharacterBody2D 管理。T02 按动作状态提供允许的速度，DEAD 为零。Harness 在本次修复中补上声明和变更记录即可，无须再询问。
- 允许保留小型纯函数辅助类，未发现插件/Autoload/全树扫描等越界实现。
- 主场景替换为 arena 合理；是否保留未引用 bootstrap 不影响 T01。当前磁盘上 bootstrap.tscn **仍存在**，报告“已删除”不符合现状，请改正记录，不必为追求记录而删除文件。
- T01 集中在端口中的速度常量可暂保留；T02 按已约定迁到参数 Resource。
- .gd.uid 应保留用于资源引用稳定性。

## 测试和报告修订
1. 原 60 项测试确实执行了真实物理，不是全部无效；但移动大多绕过输入适配器，瞄准每次补发鼠标事件，因此漏掉 R1/R2。
2. 无头鼠标可使用 root.push_input(event, true) 注入视口局部坐标。本轮已实测不需要经验自标定。请改用明确坐标空间，并用独立期望值断言，减少读取实现私有字段校准自身的依赖。
3. work/stretch_probe.gd 只是可丢弃目录中的证据，若作为长期验收依据，应移到 tests 下。其当前仅比较各尺寸速度相同，全部为零也会通过；增加非零且接近设计速度的绝对断言。使用正式控制链，避免直接调用生产 _physics_process 绕过调度。
4. 不必让 check.ps1 忽略全部 ERROR。当前代码会把捕获到的根证书 ERROR 同样判失败；“同一检查输出中仍有 ERROR 但全 PASS”的旧描述需要附具体原始日志解释，不能直接归因成无害。最新无报错复测可作为当前证据。
5. 最小 160×90 可读性、相机平滑舒适度和贴墙滑行偏好可列用户体验待确认，不单独阻塞技术修复；真人键鼠仍未验证，不能写“真人输入通过”。

## 交给 Harness 的下一条消息
```text
在 D:\vibe coding\OutpostRPG 继续。先读取 reports/T01_REVIEW_CODEX.md 和项目规则。
T01 结论是 CHANGES_REQUESTED，请修复 R1 静止光标瞄准、R2 输入物理步顺序，以及 R3 渐变资源绑定。
按报告已批准的语义补全 ActorCommandPort.get_velocity()，保留已批准的 get_facing()，补 CHANGE_REQUEST 记录。
补覆盖真实输入适配器的回归测试，使用明确的视口局部坐标注入；整理可重跑的窗口缩放测试并增加绝对速度断言，修正报告与磁盘实际不符的描述。
重跑 check.ps1 和 T01 全部相关测试，将结果写入 reports/T01_REVISION_1.md，未验证项如实列出。完成后把 T01 改为 READY_FOR_REVIEW，等待 Codex 复审，不进入 T02。
```
