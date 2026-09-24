extends RefCounted
## 事件映射到已许可采样，表现层统一播放；所有文件来源与许可随 assets/audio/sfx 保留。
const FOLDER="res://assets/audio/sfx/"
const CLIPS={
	"step":["footstep_grass_000.ogg","footstep_grass_001.ogg","footstep_grass_002.ogg"],
	"step_wood":["footstep_wood_000.ogg","footstep_wood_001.ogg","footstep_wood_002.ogg"],
	"swing":["knifeSlice.ogg","knifeSlice2.ogg"],
	"bow":["bow_release.ogg"],
	"bow_draw":["bow_draw.ogg"],
	"arrow_impact":["impactWood_medium_000.ogg","impactWood_medium_001.ogg"],
	"hit":["impactPunch_medium_000.ogg","impactPunch_medium_001.ogg"],
	"guard":["impactMetal_light_000.ogg","impactMetal_light_001.ogg"],
	"jump":["cloth1.ogg","cloth2.ogg"],
	"land":["boots-leather-jump-01.wav","boots-leather-jump-02.wav"],
	"roll":["cloth3.ogg","dropLeather.ogg"],
	"alert":["beltHandle1.ogg"],"death":["impactSoft_heavy_000.ogg"],
	"chest_open":["creak1.ogg"],"chest_close":["doorClose_1.ogg"],
	"inventory":["handleSmallLeather.ogg"],"read":["bookOpen.ogg","bookFlip1.ogg"],"coins":["handleCoins.ogg"]}
