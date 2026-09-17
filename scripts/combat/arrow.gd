extends Node3D
const Trace = preload("res://scripts/combat/space_trace.gd")
var velocity := Vector3.ZERO
var lifetime := 0.0
var stopped := false
var result: Dictionary = {}
var shaft: MeshInstance3D
var notify: Callable
var hit_mask := 8 | 16
var hostile := false
var pierced: Array[RID] = []

func _ready() -> void:
	shaft = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.035, 0.035, 0.65)
	shaft.mesh = mesh
	shaft.position.z = 0.325 # The collision point is the tip; the shaft stays behind it.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("ffe1a0")
	shaft.material_override = mat
	add_child(shaft)

func _physics_process(delta: float) -> void:
	lifetime += delta
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
		# Avoid counting the same cloth again while the next segment starts inside it.
		if hit.has("position"):
			global_position = hit.position
			result = hit
			stopped = true
			if hostile and hit.collider.has_method("receive_damage"):
				hit.collider.receive_damage(15,velocity.normalized())
			elif hit.collider.has_method("receive_strike"):
				var region: String = hit.collider.receive_strike(hit.position, hit.normal, velocity)
				if notify.is_valid(): notify.call("弓箭命中：" + region)
			elif notify.is_valid(): notify.call("箭被实体挡住")
		elif hit.get("blocked", false): stopped = true
		else: global_position = finish
		velocity += Vector3.DOWN * 9.8 * dt
		remaining -= dt
	if velocity.normalized().cross(Vector3.UP).length() > 0.01:
		shaft.look_at(global_position + velocity, Vector3.UP)
