# 当前工程架构

描述实际源码和扩展边界；接手状态见 `../HANDOFF.md`，制作步骤分别见 `ENVIRONMENT_ART.md`、`ART_PIPELINE.md`。不另建函数索引或全局管理框架。

## 职责与入口

| 所有者 | 职责 / 扩展入口 | 不应承担 |
| --- | --- | --- |
| `world/level.gd` | 装配玩家、相机、战斗、UI、导航、遮挡；地图覆盖 `_build_environment / spawn_point / enemy_layout / navigation_bounds` | 生成画稿、图集播放细节、库存 I/O |
| `world/woodpath_region.gd` | 正式Map的物件集合绑定；保留旧实验布局生成及道路折线 | 任务/库存/存档 |
| `tests/fixtures/legacy/` | 旧荒堡/驿站/高度场的物理回归夹具，不是活跃地图 | 新玩法入口 |
| `world/painted_courtyard.gd` | 绘画小院装配及观察快捷键；combat_mode 决定是否启用玩法 | 未来完整游戏已实现的承诺 |
| `world/terrace_layout.gd` → `terrace_ground.gd` | 粗格高度/坡向/外露边 → 平台与侧壁网格、同源碰撞；由小院注入种子 | 玩家移动、战斗、导航或进度状态 |
| `world/rolling_meadow.gd` | 保留旧连续缓坡对照，`outskirts_mode=1` 才装配 | 默认地图生成 |
| `actors/player.gd` | 移动、姿态、瞄准、受伤；速度经统一 `move_and_slide` | 图片制作、奖励和保存 |
| `actors/enemy.gd` / `creature.gd` | 感知、最后目击、路径、出招状态；物种资源与遭遇调参 | UI、玩家进度 |
| `combat/` | 动作窗口、近战扫线、弓箭线段、命中与附着 | 用美术轮廓代替伤害判定 |
| `presentation/` | 颜色/深度播放、握点、绘画资产、阴影、遮挡、效果 | 玩法状态机或存档 |
| `art/`、`tools/` | 来源协议、图集工作台、离线烘焙与制作导出 | 游戏每帧重新生成角色 |
| `items/`、`contracts/` | 物品定义、实例、库存深拷贝、装备意图/快照 | 直接控制 HUD |
| `progression/camp_progress.gd` | 换装/成长/背包显示/持久化的协调 | 场景美术 |
| `persistence/tactical_save.gd` | v1/v2 JSON、升级备份、临时写入后替换 | 任务/战斗逻辑 |
| `ui/` | HUD、背包、结果、窗口输入 | 修改库存内部数据或重算伤害 |

以上路径以 `scripts/` 为根。游戏未增加 Autoload；现有 Autoload 是 Godot AI 工具辅助。第三方插件不参与自有业务整理。

## 正式地图的人工编辑入口（2026-09-24）

`scenes/courtyard_combat.tscn/Map` 保存固定地图，`scenes/props/` 保存18种可复用物件场景。树、石墙、地板、屋内空间代理、画稿和箱子碰撞在运行前已存在；`courtyard_combat._build_environment` 只绑定这些节点，不从旧layout重建。收藏集合的 `authored_layout` 只做节点发现。无Map的历史实验保持旧生成入口；明确关闭story_mode的回归会移除正式Map后装配实验布局。

`illustrated_prop` / `animated_container` 的 `@tool` 只绑定已保存节点、独立材质并同步脚点，不是整个地图的编辑器生成器。物件平移时画稿深度原点、顶层阴影同步；碰撞是同根子节点。小屋保存原Roof、七片画稿和物理体，墙注册之后 `painted_cottage.setup` 绑定现有画稿，不覆盖网格/变换。NPC的EditorPose只供摆放，运行时隐藏并继续现有离线图集播放。

任务由 `courtyard_combat.create_objective` 注入Map。`woodpath_story.bind_progress` 收集 `metadata/interaction_id`，把节点与既有容器ID/剧情事实绑定；`_refresh_spots` 从global_position派生标签/距离/声音坐标。药车、路标和纪念石堆的调查Marker是其子节点。原SPOTS只服务未迁移实验；不作为正式地图位置来源。ID关联既有存档，不能复制同ID当作新库存；本轮未改存档结构。

详见 `EDITING_MAP.md`。地表道路折线、敌人布局、相机跟随和UI仍由原模块负责。地图节点的保存不等于任意转动单视角插画；固定视角约束不变。新场景直接引用的像素/深度纹理关闭detect_3d自动压缩，保留无损无mipmap规格，防止编辑器首次看到3D引用就重新有损导入。

## 装配顺序与状态所有权

`level._ready`：terrain_builder → 环境/光照 → 地图 → 效果 → 玩家 → 相机 → 环境颜色通道/墙遮挡 → HUD → 战斗。相机固定 -35°/25°、正交、`17 / VIEW_ZOOM`，VIEW_ZOOM=1.2；只将渲染相机对齐像素，物理坐标保持连续。

小院覆盖跟随焦点为玩家脚点上方半个站立身高；M 仍切全院焦点。滚轮在 `_unhandled_input` 设置目标视野，物理帧在跟随/遮挡采样前以指数阻尼更新 `camera.size`；上下限为默认视野的 0.5/2 倍。默认大小和人物源保持原基准，UI 不参与世界缩放；暂停不接收缩放。调参入口集中在 `world/painted_courtyard.gd`。

墙遮挡注册延迟到地图网格生成后；绘画房屋和实物在其后绑定最终材质副本。顺序不能反过来，否则绘画读取原材质而看不到控制器发布的透视状态。纯美术小院 `encounter/mission/progress/results` 均关闭；`courtyard_combat.gd` 子类启用玩法并提供三敌布局/任务坐标，F5 的 `start_encounter` 等待物理同步后建立导航、敌人、任务、成长和结算。

`enemy_layout` 可以携带 `creature / art_id / enemy_tuning`。物种决定实体和攻击，art_id 只换外观；调参在入树前应用。驿站 18m 离岗和回营归队是其遭遇配置，不应改成所有关卡全局默认。

旧粗格对照模式在 X=8 接上 `terrace_ground`，覆盖 X[8,48] / Z[-20,28]。原东侧平板截断，坑底不会被旧地板托住。`terrace_layout` 每个 4m 格记录整数高度（0.5m 一档）、坡道升高和朝向；每个 XZ 只有一个表面，半高平块仍是平面，坡道才线性升降。`exposed_edges` 比较相邻边端点，删除同高内部面，只保留正高差；凹坑与凸台共用这套规则，不另做坑特判。二级坡道入口必须留同高转接平台，不能从坡道侧壁进。

`terrace_ground` 只在装配时生成两份显示网格和一份同源三角碰撞，整体标记 support，不给地板开透视洞。顶面 COLOR 存四边草沿标志，侧壁 UV2.x 存距崖顶米数；材质拼接与物理边界同源。模块以世界原点装配，常量/着色器的 4m 格与原点参数必须同步修改。玩家、战斗、导航保持原调用链，寻路按真实碰撞采样，范围 X[-10,42] / Z[-12,24]。首版不支持洞穴/桥下多层或运行时挖地。

`terrace_seed=0` 为验收布局；非零种子只改变南侧平台长度、列和可选主台扩展，坡道与出入口验证后装配；主路和凹坑出口固定。`roads()` 与装饰避让共享路径数据。`extend_terraces` 只在平坦格内部放画稿，避开坡道/崖沿/道路。统一太阳应用后再注入崖壁材质，V/F3 只改表现。旧 `outskirts_mode=1` 的连续缓坡保留以下兼容入口，用户已否定其当前观感，不自动恢复为默认。

`presentation/painted_courtyard.extend_meadow` 在地表就绪后复用目录画稿并采样落点。新增物件的 `illustration_shadow.fit_ground` 接收高度 Callable，装配/移动时生成贴坡网格；不增加逐帧重建。花草深度使用脚点切平面，人物已有接触影与实时投影继续走原系统。F3 只改网格显示参数，不改变地形/碰撞。

缓坡可读性在 `courtyard_ground.gdshader` 控制：只在 X=8～14 平滑进入扩展区效果，降低草纹反差并增强真实法线沿公共太阳方向的大片明暗。光向由小院 `_finish` 在 `shadow_style.apply_sun` 后注入，不另设太阳；院内仍用原四档着色。`rolling_meadow.climb_path` 输出上丘曲线的 17 点，同时供地表土路与花草避让读取，不参与高度生成。`relief_strength=0` 是同机位材质对照入口，正常默认为 1。

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

渲染阶段：不透明/像素裁切环境 → 环境颜色合成（-128）→ 绘画地面影子（-120）→ 花草（-110）→ 灰色身体（-1）→ 人物/武器（0）→ 箭矢（1）→ 地点名称/UI。身体/武器进入透明阶段仍必须 `depth_draw_always` 写图集表面深度，不能仅靠排序。

2026-09-23用户实测否定整屏640×360采样（画面/小字受损）。当前故事不装配WorldPixelGrid，标准显示1280×720；像素密度由素材28px/m约束，F2仅提示规格，旧测试场保持旧通道。交互名称由woodpath_story投影到CanvasLayer 1，固定17px字号，在镜头更新后更新位置；其可见距离和藏物知识条件保留。源深度/物理/瞄准不变。制作与验收见 `PIXEL_ART_STANDARD.md`。

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

`camp_progress.setup(player,combat)` → ActorInventory 恢复 v1/v2 → ExpeditionState 恢复容器/事实 → 接通信号与视图 → 应用装备并保存。继续使用 `user://tactical_progress_v1.json` 路径但内部 version=2；首次升级保留 `.v1.bak`，日常替换保留 `.bak`。测试设置 tactical/testing 或独立 work 路径，不改玩家真实进度。

- `items/inventory_grid` 是无状态矩形排布校验；ActorInventory 的48个数组位只在左上角存实例，其余占格由尺寸推导。物品实例增加 quantity/rotated，快照锚点带 x/y；所有查询快照都是副本。装备包含 weapon/head/body/hands/feet/cloak/accessory。换装需能收回旧装备，失败完整回滚。未知定义或迁移溢出进入 recovery，不删除。
- `progression/expedition_state` 拥有3个野外容器、营地仓库、钱币、日志和篇章事实；补给购买先确认空间再扣款。所有容器复用库存规则；跨容器转移先试放副本，再同时提交两端，只通知一次保存。空容器有快照即不重新生成。试用武器补发检查所有容器和恢复仓储，不能把武器存箱后重启刷取。
- `world/woodpath_story` 只负责空间交互与对话选项：距离/视线检查后交给进度模块开容器，选项执行时再次验条件；不得让界面直接修改事实或奖励。`level.create_objective()` 为薄装配入口，旧地图仍返回原任务，小院 story_mode=true 返回新篇章。
- `camp_progress` 协调库存、装备效果、显示和保存。护甲在玩家受击时扣减（有效命中至少1），生命上限从装备重新汇总。武器槽为空时隐藏手持武器并禁用攻击/格挡，不凭空补刀。交付原件、记录结果、首通奖励一起保存；满包奖励进入恢复仓储。身体装备暂不改变人物烘焙外观。
- `ui/inventory_panel` 发布 move/equip/unequip/use/read/split/transfer/recover 意图，`inventory_grid_view` 只绘制与命中测试。拖动期间不先移走物品；无效投放保留原状态，Esc先取消再关闭，R只旋转。容器输入由已校验的世界交互打开，暂停保证交互期间角色不离开范围。
- F5故事以平地模式2停用粗格/缓坡实验；原代码和专项保留，测试显式 story_mode=false。新篇章不是完整开放世界；对话为固定分支，未连接在线AI。死亡重置敌人，已保存库存/容器/故事保留；R不重置已选结局。
- 图标原稿与区域表在 `assets/ui/items/`，运行时只用 AtlasTexture；BGM来源及音量在 `assets/audio/README.md`。音乐只在小院故事中播放，背包暂停不停曲。

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

## 小院战斗输入与动画增量

- F5 `courtyard_combat` 继承绘画小院，仅选择玩法开关、出生/敌人/任务布局；复用 `level.start_encounter`，不复制美术装配或库存。纯美术场景继续禁用玩法，数字键只在该模式定位。
- `player_combat` 解释左键当前装备攻击、右键格挡；可装备弓由 `weapon_data.ranged` 声明。格挡状态投影到玩家用于朝向减伤，玩家通过注入的 `can_roll` 查询攻击是否允许翻滚。翻滚时间/冷却/方向及碰撞、免伤均由玩家拥有；战斗在翻滚期间拒绝攻击并隐藏武器。
- 断剑 `charge_hits` 属于战斗实例，不写共享 Resource 或存档。`receive_strike` 确认敌人掉血且未盾挡后每挥击最多增加一次；三次后下一次攻击消耗。真实扫线与武器曲线都允许反向横扫。
- `roll` 强制上下身同帧；`weapon_guard` 可叠加原步态，剑术站姿屈膝/错步，移动中仍沿原下身混合。新增动作从保存的 Blender 源导出并离线烘焙。
- 五格栏和背包是 `inventory_panel` 的两个视图，数字键和点击统一回到 `camp_progress.equip`，不维护额外装备状态。攻击、死亡、翻滚和非背包暂停期间拒绝换装。空间背包为v2，兼容迁移v1（见上文）。

## 林路篇章扩展（2026-09-23）

F5 `courtyard_combat` 在平地模式2装配 `woodpath_region`。后者输出三条道路折线、交互点和资产代理；同一折线既供地表 shader 绘土路，也供树群避让。普通绘画小院不注入林路。导航范围为 X[-10,77] / Z[-27,27]，战斗只保留三名敌人，离岗范围14m。路线自动检查会禁用敌人AI以检查可达性；战斗行为由独立小院专项覆盖，不能据此宣称整条路线已完成手感验收。

`woodpath_story` 读取 Region.SPOTS → 距离/视线检查 → 宝箱先播放0.24秒开盖再打开容器，期间 busy 防重复，等待后再次检查距离。背包关闭信号触发反播；箱体总保持原位。NPC只是独立颜色/深度图集的轻呼吸播放，没有完整战斗/走路资产。

状态仍在 `expedition_state`；新增 supply 容器只在旧快照缺该键时播种三包药材，不重置其他容器。物品定义新增可选 icon_texture，旧icon_index图集继续有效；存档仍只记录稳定定义ID，无版本变化。sell_carried 白名单消费随身物品并一次发送 changed；成长协调层保存同一快照。可回营存放物品，再回来取原箱剩余物，不新增重量/撤离损失规则。

`encounter_effects` 从 sound_library 加载短采样，统一SFX总线/事件限频/并发数/距离音量。人物发出动作事件，交互桥发出容器和翻阅事件；不由声音推动伤害或状态。库存与对话复用 pixel_style，装备示意图纯显示，不拦截鼠标。
