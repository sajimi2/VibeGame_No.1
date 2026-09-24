extends SceneTree
## 一次性迁移工具：只在尚未存在可编辑地图时运行，拒绝覆盖用户摆放。
const TARGET="res://scenes/courtyard_combat.tscn"
const PREFABS="res://scenes/props/"
var library: Dictionary={}
var sizes: Dictionary={}
var lab: Node3D
func _initialize() -> void: run.call_deferred()

func own_branch(node: Node, scene: Node) -> void:
	var index:=0
	for child in node.get_children():
		index+=1
		if str(child.name).begins_with("@"):
			child.name=child.get_class()+str(index)
		child.owner=scene
		child.scene_file_path=""
		own_branch(child,scene)

func save_raw(node: Node, path: String) -> void:
	node.scene_file_path=""
	own_branch(node,node)
	var scene:=PackedScene.new()
	assert(scene.pack(node)==OK)
	assert(ResourceSaver.save(scene,path)==OK)

func prop_instance(source: Node3D) -> Node3D:
	var id: String=source.asset_id+("_grounded" if source.has_node("GroundContact") else "")
	var pose: Transform3D=source.transform
	if not library.has(id):
		var original_name:=source.name
		source.name=id.to_pascal_case()
		source.transform=Transform3D.IDENTITY
		sizes[id]=source.built_scale
		save_raw(source,PREFABS+id+".tscn")
		library[id]=load(PREFABS+id+".tscn")
		source.name=original_name
		source.transform=pose
	var result: Node3D=library[id].instantiate()
	result.name=source.name
	result.transform=pose.scaled_local(Vector3.ONE*(source.built_scale/float(sizes[id])))
	return result

func run() -> void:
	var existing=load(TARGET).instantiate()
	if existing.has_node("Map"):
		existing.free()
		push_error("已存在可编辑Map；迁移工具拒绝覆盖。请直接编辑tscn。")
		quit(1)
		return
	existing.free()
	DirAccess.make_dir_recursive_absolute(PREFABS)
	ProjectSettings.set_setting("tactical/testing",true)
	lab=load(TARGET).instantiate()
	root.add_child(lab)
	for i in 240:
		await physics_frame
		if is_instance_valid(lab.objective) and is_instance_valid(lab.objective.state): break
	assert(is_instance_valid(lab.objective.state))
	lab.name="MigrationSource"
	lab.player.test_mode=true
	for enemy in get_nodes_in_group("tactical_enemies"): enemy.ai_enabled=false
	await process_frame
	var output:=Node3D.new()
	output.name="CourtyardCombat"
	root.add_child(output)
	var map:=Node3D.new()
	map.name="Map"
	output.add_child(map)
	map.owner=output
	var ground:=Node3D.new()
	ground.name="Ground"
	map.add_child(ground)
	ground.owner=output
	for child in lab.get_children():
		if child is StaticBody3D and child.get_meta("occlusion_role","")=="support":
			child.reparent(ground)
			if str(child.name).begins_with("@"): child.name="MeadowMargin"+str(ground.get_child_count())
			child.owner=output
			own_branch(child,output)
	for collection in [lab.courtyard,lab.region]:
		collection.reparent(map)
		collection.owner=output
		collection.authored_layout=true
		for child in collection.get_children():
			if child.get_script()==preload("res://scripts/presentation/courtyard_ambience.gd"):
				child.free()
			elif child.get_script()==preload("res://scripts/presentation/illustrated_prop.gd"):
				var instance:=prop_instance(child)
				child.free()
				collection.add_child(instance)
				instance.owner=output
			else:
				if str(child.name).begins_with("@"): child.name=child.get_class()+str(child.get_index())
				child.owner=output
				own_branch(child,output)
	# 小屋把现有灰模、承托、七片绘画和屋顶全部落盘，不把保存画面当运行时截图。
	var cottage: Node3D=lab.cottage
	for visual in lab.painting.original_layers:
		visual.set_meta("original_layers",lab.painting.original_layers[visual])
	for piece in cottage.roof.pieces:
		piece.set_meta("original_layers",lab.painting.roof_layers[piece.get_instance_id()])
	cottage.roof.authored_geometry=true
	save_raw(cottage,PREFABS+"cottage.tscn")
	var cottage_instance=load(PREFABS+"cottage.tscn").instantiate()
	map.add_child(cottage_instance)
	cottage_instance.owner=output
	var interactions:=Node3D.new()
	interactions.name="Interactions"
	map.add_child(interactions)
	interactions.owner=output
	var story: Node=lab.objective
	var chest_source: Node3D=story.containers.chest
	var old_position: Vector3=chest_source.position
	chest_source.position=Vector3.ZERO
	save_raw(chest_source,PREFABS+"chest.tscn")
	chest_source.position=old_position
	var chest_scene=load(PREFABS+"chest.tscn")
	for id in story.spots:
		var node: Node3D
		if id in ["chest","stash","cache","supply"]:
			node=chest_scene.instantiate()
		elif id in ["steward","healer"]:
			var npc: Node3D
			for child in story.get_children():
				if child.get_script()==preload("res://scripts/presentation/story_villager.gd") and child.asset_id==id: npc=child
			node=CharacterBody3D.new()
			node.set_script(preload("res://scripts/presentation/story_villager.gd"))
			node.asset_id=id
			node.name=id.to_pascal_case()
			var preview:=Node3D.new()
			preview.name="EditorPose"
			node.add_child(preview)
			for part in npc.visual.layers.values():
				var image: MeshInstance3D=part.body.duplicate()
				image.transform=npc.global_transform.affine_inverse()*part.body.global_transform
				preview.add_child(image)
			save_raw(node,PREFABS+id+".tscn")
			node.free()
			node=load(PREFABS+id+".tscn").instantiate()
		elif id=="satchel":
			node=Node3D.new()
			node.name="Satchel"
			var art=preload("res://scripts/presentation/weapon_art.gd")
			art.block(node,Vector3(.42,.28,.34),Vector3.UP*.14,"795b40")
			art.block(node,Vector3(.08,.30,.36),Vector3.UP*.16,"b09060")
			save_raw(node,PREFABS+"satchel.tscn")
			node.free()
			node=load(PREFABS+"satchel.tscn").instantiate()
		else:
			# 调查脚点与相应实物同一父节点；拖动实物根节点即可一起搬迁。
			node=Marker3D.new()
			var visual: Node3D
			var nearest_distance:=100.0
			for child in lab.region.get_children():
				if child is Node3D and child.position.distance_to(story.spots[id])<nearest_distance:
					visual=child
					nearest_distance=child.position.distance_to(story.spots[id])
			node.name=id.to_pascal_case()+"Interaction"
			visual.add_child(node)
			node.global_position=story.spots[id]
			node.set_meta("interaction_id",id)
			node.owner=output
			continue
		node.name=id.to_pascal_case()
		node.set_meta("interaction_id",id)
		interactions.add_child(node)
		node.position=story.spots[id]
		node.owner=output
	var spawn:=Marker3D.new()
	spawn.name="PlayerSpawn"
	spawn.position=lab.spawn_point()
	map.add_child(spawn)
	spawn.owner=output
	var environment:=WorldEnvironment.new()
	environment.name="WorldEnvironment"
	environment.environment=lab.lighting.environment.duplicate()
	output.add_child(environment)
	environment.owner=output
	var light: DirectionalLight3D=lab.lighting.sun.duplicate()
	light.name="Sunlight"
	output.add_child(light)
	light.owner=output
	var camera:=Camera3D.new()
	camera.name="EditorCamera"
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=lab.camera.size
	camera.transform=lab.camera.transform
	camera.current=false
	output.add_child(camera)
	camera.owner=output
	output.set_script(preload("res://scripts/world/courtyard_combat.gd"))
	var packed:=PackedScene.new()
	assert(packed.pack(output)==OK)
	assert(ResourceSaver.save(packed,TARGET)==OK)
	print("MIGRATED ",library.size()," prop scenes; authored map saved")
	quit()
