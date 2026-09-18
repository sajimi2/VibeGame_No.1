extends SceneTree
## 用隔离目录跑真实 PNG 往返、持久化、角色接入和工具交互，不触碰玩家覆盖资源或存档。
const Store = preload("res://scripts/art/atlas_store.gd")
const Document = preload("res://scripts/art/atlas_document.gd")
const Registry = preload("res://scripts/art/source_registry.gd")
const Spec = preload("res://scripts/art/frame_spec.gd")
const Art = preload("res://scripts/presentation/directional_art.gd")
const ArrowArt = preload("res://scripts/presentation/arrow_art.gd")
var checks := 0
var failures := 0
var directory := ""
var sources: Array[Resource]

func _initialize() -> void:
	if OS.get_cmdline_user_args().size() == 2 and OS.get_cmdline_user_args()[0] == "verify":
		verify_restart.call_deferred(OS.get_cmdline_user_args()[1])
	else: run.call_deferred()

## 独立新进程读取上次资源，证明生效不依赖预览进程的静态缓存。
func verify_restart(path: String) -> void:
	Store.root_path = path
	var data := Art.frame("player",Spec.character(3,5,false,9,0,-1,0,-1,0,true))
	check(data.grip == Vector2(20,25) and data.texture.get_image().get_pixel(16,20).is_equal_approx(Color8(175,65,211)),"新进程从磁盘恢复人物手绘帧与握点")
	check(ArrowArt.texture().get_image().get_pixel(15,5) == Color.MAGENTA,"新进程恢复箭矢手绘外形")
	print("ATLAS_RESTART: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+label)
func frames(count: int) -> void:
	for i in count: await physics_frame

func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func make_document(source: Resource, clip_id: String, options: Dictionary = {}) -> RefCounted:
	var document := Document.new()
	for clip in source.animations():
		if clip.id == clip_id: document.build(source,clip,options); break
	return document

## 覆盖每种现有来源/动作的导出协议；非人形箭没有十二列或握点，同一个工具仍可处理。
func source_contracts() -> void:
	check(sources.size() == 4,"自动发现玩家、守卫、弓手与箭矢四种来源")
	for source in sources:
		for clip in source.animations():
			var document := make_document(source,clip.id)
			var keys := {}
			for cell in document.cells: keys[cell.key] = true
			check(document.image.get_size() == source.cell_size*Vector2i(source.direction_count,int(clip.frames)) and keys.size() == document.cells.size(),source.asset_id+" / "+clip.id+" 原尺寸与帧键有效")
	var custom := sources[1].duplicate()
	custom.asset_id = "test_new_enemy"
	custom.title = "新增敌人"
	DirAccess.make_dir_recursive_absolute(directory.path_join("sources"))
	ResourceSaver.save(custom,directory.path_join("sources/new_enemy.tres"))
	var discovered := Registry.list_sources(directory.path_join("sources"))
	check(discovered.size() == 1 and discovered[0].asset_id == custom.asset_id,"只增加来源资源即可注册新敌人")

## 模拟外部软件改 PNG 和握点，重新读盘后检查多行裁片、隔离 ID 与资源重载。
func roundtrip() -> Dictionary:
	var document := make_document(sources[0],"run",{"move":6,"pose":0,"weight":0})
	var exported: Dictionary = document.export_to(directory)
	check(not exported.has("error"),"导出 PNG 与伴随 JSON")
	var checked := Store.inspect_package(exported.json)
	check(checked.image.get_size() == Vector2i(384,384),"原尺寸疾跑图集为 384×384")
	var pic: Image = checked.image
	# 每格放一个不同色标，既验证回导，也能捕获整除错误造成的跨行裁片。
	for row in 8:
		for column in 12: pic.set_pixel(column*32+16,row*48+20,Color8(100+row*15,20+column*15,211))
	checked.manifest.cells[5*12+3].anchors.grip = [19,24]
	pic.save_png(exported.png)
	write_json(exported.json,checked.manifest)
	var result := Store.import_package(exported.json)
	check(not result.has("error") and result.frames == 96,"编辑稿回导并持久化 96 帧")
	var matches := true
	for row in 8:
		for column in 12:
			var state := Spec.character(column,row,false,(column+6)%12,0,-1,0,-1,0,true)
			var data := Art.frame("player",state)
			matches = matches and data.texture.get_image().get_pixel(16,20).is_equal_approx(Color8(100+row*15,20+column*15,211))
	check(matches,"十二列八行的运行时帧均来自编辑后 PNG")
	var state := Spec.character(3,5,false,9,0,-1,0,-1,0,true)
	check(Art.frame("player",state).grip == Vector2(19,24),"手绘握点同时回导")
	check(Store.lookup("guard",Spec.key(state)).is_empty(),"玩家覆盖不会串到守卫")
	check(Store.lookup("player",Spec.key(Spec.character(3,-1,false))).is_empty(),"未导出的站立帧保留程序生成")
	Store.reload_catalog()
	check(Art.frame("player",state).grip == Vector2(19,24),"清空缓存后从资源目录重新加载覆盖")
	var loaded := Document.new()
	var load_error := loaded.load_package(Store.inspect_package(exported.json),sources)
	if not load_error.is_empty(): print("LOAD: "+load_error)
	check(load_error.is_empty() and loaded.image.get_data() == pic.get_data(),"预览文档载入实际编辑稿而非重新绘制程序图")
	# 第二次回导同一范围必须替换目录，不能因 Windows 文件已存在而失效。
	checked.manifest.cells[5*12+3].anchors.grip = [18,23]
	write_json(exported.json,checked.manifest)
	result = Store.import_package(exported.json)
	check(not result.has("error") and Store.catalog.sheets.size() == 1 and Art.frame("player",state).grip == Vector2(18,23),"重复回导替换生效且目录不累积整张旧覆盖")
	return exported

## 错误尺寸、帧键、版本和锚点都必须报错，原有效资源哈希保持不变。
func rejected_packages(exported: Dictionary) -> void:
	var original := Store.inspect_package(exported.json)
	var before := FileAccess.get_sha256(Store.root_path.path_join("catalog.tres"))
	for mode in ["version","duplicate","anchor","dimensions"]:
		var manifest: Dictionary = original.manifest.duplicate(true)
		if mode == "version": manifest.format = "unknown"
		if mode == "duplicate": manifest.cells[1].key = manifest.cells[0].key
		if mode == "anchor": manifest.cells[0].anchors.grip = [32,99]
		if mode == "dimensions": manifest.cell_size = [33,48]
		var path := directory.path_join("bad_"+mode+".json")
		write_json(path,manifest)
		check(Store.import_package(path).has("error") and FileAccess.get_sha256(Store.root_path.path_join("catalog.tres")) == before,"拒绝错误 "+mode+" 且不破坏现有覆盖")
	var changed: Dictionary = original.duplicate(true)
	changed.manifest.cells[0].key = "unknown_frame"
	check(not Document.new().load_package(changed,sources).is_empty(),"预览拒绝与来源不符的帧键")

## 回导箭侧影同时进入飞行箭和弓上展示箭；角色真实节点也必须采用回导纹理、握点和阴影。
func runtime_integration() -> void:
	var arrow_doc := make_document(sources[3],"profile")
	arrow_doc.image.set_pixel(15,5,Color.MAGENTA)
	var file: Dictionary = arrow_doc.export_to(directory)
	check(not Store.import_package(file.json).has("error"),"箭侧影复用相同回导流程")
	var arrow := ArrowArt.model()
	var bow := preload("res://scripts/presentation/weapon_art.gd").bow()
	check(arrow.material_override.albedo_texture.get_image().get_pixel(15,5) == Color.MAGENTA and bow.get_node("NockedArrow").material_override.albedo_texture == arrow.material_override.albedo_texture,"飞行箭和搭弓箭共享回导外形")
	arrow.free()
	bow.free()
	var lab = load("res://scenes/battlefield.tscn").instantiate()
	lab.results_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.player.test_mode = true
	while not is_instance_valid(lab.guard): await frames(1)
	for enemy in get_nodes_in_group("tactical_enemies"): enemy.ai_enabled = false
	lab.effects.streams.clear()
	var player = lab.player
	player.set_physics_process(false)
	lab.combat.set_physics_process(false)
	player.direction_index = 3
	player.movement_direction = 9
	player.sprinting = true
	player.jump_frame = -1
	player.crouch_blend = 0
	player._refresh_art(5)
	check(player.sprite.texture.get_image().get_pixel(16,20).is_equal_approx(Color8(175,65,211)) and player.grip_pixel == Vector2(18,23),"实际 Player 接入回导纹理与握点")
	check(player.world_shadow.texture == player.sprite.texture and player.outline.texture == Art.outline_texture(player.sprite.texture),"实际投影和遮挡轮廓使用手绘帧形体")
	var enemy_doc := make_document(sources[1],"idle")
	enemy_doc.image.set_pixel(16,20,Color.MAGENTA)
	file = enemy_doc.export_to(directory)
	Store.import_package(file.json)
	lab.guard.facing = Vector3.BACK.rotated(Vector3.UP,lab.camera.rotation.y)
	lab.guard.state = "guard"
	lab.guard.update_visuals(0)
	check(lab.guard.sprite.texture.get_image().get_pixel(16,20) == Color.MAGENTA,"实际守卫也解析自己的回导资产")
	check(Store.restore_asset("player") == OK and Store.lookup("player",Spec.key(Spec.character(3,5,false,9,0,-1,0,-1,0,true))).is_empty() and not Store.lookup("arrow","profile").is_empty(),"恢复玩家仅取消玩家覆盖，箭矢仍保留")
	lab.queue_free()
	await process_frame

## 测试界面的载入、选帧、握点修改与应用按钮调用链，避免只验证底层 API。
func viewer(exported: Dictionary) -> void:
	var ui = load("res://tools/art_preview.tscn").instantiate()
	root.add_child(ui)
	current_scene = ui
	await frames(2)
	ui.load_draft(exported.json)
	check(ui.document.settings.move == 6 and ui.action.selected == 2,"工具回读选项及十二方向疾跑编辑稿")
	ui.direction.select(3)
	ui.select_frame(5)
	ui.edit_grip.button_pressed = true
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = Vector2(20,25)*6+Vector2(1,1)
	ui.grip_input(event)
	check(ui.document.cells[5*12+3].anchors.grip == [20,25],"点击大图能修改当前帧握点")
	check(not ui.apply_atlas().has("error") and Art.frame("player",Spec.character(3,5,false,9,0,-1,0,-1,0,true)).grip == Vector2(20,25),"界面应用后运行时读取新握点")
	if DisplayServer.get_name() != "headless":
		await frames(2)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://work/atlas_workbench.png")
	ui.asset.select(3)
	ui.configure_source()
	check(ui.direction.item_count == 1 and ui.frame.max_value == 0 and ui.edit_grip.disabled,"箭矢共用查看器，无人物尺寸或握点硬编码")
	if DisplayServer.get_name() != "headless":
		await frames(2)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://work/arrow_workbench.png")
	ui.queue_free()
	await process_frame

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	directory = "res://work/atlas_test_%d_%d" % [int(Time.get_unix_time_from_system()),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(directory)
	Store.root_path = directory.path_join("overrides")
	Store.reload_catalog()
	sources = Registry.list_sources()
	source_contracts()
	var exported := roundtrip()
	rejected_packages(exported)
	await runtime_integration()
	await viewer(exported)
	var path_file := FileAccess.open("res://work/atlas_last_test_root.txt",FileAccess.WRITE)
	path_file.store_string(Store.root_path)
	path_file.close()
	print("ATLAS_PIPELINE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
