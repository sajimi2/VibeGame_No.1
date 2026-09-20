extends RefCounted
## 两类透视圆共用默认尺度与残留覆盖率，避免屋顶和墙体各调一套基准。
const RADIUS := 3.375
const FEATHER := 1.275
## 墙圆中心约 0.91m 全透，随后递增到残留覆盖率；外缘继续淡回正常墙面。
const CLEAR_CORE_FRACTION := .27
const FADED_COVERAGE := .22
const FADE_SECONDS := .28
