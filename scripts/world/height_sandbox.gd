extends "res://scripts/world/level.gd"
## 保留的 3D 试验场，用于验证高差、掩体、布帘和通行路线。

## 拼接平地、低洼、高台和坡道，构成高度回归测试环境。
func _build_ground() -> void:
	# 低洼范围为 x[-10,-4]、z[-8,-2]，周围拼接可行走地面。
	box("NorthGround", Vector3(0, -0.5, -11), Vector3(32, 1, 6), "grass")
	box("SouthGround", Vector3(0, -0.5, 6), Vector3(32, 1, 16), "grass")
	box("WestGround", Vector3(-13, -0.5, -5), Vector3(6, 1, 6), "grass")
	box("EastGround", Vector3(6, -0.5, -5), Vector3(20, 1, 6), "grass")
	box("Depression", Vector3(-7, -1.5, -5), Vector3(6, 1, 6), "soil")
	ramp("DepressionExit", Vector3(-7, -1, -4), 3, 4, 1)
	natural_ledge("HighPlatform", Vector3(5, 0, -7), PackedVector2Array([
		Vector2(-4, -1.8), Vector2(-3.2, -3), Vector2(-1.1, -3.35),
		Vector2(0.5, -2.9), Vector2(2.8, -3.2), Vector2(3.7, -1.8),
		Vector2(4, 0.4), Vector2(3.5, 2), Vector2(2, 3),
		Vector2(-2, 3), Vector2(-3.8, 2.1), Vector2(-4.3, 0.4)]), 2.0)
	natural_ledge("LowRockShelf", Vector3(12.5, 0, -10.5), PackedVector2Array([
		Vector2(-1.6, -0.8), Vector2(-0.5, -1.6), Vector2(1, -1.3),
		Vector2(1.7, -0.2), Vector2(1.3, 1.1), Vector2(-0.8, 1.1),
		Vector2(-1.7, 0.4)]), 0.8)
	ramp("RockShelfAccess", Vector3(12.5, 0, -7.4), 1.5, 2, 0.8)
	_label("岩台 +0.8m", Vector3(12.5, 1.05, -10.5))
	ramp("HighRamp", Vector3(5, 0, 2), 4, 6, 2)
	for x in [-16.25, 16.25]: box("Boundary", Vector3(x, 0.5, 0), Vector3(0.5, 3, 28), "wall")
	for z in [-14.25, 14.25]:
		box("Boundary", Vector3(0, 0.5 if z < 0 else -0.3, z), Vector3(32, 3 if z < 0 else 1.6, 0.5), "wall")
	_label("土坡高地 +2m", Vector3(5, 2.05, -8))
	_label("坡道", Vector3(5, 0.5, 1))
	_label("低洼 -1m", Vector3(-7, -0.8, -5))

## 生成墙、布帘、树冠和低梁，分别覆盖通行、视野、箭穿透与净空场景。
func _build_props() -> void:
	box("StoneWall", Vector3(-1, 1.6, 3), Vector3(0.65, 3.2, 5), "wall")
	box("LowCover", Vector3(-6, 0.6, 1), Vector3(4, 1.2, 0.6), "wall")
	var cloth := box("ClothScreen", Vector3(9, 1.2, 6), Vector3(4, 2.4, 0.08), "cloth", 4 | 8)
	cloth.set_meta("penetrable", true)
	box("ClothBackWall", Vector3(9, 1.4, 3.8), Vector3(4, 2.8, 0.4), "wall")
	for x in [7.0, 11.0]: box("ClothPost", Vector3(x, 1.3, 6), Vector3(0.14, 2.6, 0.14), "wood")
	# 低梁用于验证：头顶受阻时不能站起穿模。
	box("LowBeam", Vector3(-10, 1.4, 6), Vector3(3, 0.4, 2), "wood")
	for x in [-11.6, -8.4]: box("BeamPost", Vector3(x, 0.7, 6), Vector3(0.2, 1.4, 2), "wood")
	for location in [Vector3(-12, 0, 0), Vector3(12, 0, -3), Vector3(2, 0, 9), Vector3(-12.5, 0, 10)]:
		var trunk := box("Tree", location + Vector3(0, 1, 0), Vector3(0.55, 2, 0.55), "wood")
		trunk.get_child(1).hide()
		var sprite := Sprite3D.new()
		sprite.texture = Art.tree()
		sprite.pixel_size = 0.075
		sprite.position = location
		sprite.offset = Vector2(0, 30)
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		Lighting.tree_shadow(self,location)
		# 树冠参与视野与相机遮挡，不阻挡脚下移动。
		var canopy := box("Canopy", location + Vector3(0, 2.7, 0), Vector3(2.8, 2.8, 0.15), "grass", 4)
		canopy.get_child(1).hide()
	_label("矮墙 · 按住 C 下蹲", Vector3(-6, 1.5, 1))
	_label("石墙 · 绕行", Vector3(-1, 3.6, 3))
	_label("布帘 · 穿箭 / 三次破损", Vector3(9, 2.8, 6))
	_label("低梁 · 蹲下通过", Vector3(-10, 2, 6))

## 组合试验场基础地形和装饰，按开关添加任务路线。
func _build_environment() -> void:
	_build_ground()
	_build_props()
	preload("res://scripts/world/sandbox_art.gd").build(self)
	if encounter_enabled and mission_enabled:
		# 低断栏提供跳跃捷径，贴地移动的敌人需要绕行。
		box("JumpFence",Vector3(-4,0.21,2),Vector3(3.0,0.42,0.20),"wood")
		_label("断栏 · 空格短跳 / 两侧绕行",Vector3(-4,0.8,2))
		preload("res://scripts/world/sandbox_route.gd").build(self)

func spawn_point() -> Vector3: return Vector3(-3.5,0.1,11)
func objective_point() -> Vector3: return Vector3(4.3,2,-6.1)
func navigation_bounds() -> Rect2: return Rect2(-15,-15.6,30,31.2)
func level_title() -> String: return "林间废弃哨站 / 夺回密函"

## 任务模式生成守卫与弓手，单遭遇模式只生成一名守卫。
func enemy_layout() -> Array:
	return [{"position":Vector3(-5,0,-0.9)},{"position":Vector3(6,2,-7.8),"ranged":true}] if mission_enabled else [{"position":Vector3(2,0,-0.5)}]

## 非完整任务模式下创建训练靶，并把说明文字纳入标注开关。
func _build_targets() -> void:
	var points := [] if encounter_enabled and mission_enabled else [Vector3(-4, 0, 5), Vector3(5, 2, -7), Vector3(10, 0, -7), Vector3(12.5, 0, 7)]
	for point in points:
		var target := preload("res://scripts/world/training_target.gd").new()
		target.position = point
		add_child(target)
		target.feedback.add_to_group("sample_annotations")
		target.feedback.visible = false
