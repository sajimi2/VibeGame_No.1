# 当前回归测试

测试只覆盖当前三维战场与有效工具；已移除旧二维人物绘制专项，相关移动/握点/遮挡验证改为检查真实烘焙角色。测试设置 `tactical/testing=true`，存档和手绘覆盖只写 `work/` 隔离目录。

```powershell
./scripts/check.ps1 -Suite smoke
./scripts/check.ps1 -Suite core
./scripts/check.ps1 -Suite all
./scripts/check.ps1 -Suite core -Rendered
./scripts/check.ps1 -Suite art -Rendered
```

每项单独启动引擎，导入及运行日志保存在 `work/checks`。入口同时检查退出码、脚本错误及失败断言；无头通过不代表画面或手感验收。渲染检查需要 Compatibility 实际 GPU，不带 `--headless`。

`display_mode` 在原生 `--wid` 父子窗口中改走内嵌分支：确认引擎限制下两种快捷键显示操作提示、保持窗口与暂停状态；独立启动才验证真实全屏。不要只用 `Window.is_embedded()` 代表编辑器原生嵌入，当前引擎须查询 `Engine.is_embedded_in_editor()`。

| 专项 | 当前责任 |
| --- | --- |
| `startup_smoke` | F5 装配、五敌人、正交相机、装备与安全出生点 |
| `painted_courtyard` / `painted_courtyard_motion` | 小院真实穿门、绕井/绕车、墙碰撞、纯装饰隔离与 V/F3/F4；GPU 矮墙/石头前后深度，窗口/全屏粗细两档滚屏；截图与指标 `work/painted_courtyard` |
| `courtyard_presentation` | 实际 GPU 树前零灰显、树后透视与灰显保留、花草不遮人；影子开关画面差分及井/车/墙独立影子；原灰模退出颜色显示且保留几何、内景地板承托保护，默认原始环境精度 |
| `painted_cottage` / `painted_cottage_motion` | 分层插画实际穿门/绕屋/碰撞阻弹、墙/顶渲染前后深度、V 保持物理、双屋隔离与承托保护；GPU 窗口/全屏及粗/细两档新旧滚屏，截图 `work/painted_cottage` |
| `display_mode` | 独立渲染进程实际切窗口/全屏、完整屏幕尺寸、暂停/最大化/场景重开及原窗口恢复；静止鼠标瞄准、屋顶圆心与画布不漂移。需直接运行 `--script res://tests/tactical/display_mode_test.gd`，不加 `--headless`；无头仅验证装配 |
| `waystation_blockout` | 驿站真实步行路线、南北木桥、仓库门洞、侧路与野地连通；局部透视及恢复、勘察快捷键与原连续坡碰撞；不启动任务/存档 |
| `environment_art` | 三个场景及构件预览共用磁盘材质、建筑合并网格、桥坡碰撞；屋檐外/下蹲/屋面上方/恢复/多建筑透视；渲染时实际比较圆内变化、圆外及阴影不变 |
| `environment_resolution` | F2 开关/连发/暂停；实际窗口与全屏下核对七角色身体和武器逐像素不变，环境形成 2×2 色块；对照图输出至 `work/environment_resolution`。无头仅检查输入，不代表画面验证 |
| `occlusion_presentation` | 局部灰色的实际像素覆盖/无遮挡零染色/中心射线漏检/F2/全屏；室内淡屋顶叠圆、室外只开圆、屋上/离开恢复，实际残影及移动网点稳定性；截图 `work/occlusion` |
| `wall_occlusion` | 普通遮挡合计 90% 触发、80% 退出缓冲；12 朝向站/跑/蹲/跳，无碰撞真实网格，透视不自反馈；实际 GPU 中心全透/递增至 22% 残影/半径扩大 50%、圆外/阴影不变、移动稳定、F2/全屏对齐、仓库屋外两圆叠加；截图 `work/occlusion` |
| `selective_wall` | 同材质前墙开圆时，圆内旁墙/近后墙逐像素不变；重叠前墙都淡化、旧遮挡独立恢复；真实仓库南北走道的非遮挡矮墙及压顶完整保留。GPU 截图 `work/occlusion/selective_*` |
| `near_wall_reveal` | 实际 GPU 斜墙/斜屋面跨人物深度的折角复现，中心小圆无残留、远后方墙体不受影响；仓库贴墙与墙角截图 `work/occlusion/near_*`，无头明确跳过 |
| `occlusion_support` | 石台/地板/双木桥的承托角色保护、薄墙帽一起透视；实际 GPU 比较透视开关前后承托结构逐像素不变、确实渲染且薄压顶无残留，截图 `work/occlusion/support_*` |
| `environment_motion` | 实际 GPU 镜头连续横纵/斜移，抵消位移后核对环境时间稳定性；覆盖墙瓦/野地、窗口/全屏及原始/粗环境，另单独检查仓库端柱小区域的共面跳变。指标与截图在 `work/environment_motion/regression`；无头明确跳过 |
| `waystation_combat` | 十名混合敌人实际出生、血量/时序/扣血；守卫与三种新体型实际穿门、上坡追击；离岗归队、营地恢复、隔离装备及禁用勘察跳转 |
| `creature_encounter` | 哥布林锁向矛刺/后撤、石头人预告砸地/重刀打断/跳跃与墙体避伤、史莱姆实际碰撞/遇墙停止；三种完整图集和死亡渐隐，渲染时保存起手与命中图 |
| `melee_aoe` | 实际攻击扫过前后/并排目标、随动作逐段扣血、刀刃/冲击共享上限与去重、轻刀/突刺单体、墙与楼层阻隔、空中不冲击、逐人盾挡及真实击退；渲染时保存群攻截图 |
| `baked_player` | 七角色完整 96² 动作覆盖；原类人固定骨长/跑跳膝盖、实际世界握点、源动画编辑、死亡、工作台模型与分层补色；渲染时验证墙挡 |
| `skeleton_pipeline` | 骷髅 Blender 骨骼复用、实体蒙皮表面、统一 96² 运行、剑盾握点、补色与遮挡 |
| `atlas_pipeline` | 八个当前来源、原尺寸导出/回导、错误稿保护、重复替换、资产/尺寸隔离、界面握点修改与独立进程重启；三种整身补色及实际源动作变化 |
| `pixel_weapon` / `weapon_choreography` | GPU 武器/刀光、封闭厚度、宝剑缩小、轻中重移动、交替出招、握点、前冲/撞墙、拖地尘/重击扬尘、射击精度、死亡与真实背向遮挡 |
| `arrow_attachment` / `guard_reaction` | 飞行/搭弓/插箭、盾挡警觉、移动转身跟随、消隐、刀光世界坐标与去重伤害 |
| `locomotion_art` / `rock_collision` | 实际 Shift 输入、蹲行、跳跃阶段、空中握点、剪影、鼠标后退跳膝盖；绕石物理压力与阻弹 |
| 战斗/任务/地图其余专项 | 敌人状态、攻击时序、库存/保存兼容、任务闭环、坡道、净空、遮挡及安全区 |

`art` 聚焦已确认的绘画路线及环境渲染，使用 `scripts/check.ps1 -Suite art -Rendered`；`core` 是玩法/角色基线，`all` 加上现有地图边缘与全部绘画专项。具体清单以 check.ps1 为准。退役的逐面贴图测试已移除，有效双屋测试使用 tests/fixtures，滚屏取帧共用 tests/helpers。绕石压力测试固定 60Hz 无头加速；headless 跳过画面检查不能算渲染通过。

Blender 独立验证：运行 `tools/blender/validate_characters.py`，读取七份 `.blend`，检查实际骨架、权重、动作及手部/矛/石拳/胶体顶点运动；结果写 `work/checks/blender_characters.json`。工具不写回源文件。

- `courtyard_shadow_style_test.gd`：真实 GPU 检查共享阴影浓度/柔边、人物与环境世界光向、房屋旧代理退出和 V 恢复、轻微风摆归零/不动碰撞、平移锚点同步，以及未配置新物件的默认影形。只证明指定渲染/状态行为，美术风格仍由试玩确认。
