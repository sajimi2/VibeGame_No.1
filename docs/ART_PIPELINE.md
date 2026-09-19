# 当前美术制作流程

2026-09-19 用户确认采用 **Blender 建模/绑定/动作 → GLB → Godot 离线烘焙 → 游戏像素图集**。现有玩家、守卫、弓箭手和骷髅均使用 96×96、十二朝向；角色屏幕大小沿用 `VIEW_ZOOM = 1.2`，不随图集分辨率改变世界身高。此前直接二维人物绘制与 Godot 程序建模种子已退出当前工程。

## 制作源与职责

| 位置 | 内容与使用方式 |
| --- | --- |
| `assets/characters/blender/` | 玩家、弓箭手、守卫、骷髅四份可编辑 `.blend` |
| `assets/characters/candidates/` | 尚未接入游戏的哥布林、史莱姆、石头人等静态候选；保留供后续选择 |
| `assets/characters/*_source.glb` | 从 Blender 导出的交换资产，Godot 在工具侧读取 |
| `assets/characters/*_rig.tscn` | 薄适配场景；装入 GLB 并提供姿态采样接口 |
| `assets/characters/*_baked/` | 游戏读取的颜色/深度图页及 `atlas.json`，由烘焙工具生成 |
| `data/art_sources/` | 工作台来源注册：四种角色和箭矢 |

当前类人共用 15 骨命名和同一套采样协议；动作已复制到各自 Blender 文件。修改某个角色不会自动覆盖其他角色，复用或同步动作时须明确目标范围。当前仍以单骨权重的刚性身体分段为主，尚未验收连续软皮肤或任意比例自动重定向。走兽、软体或特殊 Boss 需要适合自身形体的骨架，不能硬套类人。

`imported_humanoid_rig` 读取标准 Skeleton3D、Skin、材质并采集变形表面；`humanoid_rig` 只负责已保存动画的采样与上下身组合。两者仅用于工作台和离线烘焙。游戏的 `baked_human` 不实例化骨架或角色烘焙视口，直接返回世界手心供武器使用。

## 修改与发布角色

1. 在 Blender 编辑并保存对应 `.blend`；保留骨名、身体网格的 `art_part`（upper/lower）及 `bound_bone` 属性。Action Editor 可选动作，NLA 各动作默认静音；0～96 帧表示归一化一秒，游戏出手速度仍由战斗逻辑驱动。
2. 在工程根目录运行导出，参数可选 `player guard archer skeleton` 中一个或多个。不传参数导出全部已登记角色。脚本只读 `.blend`，不重新建模或写回源文件。
3. 导入 GLB，再用非无头引擎烘焙选定角色，最后导入生成图页；重开 F5/F6 验证。

```powershell
& 'D:\blender\blender4.2\blender.exe' --background --factory-startup --disable-autoexec --python-exit-code 1 --python tools/blender/export_characters.py -- player
& 'D:\vibe coding\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --editor --import
& 'D:\vibe coding\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path . --disable-vsync --script res://tools/bake_characters.gd -- player
& 'D:\vibe coding\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --editor --import
```

GLB 导入保持 96 Hz 并关闭有损动画优化，避免快速出手关键时刻偏移。先在 `work/character_bake` 出图并检查空帧/裁边，验证完成才发布。帧图页统一 1024²，颜色与深度成对，清单保存上下身枢轴和双手锚点。96² 是采样格，不代表人物高度占满 96 像素；每格世界采样范围仍为 2.56m。

当前玩家 19,332 帧/9 页对，守卫 9,324/5，弓箭手 7,956/4，骷髅 9,324/5。共 23 组颜色/深度图页，原始 RGBA8 像素约 184 MiB，不含驱动和清单开销；同类演员共用贴图。

## 查看、导出和补色

打开 `tools/art_preview.tscn` 按 F6。四种角色可查看十二朝向、现有动作、移动方向和上下身；“3D 源模型”显示实际 GLB，支持旋转、缩放。纯箭矢来源自动关闭该选项。

- 完整合成按每像素深度叠加上下身，可查看/导出。
- 补色回导选择“上身”或“下身”，导出原尺寸 PNG + JSON 到 `work/art_atlases`。编辑时不缩放图片、不改帧键；重复 binding 必须同步修改。
- 工作台载入编辑稿后可修正握点，再应用；颜色和握点进入 `data/art_overrides`，深度仍来自实体。
- 增加轮廓、改变形体或肢体长度须改 Blender 再烘焙，不能用只有颜色的新增像素猜深度。
- 旧 32×48 人物来源已移除；旧 64² 补色稿也不能套入 96²。历史人工文件不主动删除，需要从当前来源重新导出再补色；不同尺寸覆盖会被跳过，工作台明确拒绝不匹配尺寸。

## 武器、树与环境

身体不重复烘焙剑盾弓。当前武器源仍在 `weapon_art.gd`，握柄由身体世界手心定位，像素武器及刀光继续使用独立 GPU 后端，详见 [武器表现](WEAPON_PIXEL_EXPERIMENT.md)。宝剑实体缩小 20%，厚度、装饰、阴影和刀光端点一起调整；伤害与判定距离未改。

`tree_art.gd` 只负责已认可的像素树；石材由 `stone_palette` / `pixel_stone` 管理，碰撞仍独立。它们是有效环境美术，不属于已删除的二维人物遗留。

## 验证

`tools/blender/validate_characters.py` 独立重开四份制作源，检查骨骼、材质、归一化权重和实体手部运动，不保存源文件。Godot 的 `baked_player`、`skeleton_pipeline`、`atlas_pipeline` 检查当前图集/源模型/回导；`weapon_choreography`、`pixel_weapon`、`arrow_attachment` 检查战斗表现。运行方式见 [tests/README.md](../tests/README.md)，自动验证与主观试玩分开记录。
