extends Resource
## 游戏动作资源描述时序、武器旋转与移动能力；身体姿态由 Blender 动画制作并离线烘焙。
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
@export var blades := PackedVector3Array()

## 分段曲线保持武器旋转连续；资源以度存储，输出弧度，不再混入旧二维身体关节。
func sample(progress: float) -> Dictionary:
	var t := clampf(progress,0,1)
	var index := 0
	while index < times.size()-2 and t > times[index+1]: index += 1
	var linear := clampf((t-times[index])/(times[index+1]-times[index]),0,1)
	var power := eases[index] if index < eases.size() else 0.0
	var factor := pow(linear,power) if power>0 else smoothstep(0,1,linear)
	return {"blade":vector_at(blades,index,factor)*PI/180.0}

func vector_at(values: PackedVector3Array, index: int, factor: float) -> Vector3:
	return values[index].lerp(values[index+1],factor) if values.size() == times.size() else Vector3.ZERO

## 前冲仅在挥出窗口产生；落地/碰撞约束由角色移动层负责，不能直接改 position。
func forward_speed(progress: float) -> float:
	if progress <= windup_end or progress >= active_end: return 0
	return sin((progress-windup_end)/(active_end-windup_end)*PI)*lunge_speed
