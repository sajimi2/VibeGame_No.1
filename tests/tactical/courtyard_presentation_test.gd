extends "res://tests/tactical/painted_courtyard_test.gd"
## 使用真实颜色/深度渲染验证树前误灰、装饰遮人和可见影子；节点存在不能替代这些检查。
func frame() -> Image:
	for i in 4: await process_frame
	RenderingServer.force_draw(false)
	return root.get_texture().get_image()

func gray_pixels(_image: Image) -> int:
	# 以灰显层开关的实际差分计数，避免屏幕后续调色让硬编码 RGB 失效。
	scene.player.set_physics_process(false)
	scene.combat.set_physics_process(false)
	for layer in scene.player.baked_visual.layers.values(): layer.occlusion.show()
	var shown:=await frame()
	for layer in scene.player.baked_visual.layers.values(): layer.occlusion.hide()
	var hidden:=await frame()
	for layer in scene.player.baked_visual.layers.values(): layer.occlusion.show()
	scene.player.set_physics_process(true)
	scene.combat.set_physics_process(true)
	var point: Vector2=scene.camera.unproject_position(scene.player.position+Vector3.UP*.9)
	var count:=0
	for y in range(maxi(0,int(point.y)-65),mini(shown.get_height(),int(point.y)+65)):
		for x in range(maxi(0,int(point.x)-40),mini(shown.get_width(),int(point.x)+40)):
			if shown.get_pixel(x,y)!=hidden.get_pixel(x,y): count+=1
	return count

func place(point: Vector3,focus: Vector3) -> void:
	scene.player.position=point
	scene.player.velocity=Vector3.ZERO
	for i in 35: await physics_frame
	scene.camera.position=scene.snapped_camera_position(focus+scene.camera.global_basis.z*26)
	scene.environment_pixels._process(0)

func differences(a: Image,b: Image) -> int:
	var count:=0
	for y in a.get_height():
		for x in a.get_width():
			var ca:=a.get_pixel(x,y)
			var cb:=b.get_pixel(x,y)
			if maxf(absf(ca.r-cb.r),maxf(absf(ca.g-cb.g),absf(ca.b-cb.b)))>.04: count+=1
	return count

func run() -> void:
	if DisplayServer.get_name()=="headless": print("SKIP presentation requires GPU"); quit(); return
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/painted_courtyard")
	scene=load("res://scenes/painted_courtyard.tscn").instantiate()
	root.add_child(scene)
	current_scene=scene
	scene.player.test_mode=true
	for i in 35: await physics_frame
	check(not scene.environment_pixels.enabled,"小院默认原始 1280×720")
	scene.set_physics_process(false)
	scene.hud.hide()
	scene.courtyard.ambience.animated=false
	var tree: Node3D=scene.courtyard.get_node("WestOak")
	var toward:=Vector3(scene.camera.basis.z.x,0,scene.camera.basis.z.z).normalized()
	await place(tree.position+toward*.95+Vector3.UP*.1,tree.position+Vector3.UP*1.6)
	var image:=await frame()
	var count:=await gray_pixels(image)
	check(count<3,"树干前人物不误灰：%d 像素"%count)
	image.save_png("res://work/painted_courtyard/tree_front_fixed.png")
	await place(tree.position-toward*.95+Vector3.UP*.1,tree.position+Vector3.UP*1.6)
	check(scene.wall_occlusion.reveal>.9,"树后大面积遮挡继续触发透视")
	# 暂停该物件透视以独立检查灰显深度；正常透视已清空中心时，不应期待还留灰人。
	tree.set_physics_process(false)
	tree.art_material.set_shader_parameter("wall_reveal",0.0)
	image=await frame()
	count=await gray_pixels(image)
	check(count>20,"树后仍保留局部灰显：%d 像素"%count)
	image.save_png("res://work/painted_courtyard/tree_back_fixed.png")
	tree.set_physics_process(true)
	var flower: Node3D=scene.courtyard.flowers[0]
	await place(flower.position+Vector3.UP*.1,flower.position+Vector3.UP*.8)
	image=await frame()
	count=await gray_pixels(image)
	check(count<3,"装饰花草不造成灰色遮挡：%d 像素"%count)
	image.save_png("res://work/painted_courtyard/flowers_fixed.png")
	scene.player.hide()
	scene.combat.hide()
	scene.camera.position=scene.snapped_camera_position(Vector3(0,2,5)+scene.camera.global_basis.z*26)
	var with_shadows:=await frame()
	with_shadows.save_png("res://work/painted_courtyard/shadows_fixed.png")
	for prop in scene.courtyard.props: prop.shadow.hide()
	var without_shadows:=await frame()
	var changed:=differences(with_shadows,without_shadows)
	check(changed>1000,"新资产确实投出可见阴影：%d 像素"%changed)
	without_shadows.save_png("res://work/painted_courtyard/no_shadows_compare.png")
	for prop in scene.courtyard.props: prop.shadow.show()
	for prop_name in ["Well","Cart","GateWallLeft"]:
		var prop: Node3D=scene.courtyard.get_node(prop_name)
		prop.shadow.hide()
		changed=differences(with_shadows,await frame())
		check(changed>10,prop_name+" 独立阴影可见：%d 像素"%changed)
		prop.shadow.show()
	scene.player.show()
	scene.combat.show()
	await place(Vector3(0,.1,0),Vector3(0,1,0))
	var all_hidden:=true
	for visual in scene.painting.original_layers: all_hidden=all_hidden and visual.layers==0 and visual.visible
	check(all_hidden and scene.painting.original_layers.size()>=8,"原内外墙/墙厚/地板退出颜色显示，几何检测节点仍存在")
	check(scene.painting.cards.size()==7,"内景三片与外墙/屋顶共同使用绘画")
	var floor_card: MeshInstance3D=scene.painting.get_node("PaintedInterior_floor")
	check(floor_card.material_override.get_shader_parameter("is_support"),"绘画地板不参与透视裁切")
	await shot("interior_fixed")
	await place(Vector3(0,.1,-4.2),Vector3(0,1,0))
	await shot("behind_fixed")
	print("COURTYARD_PRESENTATION: %d checks, %d failures"%[checks,failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
