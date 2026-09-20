# 当前工程架构

描述实际源码和扩展边界；接手状态见 `../HANDOFF.md`，制作步骤分别见 `ENVIRONMENT_ART.md`、`ART_PIPELINE.md`。不另建函数索引或全局管理框架。

## 职责与入口

| 所有者 | 职责 / 扩展入口 | 不应承担 |
| --- | --- | --- |
| `world/level.gd` | 装配玩家、相机、战斗、UI、导航、遮挡；地图覆盖 `_build_environment / spawn_point / enemy_layout / navigation_bounds` | 生成画稿、图集播放细节、库存 I/O |
| `world/battlefield.gd`、`waystation_blockout.gd`、`height_sandbox.gd` | 当前玩法地图与高低回归，场景保留实际几何和碰撞 | 新美术路线选型 |
| `world/painted_courtyard.gd` | 已确认美术基准的场景装配、查看快捷键；尚无遭遇/任务/进度 | 未来完整游戏已实现的承诺 |
| `actors/player.gd` | 移动、姿态、瞄准、受伤；速度经统一 `move_and_slide` | 图片制作、奖励和保存 |
| `actors/enemy.gd` / `creature.gd` | 感知、最后目击、路径、出招状态；物种资源与遭遇调参 | UI、玩家进度 |
| `combat/` | 动作窗口、近战扫线、弓箭线段、命中与附着 | 用美术轮廓代替伤害判定 |
| `presentation/` | 颜色/深度播放、握点、绘画资产、阴影、遮挡、效果 | 玩法状态机或存档 |
| `art/`、`tools/` | 来源协议、图集工作台、离线烘焙与制作导出 | 游戏每帧重新生成角色 |
| `items/`、`contracts/` | 物品定义、实例、库存深拷贝、装备意图/快照 | 直接控制 HUD |
| `progression/camp_progress.gd` | 换装/成长/背包显示/持久化的协调 | 场景美术 |
| `persistence/tactical_save.gd` | v1 JSON 读写 | 任务/战斗逻辑 |
| `ui/` | HUD、背包、结果、窗口输入 | 修改库存内部数据或重算伤害 |

以上路径以 `scripts/` 为根。游戏未增加 Autoload；现有 Autoload 是 Godot AI 工具辅助。第三方插件不参与自有业务整理。

## 装配顺序与状态所有权

`level._ready`：terrain_builder → 环境/光照 → 地图 → 效果 → 玩家 → 相机 → 环境颜色通道/墙遮挡 → HUD → 战斗。相机固定 -35°/25°、正交、`17 / VIEW_ZOOM`，VIEW_ZOOM=1.2；只将渲染相机对齐像素，物理坐标保持连续。

墙遮挡注册延迟到地图网格生成后；绘画房屋和实物在其后绑定最终材质副本。顺序不能反过来，否则绘画读取原材质而看不到控制器发布的透视状态。小院 `encounter/mission/progress/results` 均关闭；F5 的 `start_encounter` 等待物理同步后建立导航、敌人、任务、成长和结算。

`enemy_layout` 可以携带 `creature / art_id / enemy_tuning`。物种决定实体和攻击，art_id 只换外观；调参在入树前应用。驿站 18m 离岗和回营归队是其遭遇配置，不应改成所有关卡全局默认。

## 已确认场景美术数据流

`assets/environment/painted` 是活跃制作目录：

```
灰模尺寸/简单碰撞 + 固定正交参考
  → 完整单视角画稿（source 原图 + prompts）
  → 离线像素整理（运行纹理 + baked / registration）
  → illustrated_prop / painted_cottage
  → 原世界深度、独立简单碰撞、已有遮挡控制器
```

- `painted_courtyard` 读取 catalog/layout，装配实物和纯装饰，不持有玩家/UI。`illustrated_prop` 输入图片、锚点、尺寸、深度范围与碰撞规格，分别创建画稿、隐藏盒/柱及几何代理。
- 物件画稿不是模型表面的重复纹理。alpha 决定可见轮廓，深度盒近似物体体积；树采用经过树干的竖直深度面，不能把整个树冠盒前沿当作树干，否则树前人物误灰。
- 花草走 `ground_decoration`，不写环境遮挡深度，先于人物显示，不参与墙圆或碰撞。蝴蝶/落叶由 `courtyard_ambience` 管理，不参加战斗。
- `cottage/structure` 保留 `.blend`/GLB 与空间装配，前墙左/右/门楣/山墙同组，其余墙独立分组，地板是 support。原 GLB 的碰撞与采样保留，可见的内外墙/地板退出颜色层。
- `painted_cottage` 将完整屋顶/墙身/内景画分配至七片承载面，`registration` 配准外观，`interior_registration` 配准内景。地板 `is_support=true`，不能被透视圆挖掉。这里的少量承载面不等于已经退役的“每个 3D 面单独生成贴图”。
- `occlusion_style` 集中保存墙/屋顶参数字段契约，绘画层只订阅控制器，不拥有另一套遮挡状态机。通用道具不依赖具体房屋脚本。

### 阴影与轻微晃动

`shadow_style.tres` 是新路线唯一方向/颜色/覆盖率/柔边/像素网格/晃动上限来源；`shadow_profiles.json` 只存体量（团块、高度、接触区、凸包点）。无专属配置的新资产从 depth_box 得到默认影形。

`illustration_shadow` 初始化地面承载面和参数，同件部分取最大覆盖而非叠黑。房屋接管旧实时代理时同时关闭投影及其颜色层；只将 SHADOWS_ONLY 改成 OFF 会露出旧瓦顶。V 对照恢复几何外观和旧投影，不改碰撞。人物仍用姿态实时投影，由同一样式校准太阳方向/强度。

固定朝向平移通过变换通知同步画稿深度原点和阴影脚点。`set_visual_sway(Vector2)` 接受世界 XZ 米制偏移：限幅 0.12m，画稿从脚点向顶部渐增偏移，上部影子跟随，接触区与碰撞不动。调用方管理时钟，默认不自动风摆，无逐帧建网格/图片。仍限固定视角、平地和小幅形变；不同物件相交为普通透明混合，夜间和斜坡接收面未实现。

## 遮挡与渲染隐藏约定

1. `body_occlusion_probe` 读取当前角色帧颜色 alpha/深度，合并上下身最前表面。`wall_occlusion` 每秒 10 次对淡化前的原始几何采样，累计覆盖 90% 开启、80% 退出；不能用已淡化深度触发自身，否则反复闪烁。
2. 命中集合收集全部遮挡构件，不能只留最近墙。以最近物理父节点分组，墙身/帽/窗框一起透，相邻墙即使同材质也独立。材质按组复制，不通过调整深度余量代替构件筛选。
3. `metadata/occlusion_role="support"` 由结构声明，注册沿祖先排除整组承托面；不是按厚度、材质猜地板。薄墙帽仍须参与，否则留下悬浮面。
4. 普通墙圆半径 3.375m，中心 27% 全透，向外到 22% 覆盖后恢复；近墙深度边界共用 0.85m 余量 + 1m 柔边，不能恢复硬深度平面切割。
5. `interior_roof` 以相机到脚/胸/头与屋面盒相交决定局部圆，屋檐外也有效。室内 AABB 另控制整顶保留 22%，与圆孔相乘；室外仅圆。各屋独立，约 0.28s 渐变。未来非盒形屋顶需更精确遮挡形状。
6. 少量遮挡由 `baked_human` 灰色变体逐像素比较环境深度，只绘被挡身体；正常身体随后覆盖可见部分。中心物理射线仅作调试，不能控制全身描边开关。
7. 显示层 `layers=0` 的几何代理仍保持 visible 供采样；禁止直接隐藏父节点让检测一起消失。新动态构件须显式注册子树，替换网格后要重新注册新节点。

渲染阶段：不透明/像素裁切环境 → 环境颜色合成（-128）→ 绘画地面影子（-120）→ 花草（-110）→ 灰色身体（-1）→ 原精度人物/武器（0）→ 箭矢（1）→ UI。身体/武器进入透明阶段仍必须 `depth_draw_always` 写图集表面深度，不能仅靠排序。

F2 是颜色后处理：2×2 整数 texelFetch 面积平均，世界网格锚定；原始环境深度未降采样，不是节省世界光栅化的方案。禁止恢复归一化最近邻块中心读取，纹素边界会跳闪。小院默认关闭；旧玩法地图维持原默认。窗口/全屏保持 1280×720 逻辑画布和等比例小数缩放。

## 角色、武器与战斗

保存的七份 `.blend` → GLB → `bake_characters` → 96²/十二朝向颜色、深度、握点清单 → `baked_human`。运行时不实例化角色骨架或烘焙视口。四类人上下身组合；哥布林/石头人/史莱姆整身 `parts=[full]`，不强迫提供人形握点。

`player_combat._unhandled_input → player.update_aim → attack → _physics_process 动作窗口 → strike → melee_query.sweep → space_trace.trace → enemy.receive_strike`。身体动作和武器共用动作相位，刀光用实际端点，伤害不取图像边缘。近战按角度扫线，实例 ID 去重；弓箭每帧检测飞行线段，先结算再绑定附着。

- `data/actions` 管动作曲线、分段速度、有效窗口与前冲；`data/weapons` 管参数和动作序列。玩家查询 combat_movement 后统一 move_and_slide，不直接改位置前冲。
- 宝剑横斩最多三人，重刀刀刃与落地 1.25m 冲击合计最多四人；冲击检查高度和隔墙。武器枚举保留 HEAVY=1 / MEDIUM=2，兼容既有资源。
- 装备通过来源键登记疾跑限制，轻武器仅改变主动移动倍率，不影响跳跃或攻击前冲。
- `PixelWeaponVisual` 从实际模型与世界握点，经小 SubViewport 输出颜色/深度；屏外/隐藏/同姿态停止刷新。箭和刀光各有像素表现；不是角色烘焙的一部分。
- `enemy` 依次 update_senses → choose_movement → move_and_slide → update_visuals；最后目击只在真实见到玩家时更新。`creature` 复用基础字段、导航、受击与死亡接口，特殊生命周期仍须检查继承耦合。
- `death_visual` 只管倒地/淡出；敌人 hp、碰撞关闭、击败统计仍由演员拥有。尸体隐藏后根节点保留给任务计数。

工作台 `data/art_sources → atlas_source → atlas_document → art_preview`；`atlas_store` 以资产 ID/帧键查询补色。导入验证格子尺寸，96² 不接受旧 32×48/64² 稿；补色不提供新轮廓的几何深度。武器保持读取 `last_grip / last_support`，不重绕二维握点转换。

## 库存、进度和输入

`camp_progress.setup(player,combat)` → 创建 ActorInventory → 恢复 v1 快照 → 库存信号触发装备应用/保存/视图刷新。库存拥有实例深拷贝，UI 只发换装意图、收显示数据。`tactical_save` 只读写 JSON；版本、`user://tactical_progress_v1.json` 和装备实例 ID 本轮不迁移。自动测试设置 tactical/testing 或独立 work 存档，禁止覆盖玩家真进度。

`run_screen` 持有明确注入的玩家/任务/成长依赖。空 hint_provider 会显示默认路线提示，正式战场传一个空格是隐藏约定。暂停由背包/结果/瞄准共同参与，新输入入口需检查暂停恢复。

`window_mode` 挂 Window，F11/Alt+Enter 恢复原窗口尺寸/位置，R 重开不丢失模式。玩家每帧读取 Viewport 鼠标位置，不能只依赖最后一次 MouseMotion；测试也不能仅设置旧的 cursor 字段后等待其不变。

## 仍有效的原型资产与已知限制

- `environment_library / architecture_piece / terrain_builder / battle_prop` 仍用于荒堡、驿站、坡桥、石头和旧地图回归，不能删。新可见内容默认走绘画资产，不再扩充逐面生图投影器；相关生产代码、专用资产及样板已退出活跃树。
- 不同碰撞掩码有不同职责：行走和寻路使用地形 + 移动代理 `1|32`；视线/弹道有独立遮挡层。巨石视觉/阻弹网格与移动凸包分开，不为美术统一而合并。
- 导航一个 XZ 网格只有一个行走面，桥上下并行路径未支持。木坡桥仍基于实心坡道。
- 生成节点仍有少量 `get_child(1)` 顺序依赖；角色字段也有直接读写。扩展时先查实际调用方，按需要修，不为“整洁”一次重写战斗总控。
- 保存尚非原子写入，异常数据保护有限；未来单独修改并测试，不把本轮整理称为已解决所有技术债。
- 美术已认可，玩法地图尚未完成新美术迁移。下一阶段由用户定范围，不自动扩世界、敌人数量或全局框架。

## 验证入口

`check.ps1 -Suite art -Rendered` 覆盖绘画小院/双屋/遮挡/阴影/移动/精度；`-Suite core` 覆盖角色、武器、战斗、任务、存档与原地图；完整列表以脚本为准。画面必须用真实 GPU，headless 的跳过不算通过。主观手感仍由用户试玩决定。
