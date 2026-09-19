extends Node3D
## 箭的飞行与连续碰撞；玩家和弓手复用，通过 hostile 区分伤害对象。
const Trace = preload("res://scripts/combat/space_trace.gd")
const Art = preload("res://scripts/presentation/arrow_art.gd")
const Attachment = preload("res://scripts/combat/impact_attachment.gd")
@export var art_id := "arrow"
var velocity := Vector3.ZERO
var lifetime := 0.0
var stopped := false
var result: Dictionary = {}
var shaft: MeshInstance3D
var notify: Callable
var hit_mask := 8 | 16
var hostile := false
var hostile_damage := 15
var pierced: Array[RID] = []
var attachment: RefCounted
var attached_time := 0.0
const FADE_DURATION := 0.8

## 飞行箭与搭弓箭复用像素侧影；晚于角色物理更新附着，避免移动时落后一帧。
func _ready() -> void:
	process_physics_priority = 20
	shaft = Art.model(art_id)
	add_child(shaft)
	orient_flight()

## -Z 朝向速度、原点留在箭尖；近乎垂直的射击改用备用上方向以避免退化基底。
func orient_flight() -> void:
	if velocity.length_squared() < 0.0001: return
	var forward := velocity.normalized()
	global_basis = Basis.looking_at(forward,Vector3.RIGHT if absf(forward.dot(Vector3.UP)) > 0.99 else Vector3.UP)

## 把本帧运动拆成小时间步，以连续线段检查飞行轨迹并施加重力。
## 玩家附着箭按命中后时间淡出，期间仍跟随；其余附着/飞行箭沿用原有清理规则。
func _physics_process(delta: float) -> void:
	lifetime += delta
	if attachment != null:
		if not attachment.follow(self): queue_free(); return
		if attachment.persistent:
			attached_time += delta
			if attachment.fade_after>=0 and attached_time>attachment.fade_after:
				var progress: float = (attached_time-attachment.fade_after)/FADE_DURATION
				if progress>=1: queue_free(); return
				Art.set_opacity(shaft,1.0-smoothstep(0,1,progress))
			return
	if lifetime > 5: queue_free(); return
	if stopped: return
	var remaining := delta
	while remaining > 0.00001 and not stopped:
		var dt := minf(remaining, 1.0 / 120)
		var finish := global_position + velocity * dt + Vector3.DOWN * 4.9 * dt * dt
		var hit := Trace.trace(get_world_3d(), global_position, finish, pierced, hit_mask)
		for cloth in hit.get("penetrated", []):
			pierced.append(cloth.get_rid())
			Trace.apply_cloth(cloth)
			if notify.is_valid(): notify.call("箭穿过布帘")
		# 穿过的布帘已加入排除列表，下一段从布内出发也不会重复计数。
		if hit.has("position"):
			global_position = hit.position
			result = hit
			stopped = true
			orient_flight()
			var region := "身体"
			if hostile and hit.collider.has_method("receive_damage"):
				hit.collider.receive_damage(hostile_damage,velocity.normalized())
			elif hit.collider.has_method("receive_strike"):
				region = hit.collider.receive_strike(hit.position, hit.normal, velocity)
				if notify.is_valid(): notify.call("弓箭命中：" + region)
			elif notify.is_valid(): notify.call("箭被实体挡住")
			if hit.collider is Node3D:
				attachment = Attachment.new()
				attachment.bind(self,hit.collider,region,velocity)
		elif hit.get("blocked", false): stopped = true
		else: global_position = finish
		velocity += Vector3.DOWN * 9.8 * dt
		remaining -= dt
	if not stopped: orient_flight()
