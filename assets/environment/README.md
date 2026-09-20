# 环境资产库

- `textures/`：可直接编辑的 128×128 PNG。
- `materials/`：游戏与工具共用的像素材质。
- `prefabs/`：可调尺寸的建筑墙、石墙、塔、箱子、推车、木架桥，仅提供外观。
- `experiments/cottage/`：已验收的简单 Blender 小屋与生成图片原型，含保存源和投影配置。
- `experiments/painted_cottage/`：完整墙/顶插画分层与固定视角配准；原双屋实验保留。
- `experiments/painted_courtyard/`：直接生成的单视角树、石墙、井车箱桶与装饰，独立简单碰撞；当前待试玩，见 [小院说明](experiments/painted_courtyard/README.md)。
- `warehouse_slice/`：仓库样板的生成贴图、提示词、对齐配置与箱桶预制件；流程见 [样板说明](warehouse_slice/README.md)。

打开 `tools/environment_preview.tscn` 按 F6 查看。编辑、再生成、碰撞边界和屋顶透视说明见 [环境美术](../../docs/ENVIRONMENT_ART.md)。
