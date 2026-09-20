extends SceneTree
## 隔离存档；用真实画面差分确认只粗化环境，并覆盖所有角色、原生全屏及暂停快捷键。
var scene: Node3D
var checks := 0
var failures := 0
var cards: Array[MeshInstance3D] = []
var actors: Array[Node3D] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+label)
func frames(n: int) -> void:
	for i in n: await process_frame
func screen() -> Image:
	await frames(3)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func key(echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F2
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	await frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

## 只隐藏彩色纸片，保留原阴影；因此前后差分准确表示角色/武器实际占据的像素。
func collect_cards(node: Node) -> void:
	if node is MeshInstance3D and node.visible and node.material_override is ShaderMaterial:
		var path: String = node.material_override.shader.resource_path
		if path.ends_with("baked_human.gdshader") or path.ends_with("pixel_weapon.gdshader") or path.ends_with("arrow_sprite.gdshader"):
			cards.append(node)
	for child in node.get_children(): collect_cards(child)
func freeze(node: Node) -> void:
	node.set_physics_process(false)
	node.set_process(false)
	for child in node.get_children(): freeze(child)

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/environment_resolution")
	scene = load("res://scenes/waystation_blockout.tscn").instantiate()
	scene.combat_enabled = false
	root.add_child(scene)
	current_scene = scene
	scene.player.test_mode = true
	scene.player.position = Vector3(0,.02,26)
	scene.update_camera_position()
	scene.set_physics_process(false)
	scene.player.set_physics_process(false)
	scene.combat.set_physics_process(false)
	scene.hud.hide()
	for label in scene.review_labels: label.hide()
	actors.append(scene.player)
	for id in ["guard","archer","skeleton","goblin","slime","golem"]:
		var creature: bool = id in ["goblin","slime","golem"]
		var actor = load("res://scripts/actors/creature.gd").new() if creature else load("res://scripts/actors/enemy.gd").new()
		if creature: actor.profile = load("res://data/enemies/"+id+".tres")
		actor.art_id = id
		actor.ranged = id=="archer"
		actor.ai_enabled = false
		actor.player = scene.player
		actor.camera = scene.camera
		actor.sunlight = scene.lighting.sun
		actor.effects = scene.effects
		scene.add_child(actor)
		actor.set_physics_process(false)
		actor.marker.hide()
		actor.health_bar.hide()
		actors.append(actor)
	for i in actors.size():
		var actor = actors[i]
		actor.position = Vector3(0,.02,26)+scene.camera.global_basis.x*(i-3)*2.3
		actor.occluded = false
		if i==0: actor._refresh_art(-1)
		else: actor.update_visuals(0)
	await frames(8)
	freeze(scene)
	scene.environment_pixels.set_process(true)
	collect_cards(scene)
	check(scene.environment_pixels.enabled,"默认启用环境粗像素")
	await key()
	check(not scene.environment_pixels.enabled,"F2 切回原始环境")
	await key(true)
	check(not scene.environment_pixels.enabled,"按键连发不反复切换")
	paused = true
	await key()
	check(scene.environment_pixels.enabled and paused,"暂停时 F2 仍可切换且不改变暂停状态")
	paused = false
	scene.environment_pixels.caption.hide()
	if DisplayServer.get_name()!="headless":
		await rendered("window")
		var previous: int = root.mode
		root.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		await frames(15)
		await rendered("fullscreen")
		root.mode = previous
	else: print("SKIP 无头模式不能验证画面精度")
	scene.queue_free()
	await frames(2)
	print("ENVIRONMENT_RESOLUTION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func rendered(prefix: String) -> void:
	var with_actor: Array[Image] = []
	var without_actor: Array[Image] = []
	for enabled in [false,true]:
		scene.environment_pixels.set_enabled(enabled,false)
		for card in cards: card.show()
		with_actor.append(await screen())
		for card in cards: card.hide()
		without_actor.append(await screen())
	for card in cards: card.show()
	for i in 2:
		with_actor[i].save_png("res://work/environment_resolution/"+prefix+("_original" if i==0 else "_coarse")+".png")
	var changed := 0
	for y in range(120,600):
		for x in range(20,1260):
			if without_actor[0].get_pixel(x,y)!=without_actor[1].get_pixel(x,y): changed+=1
	check(changed>15000,prefix+" 环境实际改变超过 15000 个像素")
	# 在没有角色/界面的地面区域核对真正的 2×2 色块，避免只改调色也能通过差分检查。
	var origin: Vector2 = scene.environment_pixels.material_override.get_shader_parameter("grid_origin")
	var groups := 0
	var equal_groups := 0
	for y in range(470+int(origin.y),600,2):
		for x in range(40+int(origin.x),1240,2):
			groups+=1
			var color: Color = without_actor[1].get_pixel(x,y)
			if color==without_actor[1].get_pixel(x+1,y) and color==without_actor[1].get_pixel(x,y+1) and color==without_actor[1].get_pixel(x+1,y+1): equal_groups+=1
	check(equal_groups>groups*.99,prefix+" 环境按世界锚定网格形成 2×2 同色像素块")
	for actor in actors:
		var center: Vector2 = scene.camera.unproject_position(actor.position+Vector3.UP)
		var count := 0
		var mismatch := 0
		for y in range(int(center.y)-90,int(center.y)+85):
			for x in range(int(center.x)-52,int(center.x)+52):
				var original: Color = with_actor[0].get_pixel(x,y)
				var coarse: Color = with_actor[1].get_pixel(x,y)
				var a: bool = original!=without_actor[0].get_pixel(x,y)
				var b: bool = coarse!=without_actor[1].get_pixel(x,y)
				if a or b:
					count+=1
					if a!=b or original!=coarse: mismatch+=1
		print(prefix," ",actor.baked_visual.asset_id," occupied/mismatch=",count,"/",mismatch)
		check(count>50 and mismatch==0,prefix+" "+actor.baked_visual.asset_id+" 身体与武器逐像素相同")
