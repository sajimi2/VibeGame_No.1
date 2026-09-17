extends SceneTree
var lab: Node3D
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await physics_frame
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/battlefield_"+label+".png")
func walk_to(point: Vector3) -> bool:
	var player=lab.player
	var excluded: Array[RID]=[]
	for enemy in get_nodes_in_group("tactical_enemies"): excluded.append(enemy.get_rid())
	var path: PackedVector3Array=lab.routes.path(player.position,point,excluded)
	if path.is_empty(): return false
	for target in path:
		var reached := false
		for i in 90:
			var offset: Vector3=target-player.position
			if Vector2(offset.x,offset.z).length()<0.14:
				reached=true
				break
			player.test_motion=Vector2(offset.x,offset.z).normalized()
			await frames(1)
		if not reached:
			print("Blocked ",player.position," toward ",target)
			player.test_motion=Vector2.ZERO
			return false
	player.test_motion=Vector2.ZERO
	return player.position.distance_to(point)<0.85
func run() -> void:
	ProjectSettings.set_setting("tactical/testing",true)
	lab=load("res://scenes/battlefield.tscn").instantiate()
	root.add_child(lab)
	current_scene=lab
	while not is_instance_valid(lab.progression): await frames(1)
	lab.player.test_mode=true
	for enemy in get_nodes_in_group("tactical_enemies"): enemy.ai_enabled=false
	await frames(15)
	check(lab.player.safe_zone,"new spawn matches safe camp")
	check(get_nodes_in_group("tactical_enemies").size()==5,"five combatants of two existing roles")
	check(lab.navigation_bounds().get_area()>2400 and lab.routes.graph.get_point_count()>4000,"navigation covers the enlarged battlefield")
	check(lab.get_node("Cover").get_child_count()==19,"new cover assets are individually scene-placeable")
	await capture("camp")
	var cover=lab.get_node("Cover/SplitBoulder")
	var ray := PhysicsRayQueryParameters3D.create(cover.position+Vector3(-5,1,0),cover.position+Vector3(5,1,0),8)
	var hit: Dictionary=lab.get_world_3d().direct_space_state.intersect_ray(ray)
	check(hit.get("collider")==cover,"faceted boulder physically blocks projectile ray")
	check(await walk_to(Vector3(-9,0,13)),"walking from camp to first fight")
	await capture("gate")
	check(await walk_to(Vector3(0,0,7)),"walking around boulders and broken entry walls")
	check(await walk_to(Vector3(1,0,-4)),"walking into courtyard between ruined wall gaps")
	await capture("courtyard")
	check(await walk_to(Vector3(8,0,-9)),"walking from courtyard to upper fight")
	check(await walk_to(lab.objective.pickup_point+Vector3(0,0,0.9)),"actual slope traversal reaches high-ground objective")
	await capture("fort")
	check(lab.objective.interact(),"new map objective uses its own location")
	# Real guard locomotion follows the enlarged graph around physical cover.
	var guard=lab.guard
	guard.position=Vector3(8,0.02,-9)
	guard.velocity=Vector3.ZERO
	guard.state="chase"
	guard.facing=Vector3.FORWARD
	guard.last_seen=lab.player.position
	guard.lost_time=0
	guard.cooldown=10
	lab.player.invulnerable=100
	guard.ai_enabled=true
	await frames(280)
	check(guard.position.y>2.0,"guard physically pursues player onto new plateau")
	guard.ai_enabled=false
	check(await walk_to(lab.objective.exit_point),"return path remains physically connected to camp")
	await frames(8)
	check(lab.objective.completed and lab.objective.interact(),"new map completes existing equipment-reward loop")
	await process_frame
	await process_frame
	check(paused and lab.run_flow.details.text.contains("/ 5"),"result counts all five enemies without hardcoded old total")
	await capture("result")
	lab.run_flow.dismiss()
	lab.player.hp=100
	lab.player.invulnerable=0
	lab.player.position=Vector3(-9,0.02,10.5)
	guard.position=guard.home+Vector3.UP*0.03
	guard.velocity=Vector3.ZERO
	guard.state="chase"
	guard.facing=Vector3.BACK
	guard.lost_time=0
	guard.cooldown=0
	guard.ai_enabled=true
	await frames(100)
	check(lab.player.hp<100,"first guard actually lands an attack on new terrain")
	guard.ai_enabled=false
	lab.player.hp=100
	lab.player.invulnerable=0
	lab.player.position=Vector3(-7,0.02,-2.5)
	lab.player.velocity=Vector3.ZERO
	lab.archer.ai_enabled=true
	lab.archer.facing=Vector3.BACK
	await frames(120)
	check(lab.player.hp<100,"courtyard archer acquires and shoots player through an open line")
	lab.archer.ai_enabled=false
	print("BATTLEFIELD: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
