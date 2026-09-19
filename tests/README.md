# 当前回归测试

测试只覆盖当前三维战场与有效工具；已移除旧二维人物绘制专项，相关移动/握点/遮挡验证改为检查真实烘焙角色。测试设置 `tactical/testing=true`，存档和手绘覆盖只写 `work/` 隔离目录。

```powershell
./scripts/check.ps1 -Suite smoke
./scripts/check.ps1 -Suite core
./scripts/check.ps1 -Suite all
./scripts/check.ps1 -Suite core -Rendered
```

每项单独启动引擎，导入及运行日志保存在 `work/checks`。入口同时检查退出码、脚本错误及失败断言；无头通过不代表画面或手感验收。渲染检查需要 Compatibility 实际 GPU，不带 `--headless`。

| 专项 | 当前责任 |
| --- | --- |
| `startup_smoke` | F5 装配、五敌人、正交相机、装备与安全出生点 |
| `waystation_blockout` | 独立灰盒真实步行路线、南北坡、仓库门洞、侧路与野地连通；屋顶进出渐隐、高度隔离/门槛滞回/多建筑独立、勘察快捷键、坡道显示碰撞重合；不启动任务/存档 |
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

`all` 额外包括 height_lab、height_edge、art_route、outpost_sample、letter_interaction、feedback_edges、tower_feedback。绕石压力测试固定 60Hz 无头加速；其他渲染专项保持真实帧推进。测试规模由当前输出统计，不沿用历史通过数量。

Blender 独立验证：运行 `tools/blender/validate_characters.py`，读取七份 `.blend`，检查实际骨架、权重、动作及手部/矛/石拳/胶体顶点运动；结果写 `work/checks/blender_characters.json`。工具不写回源文件。
