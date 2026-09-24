extends SceneTree
## 实际GPU验证统一像素网格、低分辨率资产接入与UI背景；不读写玩家存档。
var lab:Node3D
var failures:=0
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(ok:bool,text:String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+text)
func frames(n:int) -> void:
	for i in n: await process_frame
func capture(id:String) -> Image:
	await frames(6)
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	image.save_png("res://work/art_unity_v4/"+id+".png")
	return image
func run() -> void:
	if DisplayServer.get_name()=="headless":
		print("SKIP ART_UNITY: 需要实际GPU像素截图，无头不算视觉验收")
		quit()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work/art_unity_v4"))
	ProjectSettings.set_setting("tactical/testing",true)
	lab=load("res://scenes/courtyard_combat.tscn").instantiate()
	root.add_child(lab)
	current_scene=lab
	while not is_instance_valid(lab.progression) or lab.objective.state==null: await process_frame
	lab.player.test_mode=true
	for enemy in get_nodes_in_group("tactical_enemies"):
		enemy.update_visuals(0)
		enemy.ai_enabled=false
	check(not lab.has_node("WorldPixelGrid"),"不再安装损伤文字和人物的整屏降采样")
	check(not lab.environment_pixels.enabled and lab.environment_pixels.unified_world,"停用仅环境采样的旧双标准")
	var kinds:={}
	var density_ok:=true
	for prop in lab.region.props:
		if prop.asset_id.begins_with("tree") or prop.asset_id=="wall_z":
			kinds[prop.asset_id]=true
			density_ok=density_ok and prop.art_material.get_shader_parameter("logical_size")== (prop.art.mesh.size*28).round()
	check(kinds.size()==4 and density_ok,"三树形与竖墙共用28逻辑像素每米")
	var image:=await capture("camp")
	# 世界应保留原显示细节，不再被强制压成同色2×2块；避开HUD区域。
	var mismatches:=0
	for y in range(180,440,2):
		for x in range(760,1200,2):
			var color:=image.get_pixel(x,y)
			if color!=image.get_pixel(x+1,y) or color!=image.get_pixel(x,y+1) or color!=image.get_pixel(x+1,y+1): mismatches+=1
	check(mismatches>1000,"实际截图保留原显示细节：非同色2×2块%d"%mismatches)
	check(lab.objective.labels.chest is Label and lab.objective.labels.chest.get_theme_font_size("font_size")==17,"宝箱名称独立以17px清晰文字绘制")
	lab.progression.toggle()
	await capture("inventory")
	check(lab.progression.view.panel.theme.default_font is SystemFont,"正文使用清晰CJK字体")
	check(not lab.progression.view.quick_bar.visible,"全幅背包不被快捷栏覆盖")
	lab.progression.toggle()
	for pair in [["wall_corner",Vector3(56,.03,-2)],["grove",Vector3(28,.03,20)],["meadow",Vector3(39,.03,14)],["ruin",Vector3(60,.03,-7)]]:
		lab.player.position=pair[1]
		await frames(30)
		await capture(pair[0])
	lab.player.position=Vector3(66,.03,-1)
	await frames(30)
	var text_size:Vector2=lab.objective.labels.chest.size
	await capture("wall_and_chest")
	lab.camera.size*=.65
	# 手动截图前禁用场景镜头更新，验证文字不随缩放改变尺寸。
	lab.set_physics_process(false)
	await frames(5)
	check(lab.objective.labels.chest.size==text_size,"镜头拉近时地点文字字号不变")
	await capture("wall_and_chest_zoom")
	lab.progression.open_container("supply")
	await capture("container")
	lab.progression.toggle()
	print("ART_UNITY: %d checks, %d failures"%[checks,failures])
	lab.queue_free()
	await frames(4)
	quit(1 if failures else 0)
