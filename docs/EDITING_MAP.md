# 在 Godot 里编辑林路地图

当前入口是 `scenes/courtyard_combat.tscn`，不是 tools 下的环境预览或旧地图。编辑器若提示文件在外部更新，选择“从磁盘重新加载”，保留磁盘上的新场景。

## 先试一次：移动宝箱

1. 打开主场景，切到上方 **3D**。
2. 左侧展开 `Map → Interactions`，选择 `Chest`（驿站货箱）。
3. 按 **F** 聚焦选中物件。用移动工具沿 X/Z 拖动，或在检查器的 Transform → Position 输入坐标；Y 通常保持0。
4. **Ctrl+S** 保存，再 **F5** 运行。宝箱的画面、碰撞、名字提示和 E 交互会一起移到新位置。
5. 重新打开这个场景，位置仍然保留。运行游戏不会重建旧布局覆盖它。

这是普通Godot场景编辑，不需要先运行游戏，也不需要再修改脚本中的坐标。运行期间的“远程”场景树用于调试，不会替你保存地图；要编辑的是“本地”场景树。

## 场景树中各部分是什么

| 节点 | 可以调整什么 |
| --- | --- |
| Map/Ground | 固定地面及其碰撞，先保持现状即可 |
| Map/Courtyard | 营地的井、桶、车、石头、院墙和花草 |
| Map/WoodpathRegion | 林路树木、遗迹、外围墙和调查物件 |
| Map/Cottage | 整栋小屋，包含绘画面、墙体碰撞和屋顶透视 |
| Map/Interactions | Steward管事、Healer药师、Stash营地仓库、Chest货箱、Cache藏箱、Supply药材箱、Satchel背包 |
| Map/PlayerSpawn | 玩家出生点标记 |
| EditorCamera | 选择后勾选视口的“预览”，按游戏固定角度观察；不是运行时跟随相机 |

展开树林后名字含tree_a/tree_b/tree_c的是三种树，wall/wall_z是两种墙向。选择**物件最外层节点**移动，可让画面、地面接触层、影子和碰撞保持在一起。不要只拖动里面的Illustration。

## 复制与复用

- 树、石头、墙等普通景物可以 **Ctrl+D** 复制后移动；也可以从 `scenes/props/` 把对应 `.tscn` 拖入 `Map/Courtyard` 或 `Map/WoodpathRegion`。
- 场景实例可右键选择“可编辑子节点”，查看或微调其中的 SimpleBody/CollisionShape3D。若只是摆位置，修改最外层节点即可。
- 双击物件的场景图标，会打开其模板。修改模板会影响引用它的实例；只想改一件时，在地图中修改该实例。
- 删除普通景物并保存后，运行时不会补回来。
- 药车、路标、纪念石堆内有调查Marker，移动父物件会一起移动调查点。

## 本轮保留的边界

- 插画仍是固定视角。可平移和小幅等比缩放，横墙/竖墙用各自模板；不要随意旋转或非等比拉伸树、墙、小屋，否则画稿会与空间关系不符。
- `Map`、`Courtyard`、`WoodpathRegion`、`Cottage` 是装配入口，暂不要重命名或删除它们。普通景物名字可以自行改。
- 任务物件的Metadata中 `interaction_id` 是现有故事和存档的身份，不是显示名称。**不要通过复制相同ID创建第二个任务宝箱/NPC**。新增独立容器还需要配置库存与故事数据；本轮先解决已有物件的人工摆放。
- NPC的EditorPose是已有角色图集的静态站姿，运行时切回原来的呼吸动画；不是新的人物制作管线。
- 道路绘制、地图边界范围、敌人出生/寻路配置、相机跟随、统一光照、UI仍由原脚本管理。本轮没有把所有游戏行为迁出代码，也没有增加可视化道路编辑器。
- `tools/materialize_courtyard.gd` 是一次性迁移工具，已有Map时会拒绝覆盖。日常编辑不运行它，不重跑旧布局生成器。

## 开发验证

`tests/tactical/editable_scene_test.gd` 在work内保存一份搬移/复制/删除后的地图，重载后检查真实物理、开箱、调查和移动小屋后的屋顶透视；开启tactical/testing，不访问玩家真实进度。已加入core/art套件。

`tests/tactical/editable_scene_editor_test.gd` 需使用 `--headless --editor --script` 运行，检查引擎编辑模式下无需运行游戏就有画面节点，移动后同步材质原点和影子。它与桌面中实际拖动的人工验收是不同证据。
