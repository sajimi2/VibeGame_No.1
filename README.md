# Outpost RPG

Godot 4.7.2 / GDScript / Compatibility。当前是固定斜角正交、三维空间与像素绘画呈现的短篇探索原型：「失踪信使」。小院安全营地连通分岔林路与灰榆驿站，包含少量即时战斗、地点调查、搜刮整理、两位NPC和两种委托结果。

## 运行

- 双击 `play.bat`（或 `play_courtyard.bat`）运行最新源码，默认全屏；不再读取可能过时的 builds 导出包。启动器优先使用 GODOT_BIN，其次相邻 Godot 4.7.2 文件夹，最后 PATH 中的 godot.exe。
- Godot 打开 `project.godot` 后 F5，同样进入 `scenes/courtyard_combat.tscn`。编辑器内嵌窗口受编辑器控制，需要独立全屏时使用BAT。
- WASD移动，Shift疾跑，Alt翻滚，空格跳跃，左键使用当前武器，按住右键格挡，1–5切换随身武器；第五格为独立弓。滚轮阻尼缩放。
- E交谈/调查/搜查，I行囊与日志。拖动整理，拖动时R旋转，右键操作，Shift单击快速转移。7个装备槽，8×6行囊；营地仓库可存物品。装备当前不改变人物外观。
- F11 / Alt+Enter切换全屏；退出时恢复原窗口状态。设计画布1280×720，保持比例缩放，非16:9屏幕有必要黑边。背包可独立调节音乐和音效。
- 走东面大路或北侧林径寻找信使背包；药车、路标、南侧石堆可以调查。信件、戒指和药师证词影响交付。遗迹内药材占3×3格，可回营向药师换钱；装不下的物品留在原处。
- R重新出发保留既有物品和任务结果，重置敌人；不是重新开档。当前没有篇章重置按钮，也没有硬核撤离丢失物品规则。

## 接手与制作

先读 [HANDOFF.md](HANDOFF.md)、[AI_SYNC.md](AI_SYNC.md)、[架构](docs/ARCHITECTURE.md)。地图和资产扩展入口是 `woodpath_region.gd`，交互是 `woodpath_story.gd`，箱子/日志/钱币状态是 `expedition_state.gd`。

- 场景沿用完整固定单视角画稿＋隐藏简单空间代理。[环境规范](docs/ENVIRONMENT_ART.md)，[林路原稿和配准](assets/environment/painted/woodpath/README.md)。纯美术基准 `scenes/painted_courtyard.tscn` 与F5篇章分开。
- 人物沿用保存的 Blender源 → GLB → 96×96十二朝向颜色/深度/握点。[人物管线](docs/ART_PIPELINE.md)。管事与药师为独立源，仅烘焙轻呼吸；玩家动作源不为NPC制作重建。
- 武器/刀光保持独立GPU像素化：[武器说明](docs/WEAPON_PIXEL_EXPERIMENT.md)。图集工作台 `tools/art_preview.tscn`，模型对照 `tools/weapon_pixel_lab.tscn`。
- 物品图标原稿与提示词 `assets/ui/items/`；[像素字体许可](assets/ui/fonts/README.md)；[音效来源](assets/audio/sfx/README.md)。BGM为用户提供的 Sunlit Woodpath，原文件完整保留。

## 验证

```powershell
./scripts/check.ps1 -Suite smoke
./scripts/check.ps1 -Suite core
./scripts/check.ps1 -Suite core -Rendered
```

单项范围见 [tests/README.md](tests/README.md)。新篇章专项为 woodpath_expedition / woodpath_region；相机、战斗、全屏有各自专项。测试通过 tactical/testing 隔离玩家进度，日志和截图放 work/；自动检查和画面检查不等于主观好玩验收。

## 进度与历史

存档仍用 `user://tactical_progress_v1.json`，内部version=2。旧v1迁移保留备份，溢出/未知物品保存在恢复仓储，不丢弃。已完成委托继续保留；新药材箱只在快照中缺失时初始化。

旧荒堡/旧驿站/高度场场景和脚本已退出活跃目录，物理回归依赖集中 `tests/fixtures/legacy/`，旧BAT及过时导出脚本移出。共享材质/角色工具仍保留。粗格/缓坡是历史对照，F5不使用。不要为了查历史重置当前工作区。

当前未接在线AI，无开放世界生成、建造种植、重量饥饿或完整NPC生活模拟。第三方 Godot AI 插件保持原样，接入见 [GODOT_AI_SETUP.md](GODOT_AI_SETUP.md)。

## 在 Godot 编辑地图

主场景 `scenes/courtyard_combat.tscn` → 展开 `Map`。树、墙、宝箱和NPC可以直接选中移动保存；模板位于 `scenes/props/`。操作与边界见 [地图编辑说明](docs/EDITING_MAP.md)。
