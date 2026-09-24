# 林路与灰榆驿站资产 · 2026-09-23

本批由 Codex 内置 `image_gen` 生成；完整原图在 `source/`，请求提示词在 `prompts/`。未下载他人游戏素材，参考只用于风格方向。

| 原图 | 用途 |
| --- | --- |
| oak_calm.png | 克制的大块树冠，疏密错落的成树 |
| oak_young.png | 窄冠幼树；生成后用同一工具去除背景光晕 |
| wall_z.png | 与既有横墙互补的世界 Z 向石墙，不旋转同一张图硬凑 |
| waystation_ruin.png | 可走入的无顶驿站残屋，门洞和墙体分开碰撞 |
| chest_motion.png | 闭合、半开、近开、全开四帧；反播合盖 |

`tools/register_woodpath_art.gd` 只登记原图 alpha 包围盒到 `catalog.json`，不修改生成像素。运行时 AtlasTexture 取原稿区域，环境低分辨率通道与最近邻采样统一屏幕像素密度。新画稿保持固定相机方向；不得旋转相机看背面。

目录记录世界宽度、脚点锚点、简单碰撞与遮挡代理。残屋用五个墙盒保留门洞，不拿整栋实心盒堵门。美术与隐藏代理允许适度偏差；树冠 alpha 半透明外缘由既有 shader 截断。共用小院 shadow_style 阴影，画稿不自带第二份地面投影。

`woodpath_region.gd` 的 MAIN / SIDE / RETURN 同时驱动柔边土路与装饰避让；固定 seed=92351 生成树群位置，混用两种树与0.72～1.05缩放。不是每次读档随机，也不是新地形生成路线。宝箱保持固定画布/锚点和碰撞，动画不移动交互点。

实际1280×720截图在忽略目录 `work/woodpath_v2/`；可用 `woodpath_region_test.gd` 重建。原始生成路径在 `.codex/generated_images/`，本目录保留独立副本，运行不依赖该机器缓存。
