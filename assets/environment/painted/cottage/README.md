# 分层绘画小屋

已确认美术路线的一种可进入建筑。美术入口 `scenes/painted_courtyard.tscn`；双屋实例隔离见 `tests/fixtures/painted_cottage_scene.tscn`，它仅作回归，不是另一套生产流程。

## 制作源与运行图

- `source/complete.png`：完整单视角小屋参考。
- `source/walls.png`、`source/roof.png`、`source/interior.png`：生成的分层原图，`.gdignore` 防止完整原稿导入运行。
- `walls.png`、`roof.png`、`interior.png`：320² 运行图；`tools/bake_painted_cottage.gd` 从原稿统一整理，不在运行时缩图。
- `prompts.json`、`interior_prompt.json`：实际提示词；`guide.png`、`interior_guide.png`：固定相机配准参考，不当作最终画面。
- `registration.json`：外墙和屋顶配准。设计画布坐标归一化后使用，不能假定模型输出尺寸等于请求尺寸。
- `interior_registration.json`：后墙、左墙、地板的顶点和 UV；地板设置 is_support，不参与透视。
- `structure/`：简单模型制作源与空间装配，不承载生成的逐面材质。

## 运行契约

先装配 structure，等待 wall_occlusion 注册完成，再创建 `painted_cottage.setup(structure)`。七片承载面显示完整绘画：外墙两片、屋顶两片、内景三片。虽然使用少量网格承载图片，瓦片/木纹/藤蔓的形体仍由整幅画稿负责，并未重新建精模。

墙与屋顶状态来自原控制器；不重建碰撞或第二套透视状态。原网格 layers=0 但仍 visible，供原始几何采样；不要隐藏整个结构父节点。房屋采用统一浅色柔边体量阴影，代理的阴影和颜色均退出，V 对比恢复空间代理。

固定视角/配准点仍是限制；画稿不严格服从简模，门洞/屋檐已人工配准。背面及室内仍用少量面近似，不保证任意相机或精确美术碰撞。新增建筑按实际房间、开口、承托和透视组另做配置，不能简单把一整张建筑卡片当完整深度。

验证：`painted_cottage`、`painted_cottage_motion` 和小院的表现/阴影专项，真实 GPU 与物理通行均要执行。截图写 work，不把源图当作实机证据。
