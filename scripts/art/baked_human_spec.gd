extends RefCounted
## 人形离线帧协议：与模型和界面无关；身体/移动朝向独立，动作与步态分层组合。
const CELL := 64
const PIXEL := 0.04
const PITCH := -35.0
const CENTER := Vector3(0,0.88,0)
const FOLDER := "res://assets/characters/player_baked"
const LIBRARY := "res://assets/characters/humanoid_moves.tres"
const ACTIONS := {
	"player":["light_ready","light_rise","light_stab","sword_ready","sword_slash","sword_thrust","heavy_drag","heavy_swing","bow_ready","bow_draw","hurt","death_fall"],
	"guard":["shield_ready","shield_slash","shield_thrust","hurt","death_fall"],
	"archer":["bow_ready","bow_draw","hurt","death_fall"]}
const LABELS := {"light_ready":"反持戒备","light_rise":"匕首上挥","light_stab":"匕首下刺","sword_ready":"双手持剑","sword_slash":"宝剑横斩","sword_thrust":"宝剑突刺","heavy_drag":"重刀拖地","heavy_swing":"重刀前劈","shield_ready":"剑盾戒备","shield_slash":"剑盾横斩","shield_thrust":"剑盾突刺","bow_ready":"持弓戒备","bow_draw":"拉弓/释放","hurt":"受击卸力","death_fall":"死亡倒地"}

static func folder(asset: String) -> String: return "res://assets/characters/"+asset+"_baked"
static func ready(asset: String) -> String: return "shield_ready" if asset=="guard" else "bow_ready" if asset=="archer" else "light_ready"
static func phases(action: String) -> int:
	return 1 if action.ends_with("ready") or action=="heavy_drag" else 9 if action in ["bow_draw","hurt"] else 33
static func key(part: String, action: String, direction: int, move := 0, phase := 0) -> String:
	return "%s/%s/%d/%d/%d" % [part,action,direction,move,phase]

## 不生成动作×步态的笛卡尔积；腾空/下蹲替换腿部，攻击上身继续使用动作帧。
static func select(state: Dictionary, asset := "player") -> Dictionary:
	var action: String=state.get("action","")
	if action.is_empty(): action="bow_draw" if state.get("pose",0)==4 else ready(asset)
	if action not in ACTIONS.get(asset,[]): return {}
	var direction: int=state.get("direction",0)
	var move:=posmod(int(state.get("move",direction))-direction,12)
	var phase:=clampi(int(state.get("action_frame",0)),0,phases(action)-1)
	if action=="bow_draw": phase=clampi(int(state.get("draw",0)),0,8)
	var upper:=key("upper",action,direction,0,phase)
	var lower:=key("lower",action,direction,0,phase)
	if action=="death_fall": return {"upper":upper,"lower":lower}
	var step: int=state.get("step",-1)
	var crouch: int=state.get("crouch",0)
	var jump: int=state.get("jump",-1)
	if jump>=0:
		lower=key("lower","jump",direction,move,jump)
	elif crouch>0:
		lower=key("lower","crouch_walk",direction,move,step) if step>=0 and crouch>=4 else key("lower","crouch",direction,0,crouch)
	elif step>=0:
		lower=key("lower","run" if state.get("run",false) else "walk",direction,move,step)
	# 戒备上身随步态摆臂；重刀保持承重，不套用轻装摆臂。
	if phases(action)==1:
		if jump>=0: upper=key("upper",action+"_jump",direction,0,jump)
		elif crouch>0: upper=key("upper",action+"_crouch",direction,0,crouch)
		elif step>=0: upper=key("upper",action+("_run" if state.get("run",false) else "_walk"),direction,move,step)
	return {"upper":upper,"lower":lower}

## 作业清单也是预览与验证的枚举入口，避免烘焙范围与选帧条件各写一套。
static func jobs(asset: String) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for action in ACTIONS[asset]:
		for part in ["upper","lower"]:
			result.append({"part":part,"id":action,"clip":action,"frames":phases(action),"moves":1})
		if phases(action)!=1: continue
		for gait in ["walk","run","crouch","jump"]:
			result.append({"part":"upper","id":action+"_"+gait,"clip":action,"overlay":gait,"frames":7 if gait=="crouch" else 5 if gait=="jump" else 8,"moves":12 if gait in ["walk","run"] else 1})
	for gait in ["walk","run","crouch_walk","crouch","jump"]:
		result.append({"part":"lower","id":gait,"clip":gait,"frames":7 if gait=="crouch" else 5 if gait=="jump" else 8,"moves":1 if gait=="crouch" else 12})
	return result
