extends RefCounted
## 倒地只操作表现节点，尸体根节点保留给击败统计；渐隐完成后不再生成帧或更新变换。
const Spec = preload("res://scripts/art/frame_spec.gd")
var elapsed := 0.0
var started := false
var finished := false
var direction := 0
var ground_point := Vector3.ZERO
var ground_normal := Vector3.UP
var fall_direction := Vector3.FORWARD

func update(actor: CharacterBody3D, delta: float) -> void:
	if finished: return
	if not started:
		started = true
		var view: Vector3 = actor.facing.rotated(Vector3.UP,-actor.camera.rotation.y)
		direction = posmod(roundi(atan2(view.x,view.z)/(PI/6)),12)
		# 尸体沿真实地面法线放倒，坡道上不把半截身体埋进坡面。
		ground_point = actor.global_position
		var ray := PhysicsRayQueryParameters3D.create(ground_point+Vector3.UP*0.4,ground_point+Vector3.DOWN,1|32,[actor.get_rid()])
		var floor_hit := actor.get_world_3d().direct_space_state.intersect_ray(ray)
		if not floor_hit.is_empty():
			ground_point = floor_hit.position
			ground_normal = floor_hit.normal
		var impact: Vector3 = actor.knockback if actor.knockback.length()>0.01 else -actor.facing
		fall_direction = (impact-ground_normal*impact.dot(ground_normal)).normalized()
		actor.sword.hide()
		actor.trail.hide()
		if is_instance_valid(actor.shield_node): actor.shield_node.hide()
		actor.marker.hide()
		actor.health_bar.hide()
		actor.baked_visual.set_occluded(false)
	elapsed += delta
	var fall := clampf(elapsed/0.85,0,1)
	# 专用姿态先卸力下沉，随后伸开四肢；末帧不复用蹲姿，避免倒地后仍像坐着。
	var state := Spec.with_action(Spec.character(direction,-1,false),"death_fall",roundi(fall*32))
	if is_instance_valid(actor.baked_visual) and actor.baked_visual.enabled:
		var visual: Node3D=actor.baked_visual
		visual.tint=Color(.72,.70,.68)
		visual.opacity=1.0-clampf((elapsed-2.8)/1.2,0,1)
		visual.grounded_death=true
		visual.ground_origin=ground_point+ground_normal*.035
		visual.ground_basis=Basis(Quaternion(Vector3.UP,ground_normal))
		# 图集默认向身后倒；按致命来向选择十二方向，仍由骨骼帧完成倒地。
		var view: Vector3=(-fall_direction).rotated(Vector3.UP,-actor.camera.rotation.y)
		state.direction=posmod(roundi(atan2(view.x,view.z)/(PI/6)),12)
		if visual.apply_frame(state):
			if elapsed>=4:
				finished=true
				actor.hide()
			return
## 重试通常重建场景；测试或未来复活流程恢复表现时可复用这个入口。
func restore(actor: CharacterBody3D) -> void:
	started = false
	finished = false
	elapsed = 0
	ground_normal = Vector3.UP
	actor.show()
	if is_instance_valid(actor.baked_visual):
		actor.baked_visual.opacity=1.0
		actor.baked_visual.grounded_death=false
		actor.baked_visual.ground_basis=Basis.IDENTITY
	actor.sword.show()
	actor.trail.show()
	actor.marker.show()
	actor.health_bar.show()
	if is_instance_valid(actor.shield_node): actor.shield_node.show()
