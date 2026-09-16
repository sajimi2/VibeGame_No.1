extends Node3D
const Trace = preload("res://scripts/tactical/space_trace.gd")
const Arrow = preload("res://scripts/tactical/space_arrow.gd")
var actor: CharacterBody3D
var notify: Callable
var cooldown := 0.0
var swing_time := 0.0
var previous_angle := -35.0
var struck: Dictionary = {}
var locked_direction := Vector3.FORWARD
var weapon: MeshInstance3D
var bow: MeshInstance3D
var bow_time := 0.0
var hand: Node3D
var arrows: Node3D
var melee_hits := 0

func setup(body: CharacterBody3D, callback: Callable) -> void:
 actor = body
 notify = callback
 hand = Node3D.new()
 actor.add_child(hand)
 weapon = MeshInstance3D.new()
 var mesh := BoxMesh.new()
 mesh.size = Vector3(0.09, 0.035, 1.8)
 weapon.mesh = mesh
 weapon.position.z = -0.95
 var mat := StandardMaterial3D.new()
 mat.albedo_color = Color("dce5d6")
 mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 weapon.material_override = mat
 hand.add_child(weapon)
 bow = MeshInstance3D.new()
 var bow_mesh := ImmediateMesh.new()
 bow_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
 for i in 8:
  for sample in [i, i + 1]:
   var y: float = -0.5 + sample / 8.0
   bow_mesh.surface_add_vertex(Vector3(0, y, -0.3 - 0.25 * cos(y * PI)))
 bow_mesh.surface_add_vertex(Vector3(0,-0.5,-0.3))
 bow_mesh.surface_add_vertex(Vector3(0,0.5,-0.3))
 bow_mesh.surface_end()
 bow.mesh = bow_mesh
 bow.material_override = mat
 bow.hide()
 hand.add_child(bow)
 arrows = Node3D.new()
 arrows.name = "Arrows"
 get_parent().add_child(arrows)
 process_physics_priority = 5

func muzzle() -> Vector3:
 return actor.global_position + Vector3.UP * (0.68 if actor.crouched else 1.15)

func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseButton and event.pressed:
  actor.update_aim(event.position)
  if event.button_index == MOUSE_BUTTON_LEFT: attack(actor.aim_point)
  if event.button_index == MOUSE_BUTTON_RIGHT: shoot(actor.aim_point)

func attack(point: Vector3) -> bool:
 if cooldown > 0: return false
 locked_direction = (point - muzzle()).normalized()
 if locked_direction.length() < 0.1: locked_direction = Vector3(actor.facing.x, 0, actor.facing.y)
 cooldown = 0.38
 swing_time = 0.3
 previous_angle = -35
 struck.clear()
 return true

func shoot(point: Vector3):
 if cooldown > 0: return null
 cooldown = 0.45
 bow_time = 0.45
 var arrow := Arrow.new()
 arrows.add_child(arrow)
 arrow.global_position = muzzle()
 arrow.velocity = Trace.launch_velocity(muzzle(), point)
 arrow.notify = notify
 return arrow

func _physics_process(delta: float) -> void:
 cooldown = maxf(0, cooldown - delta)
 bow_time = maxf(0, bow_time - delta)
 bow.visible = bow_time > 0
 weapon.visible = bow_time <= 0
 hand.global_position = muzzle()
 var direction := locked_direction if swing_time > 0 else Vector3(actor.facing.x, 0, actor.facing.y)
 if direction.cross(Vector3.UP).length() > 0.01: hand.look_at(hand.global_position + direction)
 if swing_time > 0:
  swing_time = maxf(0, swing_time - delta)
  var angle := lerpf(-35, 35, clampf((0.2 - swing_time) / 0.12, 0, 1))
  hand.rotate_object_local(Vector3.UP, deg_to_rad(angle))
  if swing_time <= 0.2 and previous_angle < 35:
   strike(previous_angle, angle)
   previous_angle = angle

func strike(from_angle: float, to_angle: float) -> void:
 var samples := maxi(1, ceili(absf(to_angle - from_angle) / 3))
 for sample in samples + 1:
  var angle := lerpf(from_angle, to_angle, float(sample) / samples)
  var direction := locked_direction.rotated(Vector3.UP, deg_to_rad(angle))
  var hit := Trace.trace(get_world_3d(), muzzle(), muzzle() + direction * 1.9)
  for cloth in hit.get("penetrated", []):
   if not struck.has(cloth.get_instance_id()):
    struck[cloth.get_instance_id()] = true
    Trace.apply_cloth(cloth)
  if not hit.has("collider"): continue
  var target: Object = hit.collider
  if struck.has(target.get_instance_id()): continue
  struck[target.get_instance_id()] = true
  if target.has_method("receive_strike"):
   melee_hits += 1
   var region: String = target.receive_strike(hit.position, hit.normal, direction)
   if notify.is_valid(): notify.call("近战命中：" + region)
