extends Node3D
## Composition root: constructs systems and supplies their dependencies.
## Map subclasses provide geometry, spawn points and encounter specifications.
const Actor = preload("res://scripts/actors/player.gd")
const Art = preload("res://scripts/presentation/directional_art.gd")
var player: CharacterBody3D
var camera: Camera3D
var terrain: RefCounted
var hud: CanvasLayer
var stylized := true
var combat: Node3D
var last_feedback := "空格短跳 · E 取得密函 · 留意弓箭手的瞄准动作"
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
const Lighting = preload("res://scripts/presentation/world_lighting.gd")

func _ready() -> void:
	terrain = preload("res://scripts/world/terrain_builder.gd").new(self)
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
	_build_environment()
	effects = preload("res://scripts/presentation/encounter_effects.gd").new()
	add_child(effects)
	player = Actor.new()
	player.effects = effects
	player.name = "Explorer"
	player.spawn = spawn_point()
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
	hud = preload("res://scripts/ui/game_hud.gd").new()
	add_child(hud)
	hud.setup(level_title())
	_build_targets()
	combat = preload("res://scripts/combat/player_combat.gd").new()
	add_child(combat)
	combat.setup(player, func(message: String): last_feedback = message)
	if encounter_enabled: start_encounter.call_deferred()

func _physics_process(_delta: float) -> void:
	update_camera_position()
	var message := "你已倒下 · 按 R 重置" if player.hp <= 0 else "守卫已击败 · 按 R 重置遭遇" if not mission_enabled and is_instance_valid(guard) and guard.hp <= 0 else last_feedback
	hud.update_status(player.hp, player.max_hp, player.position.y, player.crouched, player.occluded, message)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R: get_tree().reload_current_scene()
		if event.physical_keycode == KEY_F1:
			for label in get_tree().get_nodes_in_group("sample_annotations"): label.visible = not label.visible
		if event.physical_keycode == KEY_B: toggle_shading()
		if event.physical_keycode == KEY_ESCAPE: get_tree().quit()

func update_camera_position() -> void:
	camera.position = snapped_camera_position(player.position + camera.global_basis.z * 26.0)

func snapped_camera_position(desired: Vector3) -> Vector3:
	# Quantize only the render camera, never physics or aiming coordinates.
	var pixel := camera.size / float(get_window().content_scale_size.y)
	var local := camera.global_basis.inverse() * desired
	local.x = snappedf(local.x, pixel)
	local.y = snappedf(local.y, pixel)
	return camera.global_basis * local

func toggle_shading() -> void:
	stylized = not stylized
	for material_value in terrain.materials.values():
		material_value.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON if stylized else BaseMaterial3D.DIFFUSE_BURLEY
	last_feedback = "分段明暗" if stylized else "连续明暗 · 对比模式"

func start_encounter() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame
	routes = preload("res://scripts/world/terrain_routes.gd").new()
	add_child(routes)
	routes.build(get_world_3d(),navigation_bounds())
	for spec in enemy_layout():
		var enemy=preload("res://scripts/actors/enemy.gd").new()
		enemy.ranged=spec.get("ranged",false)
		enemy.max_hp=40 if enemy.ranged else 60
		enemy.hp=enemy.max_hp
		enemy.home=spec.position
		enemy.position=enemy.home+Vector3.UP*0.05
		enemy.player=player
		enemy.camera=camera
		enemy.routes=routes
		enemy.effects=effects
		add_child(enemy)
		if enemy.ranged and not is_instance_valid(archer):
			archer=enemy
			enemy.name="OutpostArcher"
		elif not enemy.ranged and not is_instance_valid(guard): guard=enemy
	# Static navigation ignores actor bodies, while actual locomotion still
	# collides with them. This avoids sampling a path endpoint on a teammate.
	for enemy in get_tree().get_nodes_in_group("tactical_enemies"):
		for teammate in get_tree().get_nodes_in_group("tactical_enemies"):
			if not enemy.navigation_excluded.has(teammate.get_rid()): enemy.navigation_excluded.append(teammate.get_rid())
	if mission_enabled:
		objective=preload("res://scripts/world/objective.gd").new()
		objective.player=player
		objective.exit_point=spawn_point()*Vector3(1,0,1)
		objective.pickup_point=objective_point()
		add_child(objective)
		progression=preload("res://scripts/progression/camp_progress.gd").new()
		progression.setup(player, combat)
		progression.persist=progress_enabled
		add_child(progression)
		objective.progress=progression
		if results_enabled:
			run_flow=preload("res://scripts/ui/run_screen.gd").new()
			run_flow.setup(player, objective, progression, combat_hint)
			add_child(run_flow)

func spawn_point() -> Vector3:
	return Vector3.ZERO

func objective_point() -> Vector3:
	return Vector3.ZERO

func navigation_bounds() -> Rect2:
	return Rect2(-15, -15.6, 30, 31.2)

func level_title() -> String:
	return "Outpost RPG"

func enemy_layout() -> Array:
	return []

func combat_hint() -> String: return ""

func material(kind: String) -> StandardMaterial3D:
	return terrain.material(kind)

func box(label: String, center: Vector3, size: Vector3, kind: String, layers: int = 13) -> StaticBody3D:
	return terrain.box(label, center, size, kind, layers)

func ramp(label: String, origin: Vector3, width: float, length: float, rise: float) -> void:
	terrain.ramp(label, origin, width, length, rise)

func natural_ledge(label: String, origin: Vector3, outline: PackedVector2Array, height: float) -> void:
	terrain.natural_ledge(label, origin, outline, height)

func _label(text: String, where: Vector3) -> void:
	terrain._label(text, where)

func _build_environment() -> void:
	pass

func _build_targets() -> void:
	pass
