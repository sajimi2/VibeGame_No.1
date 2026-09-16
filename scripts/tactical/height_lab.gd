extends Node3D
## Isolated spatial prototype. No production save, inventory or quest mutation.
const Actor = preload("res://scripts/tactical/height_actor.gd")
const Art = preload("res://scripts/tactical/directional_art.gd")
var player: CharacterBody3D
var camera: Camera3D
var status: Label
var notice: Label
var perspective := false
var combat: Node3D
var feedback: Label
var last_feedback := "左键挥刀 / 右键射箭：瞄准训练靶身体或金色顶部"
var materials: Dictionary = {}

func _ready() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size = Vector2i(960, 540)
	RenderingServer.set_default_clear_color(Color("202e36"))
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("202e36")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b9cbd4")
	environment.ambient_light_energy = 0.65
	environment_node.environment = environment
	add_child(environment_node)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-55, -30, 0)
	sunlight.light_color = Color("ffe4b5")
	sunlight.light_energy = 0.9
	sunlight.shadow_enabled = true
	add_child(sunlight)
	_build_ground()
	_build_props()
	player = Actor.new()
	player.name = "Explorer"
	add_child(player)
	player.reset_position()
	camera = Camera3D.new()
	camera.name = "FixedAngleCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17
	camera.far = 160
	process_physics_priority = 10
	add_child(camera)
	camera.position = player.position + camera.global_basis.z * (40.0 if perspective else 26.0)
	camera.rotation_degrees = Vector3(-35, 25, 0)
	camera.position = player.position + camera.global_basis.z * 26
	camera.current = true
	player.camera = camera
	_build_ui()
	_build_targets()
	combat = preload("res://scripts/tactical/lab_combat.gd").new()
	add_child(combat)
	combat.setup(player, func(message: String): last_feedback = message)

func _physics_process(_delta: float) -> void:
	camera.position = player.position + camera.global_basis.z * (40.0 if perspective else 26.0)
	feedback.text = last_feedback
	status.text = ("弱透视" if perspective else "斜角正交") + "  |  高度 %.2f m  ·  %s  ·  %s" % [player.position.y, "下蹲" if player.crouched else "站立", "遮挡轮廓" if player.occluded else "可见"]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R: get_tree().reload_current_scene()
		if event.physical_keycode == KEY_V: toggle_camera()
		if event.physical_keycode == KEY_ESCAPE: get_tree().quit()

func material(kind: String) -> StandardMaterial3D:
	if materials.has(kind): return materials[kind]
	var palette := {"grass": Color("536448"), "stone": Color("778184"), "wall": Color("626b72"), "path": Color("988468"), "soil": Color("514a3e"), "wood": Color("796349"), "cloth": Color("985b4f")}
	var base: Color = palette.get(kind, Color.GRAY)
	var image := Image.create(32, 32, false, Image.FORMAT_RGB8)
	image.fill(base)
	for y in 32:
		for x in 32:
			var shade := (x * 37 + y * 19 + x * y) % 47
			if kind in ["wall", "stone"] and (y % 8 == 0 or (x + (y / 8 as int) * 8) % 16 == 0):
				image.set_pixel(x, y, base.darkened(0.27))
			elif shade < 3: image.set_pixel(x, y, base.lightened(0.12))
	var result := StandardMaterial3D.new()
	result.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	result.albedo_texture = ImageTexture.create_from_image(image)
	result.uv1_triplanar = true
	result.uv1_scale = Vector3(0.5, 0.5, 0.5)
	materials[kind] = result
	return result

func box(label: String, center: Vector3, size: Vector3, kind: String, layers: int = 13) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = center
	body.collision_layer = layers
	body.collision_mask = 0
	add_child(body)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material(kind)
	body.add_child(visual)
	return body

func ramp(label: String, origin: Vector3, width: float, length: float, rise: float) -> void:
	# Wedge rises toward -Z, with exactly matching mesh and collision vertices.
	var vertices := PackedVector3Array([
		Vector3(-width / 2, 0, 0), Vector3(width / 2, 0, 0),
		Vector3(-width / 2, 0, -length), Vector3(width / 2, 0, -length),
		Vector3(-width / 2, rise, -length), Vector3(width / 2, rise, -length)])
	var body := StaticBody3D.new()
	body.name = label
	body.position = origin
	body.collision_layer = 13
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = vertices
	collision.shape = shape
	body.add_child(collision)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in [0, 1, 5, 0, 5, 4, 2, 4, 5, 2, 5, 3, 0, 4, 2, 1, 3, 5, 0, 2, 3, 0, 3, 1]:
		surface.add_vertex(vertices[index])
	surface.generate_normals()
	var visual := MeshInstance3D.new()
	visual.mesh = surface.commit()
	var mat := material("path").duplicate() as StandardMaterial3D
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	visual.material_override = mat
	body.add_child(visual)

func _build_ground() -> void:
	# Rectangular depression x[-10,-4], z[-8,-2], surrounded by walkable ground.
	box("NorthGround", Vector3(0, -0.5, -11), Vector3(32, 1, 6), "grass")
	box("SouthGround", Vector3(0, -0.5, 6), Vector3(32, 1, 16), "grass")
	box("WestGround", Vector3(-13, -0.5, -5), Vector3(6, 1, 6), "grass")
	box("EastGround", Vector3(6, -0.5, -5), Vector3(20, 1, 6), "grass")
	box("Depression", Vector3(-7, -1.5, -5), Vector3(6, 1, 6), "soil")
	ramp("DepressionExit", Vector3(-7, -1, -4), 3, 4, 1)
	box("HighPlatform", Vector3(5, 1, -7), Vector3(8, 2, 6), "stone")
	ramp("HighRamp", Vector3(5, 0, 2), 4, 6, 2)
	for x in [-16.25, 16.25]: box("Boundary", Vector3(x, 0.5, 0), Vector3(0.5, 3, 28), "wall")
	for z in [-14.25, 14.25]: box("Boundary", Vector3(0, 0.5, z), Vector3(32, 3, 0.5), "wall")
	_label("高台 +2m", Vector3(5, 2.05, -8))
	_label("坡道", Vector3(5, 0.5, 1))
	_label("低洼 -1m", Vector3(-7, -0.8, -5))

func _build_props() -> void:
	box("StoneWall", Vector3(-1, 1.6, 3), Vector3(0.65, 3.2, 5), "wall")
	box("LowCover", Vector3(-6, 0.6, 1), Vector3(4, 1.2, 0.6), "wall")
	var cloth := box("ClothScreen", Vector3(9, 1.2, 6), Vector3(4, 2.4, 0.08), "cloth", 4 | 8)
	cloth.set_meta("penetrable", true)
	box("ClothBackWall", Vector3(9, 1.4, 3.8), Vector3(4, 2.8, 0.4), "wall")
	for x in [7.0, 11.0]: box("ClothPost", Vector3(x, 1.3, 6), Vector3(0.14, 2.6, 0.14), "wood")
	# Low beam verifies that standing up cannot clip into solid ceilings.
	box("LowBeam", Vector3(-10, 1.4, 6), Vector3(3, 0.4, 2), "wood")
	for x in [-11.6, -8.4]: box("BeamPost", Vector3(x, 0.7, 6), Vector3(0.2, 1.4, 2), "wood")
	for location in [Vector3(-12, 0, 0), Vector3(12, 0, -3), Vector3(2, 0, 9)]:
		var trunk := box("Tree", location + Vector3(0, 1, 0), Vector3(0.55, 2, 0.55), "wood")
		trunk.get_child(1).hide()
		var sprite := Sprite3D.new()
		sprite.texture = Art.tree()
		sprite.pixel_size = 0.075
		sprite.position = location + Vector3(0, 2.25, 0)
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		# Canopy occludes sight/camera but does not block feet.
		var canopy := box("Canopy", location + Vector3(0, 2.7, 0), Vector3(2.8, 2.8, 0.15), "grass", 4)
		canopy.get_child(1).hide()
	_label("矮墙 · 按住 C 下蹲", Vector3(-6, 1.5, 1))
	_label("石墙 · 绕行", Vector3(-1, 3.6, 3))
	_label("布帘 · 穿箭 / 三次破损", Vector3(9, 2.8, 6))
	_label("低梁 · 蹲下通过", Vector3(-10, 2, 6))

func _label(text: String, where: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 24
	label.pixel_size = 0.026
	label.outline_size = 6
	label.modulate = Color("eddbac")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# World annotations are UI: terrain must not cut off their lower half.
	label.no_depth_test = true
	label.render_priority = 20
	label.position = where
	add_child(label)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := ColorRect.new()
	panel.color = Color(0.05, 0.08, 0.10, 0.88)
	panel.position = Vector2(10, 10)
	panel.size = Vector2(545, 94)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	var title := Label.new()
	title.text = "立体战术试验场 / 02 高度攻击与弹道"
	title.position = Vector2(18, 14)
	title.add_theme_font_size_override("font_size", 20)
	title.modulate = Color("eddbac")
	layer.add_child(title)
	status = Label.new()
	status.position = Vector2(18, 40)
	status.add_theme_font_size_override("font_size", 16)
	layer.add_child(status)
	notice = Label.new()
	notice.text = "WASD 移动 · C 下蹲 · 左键挥刀 · 右键射箭 · V 切换镜头\nR 重置试验场 · Esc 退出 | 金色靶顶可从上方命中；本轮尚无敌人 AI"
	notice.position = Vector2(16, 492)
	notice.add_theme_font_size_override("font_size", 14)
	notice.add_theme_color_override("font_shadow_color", Color.BLACK)
	notice.add_theme_constant_override("shadow_offset_x", 1)
	notice.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(notice)

func toggle_camera() -> void:
	perspective = not perspective
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE if perspective else Camera3D.PROJECTION_ORTHOGONAL
	camera.fov = rad_to_deg(2 * atan(17.0 / 80.0))
	camera.position = player.position + camera.global_basis.z * (40.0 if perspective else 26.0)

func _build_targets() -> void:
	for point in [Vector3(-4, 0, 5), Vector3(5, 2, -7), Vector3(10, 0, -7), Vector3(12.5, 0, 7)]:
		var target := preload("res://scripts/tactical/training_target.gd").new()
		target.position = point
		add_child(target)
	feedback = Label.new()
	feedback.position = Vector2(18, 70)
	feedback.add_theme_font_size_override("font_size", 14)
	feedback.modulate = Color("ebcd84")
	status.get_parent().add_child(feedback)
