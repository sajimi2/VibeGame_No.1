# 表现修整 01

2026-09-16，Codex。用户已试玩射箭无 bug，本轮回应行走、浮空及2D/3D风格混合问题。

## 改动
- directional_art.gd：十二朝向保持；新增八相位关节步态，一腿支撑时另一腿摆动，脚踝、膝盖和手臂配合，躯干不随帧整块蹦跳。正面补前后摆动。
- height_actor.gd：按实际地面移动距离推进动画，顶墙不原地踏步；以脚底为 Sprite3D 本地原点，偏移用像素坐标，使纸片旋转不再挪动落点。
- ground_shadow.gd：像素接触影，以地面射线位置及法线摆放，适配坡道；人物及树木的纸片实时投影关闭，避免镜头朝向影响投影根部。树根按实际树干底端像素对齐。
- height_lab.gd：卡通漫反射、关闭高光、坡道硬面法线；B 切环境分段/连续明暗，V 切镜头。训练靶使用同类卡通材质。

## 验证
真实渲染窗口 tests/visual_polish_test.gd：33 项零失败。验证支撑脚、不同步态、脚底原点、接触影、顶墙停止动画和材质切换；日志 work/visual-polish-test.log。
真实窗口 tests/space_combat_test.gd 27 项通过、tests/height_lab_test.gd 20 项通过；日志 work/visual-combat-test.log、work/visual-space-test.log。碰撞/攻击规则未改。
已查看 work/walk_cycle_sheet.png 的逐帧图与 work/combat_perspective.png 的落点/地形画面。独立导出及启动日志 work/visual-export-startup.log。

## 限制
用户尚未试玩新动画。卡通漫反射和硬法线是第一步风格处理，不是完整三渲二美术管线；地形仍为试验场几何。接触影是美术近似，不模拟树冠长投影。动画仍为代码生成的像素样品。
跳跃没有实现。建议以后先评估低幅短跳/越低障碍；难点主要是落点、路线、敌人导航与空中战斗规则，而非给垂直速度赋值。
