@tool
extends "res://scripts/art/imported_humanoid_rig.gd"
## 非分层敌人仍读取标准 Blender 骨骼轨道；软体不要求类人的手、腿或骨盆命名。
func anchors() -> Dictionary:
	return {"pelvis":Vector3.ZERO,"grip":Vector3.ZERO,"support":Vector3.ZERO}

func sample_job(job: Dictionary, _move: int, phase: int) -> Dictionary:
	return sample(job.clip,float(phase)/maxf(1,job.frames-1))

func apply_state(state: Dictionary) -> Dictionary:
	var clip: String=state.get("action","idle")
	return sample(clip,float(state.get("action_frame",0))/maxf(1,Spec.phases(clip)-1))
