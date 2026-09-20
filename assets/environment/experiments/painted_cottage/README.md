# 固定视角分层插画小屋实验

双屋入口 `tools/painted_cottage_lab.tscn`（F6）。根目录 `play_painted_cottage.bat` 现已进入扩展小院，快捷键见小院 README。双屋中 V 对比完整插画与上一版表面贴图；1 门前、2 室内、3 屋后、4 第二栋；F2 粗/细环境，F11 全屏。无敌人/任务/玩家进度。正式地图和仓库样板不替换。

## 这次实际改变

先让内置 imagegen 按固定相机草图画整栋小屋，再生成同画布的屋顶和墙身透明分层。两张插画已画好瓦片厚度、屋檐雕花、窗框、灯笼、石脚和植物，不逐个制作这些细节的网格。颜色不受引擎光照二次染色。

运行时有七个独立绘画网格：前墙、右墙、两片屋顶，加上内景后墙、左墙与地板；它们是带 alpha 的简单承载平面，依照相应结构面放在真实空间，因此直接具有平面深度。这不是屏幕 UI 覆盖，也不是每个细节都有准确三维深度的重建；枝叶、灯笼和浮雕深度近似到所在平面。画出的不规则边沿可超出简模，主要碰撞轮廓仍按原房屋。

原 `cottage/source/cottage.blend` / `cottage_shell.glb` 继续负责墙、门洞、地板、阻弹与空间。墙遮挡采样、屋顶室内判断和透视参数也仍来自原系统。所有原墙面、墙厚端面及地板通过 `layers=0` 退出颜色显示，但保持 visible 供几何检测，独立阴影代理继续存在；V 恢复原渲染层。插画接收各自控制器参数执行圆孔裁切，绘画地板显式声明 `is_support`，不被墙圆擦除。

## 制作源与复现

- `source/complete.png`：实际 1254² 完整提案原稿，来自内置 imagegen，非运行截图。请求的画布是 1280²，实际输出尺寸经文件读取确认。
- `source/walls.png`、`source/roof.png`：内置 imagegen 同画布拆层结果，真实透明背景与门洞。
- `prompts.json`：三次生成/编辑的完整提示词。没有调用外部图像 API。
- `source/interior.png` / `interior_prompt.json`：内置 imagegen 新生成的完整后墙、左墙、地板画稿和完整提示词；`interior_guide.png` 是空间草图，`interior_registration.json` 保存人工确认的归一化画稿坐标。运行图 `interior.png` 为 320²。重新输出草图只写 `interior_guide_registration.json`，不覆盖手工配准。
- `guide.png`：按正式相机方向、原 GLB 输出的定位草图；`tools/cottage_paint_guide.gd` 可重建草图，不写 Blender 源。
- `registration.json`：门洞、墙脚、墙角、屋脊、屋檐的对应点。配准使用 1280² 的设计坐标，除以 `coordinate_canvas` 后转换为归一化 UV，与原图实际大小解耦；`source_canvas` 单独校验文件尺寸。源图未严格遵守草图比例，当前已人工配准，不能声称任意生图自动贴合。
- `walls.png`、`roof.png`：离线缩为 320² 的运行时图片，最近邻、无 mipmap、无有损压缩。两张 RGBA8 原始像素数据合计约 0.78 MiB，不含引擎资源/导入开销。原稿目录 `.gdignore` 避免打入运行资源。

改画之后运行 Godot `--headless --path . --script res://tools/bake_painted_cottage.gd` 再导入。缩图不修改原稿；若位置/比例改变，需更新配准点并重新验证门洞/遮挡。缩图的目标是稳定的游戏显示密度，不是把每张源图硬当作同一世界尺寸。当前配准只支持这座小屋与固定方向的等比例实例；不要旋转/非均匀拉伸预制件来当另一朝向资产。

## 依赖与顺序

`level` 创建原小屋、玩家、相机 → 延迟 `wall_occlusion.register_branch` 生成墙材质副本 → 实验 `_install` 装配 `painted_cottage` 并绑定副本 → 每个物理帧在屋顶/墙控制器之后同步透视参数。V 不重建几何/碰撞/遮挡组。`painted_hide_exterior` 默认关闭，只设置已注册的显示副本，不能设置阴影代理的源材质。

## 验证及边界

`painted_cottage_test.gd` 实际检查穿门、绕屋、碰撞/阻弹、V 不变碰撞、两栋独立透视、地板保护，并用前后标记检查墙/屋顶的真实渲染深度。`painted_cottage_motion_test.gd` 检查窗口/全屏、原始/粗环境、新/旧外观的横纵斜向滚屏。截图与指标在 `work/painted_cottage/`，测试不能替代用户对美术和手感的验收。

内景墙与地板现已补成完整绘画，原室内箱子的表现仍沿用原道具；整体建筑太阳投影仍是简模轮廓，不逐灯笼/藤蔓投影。图片自带固定明暗，B 明暗对比不会重新照亮插画，也未支持昼夜、可旋转镜头、可破坏装饰或门扇动画。这是低成本路线试验，尚未确认为全项目生产标准。
