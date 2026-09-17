extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
 for i in count: await physics_frame
## 遍历蹲姿、坡道、方向与侧缘偏移，限制单帧高度跳变，检测碰撞修正问题。
func run() -> void:
 var lab = load("res://scenes/tactical_height.tscn").instantiate()
 ProjectSettings.set_setting("tactical/testing",true)
 root.add_child(lab)
 var actor = lab.player
 actor.test_mode = true
 var largest_step := 0.0
 for crouch in [false, true]:
  actor.test_crouch = crouch
  for slope in [[5.0, 2.0, -1.0, 1.0], [-7.0, 1.5, -6.0, -0.5]]:
   for side in [-1, 1]:
    for offset in [-0.27, -0.12, 0.0, 0.06, 0.12, 0.18, 0.27]:
     actor.test_motion = Vector2.ZERO
     actor.position = Vector3(slope[0] + side * (slope[1] + offset), slope[3] + 0.1, slope[2])
     actor.velocity = Vector3.ZERO
     await frames(20)
     var peak := 0.0
     for i in 180:
      actor.test_motion = Vector2(0, -1 if (i / 30 as int) % 2 == 0 else 1)
      var previous: Vector3 = actor.position
      await frames(1)
      peak = maxf(peak, absf(actor.position.y - previous.y))
     largest_step = maxf(largest_step, peak)
     checks += 1
     # 允许重力引起的正常下落；碰撞修正不能造成瞬间高度跳变。
     if peak > 0.2:
      failures += 1
      print("FAIL edge crouch=%s slope=%s side=%s offset=%s step=%s" % [crouch, slope[0], side, offset, peak])
 print("EDGE_REGRESSION: %d traces, %d failures; largest vertical step %.5f m" % [checks, failures, largest_step])
 quit(1 if failures else 0)
