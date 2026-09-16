# 高度试验场 01：空间与姿态

2026-09-16，Codex；基线 main 43b3572 / v0.2-stage3，开发分支 tactical-height-prototype。

新增 scripts/tactical/{height_lab,height_actor,directional_art}.gd、scenes/tactical_height.tscn、tests/height_lab_test.gd、play_height.bat、scripts/export_height.ps1，以及 docs/TACTICAL_HEIGHT_PLAN.md。旧生产场景、角色与存档逻辑未修改。

## 实际结果
- 固定约 35 度的正交斜视镜头只平移；真实几何体与碰撞共享尺寸，斜坡共用顶点。
- CharacterBody3D 圆柱角色受重力及地面吸附约束，支持上/下坡、真实落差；下蹲缩小高度，起身前检测头顶。
- 原创代码生成八方向像素样品、两帧步态、树木纸片和地形纹理。玩家遮挡通过相机射线触发轮廓。角色转向由鼠标所在角色高度平面决定。
- 角色/场景/视线/弹道预留不同层；布帘不阻行走，物理石墙阻行走。当前没有弹道功能，不声称已完成阻弹验证。

## 验证命令与证据
Godot --path . --fixed-fps 60 --script res://tests/height_lab_test.gd：真实 OpenGL 渲染窗口 20 项检查零失败，退出 0，日志 work/height-test.log。包含实际 InputMap 移动与 C 按下/释放，截图 work/height_overview.png、height_platform.png、height_occlusion.png、height_beam.png 已目视检查。
实测沿坡道到达 y=2.000943，低洼可回地面，低梁下无法穿顶站起；八方向纹理不同。自动动作不代表真人手感验收。
scripts/check.ps1：导入、原四关主入口启动及公共契约解析全部通过。
scripts/export_height.ps1：独立临时导出项目，不修改生产主入口；导出成功。EXE 109127680 字节、PCK 24928 字节。独立 EXE --headless --quit-after 120 退出 0，work/height-export-startup.log 无脚本错误。

## 边界
此交付只实现计划阶段 1 与阶段 2 的基础部分。尚无敌人/攻击/顶部伤害/弹道/布破坏/背包等。仍需阶段 3～6。未做人类连续试玩；遮挡采用单个身体点近似，树冠遮挡使用近似体积，后续按实际战斗需要细化，不宣称逐像素遮挡准确。

Godot 官方参考记录于 docs/TACTICAL_HEIGHT_PLAN.md。运行 play_height.bat，或 play_height.bat dev；旧桌面入口保留四关版。
