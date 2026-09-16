extends Node3D
## Tactical level; original four-scene game and its save remain separate.
const Actor = preload("res://scripts/tactical/height_actor.gd")
const Art = preload("res://scripts/tactical/directional_art.gd")
var player: CharacterBody3D
var camera: Camera3D
var status: Label
var notice: Label
var stylized := true
var combat: Node3D
var feedback: Label
var last_feedback := "空格短跳 · E 取得密函 · 留意弓箭手的瞄准动作"
var materials: Dictionary = {}
var encounter_enabled := true
var progression: Node
var progress_enabled := true
var mission_enabled := true
var archer: CharacterBody3D
var objective: Node3D
var guard: CharacterBody3D
var effects: Node3D
var routes: Node
var results_enabled := true
var run_flow: CanvasLayer
var lighting: Node3D
const Lighting = preload("res://scripts/tactical/world_lighting.gd")

func _ready() -> void:
	if ProjectSettings.get_setting("tactical/testing",false): progress_enabled=false
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size = Vector2i(1280, 720)
	get_window().min_size = Vector2i(1280, 720)
	get_window().content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	RenderingServer.set_default_clear_color(Color("202e36"))
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("202e36")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b9cbd4")
	environment.ambient_light_energy = 0.48
	environment_node.environment = environment
	add_child(environment_node)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-55, -30, 0)
	sunlight.light_color = Color("ffe4b5")
	sunlight.light_energy = 0.8
	sunlight.shadow_enabled = true
	add_child(sunlight)
	lighting = Lighting.new()
	add_child(lighting)
	lighting.pixel_material=Lighting.pixel_pass(self)
	lighting.setup(sunlight,environment)
	_build_ground()
	_build_props()
	preload("res://scripts/tactical/outpost_sample.gd").build(self)
	if encounter_enabled and mission_enabled:
		# A low broken fence offers a jump shortcut; grounded agents go around.
		box("JumpFence",Vector3(-4,0.21,2),Vector3(3.0,0.42,0.20),"wood")
		_label("断栏 · 空格短跳 / 两侧绕行",Vector3(-4,0.8,2))
		preload("res://scripts/tactical/outpost_route.gd").build(self)
	effects = preload("res://scripts/tactical/encounter_effects.gd").new()
	add_child(effects)
	player = Actor.new()
	player.effects = effects
	player.name = "Explorer"
	player.spawn = Vector3(-3.5, 0.1, 11)
	add_child(player)
	player.reset_position()
	camera = Camera3D.new()
	camera.name = "FixedAngleCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17
	camera.far = 160
	process_physics_priority = 10
	add_child(camera)
	camera.rotation_degrees = Vector3(-35,25,0)
	update_camera_position()
	camera.current = true
	player.camera = camera
	_build_ui()
	_build_targets()
	combat = preload("res://scripts/tactical/lab_combat.gd").new()
	add_child(combat)
	combat.setup(player, func(message: String): last_feedback = message)
	if encounter_enabled: start_encounter.call_deferred()

func _physics_process(_delta: float) -> void:
	update_camera_position()
	feedback.text = "你已倒下 · 按 R 重置" if player.hp<=0 else "守卫已击败 · 按 R 重置遭遇" if not mission_enabled and is_instance_valid(guard) and guard.hp<=0 else last_feedback
	status.text = ("斜角正交 · 生命 %d/%d" % [player.hp,player.max_hp]) + "  |  高度 %.2f m  ·  %s  ·  %s" % [player.position.y, "下蹲" if player.crouched else "站立", "遮挡轮廓" if player.occluded else "可见"]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R: get_tree().reload_current_scene()
		if event.physical_keycode == KEY_F1:
			for label in get_tree().get_nodes_in_group("sample_annotations"): label.visible = not label.visible
		if event.physical_keycode == KEY_B: toggle_shading()
		if event.physical_keycode == KEY_ESCAPE: get_tree().quit()

func material(kind: String) -> StandardMaterial3D:
	if materials.has(kind): return materials[kind]
	var palette := {"grass": Color("536448"), "stone": Color("778184"), "wall": Color("626b72"), "path": Color("988468"), "soil": Color("514a3e"), "wood": Color("796349"), "cloth": Color("985b4f"), "wood_frame": Color("4e4032")}
	var base: Color = palette.get(kind, Color.GRAY)
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	image.fill(base)
	var texture_rng := RandomNumberGenerator.new()
	texture_rng.seed = 7319 + kind.hash()
	for y in 64:
		for x in 64:
			var shade := int(texture_rng.randi() % 47)
			if kind in ["wall","stone"]:
				var row := y/16 as int
				var brick_x := (x+row*16)%32
				var brick_tone := ((x+row*16)/32 as int + row*3)%3
				var color := base.darkened(brick_tone*0.045)
				if y%16==0 or brick_x==0: color=base.darkened(0.32)
				elif y%16 in [1,2] or brick_x==1: color=base.lightened(0.12)
				elif y%16==15 or brick_x==31: color=base.darkened(0.14)
				image.set_pixel(x,y,color)
			elif kind == "wood":
				var grain := sin(float(x/2)*2.2+sin(float(y)*0.15))
				image.set_pixel(x,y,base.darkened(0.16) if grain>0.65 else base)
			elif kind in ["soil","path","grass"]:
				# Broad pixel clusters, no fine white noise or continuous gradients.
				var cx := x/8 as int
				var cy := y/8 as int
				var cluster := sin(cx*1.73+sin(cy*0.83)*2.0)+cos(cy*1.32-cx*0.37)
				var color := base.lightened(0.04) if cluster>1.2 else base.darkened(0.045) if cluster< -1.2 else base
				if kind=="grass": color=base.lightened(0.018) if cluster>1.65 else base.darkened(0.02) if cluster< -1.65 else base
				if kind=="soil":
					var band := (y+int(3*sin(cx*0.7)))%20
					if band<2: color=base.darkened(0.22)
				image.set_pixel(x,y,color)
			elif shade<2: image.set_pixel(x,y,base.lightened(0.055))
	var result := StandardMaterial3D.new()
	result.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	result.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	result.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	result.roughness = 1.0
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
	surface.set_smooth_group(-1)
	for index in [0, 1, 5, 0, 5, 4, 2, 4, 5, 2, 5, 3, 0, 4, 2, 1, 3, 5, 0, 2, 3, 0, 3, 1]:
		surface.add_vertex(vertices[index])
	surface.generate_normals()
	var visual := MeshInstance3D.new()
	visual.mesh = surface.commit()
	var mat := material("path")
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	visual.material_override = mat
	body.add_child(visual)

func natural_ledge(label: String, origin: Vector3, outline: PackedVector2Array, height: float) -> void:
	# Flat cap and irregular sides use the same mesh for rendering and collision.
	# Keep the south lip aligned with the access ramp.
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	top.set_smooth_group(-1)
	var indices := Geometry2D.triangulate_polygon(outline)
	for i in range(0, indices.size(), 3):
		for j in [0, 1, 2]:
			var point := outline[indices[i + j]]
			top.add_vertex(Vector3(point.x, height, point.y))
	top.generate_normals()
	top.set_material(material("grass"))
	var mesh := top.commit()
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	sides.set_smooth_group(-1)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var ring_a := Vector3(a.x, height, a.y)
		var ring_b := Vector3(b.x, height, b.y)
		var middle_a := Vector3(a.x * (1.04 + 0.02 * (i % 3)), height * (0.42 + 0.05 * (i % 3)), a.y)
		var middle_b := Vector3(b.x * (1.04 + 0.02 * (((i + 1) % outline.size()) % 3)), height * (0.42 + 0.05 * (((i + 1) % outline.size()) % 3)), b.y)
		var foot_a := Vector3(a.x * 1.1, 0, a.y)
		var foot_b := Vector3(b.x * 1.1, 0, b.y)
		for vertex in [ring_a, middle_b, ring_b, ring_a, middle_a, middle_b,
			middle_a, foot_b, middle_b, middle_a, foot_a, foot_b]:
			sides.add_vertex(vertex)
	sides.generate_normals()
	sides.set_material(material("soil"))
	sides.commit(mesh)
	var body := StaticBody3D.new()
	body.name = label
	body.position = origin
	body.collision_layer = 13
	body.collision_mask = 0
	add_child(body)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)

func _build_ground() -> void:
	# Rectangular depression x[-10,-4], z[-8,-2], surrounded by walkable ground.
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
	label.add_to_group("sample_annotations")
	label.visible = false
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
	panel.size = Vector2(700, 94)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	var title := Label.new()
	title.text = "林间废弃哨站 / 夺回密函"
	title.position = Vector2(18, 14)
	title.add_theme_font_size_override("font_size", 20)
	title.modulate = Color("eddbac")
	layer.add_child(title)
	status = Label.new()
	status.position = Vector2(18, 40)
	status.add_theme_font_size_override("font_size", 16)
	layer.add_child(status)
	notice = Label.new()
	notice.text = "WASD 移动 · 空格短跳 · C 下蹲 · 左键挥刀 · 右键射箭 · E 交互 · I 背包\nShift 精确射击 · R 重新出发（保留装备） · Esc 退出 · F1 标注 · B 明暗对比"
	notice.position = Vector2(16, 662)
	notice.add_theme_font_size_override("font_size", 14)
	notice.add_theme_color_override("font_shadow_color", Color.BLACK)
	notice.add_theme_constant_override("shadow_offset_x", 1)
	notice.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(notice)

func update_camera_position() -> void:
	camera.position = snapped_camera_position(player.position + camera.global_basis.z * 26.0)

func snapped_camera_position(desired: Vector3) -> Vector3:
	# Quantize only the render camera, never physics or aiming coordinates.
	var pixel := camera.size / float(get_window().content_scale_size.y)
	var local := camera.global_basis.inverse() * desired
	local.x = snappedf(local.x, pixel)
	local.y = snappedf(local.y, pixel)
	return camera.global_basis * local

func _build_targets() -> void:
	var points := [] if encounter_enabled and mission_enabled else [Vector3(-4, 0, 5), Vector3(5, 2, -7), Vector3(10, 0, -7), Vector3(12.5, 0, 7)]
	for point in points:
		var target := preload("res://scripts/tactical/training_target.gd").new()
		target.position = point
		add_child(target)
		target.feedback.add_to_group("sample_annotations")
		target.feedback.visible = false
	feedback = Label.new()
	feedback.position = Vector2(18, 70)
	feedback.add_theme_font_size_override("font_size", 14)
	feedback.modulate = Color("ebcd84")
	status.get_parent().add_child(feedback)


func toggle_shading() -> void:
	stylized = not stylized
	for material_value in materials.values():
		material_value.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON if stylized else BaseMaterial3D.DIFFUSE_BURLEY
	last_feedback = "分段明暗" if stylized else "连续明暗 · 对比模式"

func start_encounter() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame
	routes = preload("res://scripts/tactical/terrain_routes.gd").new()
	add_child(routes)
	routes.build(get_world_3d())
	guard = preload("res://scripts/tactical/outpost_guard.gd").new()
	guard.player = player
	guard.camera = camera
	guard.routes = routes
	guard.effects = effects
	if mission_enabled: guard.home=Vector3(-5.0,0,-0.9)
	guard.position = guard.home+Vector3.UP*0.05
	add_child(guard)

	if mission_enabled:
		archer=preload("res://scripts/tactical/outpost_guard.gd").new()
		archer.ranged=true
		archer.hp=40
		archer.max_hp=40
		archer.home=Vector3(6.0,2,-7.8)
		archer.position=archer.home+Vector3.UP*0.05
		archer.player=player
		archer.camera=camera
		archer.routes=routes
		archer.effects=effects
		add_child(archer)
		archer.name="OutpostArcher"
		objective=preload("res://scripts/tactical/outpost_objective.gd").new()
		objective.player=player
		add_child(objective)
		progression=preload("res://scripts/tactical/camp_progress.gd").new()
		progression.lab=self
		progression.persist=progress_enabled
		add_child(progression)
		objective.progress=progression
		if results_enabled:
			run_flow=preload("res://scripts/tactical/outpost_run.gd").new()
			run_flow.lab=self
			add_child(run_flow)
