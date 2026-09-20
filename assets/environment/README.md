# 环境资产

用户已确认的新生产路线见 [场景美术规范](../../docs/ENVIRONMENT_ART.md)。

- `painted/courtyard/`：完整单视角树、石墙、井车箱桶、花草、草地与土路；原图、提示词、布局、像素整理记录及共享阴影配置。
- `painted/cottage/`：完整房屋墙/顶/内景图与配准；`structure/` 是保存的 Blender/GLB 空间代理，负责门洞、碰撞、承托和遮挡。
- `textures/`、`materials/`、`prefabs/`：仍被荒堡、驿站和高度回归使用的原型材质/几何，不是新画稿生产目标；尚未逐个迁移。

入口 `scenes/painted_courtyard.tscn`。逐面生成图片贴到 3D 表面的仓库/小屋路线已退役，历史保留在 `ddb3b2c`；不要恢复为默认制作方式。角色资产不在本目录，独立遵循 Blender → 96² 烘焙管线。
