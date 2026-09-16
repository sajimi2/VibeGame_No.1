# 高度试验场 02：攻击、弹道与镜头

基线：height-lab-01 / 99eaa6c（用户要求先提交的地形试玩通过节点）。分支 tactical-height-prototype。

## 实现
- height_lab.gd：960×540、固定35°俯角/25°水平偏转、V键正交与弱透视对比、训练靶、布帘后石墙、反馈UI、R重置全场。
- directional_art.gd：十二个有区别的方向、四帧简化步态；height_actor.gd：镜头相对移动、依鼠标命中世界位置瞄准并缓存输入事件坐标。移动仍用胶囊，沿用坡缘修复。
- lab_combat.gd：左键挥刀、右键弓箭；近战有效期间按挥过的角度逐段检测，攻击内按目标去重；移动不冻结，攻击方向不随鼠标中途改变。武器为几何样品，未接正式人物攻击动画。
- space_arrow.gd / space_trace.gd：有重力的实际轨迹，低抛角初速瞄准；每物理步拆为至多1/120秒的线段检查，接触先后决定碰撞。石墙挡箭，布可穿透，一支箭对同一布只伤一次；三次后粗粒度整片落下并解除遮視。不模拟逐箭孔。箭头在接触处停止，箭杆留在后方。
- training_target.gd：圆柱训练靶、金色顶面、身体/顶部命中分类，闪色和命中次数。无额外高处伤害倍率，无敌人AI。
- export_height.ps1：导入和导出除退出码还扫描脚本错误，避免引擎退出0掩盖脚本失败。

## 验证
真实渲染窗口 tests/space_combat_test.gd 27项零失败：高速箭石墙、穿布再撞墙、每支箭仅伤布一次、布破坏前后视线、平射身体/下射顶部、高低掩体、近战隔墙/不同高度/一次命中/移动中攻击、实际高台俯射、实际鼠标左右键输入与V键切换。work/space-combat-test.log。
空间 tests/height_lab_test.gd 20项通过，含十二不同朝向、输入、上下坡、下蹲低梁；work/combat-space.log。
坡缘 tests/height_edge_test.gd 56条轨迹通过；最大单步0.12222m自然下落，work/combat-edge-test.log。
已查看真实截图 work/combat_orthographic.png、combat_perspective.png、combat_top_hit.png。首次鼠标注入验证发现旧光标坐标未更新，已改为输入事件坐标与点击即时采样，最终左右键测试通过。
导出由 scripts/export_height.ps1 执行；最终独立EXE启动扫描日志无脚本错误，见work/combat-export-startup.log。不改变旧项目主入口和存档。

## 未完成/体验边界
用户尚未试玩。本版仅提供训练靶、命中反馈和几何武器；无AI、体力/伤害数值平衡、装备成长接入或新音效。鼠标所见表面决定瞄准点，遮挡物后无法直接点选靶子。弱透视与像素缩放的主观效果待选择；正式美术仍按用户反馈逐步制作，配色和人物比例未固定。下一轮为感知追击。
