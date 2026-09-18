extends RefCounted
## 纯数据的帧标识；导出器和运行时共用，消除无效参数造成的同帧不同键。
static func character(direction: int, step: int, crouch: bool, move_direction: int = -1, pose: int = 0, arm: int = -1, weight: int = 0, draw: int = -1, crouch_frame: int = -1, running: bool = false, jump: int = -1) -> Dictionary:
	var bend := (6 if crouch else 0) if crouch_frame < 0 else clampi(crouch_frame,0,6)
	var frame := step if jump < 0 else -1
	var move := posmod(move_direction if move_direction >= 0 else direction,12)
	if frame < 0 and jump < 0: move = posmod(direction,12)
	return {"direction":posmod(direction,12), "step":frame, "move":move, "pose":pose,
		"arm":arm if pose in [1,2,3] else -1, "weight":weight,
		"draw":(8 if draw < 0 else draw) if pose == 4 else -1, "crouch":bend,
		"run":running and frame >= 0 and bend == 0 and jump < 0, "jump":jump}

static func key(state: Dictionary) -> String:
	var fields := [state.direction,state.step,state.move,state.pose,state.arm,state.weight,state.draw,state.crouch,state.run,state.jump]
	if not str(state.get("action","")).is_empty(): fields.append_array([state.action,state.action_frame])
	return JSON.stringify(fields)

## 新动作追加命名空间，旧图集的十字段帧键保持不变，不把反持/重刀稿误套到旧姿态。
static func with_action(state: Dictionary, id: String, phase: int = 0) -> Dictionary:
	var result := state.duplicate()
	result.action = id
	result.action_frame = clampi(phase,0,32)
	if not id.is_empty():
		# 编排动作已经给出完整上肢与重心，旧相位字段不再造成同图不同键。
		result.pose = 0
		result.arm = -1
		result.weight = 0
		result.draw = -1
	return result
