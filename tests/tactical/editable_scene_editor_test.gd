extends SceneTree
## 用引擎编辑模式验证@tool绑定；不运行关卡逻辑，不调用外部编辑器或真实存档。
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func run() -> void:
	check(Engine.is_editor_hint(),"测试运行于引擎编辑模式")
	var scene: Node3D=load("res://scenes/courtyard_combat.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(not scene.has_node("Explorer"),"编辑状态不启动游戏总控")
	var tree: Node3D
	for node in scene.get_node("Map/WoodpathRegion").get_children():
		if node.get("asset_id")=="tree_a": tree=node; break
	if tree==null:
		check(false,"地图含可编辑树实例")
		quit(1)
		return
	check(tree.has_node("Illustration") and tree.has_node("SimpleBody"),"编辑状态画稿与碰撞已有节点")
	var count:=tree.get_child_count()
	tree.position+=Vector3(2,0,1)
	await process_frame
	check(tree.art_material.get_shader_parameter("prop_origin").distance_to(tree.global_position)<.001,"编辑状态拖动同步材质原点")
	check(tree.shadow.material_override.get_shader_parameter("foot_origin").distance_to(Vector2(tree.global_position.x,tree.global_position.z))<.001,"编辑状态拖动同步阴影")
	check(tree.get_child_count()==count,"编辑预览不会追加生成孩子")
	var npc: Node3D=scene.get_node("Map/Interactions/Steward")
	check(npc.get_node("EditorPose").visible,"编辑状态NPC站姿可见")
	var chest: Node3D=scene.get_node("Map/Interactions/Chest")
	check(chest.get_node("Illustration").texture!=null,"编辑状态箱子闭合帧可见")
	print("%d checks, %d failures"%[checks,failures])
	scene.free()
	# 等编辑器本次资源扫描结束，避免主动中断扫描造成额外退出告警。
	for i in 30: await process_frame
	if Engine.is_editor_hint():
		while EditorInterface.get_resource_filesystem().is_scanning(): await process_frame
	quit(0 if failures==0 else 1)
