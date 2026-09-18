extends RefCounted
## 以像素为单位描述关节；同一姿态同时供人物绘制和武器握点使用，不参与伤害或移动碰撞。
const SIZE := Vector2i(32, 48)
const FOOT_Y := 45.0
const CROUCH_FRAMES := 6
## 关节先在身体局部空间计算；+Z 始终是胸口/脚尖前方，之后才按瞄准朝向投影。
const BODY_FRONT := Vector3(0, 0, 1)

## 将角色局部关节投到固定斜视角纸片；每 30 度一个方向，脚底基准始终不变。
static func project(point: Vector3, angle: float) -> Vector2:
	var rotated := point.rotated(Vector3.UP, angle)
	return Vector2(16 + rotated.x, FOOT_Y - point.y + rotated.z * 0.48).round()

## 生成站立、步行、疾跑、跳跃和上肢动作；移动方向独立于持械朝向。
## jump_frame：-1 无跳跃，0 蹬地、1 收腿上升、2 顶点、3 下落伸腿、4 落地缓冲。
static func build(direction: int, step: int, crouch: bool, move_direction: int = -1, pose: int = 0, arm_phase: int = -1, weight: int = 0, draw_phase: int = -1, crouch_frame: int = -1, running: bool = false, jump_frame: int = -1) -> Dictionary:
	var angle := posmod(direction, 12) * PI / 6
	var amount := float(CROUCH_FRAMES if crouch else 0) / CROUCH_FRAMES if crouch_frame < 0 else clampf(float(crouch_frame) / CROUCH_FRAMES, 0, 1)
	var phase := maxf(step, 0) / 8.0 * TAU
	var walking := step >= 0
	var walk_angle := (direction if move_direction < 0 else move_direction) * PI / 6
	var run := running and amount < 0.1 and jump_frame < 0
	var travel_axis := Vector3(0, 0, 1).rotated(Vector3.UP, walk_angle - angle)
	var bob := absf(sin(phase)) * 0.65 if walking else 0.0
	if run: bob = cos(phase * 2) * 1.4
	var compression: float = [2.2, 0.0, 0.5, 0.0, 3.8][jump_frame] if jump_frame >= 0 else 0.0
	var pelvis := Vector3(0, lerpf(22, 11, amount) - bob, -3.5 * amount)
	var chest := Vector3(0, lerpf(33, 21, amount) - bob, 1.8 * amount + weight * 0.7)
	pelvis.y -= compression
	chest.y -= compression
	if run: chest += travel_axis * 2.8
	var neck := chest + Vector3(0, 2.7, 0.3)
	var head := neck + Vector3(0, 3.4, 0.3)
	var joints := {"pelvis": pelvis, "chest": chest, "neck": neck, "head": head}
	for side in [-1, 1]:
		var cycle := phase + (PI if side < 0 else 0.0)
		var stride := cos(cycle) * lerpf(4.0, 2.0, amount) if walking else 0.0
		var lift := maxf(0, sin(cycle)) * lerpf(2.8, 1.0, amount) if walking else 0.0
		if run:
			stride = cos(cycle) * 8.2
			lift = maxf(0, sin(cycle)) * 7.0
		var travel := Vector3(0, 0, stride).rotated(Vector3.UP, walk_angle - angle)
		var hip := pelvis + Vector3(side * 2.3, 0, 0)
		var foot := Vector3(side * lerpf(2.5, 3.6, amount), 1.5 + lift, 0.5) + travel
		if run: foot.y += absf(cos(cycle)) * 2.5
		var knee := hip.lerp(foot, 0.52) + Vector3(0, -0.8 * amount, 6.5 * amount + 0.8)
		# 移动方向只决定迈步落点，膝盖必须朝身体前方折，后退/横移时也不能翻转。
		if run: knee += BODY_FRONT * maxf(0, sin(cycle)) * 3.5
		if jump_frame >= 0:
			# 起跳与落地弯膝，腾空时前后腿错开；不靠拉伸整张纹理表示跳跃。
			var lift_y: float = [0.0, 5.5 if side > 0 else 3.0, 4.0, 1.0, 0.0][jump_frame]
			foot = Vector3(side * 2.9, 1.5 + lift_y, 0.5) + travel_axis * (side * 2.0 if jump_frame in [1, 2] else 0.0)
			knee = hip.lerp(foot, 0.52) + BODY_FRONT * (5.0 if jump_frame in [0, 1, 2, 4] else 1.5)
		joints["hip%d" % side] = hip
		joints["knee%d" % side] = knee
		joints["foot%d" % side] = foot
		joints["toe%d" % side] = foot + Vector3(0, -0.4, 2.0)
	var swing: float = lerpf(-0.9, 0.8, arm_phase / 24.0) if arm_phase >= 0 else {1: -0.9, 2: 0.8, 3: 0.4}.get(pose, 0.0)
	var grip := chest + Vector3(2.2 + sin(swing) * 5.0, -7.0 + (1.5 if pose > 0 else 0.0), 5.0 + cos(swing) * 1.5)
	var support := chest + Vector3(-5.0, -9.0, 0.5)
	if pose in [1, 2, 3]: support = grip + Vector3(-3, -0.5, -1.3)
	elif walking: support += Vector3(0, sin(phase) * (2.0 if run else 0.8), sin(phase) * (5.0 if run else 2.0))
	if pose == 0 and run: grip += Vector3(0, -sin(phase) * 1.5, -sin(phase) * 2.0)
	if pose == 0 and jump_frame in [0, 1, 2]:
		grip.y += 2.0
		support += Vector3(-1.0, 3.0, 1.5)
	if pose == 4:
		var draw := 1.0 if draw_phase < 0 else draw_phase / 8.0
		support = chest + Vector3(-1.3, -4.0, 8.0)
		grip = support.lerp(chest + Vector3(2, -2.0, 1.0), draw)
	for side in [-1, 1]:
		var shoulder := chest + Vector3(side * 4.8, -0.5, 0)
		var hand := grip if side > 0 else support
		var elbow := shoulder.lerp(hand, 0.5) + Vector3(side * 1.3, -2.3, -0.7)
		joints["shoulder%d" % side] = shoulder
		joints["elbow%d" % side] = elbow
		joints["hand%d" % side] = hand
	var pixels := {}
	for key in joints: pixels[key] = project(joints[key], angle)
	var far_side := -1 if sin(angle) < 0 else 1
	return {"joints": joints, "pixels": pixels, "angle": angle, "crouch": amount, "far_side": far_side,
		"grip": pixels["hand-1" if pose == 4 else "hand1"]}

## 从纸片纹理像素反求世界握点；朝相机微移，防止握柄与纸片产生深度闪烁。
static func world_grip(sprite: Sprite3D, camera: Camera3D, pixel: Vector2) -> Vector3:
	var offset := Vector2(pixel.x - SIZE.x * 0.5, SIZE.y - pixel.y) * sprite.pixel_size
	var up := Vector3.UP * preload("res://scripts/presentation/character_billboard.gd").height_scale(camera)
	return sprite.global_position + camera.global_basis.x * offset.x + up * offset.y + camera.global_basis.z * 0.018
