# 林间行囊图集

2026-09-23 使用内置 image_gen 生成原创单张 4×4 物品图集。参考用户提供截图的材质层次与装备分区，不使用截图像素。原始生成图完整保留为 woodpath_atlas.png，regions.json 保存16件物品主体的包围盒（从原稿透明度主体分析），运行时由 AtlasTexture 引用原图对应区域，无破坏性裁剪。

完整提示词：

Create ONE production inventory sprite atlas for a medieval dark fantasy pixel RPG. A perfectly regular 4 column x 4 row grid on a genuinely TRANSPARENT background, square 1024x1024. Every invisible grid cell exactly 256x256, each item centered in its cell with 30 pixel transparent padding, entirely separate silhouettes, no grid lines, NO TEXT, NO labels, NO shadows behind items. Detailed hand-pixelled aesthetic with crisp pixel clusters, restricted earthy colors, dark outlines, tiny metal highlights, worn leather, similar level of material detail to classic immersive medieval pixel RPG inventories. Not vector, not flat symbols, not photoreal. Weapons upright blade up, other objects upright; orthographic item illustration. EXACT order left to right top to bottom: row1: steel hunting knife with brown grip; slender steel arming sword bronze crossguard; broad heavy single-edged cleaver sword; broken steel sword with jagged missing blade and blue remnant glow. row2: wooden hunting bow with taut string; rolled ivory linen bandage; corked glass red healing potion bottle; old gold signet ring inset dark green seal. row3: folded parchment letter with red wax seal; squat ancient bronze idol relic; worn iron helmet with leather lining; brown quilted leather torso armor. row4: pair of leather gloves; pair of leather boots; folded moss green hooded cloak; amber pendant on cord. Exactly 16 item sprites, centered at x128,384,640,896 and y128,384,640,896. Large recognizable shapes with fine pixel shading. No characters, no UI frame, no duplicate items.

顺序：猎刀、宝剑、重刀、断剑、弓、绷带、药剂、戒指、信件、遗物、头盔、护甲、手套、靴子、披风、吊坠。

## 药材货物（2026-09-23）

`medicine_bundle.png` 是内置 image_gen 生成的独立透明像素图，完整提示词 `medicine_bundle.prompt.txt`。原图保留，运行最近邻显示；定义通过 icon_texture 选择独立图，旧16格图集不改动。药材为3×3的可回收货物，每包20钱，不是可直接喝掉的药剂。
