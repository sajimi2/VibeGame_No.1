extends RefCounted
## 两类透视圆共用默认尺度与残留覆盖率，避免屋顶和墙体各调一套基准。
const RADIUS := 3.375
const FEATHER := 1.275
## 墙圆中心约 0.91m 全透，随后递增到残留覆盖率；外缘继续淡回正常墙面。
const CLEAR_CORE_FRACTION := .27
const FADED_COVERAGE := .22
const FADE_SECONDS := .28

## 绘画层只订阅控制器发布的参数，共用字段不归某一栋建筑所有。
const WALL_PARAMETERS=["wall_reveal","wall_coverage","wall_center","wall_viewport","wall_dither_origin","wall_radius","wall_feather","wall_clear_core","wall_target","wall_to_camera"]
const ROOF_PARAMETERS=["reveal","roof_opacity","reveal_center","viewport_size","dither_origin","reveal_radius","feather_width","reveal_target","view_to_camera"]
