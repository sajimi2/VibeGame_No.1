extends "res://tests/tactical/courtyard_presentation_test.gd"
## 除配置一致性外，用真实白底投影检查深浅/柔边，并检查平移、风摆和旧投影恢复。
const Shadow=preload("res://scripts/presentation/illustration_shadow.gd")

func run() -> void:
	if DisplayServer.get_name()=="headless": print("SKIP shadow style requires GPU"); quit(); return
	ProjectSettings.set_setting("tactical/testing",true)
	scene=load("res://scenes/painted_courtyard.tscn").instantiate()
	root.add_child(scene)
	current_scene=scene
	for i in 35: await physics_frame
	scene.set_physics_process(false)
	scene.player.set_physics_process(false)
	scene.combat.set_physics_process(false)
	scene.player.hide()
	scene.combat.hide()
	scene.hud.hide()
	scene.courtyard.ambience.animated=false
	scene.camera.position=scene.snapped_camera_position(Vector3(0,2,5)+scene.camera.global_basis.z*26)
	var style=Shadow.DEFAULT_STYLE
	var all_shared: bool=scene.painting.ground_shadow.style==style
	for prop in scene.courtyard.props:
		all_shared=all_shared and prop.shadow.style==style and is_equal_approx(prop.shadow.material_override.get_shader_parameter("strength"),style.opacity)
	check(all_shared,"房屋与所有实物共用样式和覆盖率")
	var ray: Vector3=-scene.lighting.sun.global_basis.z
	check((Vector2(ray.x,ray.z)/-ray.y).is_equal_approx(style.offset_per_height),"人物实时投影与环境体量投影世界光向一致")
	check(is_equal_approx(scene.lighting.sun.shadow_opacity,style.opacity),"人物实时投影强度同步")
	var proxies_hidden:=true
	for visual in scene.painting.original_casters:
		proxies_hidden=proxies_hidden and visual.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if scene.painting.original_casters[visual].casting==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			proxies_hidden=proxies_hidden and visual.layers==0
	check(proxies_hidden,"旧房屋阴影代理既不投影，也不重新露出灰瓦顶")
	var overview:=await frame()
	overview.save_png("res://work/painted_courtyard/unified_shadows.png")
	scene.painting.ground_shadow.hide()
	check(differences(overview,await frame())>100,"房屋新影形确实进入画面")
	scene.painting.ground_shadow.show()
	scene.painting.set_enabled(false)
	var restored: bool=not scene.painting.ground_shadow.visible
	for visual in scene.painting.original_casters:
		restored=restored and visual.cast_shadow==scene.painting.original_casters[visual].casting
	check(restored,"旧外观对比恢复旧投影，关闭新影形")
	scene.painting.set_enabled(true)
	check(differences(overview,await frame())==0,"切回新外观没有遗留或双重阴影")
	var tree: Node3D=scene.courtyard.get_node("WestOak")
	var body_pose: Transform3D=tree.body.global_transform
	var rid: RID=tree.shadow.mesh.get_rid()
	tree.set_visual_sway(Vector2(.10,-.03))
	var sway_frame:=await frame()
	check(differences(overview,sway_frame)>10,"风摆入口确实改变画稿和地面影子")
	check(tree.body.global_transform==body_pose and tree.shadow.mesh.get_rid()==rid,"风摆不动碰撞、不重建阴影网格")
	tree.set_visual_sway(Vector2(1,0))
	check(is_equal_approx(tree.shadow.sway_world.length(),style.max_sway),"风摆限幅与地面承载面留白一致")
	tree.set_visual_sway(Vector2.ZERO)
	check(differences(overview,await frame())==0,"风摆归零逐像素恢复原画面")
	var old_position: Vector3=tree.position
	tree.position+=Vector3(.35,0,.2)
	await frame()
	var foot: Vector2=tree.shadow.material_override.get_shader_parameter("foot_origin")
	check(foot.is_equal_approx(Vector2(tree.global_position.x,tree.global_position.z)),"平移自动同步影子锚点")
	check(tree.art_material.get_shader_parameter("prop_origin")==tree.global_position,"平移自动同步画稿深度锚点")
	tree.position=old_position

	# 在远离院子的白色平地上分别绘树与房屋，测量实际浓度和过渡区而非只检查材质值。
	var anchor:=Node3D.new()
	anchor.position=Vector3(60,0,0)
	scene.add_child(anchor)
	var ground:=MeshInstance3D.new()
	var plane:=PlaneMesh.new()
	plane.size=Vector2(30,30)
	ground.mesh=plane
	var white:=StandardMaterial3D.new()
	white.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	ground.material_override=white
	ground.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	anchor.add_child(ground)
	scene.camera.position=scene.snapped_camera_position(anchor.position+scene.camera.global_basis.z*26)
	var clean:=await frame()
	var peaks: Array[float]=[]
	for id in ["cottage","oak","new_asset_without_profile"]:
		var shadow:=Shadow.new()
		anchor.add_child(shadow)
		shadow.setup(id,1.0,Vector3(2,3,2))
		var shown:=await frame()
		shown.save_png("res://work/painted_courtyard/shadow_probe_"+id+".png")
		var peak:=0.0
		var soft:=0
		for y in shown.get_height():
			for x in shown.get_width():
				var delta: float=clean.get_pixel(x,y).r-shown.get_pixel(x,y).r
				peak=maxf(peak,delta)
				if delta>.025 and delta<.1: soft+=1
		peaks.append(peak)
		check(peak>.10 and peak<.30 and soft>30,id+" 实际浅影与柔边：峰值 %.3f，过渡 %d 像素"%[peak,soft])
		shadow.queue_free()
		await process_frame
	check(absf(peaks[0]-peaks[1])<.01 and absf(peaks[0]-peaks[2])<.01,"房屋/树/新资产在同底色上实际投影浓度一致")
	anchor.queue_free()
	print("COURTYARD_SHADOW_STYLE: %d checks, %d failures"%[checks,failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
