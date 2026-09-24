# 当前美术制作流程

2026-09-19 用户确认采用 **Blender 建模/绑定/动作 → GLB → Godot 离线烘焙 → 游戏像素图集**。现有玩家、守卫、弓箭手和骷髅均使用 96×96、十二朝向；角色屏幕大小沿用 `VIEW_ZOOM = 1.2`，不随图集分辨率改变世界身高。此前直接二维人物绘制与 Godot 程序建模种子已退出当前工程。

2026-09-23统一规格见 `PIXEL_ART_STANDARD.md`：标准画面1280×720，人物/武器/环境不再被整屏二次降采样，文字保持清晰。**不改变角色96²烘焙规格或源资产**，不重新烘焙或改变物理/显示比例。旧“只降环境、人物原精度后画”的F2方案不再用于当前故事入口。

## 制作源与职责

| 位置 | 内容与使用方式 |
| --- | --- |
| `assets/characters/blender/` | 玩家、弓箭手、守卫、骷髅、哥布林、石头人、史莱姆七份可编辑 `.blend` |
| `assets/characters/candidates/` | 已确认的静态设计初稿；作为形体参考保留，日常动作精修使用正式 `.blend` |
| `assets/characters/*_source.glb` | 从 Blender 导出的交换资产，Godot 在工具侧读取 |
| `assets/characters/*_rig.tscn` | 薄适配场景；装入 GLB 并提供姿态采样接口 |
| `assets/characters/*_baked/` | 游戏读取的颜色/深度图页及 `atlas.json`，由烘焙工具生成 |
| `data/art_sources/` | 工作台来源注册：七种角色和箭矢 |

当前类人共用 15 骨命名和同一套采样协议；动作已复制到各自 Blender 文件。修改某个角色不会自动覆盖其他角色，复用或同步动作时须明确目标范围。当前仍以单骨权重的刚性身体分段为主，尚未验收连续软皮肤或任意比例自动重定向。走兽、软体或特殊 Boss 需要适合自身形体的骨架，不能硬套类人。

哥布林使用 15 根类人关节加 `Spear` 骨；石头人以 15 个关节驱动刚性石块；史莱姆使用 Root/Gel/Crown 三骨与混合权重，保存压缩回弹的缩放轨道。三者各有 idle/walk/attack/hurt/death_fall，整身 `art_part=full`，每种 1,188 帧。哥布林的固定短矛一起烘焙，换武器需要另做动作或后续拆分；本轮不把它做成玩家装备。

`imported_humanoid_rig` 读取标准 Skeleton3D、Skin、材质并采集变形表面；`humanoid_rig` 只负责已保存动画的采样与上下身组合。两者仅用于工作台和离线烘焙。游戏的 `baked_human` 不实例化骨架或角色烘焙视口，直接返回世界手心供武器使用。

## 修改与发布角色

1. 在 Blender 编辑并保存对应 `.blend`；保留骨名、身体网格的 `art_part`（类人 upper/lower，新物种 full）及已有绑定属性。Action Editor 可选动作，NLA 各动作默认静音；0～96 帧表示归一化一秒，游戏出手速度仍由战斗逻辑驱动。
2. 在工程根目录运行导出，参数可选 `player guard archer skeleton goblin golem slime` 中一个或多个。不传参数导出全部已登记角色。脚本只读 `.blend`，不重新建模或写回源文件。
3. 导入 GLB，再用非无头引擎烘焙选定角色，最后导入生成图页；重开 F5/F6 验证。

```powershell
& 'D:\blender\blender4.2\blender.exe' --background --factory-startup --disable-autoexec --python-exit-code 1 --python tools/blender/export_characters.py -- player
& 'D:\vibe coding\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --editor --import
& 'D:\vibe coding\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path . --disable-vsync --script res://tools/bake_characters.gd -- player
& 'D:\vibe coding\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --editor --import
```

GLB 导入保持 96 Hz 并关闭有损动画优化，避免快速出手关键时刻偏移。先在 `work/character_bake` 出图并检查空帧/裁边，验证完成才发布。帧图页统一 1024²，颜色与深度成对，清单保存上下身枢轴和双手锚点。96² 是采样格，不代表人物高度占满 96 像素；每格世界采样范围仍为 2.56m。

当前玩家 23,388 帧/10 页对，守卫 9,324/5，弓箭手 7,956/4，骷髅 9,324/5。共 24 组颜色/深度图页，原始 RGBA8 像素约 192 MiB，不含驱动和清单开销；同类演员共用贴图。

三种新物种分别增加哥布林 2、石头人 5、史莱姆 2 页对；七种合计 33 页对，全部同时载入时原始 RGBA8 约 264 MiB。实际场景只加载使用的种类；角色运行时没有逐帧图像回读或烘焙视口。

## 查看、导出和补色

打开 `tools/art_preview.tscn` 按 F6。七种角色均可查看十二朝向和现有动作；四种类人另有移动方向和上下身组合。“3D 源模型”显示实际 GLB，支持旋转、缩放。纯箭矢来源自动关闭该选项。

- 完整合成按每像素深度叠加上下身，可查看/导出。
- 补色回导选择“上身”或“下身”，导出原尺寸 PNG + JSON 到 `work/art_atlases`。编辑时不缩放图片、不改帧键；重复 binding 必须同步修改。
- 三种新物种只有整身层，直接导出/补色回导；不提供无意义的握点或上/下身设置。
- 工作台载入编辑稿后可修正握点，再应用；颜色和握点进入 `data/art_overrides`，深度仍来自实体。
- 增加轮廓、改变形体或肢体长度须改 Blender 再烘焙，不能用只有颜色的新增像素猜深度。
- 旧 32×48 人物来源已移除；旧 64² 补色稿也不能套入 96²。历史人工文件不主动删除，需要从当前来源重新导出再补色；不同尺寸覆盖会被跳过，工作台明确拒绝不匹配尺寸。

## 武器、树与环境

四种类人身体不重复烘焙剑盾弓。当前可装备武器源仍在 `weapon_art.gd`，握柄由身体世界手心定位，像素武器及刀光继续使用独立 GPU 后端，详见 [武器表现](WEAPON_PIXEL_EXPERIMENT.md)。宝剑实体缩小 20%，厚度、装饰、阴影和刀光端点一起调整；伤害与判定距离未改。

新场景美术已确认使用完整单视角绘画资产与简单隐藏空间代理，见 [场景美术管线](ENVIRONMENT_ART.md)。这不取代人物的 Blender 制作与深度烘焙，也不将可装备武器改成纯静态图。

`tree_art`、`stone_palette`、`pixel_stone`、旧建筑材质仍由荒堡/驿站/高度场使用，保留用于实际玩法回归。新增环境默认使用 `assets/environment/painted/`，不沿旧逐面贴图方案继续生产。

## 验证

`tools/blender/validate_characters.py` 独立重开七份制作源，检查骨骼、材质、归一化权重和实体手部/矛/石拳/胶体运动，不保存源文件。Godot 的 `baked_player`、`skeleton_pipeline`、`atlas_pipeline` 检查图集/源模型/回导；`creature_encounter` 检查三种新攻击；`weapon_choreography`、`pixel_weapon`、`arrow_attachment` 检查原有战斗表现。运行方式见 [tests/README.md](../tests/README.md)，自动验证与主观试玩分开记录。

## 玩家剑术、格挡与翻滚（2026-09-20）

用户两张参考保存于 `assets/characters/references/`（横劈、举剑过顶下劈）。本轮定向修改保存的玩家源 `sword_ready/sword_slash`，新增 `sword_overhead/weapon_guard/roll`，不修改其他角色。`sword_thrust` 为历史来源兼容保留，宝剑和断剑正式序列不再使用。双手与剑柄方向、错步屈膝、转体及挥剑曲线一起调整；运行时仍用十二朝向颜色/深度/握点，未增加实时人物骨架。

`tools/blender/edit_player_combat.py` 是本次明确的动作编辑工具，会写回玩家源，不能混入日常导出流程。修改前源/GLB 备份位于 `work/pre_courtyard_combat/`。日常仍只运行 `export_characters.py -- player`。翻滚的上下身始终取同一动作帧，不叠加走路腿；碰撞位移在玩家脚本完成，不从动画根运动读取。

## 简化常驻NPC（2026-09-23）

管事 steward / 药师 healer 各有保存的 `assets/characters/blender/*_rig.blend`、GLB、rig.tscn 和 baked 目录。首次制作从既有人体骨架复制基础结构，加帽子/胡须/账本或头巾/围裙/草药袋，保存为独立源；没有覆盖玩家源。只制作 town_idle 呼吸，12方向×12相位×上下身，共288帧/人，每人一页颜色和一页深度。角色屏幕大小仍96×96 / VIEW_ZOOM=1.2。

`blender --background --python tools/blender/make_villagers.py`：若NPC源已存在，仅打开保存源并导出，保留人工编辑，不重复生成。随后实际GPU执行 `godot --path . --script res://tools/bake_characters.gd -- steward`（healer同理）。日常不执行玩家动作编辑脚本，也不为常驻NPC烘焙完整战斗步态组合。

`story_villager` 用12帧轻呼吸播放独立图集。当前无行走、动态转身和装备换装；未来只有NPC需要移动时再补动作。旧荒堡/驿站材质改由 tests/fixtures/legacy 使用，不是活跃玩法入口。
