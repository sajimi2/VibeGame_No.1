@tool
extends Node3D
## 美术源只采样已保存的 AnimationPlayer 骨骼轨道；不再依赖二维关节或拉伸肢体。
const Spec = preload("res://scripts/art/baked_human_spec.gd")
var rig_skeleton: Skeleton3D
var animator: AnimationPlayer
var bones: Array[Dictionary]=[]

func _ready() -> void: build()

## 由导入适配器绑定标准骨架、动画播放器和身体分层。
func build() -> void: pass

## 采样标准 Godot 关键帧并立即同步骨骼；不依赖普通帧推进或旧二维姿态计算。
func sample(clip: String, phase: float) -> Dictionary:
	build()
	assert(animator.has_animation(clip),"缺少骨骼动画："+clip)
	# 直接采样保存的标准轨道，避免 AnimationPlayer 的属性缓存跳过上次分层混合改写的骨骼。
	var animation:=animator.get_animation(clip)
	rig_skeleton.reset_bone_poses()
	var time:=clampf(phase,0,1)*animation.length
	for track in animation.get_track_count():
		if not animation.track_is_enabled(track): continue
		var path:=animation.track_get_path(track)
		if path.get_subname_count()==0: continue
		var index:=rig_skeleton.find_bone(path.get_subname(0))
		if index<0: continue
		match animation.track_get_type(track):
			Animation.TYPE_POSITION_3D: rig_skeleton.set_bone_pose_position(index,animation.position_track_interpolate(track,time))
			Animation.TYPE_ROTATION_3D: rig_skeleton.set_bone_pose_rotation(index,animation.rotation_track_interpolate(track,time).normalized())
	_sync()
	return anchors()

func _sync() -> void:
	rig_skeleton.force_update_all_bone_transforms()

func anchors() -> Dictionary:
	return {"pelvis":_bone_point("Pelvis"),"grip":_bone_point("HandR"),"support":_bone_point("HandL")}

func _bone_point(id: String) -> Vector3:
	return rig_skeleton.get_bone_global_pose(rig_skeleton.find_bone(id)).origin

## 上身以骨盆拼接；戒备移动叠加步态的躯干/头部和空闲手，不改变固定骨长。
func sample_job(job: Dictionary, move: int, phase: int) -> Dictionary:
	var gait: String=job.get("overlay",job.clip)
	var timed:=float(phase)/(8.0 if gait in ["walk","run","crouch_walk"] else maxf(1,job.frames-1))
	var clip: String=job.clip
	if clip in ["walk","run","crouch_walk","jump"]: clip+="_%02d"%move
	if not job.has("overlay"): return sample(clip,timed)
	sample(gait+("_%02d"%move if gait in ["walk","run","jump"] else ""),timed)
	var gait_poses: Array[Transform3D]=[]
	for i in bones.size(): gait_poses.append(rig_skeleton.get_bone_pose(i))
	sample(job.clip,0)
	# 躯干小幅姿态变化随步态；根部重心和腿部始终来自同一个步态片段。
	for i in bones.size():
		var id:=str(rig_skeleton.get_bone_name(i))
		if bones[i].part=="lower": rig_skeleton.set_bone_pose(i,gait_poses[i])
		elif id in ["Spine","Head"]:
			var pose:=rig_skeleton.get_bone_pose(i)
			pose.basis=(gait_poses[i].basis*rig_skeleton.get_bone_rest(i).basis.inverse()*pose.basis).orthonormalized()
			rig_skeleton.set_bone_pose(i,pose)
		elif job.clip=="light_ready" and id in ["UpperArmL","ForearmL","HandL","UpperArmR","ForearmR","HandR"]:
			rig_skeleton.set_bone_pose(i,gait_poses[i])
	_sync()
	return anchors()

## 工具侧组合预览；运行时不调用该函数，不实例化骨架。
func apply_state(state: Dictionary) -> Dictionary:
	var selection:=Spec.select(state,state.get("asset","player"))
	if selection.is_empty(): return sample("light_ready",0)
	var poses: Array[Transform3D]=[]
	for part in ["lower","upper"]:
		var fields: PackedStringArray=selection[part].split("/")
		for job in Spec.jobs(state.get("asset","player")):
			if job.part==part and job.id==fields[1]:
				sample_job(job,int(fields[3]),int(fields[4]))
				break
		if part=="lower":
			for i in bones.size(): poses.append(rig_skeleton.get_bone_pose(i))
		else:
			for i in bones.size():
				if bones[i].part=="lower": rig_skeleton.set_bone_pose(i,poses[i])
	_sync()
	return anchors()
