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
var melee_range := 1.9
var melee_damage := 20
var attack_duration := 0.3
var attack_interval := 0.38
var assist_target: Node3D
var assist_enabled := true
var assist_marker: MeshInstance3D

func setup(body: CharacterBody3D, callback: Callable) -> void:
 actor = body
 notify = callback
 hand = Node3D.new()
 actor.add_child(hand)
 weapon = preload("res://scripts/tactical/weapon_art.gd").sword()
 hand.add_child(weapon)
 bow = preload("res://scripts/tactical/weapon_art.gd").bow()
 bow.hide()
 hand.add_child(bow)
 arrows = Node3D.new()
 arrows.name = "Arrows"
 get_parent().add_child(arrows)
 assist_marker=MeshInstance3D.new()
 var ring := TorusMesh.new()
 ring.inner_radius=0.44
 ring.outer_radius=0.50
 ring.rings=32
 ring.ring_segments=6
 assist_marker.mesh=ring
 var ring_mat := StandardMaterial3D.new()
 ring_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 ring_mat.albedo_color=Color("ffe4a0")
 assist_marker.material_override=ring_mat
 assist_marker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 assist_marker.visible=false
 add_child(assist_marker)
 process_physics_priority = 5

func muzzle() -> Vector3:
 return actor.global_position + Vector3.UP * (0.68 if actor.crouched else 1.15)

func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseButton and event.pressed:
  actor.update_aim(event.position)
  if event.button_index == MOUSE_BUTTON_LEFT: attack(actor.aim_point)
  if event.button_index == MOUSE_BUTTON_RIGHT: shoot(assisted_point(actor.aim_point,actor.cursor))

func attack(point: Vector3) -> bool:
 if get_tree().paused: return false
 if cooldown > 0 or actor.hp<=0: return false
 locked_direction = (point - muzzle()).normalized()
 if locked_direction.length() < 0.1: locked_direction = Vector3(actor.facing.x, 0, actor.facing.y)
 cooldown = attack_interval
 swing_time = attack_duration
 actor.attack_facing = Vector2(locked_direction.x,locked_direction.z).normalized()
 actor.effects.sound("swing",actor.global_position)
 previous_angle = -35
 struck.clear()
 return true

func shoot(point: Vector3):
 if cooldown > 0 or actor.hp<=0: return null
 cooldown = 0.45
 bow_time = 0.45
 actor.effects.sound("bow",actor.global_position)
 var arrow := Arrow.new()
 arrows.add_child(arrow)
 arrow.global_position = muzzle()
 arrow.velocity = Trace.launch_velocity(muzzle(), point)
 arrow.notify = notify
 return arrow

func _physics_process(delta: float) -> void:
 if not actor.test_mode:
  assisted_point(actor.aim_point,actor.cursor)
  assist_marker.visible=is_instance_valid(assist_target) and actor.hp>0
  if assist_marker.visible: assist_marker.global_position=assist_target.global_position+Vector3.UP*0.04
 var phase_time := swing_time / attack_duration * 0.3
 actor.attack_pose = 1 if phase_time>0.2 else 2 if phase_time>0.08 else 3 if phase_time>0 else 4 if bow_time>0 else 0
 cooldown = maxf(0, cooldown - delta)
 bow_time = maxf(0, bow_time - delta)
 bow.visible = bow_time > 0
 weapon.visible = bow_time <= 0
 hand.global_position = muzzle()
 var direction := locked_direction if swing_time > 0 else Vector3(actor.facing.x, 0, actor.facing.y)
 if direction.cross(Vector3.UP).length() > 0.01: hand.look_at(hand.global_position + direction)
 if swing_time > 0:
  swing_time = maxf(0, swing_time - delta)
  var angle := lerpf(-35, 35, clampf((0.2 - swing_time/attack_duration*0.3) / 0.12, 0, 1))
  hand.rotate_object_local(Vector3.UP, deg_to_rad(angle))
  if swing_time/attack_duration*0.3 <= 0.2 and previous_angle < 35:
   strike(previous_angle, angle)
   previous_angle = angle

func strike(from_angle: float, to_angle: float) -> void:
 var samples := maxi(1, ceili(absf(to_angle - from_angle) / 3))
 for sample in samples + 1:
  var angle := lerpf(from_angle, to_angle, float(sample) / samples)
  var direction := locked_direction.rotated(Vector3.UP, deg_to_rad(angle))
  var hit := Trace.trace(get_world_3d(), muzzle(), muzzle() + direction * melee_range)
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
   var region: String = target.receive_strike(hit.position, hit.normal, direction, melee_damage) if target.is_in_group("tactical_enemies") else target.receive_strike(hit.position, hit.normal, direction)
   if notify.is_valid(): notify.call("近战命中：" + region)

func assisted_point(raw: Vector3, cursor: Vector2) -> Vector3:
 assist_target=null
 if not assist_enabled or actor.camera==null or Input.is_physical_key_pressed(KEY_SHIFT): return raw
 var best := 26.0
 var result := raw
 for enemy in get_tree().get_nodes_in_group("tactical_enemies"):
  if enemy.hp<=0: continue
  var target: Vector3=enemy.global_position+Vector3.UP*1.0
  if actor.camera.is_position_behind(target) or muzzle().distance_to(target)>16: continue
  var distance: float=actor.camera.unproject_position(target).distance_to(cursor)
  if distance>=best: continue
  var excluded: Array[RID]=[actor.get_rid(),enemy.get_rid()]
  var origin: Vector3=actor.camera.project_ray_origin(actor.camera.unproject_position(target))
  var sight := PhysicsRayQueryParameters3D.create(origin,target,1|4,excluded)
  if not get_world_3d().direct_space_state.intersect_ray(sight).is_empty(): continue
  sight.from=muzzle()
  if not get_world_3d().direct_space_state.intersect_ray(sight).is_empty(): continue
  # Keep deliberate head/top shots; assist only small misses outside the body.
  var raw_ray := PhysicsRayQueryParameters3D.create(actor.camera.project_ray_origin(cursor),actor.camera.project_ray_origin(cursor)+actor.camera.project_ray_normal(cursor)*100,1|4|16,[actor.get_rid()])
  var under_cursor := get_world_3d().direct_space_state.intersect_ray(raw_ray)
  if under_cursor.get("collider")==enemy:
   assist_target=enemy
   return raw
  best=distance
  result=target
  assist_target=enemy
 return result
