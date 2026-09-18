extends "res://scripts/art/atlas_source.gd"
## 人形来源适配器；把工具选择翻译为现有人物姿态，界面不再知道这些参数或帧数。
const Art = preload("res://scripts/presentation/directional_art.gd")
const Spec = preload("res://scripts/art/frame_spec.gd")
const Actions = preload("res://scripts/combat/action_library.gd")
@export var enemy_palette := false

func animations() -> Array:
	return [{"id":"idle","label":"站立","frames":1},{"id":"walk","label":"行走","frames":8},
		{"id":"run","label":"疾跑","frames":8},{"id":"jump","label":"跳跃","frames":5},
		{"id":"crouch","label":"蹲起","frames":7},{"id":"crouch_walk","label":"蹲行","frames":8},
		{"id":"swing","label":"挥砍手臂相位","frames":25},{"id":"bow","label":"拉弓相位","frames":9},
		{"id":"weapon_action","label":"全身动作编排","frames":33}]

func options() -> Array:
	var directions: Array = []
	for i in 12: directions.append("同向前进" if i == 0 else "反向后退" if i == 6 else "%d°" % (i*30))
	var labels: Array = ["原有姿态"]
	var values: Array = [""]
	var titles := {"light_ready":"反持戒备","light_rise":"小刀上挥","light_stab":"小刀下刺","heavy_drag":"重刀拖地","heavy_swing":"重刀前劈","death_fall":"死亡倒地"}
	titles.merge({"sword_ready":"双手持剑","sword_slash":"双手横斩","sword_thrust":"双手突刺","shield_ready":"剑盾戒备","shield_slash":"剑盾横斩","shield_thrust":"剑盾突刺"})
	for action in Actions.list_actions():
		labels.append(titles.get(action.id,action.id))
		values.append(action.id)
	return [{"id":"move","label":"移动方向","labels":directions,"values":range(12),"default":0},
		{"id":"pose","label":"上肢","labels":["持剑待机","蓄势","挥斩","收招","拉弓"],"values":[0,1,2,3,4],"default":0},
		{"id":"weight","label":"重心","labels":["后仰","中立","前压 1","前压 2"],"values":[-1,0,1,2],"default":0},
		{"id":"action","label":"动作编排","labels":labels,"values":values,"default":""},
		{"id":"gait","label":"编排步态","labels":["静止","步 0","步 1","步 2","步 3","步 4","步 5","步 6","步 7"],"values":[-1,0,1,2,3,4,5,6,7],"default":-1}]

## 选项转换成与演员相同的规范帧状态；查询手绘覆盖或程序图，并带回武器握点。
func sample(animation: String, direction: int, phase: int, settings: Dictionary) -> Dictionary:
	var pose := int(settings.get("pose",0))
	if animation == "swing" and pose not in [1,2,3]: pose = 2
	if animation == "bow": pose = 4
	var step := phase if animation in ["walk","run","crouch_walk"] else -1
	var bend := phase if animation == "crouch" else 6 if animation == "crouch_walk" else 0
	var state := Spec.character(direction,step,bend>0,(direction+int(settings.get("move",0)))%12,pose,
		phase if animation == "swing" else -1,int(settings.get("weight",0)),phase if animation == "bow" else -1,
		bend,animation == "run",phase if animation == "jump" else -1)
	var action_id := str(settings.get("action",""))
	if animation == "weapon_action":
		if action_id.is_empty(): action_id = "light_rise"
		# 全身动作本身定义上肢和重心，不能让旧手臂相位改变同一动作的帧键。
		state = Spec.character(direction,int(settings.get("gait",-1)),false,(direction+int(settings.get("move",0)))%12)
	state = Spec.with_action(state,action_id,phase if animation == "weapon_action" else 0)
	var data := Art.frame(asset_id,state,enemy_palette)
	return {"key":Spec.key(state),"texture":data.texture,"anchors":{"grip":[data.grip.x,data.grip.y]}}
