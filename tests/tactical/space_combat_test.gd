extends SceneTree
const Trace = preload("res://scripts/combat/space_trace.gd")
const Arrow = preload("res://scripts/combat/arrow.gd")
const Target = preload("res://scripts/world/training_target.gd")
var lab
var checks := 0
var failures := 0
func _initialize(): run.call_deferred()
func frames(count: int):
 for i in count: await physics_frame
func check(value: bool, message: String):
 checks += 1
 if not value: failures += 1
 print("%s %s" % ["PASS" if value else "FAIL", message])
func arrow(start: Vector3, velocity: Vector3):
 var shot = Arrow.new()
 lab.add_child(shot)
 shot.position = start
 shot.velocity = velocity
 return shot
func target(point: Vector3):
 var dummy = Target.new()
 lab.add_child(dummy)
 dummy.position = point
 return dummy
func capture(label: String):
 if DisplayServer.get_name() == "headless": return
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://work/combat_%s.png" % label)
## 布置空间命中样例，检查高差、顶部判定、墙阻挡和布帘穿透。
func run():
 lab = load("res://tests/fixtures/legacy/tactical_height.tscn").instantiate()
 lab.encounter_enabled = false
 ProjectSettings.set_setting("tactical/testing",true)
 root.add_child(lab)
 current_scene = lab
 lab.player.test_mode = true
 await frames(10)
 check(root.content_scale_size == Vector2i(1280, 720), "1280x720 render size")
 check(absf(rad_to_deg(lab.camera.rotation.y) - 25) < 0.1, "fixed 25 degree yaw")
 await capture("orthographic")
 await frames(3)
 check(lab.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "orthographic production camera")
 var projected_start: Vector2 = lab.camera.unproject_position(lab.player.position)
 var initial: Vector3 = lab.player.position
 lab.player.test_mode = false
 Input.action_press("move_up")
 await frames(8)
 Input.action_release("move_up")
 lab.player.test_mode = true
 var moved: Vector3 = lab.player.position - initial
 check(moved.dot(Vector3(lab.camera.global_basis.z.x,0,lab.camera.global_basis.z.z)) < -0.4, "W moves camera-relative forward")
 await capture("orthographic_moving")
 var wall = lab.get_node("StoneWall")
 var shot = arrow(Vector3(-3,1.5,3), Vector3(1000,0,0))
 await frames(3)
 check(shot.stopped and shot.result.get("collider") == wall, "fast arrow cannot tunnel through stone wall")
 var cloth = lab.get_node("ClothScreen")
 var line = Trace.trace(lab.get_world_3d(), Vector3(9,1.2,8), Vector3(9,1.2,2))
 check(line.get("penetrated",[]).size() == 1 and line.get("collider") == lab.get_node("ClothBackWall"), "cloth penetration still detects wall behind")
 var sight_query = PhysicsRayQueryParameters3D.create(Vector3(9,1.2,8),Vector3(9,1.2,5),4)
 check(not lab.get_world_3d().direct_space_state.intersect_ray(sight_query).is_empty(), "intact cloth blocks sight ray")
 for i in 3:
  var cloth_arrow = arrow(Vector3(9,1.2,8),Vector3(0,0,-45))
  await frames(9)
  check(cloth_arrow.stopped and cloth_arrow.result.get("collider") == lab.get_node("ClothBackWall"), "arrow passes cloth then stops at wall")
  check(int(cloth.get_meta("hits",0)) == i+1, "one projectile damages cloth once")
 check(cloth.collision_layer == 0, "three impacts break cloth")
 check(lab.get_world_3d().direct_space_state.intersect_ray(sight_query).is_empty(), "broken cloth no longer blocks sight")
 var dummy = target(Vector3(-12,0,10))
 await frames(2)
 var body_arrow = arrow(Vector3(-12,0.9,12), Vector3(0,0,-20))
 await frames(10)
 check(dummy.strikes == 1 and dummy.last_region == "身体", "horizontal arrow hits side")
 var top_arrow = arrow(Vector3(-12,3,10), Vector3(0,-20,0))
 await frames(8)
 check(dummy.strikes == 2 and dummy.last_region == "顶部", "descending arrow hits top")
 var over = Trace.trace(lab.get_world_3d(),Vector3(-8,2,1),Vector3(-4,2,1))
 check(not over.has("collider"), "high trajectory clears low cover")
 var under = Trace.trace(lab.get_world_3d(),Vector3(-8,0.8,1),Vector3(-4,0.8,1))
 check(under.has("collider"), "low trajectory blocked by low cover")
 lab.player.position = Vector3(-12,0.1,11.7)
 lab.player.velocity = Vector3.ZERO
 await frames(5)
 lab.combat.cooldown = 0
 lab.combat.attack(dummy.position + Vector3.UP)
 lab.player.test_motion = Vector2(0,-0.2)
 var start: Vector3 = lab.player.position
 await frames(24)
 lab.player.test_motion = Vector2.ZERO
 check(dummy.strikes == 3, "melee sweep hits each target once")
 check(lab.player.position.distance_to(start) > 0.2, "movement continues during swing")
 var high = target(Vector3(-12,4,10))
 await frames(2)
 lab.combat.cooldown = 0
 lab.combat.attack(high.position + Vector3.UP)
 await frames(24)
 check(high.strikes == 0, "melee cannot hit distant elevation")
 var behind = target(Vector3(0,0,3))
 lab.player.position = Vector3(-2,0.1,3)
 lab.player.velocity = Vector3.ZERO
 await frames(5)
 lab.combat.cooldown = 0
 lab.combat.attack(behind.position + Vector3.UP)
 await frames(24)
 check(behind.strikes == 0, "melee wall blocks target")
 lab.player.position = Vector3(8.3,2.1,-7)
 lab.player.velocity = Vector3.ZERO
 await frames(10)
 lab.combat.cooldown = 0
 lab.combat.apply_weapon(load("res://data/weapons/bow.tres"))
 var highshot = lab.combat.shoot(Vector3(10,1.5,-7))
 await frames(30)
 check(highshot.stopped and highshot.result.has("collider") and highshot.result.collider.has_method("receive_strike") and highshot.result.collider.last_region == "顶部", "actual platform shot hits lower target top")
 await capture("top_hit")
 lab.player.reset_position()
 # 把近战测试双方放到有效距离内，避免依赖展示地图的出生点。
 lab.player.position = Vector3(-5.3,0.1,5)
 lab.player.test_mode = false
 await frames(10)
 var near_dummy
 for child in lab.get_children():
  if child.has_method("receive_strike") and child.position.is_equal_approx(Vector3(-4,0,5)): near_dummy = child
 var count_before: int = near_dummy.strikes
 var screen_point: Vector2 = lab.camera.unproject_position(near_dummy.position + Vector3.UP)
 screen_point = root.get_final_transform() * screen_point
 var motion := InputEventMouseMotion.new()
 motion.position = screen_point
 motion.global_position = screen_point
 Input.parse_input_event(motion)
 await frames(3)
 lab.combat.cooldown = 0
 var click := InputEventMouseButton.new()
 click.button_index = MOUSE_BUTTON_LEFT
 click.position = screen_point
 click.global_position = screen_point
 click.pressed = true
 Input.parse_input_event(click)
 await frames(20)
 click = InputEventMouseButton.new()
 click.button_index = MOUSE_BUTTON_LEFT
 Input.parse_input_event(click)
 check(near_dummy.strikes > count_before, "mouse aiming and equipped bow left click fire through production input")
 lab.combat.cooldown = 0
 lab.combat.apply_weapon(load("res://data/weapons/knife.tres"))
 count_before = near_dummy.strikes
 click = InputEventMouseButton.new()
 click.button_index = MOUSE_BUTTON_LEFT
 click.position = screen_point
 click.global_position = screen_point
 click.pressed = true
 Input.parse_input_event(click)
 await frames(24)
 click = InputEventMouseButton.new()
 click.button_index = MOUSE_BUTTON_LEFT
 Input.parse_input_event(click)
 check(near_dummy.strikes == count_before + 1, "left click melee reaches aimed nearby target once")
 var key := InputEventKey.new()
 key.physical_keycode = KEY_V
 key.pressed = true
 Input.parse_input_event(key)
 await frames(2)
 check(lab.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "V leaves orthographic projection unchanged")
 print("SPACE_COMBAT: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)
