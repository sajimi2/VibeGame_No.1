extends SceneTree
## 只输出固定相机的配准草图，不编辑保存的 Blender 源。
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(768,768)
	viewport.own_world_3d=true
	viewport.transparent_bg=true
	root.add_child(viewport)
	var model: Node3D=load("res://assets/environment/experiments/cottage/cottage_shell.glb").instantiate()
	viewport.add_child(model)
	for part in model.find_children("*","MeshInstance3D",true,false):
		var material:=StandardMaterial3D.new()
		material.albedo_color=Color("a1adae") if str(part.name).begins_with("Roof") else Color("d4ccae")
		part.material_override=material
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-55,-30,0)
	viewport.add_child(light)
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE
	env.environment.ambient_light_energy=.6
	viewport.add_child(env)
	var camera:=Camera3D.new()
	viewport.add_child(camera)
	camera.rotation_degrees=Vector3(-35,25,0)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=11.6
	camera.position=Vector3(0,1.6,0)+camera.basis.z*26
	camera.current=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	for i in 5: await process_frame
	RenderingServer.force_draw(false)
	DirAccess.make_dir_recursive_absolute("res://assets/environment/experiments/painted_cottage")
	viewport.get_texture().get_image().save_png("res://assets/environment/experiments/painted_cottage/guide.png")
	quit()
