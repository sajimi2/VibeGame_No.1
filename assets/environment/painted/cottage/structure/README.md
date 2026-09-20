# 小屋空间代理

这是完整绘画房屋的隐藏空间来源，不是表面贴图模型。

- `source/cottage.blend`：保存的简单模型，禁止日常导出重建/覆盖人工修改。
- `cottage_shell.glb`：交换资产，提供实际门洞、墙和支撑几何。
- `cottage.gd` / `cottage.tscn`：装配独立墙段 StaticBody3D、碰撞、灰模显示和 Roof 控制器。门左/右/门楣/山墙共属 FrontWall，其他墙独立；地板声明 support。

运行时由 `painted_cottage` 覆盖可见外观，原墙/地板颜色退出绘制，采样/碰撞保留；精细轮廓来自上级目录原图和配准。V 可检查原始空间体积，不切回已经退役的各面生成贴图。

导出：Blender 后台运行 `tools/blender/cottage_experiment.py`，默认读取现有 `.blend`，输出 GLB，不保存源。`--init` 仅首次无源创建时使用；现有源存在会拒绝覆盖。修改尺寸必须重查门洞/支撑及画稿配准，不能只缩放图片猜碰撞。
