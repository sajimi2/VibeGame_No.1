extends SceneTree
## 当前 96² 身体与箭矢的真实导出/回导；拒绝坏清单，检查重启持久化和工作台操作。
const Store = preload("res://scripts/art/atlas_store.gd")
const Document = preload("res://scripts/art/atlas_document.gd")
const Registry = preload("res://scripts/art/source_registry.gd")
const ArrowArt = preload("res://scripts/presentation/arrow_art.gd")
var checks := 0
var failures := 0
var directory := ""
var sources: Array[Resource]

func _initialize() -> void:
	if OS.get_cmdline_user_args().size()==2:
		verify_restart.call_deferred(OS.get_cmdline_user_args()[1])
	else: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+label)
func write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
func make_document(source: Resource, clip: String, settings := {}) -> RefCounted:
	var document := Document.new()
	for action in source.animations():
		if action.id==clip: document.build(source,action,settings); break
	return document

## 独立进程只读持久化结果，避免静态缓存造成回导成功的假象。
func verify_restart(path: String) -> void:
	Store.root_path=path
	var entry:=Store.lookup("player_baked","upper/light_ready/3/0/0",Vector2i(96,96))
	check(not entry.is_empty() and Vector2(entry.anchors.grip[0],entry.anchors.grip[1])==Vector2(50,48),"新进程恢复 96² 身体覆盖与握点")
	check(ArrowArt.texture().get_image().get_pixel(15,5)==Color.MAGENTA,"新进程恢复箭矢覆盖")
	print("ATLAS_RESTART: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	directory="res://work/atlas_current_%d"%Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	Store.root_path=directory+"/overrides"
	Store.reload_catalog()
	sources=Registry.list_sources()
	check(sources.size()==5 and sources.filter(func(s): return s.asset_id.ends_with("_baked")).size()==4,"只发现四种当前烘焙角色和箭矢，没有过时二维人物入口")
	var source: Resource=sources[0]
	var document:=make_document(source,"idle",{"part":"upper","ready":"light_ready","move":0,"gait":-1})
	check(document.image.get_size()==Vector2i(1152,96),"十二朝向原尺寸为 1152×96")
	for y in document.image.get_height():
		for x in document.image.get_width():
			if document.image.get_pixel(x,y).a>.5: document.image.set_pixel(x,y,Color8(175,65,211))
	document.cells[3].anchors.grip=[49,48]
	check(source.validate_edit(document).is_empty(),"修改已有轮廓内颜色可回导")
	var exported: Dictionary=document.export_to(directory)
	check(not exported.has("error"),"PNG 与伴随清单真实写入磁盘")
	var result:=Store.import_package(exported.json)
	check(not result.has("error") and result.frames==12,"十二方向上身覆盖持久化")
	var grip: Array=Store.lookup("player_baked",document.cells[3].binding,Vector2i(96,96)).anchors.grip
	check(Vector2(grip[0],grip[1])==Vector2(49,48),"运行时绑定使用编辑后握点")
	check(Store.lookup("guard_baked",document.cells[3].binding).is_empty(),"玩家覆盖不串到守卫")
	check(Store.lookup("player_baked",document.cells[3].binding,Vector2i(64,64)).is_empty(),"不同单格尺寸不会错误混用")
	Store.reload_catalog()
	check(not Store.lookup("player_baked",document.cells[3].binding).is_empty(),"清空缓存后从磁盘重新加载")
	var loaded:=Document.new()
	check(loaded.load_package(Store.inspect_package(exported.json),sources).is_empty() and loaded.image.get_data()==document.image.get_data(),"工作台读回实际编辑稿")
	var checked:=Store.inspect_package(exported.json)
	var before:=FileAccess.get_sha256(Store.root_path+"/catalog.tres")
	for mode in ["version","duplicate","anchor","dimensions","binding"]:
		var data: Dictionary=checked.manifest.duplicate(true)
		match mode:
			"version": data.format="bad"
			"duplicate": data.cells[1].key=data.cells[0].key
			"anchor": data.cells[0].anchors.grip=[96,99]
			"dimensions": data.cell_size=[64,64]
			"binding": data.cells[1].binding=data.cells[0].binding; data.cells[1].anchors.grip=[1,1]
		var path: String=directory+"/bad_"+mode+".json"
		write_json(path,data)
		check(Store.import_package(path).has("error") and FileAccess.get_sha256(Store.root_path+"/catalog.tres")==before,"拒绝错误 "+mode+" 且保留有效覆盖")
	var wrong:=checked.duplicate(true)
	wrong.manifest.cells[0].key="unknown"
	check(not Document.new().load_package(wrong,sources).is_empty(),"拒绝被改写的帧键")
	var foreign:=source.duplicate()
	foreign.asset_id="future_enemy_baked"
	DirAccess.make_dir_recursive_absolute(directory+"/sources")
	ResourceSaver.save(foreign,directory+"/sources/enemy.tres")
	check(Registry.list_sources(directory+"/sources").size()==1,"新敌人通过来源资源注册，不修改查看器")
	var arrow_doc:=make_document(sources.back(),"profile")
	arrow_doc.image.set_pixel(15,5,Color.MAGENTA)
	check(not Store.import_package(arrow_doc.export_to(directory).json).has("error"),"箭矢复用原尺寸回导")
	var arrow:=ArrowArt.model()
	var bow:=preload("res://scripts/presentation/weapon_art.gd").bow()
	check(arrow.material_override.albedo_texture.get_image().get_pixel(15,5)==Color.MAGENTA and bow.get_node("NockedArrow").material_override.albedo_texture==arrow.material_override.albedo_texture,"飞行箭和搭弓箭共用编辑稿")
	arrow.free()
	bow.free()
	var ui: Control=load("res://tools/art_preview.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	ui.load_draft(exported.json)
	ui.direction.select(3)
	ui.edit_grip.button_pressed=true
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	event.position=Vector2(50,48)*4+Vector2.ONE
	ui.grip_input(event)
	check(ui.document.cells[3].anchors.grip==[50,48],"实际工作台点击修改 96² 握点")
	check(not ui.apply_atlas().has("error") and Store.catalog.sheets.size()==2,"重复回导替换原覆盖，不堆积重复目录项")
	ui.asset.select(sources.size()-1)
	ui.configure_source()
	check(ui.direction.item_count==1 and ui.edit_grip.disabled,"箭矢查看没有人物朝向和握点假设")
	ui.queue_free()
	await process_frame
	# 身体实际 shader/阴影/握点由 baked_player 和 skeleton_pipeline 同时检查。
	var output: Array=[]
	var code:=OS.execute(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/tactical/atlas_pipeline_test.gd","--","verify",Store.root_path],output,true)
	check(code==0,"新引擎进程读取持久化覆盖成功")
	check(Store.restore_asset("player_baked")==OK and Store.lookup("player_baked",document.cells[3].binding).is_empty() and not Store.lookup("arrow","profile").is_empty(),"恢复玩家不影响箭矢覆盖")
	print("ATLAS_PIPELINE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
