extends SceneTree
## 模拟用户在编辑状态搬移/复制/删除后保存，再加载运行；只写work，不动正式地图和存档。
var checks:=0
var failures:=0
var lab: Node3D
const SCENE="res://scenes/courtyard_combat.tscn"
const SAVED="res://work/editable_scene/edited_map.tscn"
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func frames(n: int) -> void:
	for i in n: await physics_frame
func hit(point: Vector3) -> Dictionary:
	return lab.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*8,point+Vector3.UP*.1,1|4|8))
func shot(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/editable_scene/"+name+".png")
func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	DirAccess.make_dir_recursive_absolute("res://work/editable_scene")
	var original: Node3D=load(SCENE).instantiate()
	check(original.has_node("Map/Courtyard/GateWallLeft/Illustration"),"运行前已有可见墙面")
	check(original.has_node("Map/Interactions/Chest/Illustration"),"运行前已有箱子画面")
	check(original.has_node("Map/Interactions/Steward/EditorPose/UpperBody"),"编辑状态NPC有真实图集站姿")
	check(original.has_node("Map/Cottage/Painting/PaintedFront"),"房屋绘画面和空间代理均已落盘")
	var wall: Node3D=original.get_node("Map/Courtyard/GateWallLeft")
	var wall_copy: Node3D=wall.duplicate()
	wall_copy.name="CopiedWall"
	original.get_node("Map/Courtyard").add_child(wall_copy)
	wall_copy.owner=original
	wall_copy.position=Vector3(10,0,20)
	var removed: Node3D=original.get_node("Map/Courtyard/RockEast")
	removed.free()
	var tree: Node3D
	for child in original.get_node("Map/WoodpathRegion").get_children():
		if child.get("asset_id")=="tree_a": tree=child; break
	var tree_path:=original.get_path_to(tree)
	var old_tree_point:=tree.position
	tree.position=Vector3(14,0,18)
	var chest: Node3D=original.get_node("Map/Interactions/Chest")
	var old_chest_point:=chest.position
	chest.position=Vector3(7,0,18)
	var cart: Node3D=original.get_node("Map/WoodpathRegion/Woodpath_cart22")
	var cart_offset:=Vector3(3,0,2)
	cart.position+=cart_offset
	original.get_node("Map/PlayerSpawn").position=Vector3(7,.1,19.6)
	original.get_node("Map/Cottage").position=Vector3(0,0,-5)
	var packed:=PackedScene.new()
	check(packed.pack(original)==OK and ResourceSaver.save(packed,SAVED)==OK,"原生PackedScene保存编辑后的布局")
	original.free()
	lab=load(SAVED).instantiate()
	check(lab.get_node("Map/Interactions/Chest").position==Vector3(7,0,18),"重新读取磁盘保留宝箱位置")
	check(lab.has_node("Map/Courtyard/CopiedWall") and not lab.has_node("Map/Courtyard/RockEast"),"复制与删除落盘")
	root.add_child(lab)
	current_scene=lab
	for i in 240:
		await physics_frame
		if is_instance_valid(lab.objective) and is_instance_valid(lab.objective.state): break
	lab.player.test_mode=true
	for enemy in get_nodes_in_group("tactical_enemies"): enemy.ai_enabled=false
	await frames(5)
	check(not lab.progression.persist,"隔离真实玩家进度")
	check(not lab.has_node("Courtyard") and not lab.has_node("WoodpathRegion"),"运行时没有重复生成地图")
	check(not lab.has_node("Map/Courtyard/RockEast"),"运行时不补回用户删掉的装饰")
	check(lab.player.global_position.distance_to(Vector3(7,0,19.6))<.15,"出生点读取编辑器标记")
	tree=lab.get_node(tree_path)
	check(tree.global_position==Vector3(14,0,18),"树的摆放未被生成器覆盖")
	check(tree.art_material.get_shader_parameter("prop_origin").distance_to(tree.global_position)<.001,"画稿深度原点跟随移动")
	check(tree.shadow.material_override.get_shader_parameter("foot_origin").distance_to(Vector2(14,18))<.001,"树影脚点跟随移动")
	var tree_hit:=hit(tree.global_position)
	check(not tree_hit.is_empty() and tree_hit.collider==tree.body,"真实物理射线命中新树位碰撞")
	var copy: Node3D=lab.get_node("Map/Courtyard/CopiedWall")
	var wall_hit:=hit(copy.global_position)
	check(not wall_hit.is_empty() and wall_hit.collider==copy.body,"复制墙实例自带有效碰撞")
	check(copy.art_material!=lab.get_node("Map/Courtyard/GateWallLeft").art_material,"复制实例拥有独立显示材质")
	var story: Node=lab.objective
	check(story.spots.chest.distance_to(Vector3(7,0,18))<.001,"任务从宝箱节点读取新交互位置")
	check(story.spots.trail.distance_to(Vector3(29,0,-8)+cart_offset)<.001,"搬动药车时调查点同步")
	check(story.can_reach("chest"),"新位置可交互")
	await story.interact()
	await create_timer(.35).timeout
	check(lab.progression.open and story.containers.chest.frame==3,"新位置实际开箱并打开库存")
	await shot("moved_chest_open")
	lab.progression.toggle()
	await create_timer(.35).timeout
	check(story.containers.chest.frame==0,"关闭库存后箱盖合上")
	lab.player.position=old_chest_point+Vector3(0,.05,1.4)
	await frames(3)
	check(not story.can_reach("chest"),"旧坐标不再残留宝箱交互")
	# 运行中移动也必须更新，不能只在进入关卡时缓存一次。
	chest=story.containers.chest
	chest.position+=Vector3(2,0,0)
	lab.player.position=chest.global_position+Vector3(0,.05,1.4)
	await frames(3)
	check(story.can_reach("chest") and story.spots.chest==chest.global_position,"运行时搬动仍同步交互")
	var box_hit:=hit(chest.global_position)
	check(not box_hit.is_empty() and box_hit.collider.get_parent()==chest,"箱子碰撞与画面始终共用父节点")
	check(lab.cottage.roof.pieces.size()==2,"迁移屋顶没有重复生成代理")
	lab.player.position=lab.cottage.global_position+Vector3(0,.1,0)
	await create_timer(.5).timeout
	check(lab.cottage.roof.inside and lab.cottage.roof.interior_fade>.9,"移动小屋后室内整顶透视沿用原控制器")
	await shot("house_interior")
	print("%d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
