extends Resource
## 动作数据只描述时间与姿态曲线；命中、碰撞移动和显示由调用者执行，可供后续技能复用。
@export var id := ""
@export var windup_end := 0.3
@export var active_end := 0.62
@export var lunge_speed := 0.0
@export var control_scale := 1.0
@export var ground_drag := false
@export var ground_impact := false
@export var eases := PackedFloat32Array()
@export var sweep_from := -0.5
@export var sweep_to := 0.5
@export var times := PackedFloat32Array([0,1])
@export var hands := PackedVector3Array()
@export var supports := PackedVector3Array()
@export var chests := PackedVector3Array()
@export var hips := PackedVector3Array()
@export var blades := PackedVector3Array()
@export var stances := PackedFloat32Array()
@export var twists := PackedFloat32Array()

## 各通道共享关键帧时间，三次平滑插值保持连续；身体以像素为单位，刀刃角度以度存储。
func sample(progress: float) -> Dictionary:
	var t := clampf(progress,0,1)
	var index := 0
	while index < times.size()-2 and t > times[index+1]: index += 1
	var linear := clampf((t-times[index])/(times[index+1]-times[index]),0,1)
	var power := eases[index] if index < eases.size() else 0.0
	var factor := pow(linear,power) if power>0 else smoothstep(0,1,linear)
	return {"hand":vector_at(hands,index,factor),"support":vector_at(supports,index,factor),
		"chest":vector_at(chests,index,factor),"hip":vector_at(hips,index,factor),
		"blade":vector_at(blades,index,factor)*PI/180.0,
		"stance":scalar_at(stances,index,factor),"twist":scalar_at(twists,index,factor)*PI/180.0}

func vector_at(values: PackedVector3Array, index: int, factor: float) -> Vector3:
	return values[index].lerp(values[index+1],factor) if values.size() == times.size() else Vector3.ZERO

func scalar_at(values: PackedFloat32Array, index: int, factor: float) -> float:
	return lerpf(values[index],values[index+1],factor) if values.size() == times.size() else 0.0

## 前冲仅在挥出窗口产生；落地/碰撞约束由角色移动层负责，不能直接改 position。
func forward_speed(progress: float) -> float:
	if progress <= windup_end or progress >= active_end: return 0
	return sin((progress-windup_end)/(active_end-windup_end)*PI)*lunge_speed
