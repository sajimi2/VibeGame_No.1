extends Node3D
var player: CharacterBody3D
var message := ""
var message_time := 0.0
var accepted := false
var claimed := false
var first_reward := false
var progress: Node
var carried := false
var completed := false
var relic: Node3D
var marker: Label3D
var hud: Label
var exit_point := Vector3(-3.5,0,11)
var pickup_point := Vector3(4.3,2,-6.1)
func _ready() -> void:
	relic=Node3D.new()
	add_child(relic)
	relic.position=pickup_point
	var art=preload("res://scripts/presentation/weapon_art.gd")
	art.block(relic,Vector3(0.55,0.4,0.4),Vector3.UP*0.2,"674831")
	art.block(relic,Vector3(0.58,0.055,0.43),Vector3.UP*0.41,"b29857")
	art.block(relic,Vector3(0.16,0.18,0.04),Vector3(0,0.3,0.23),"d8c68a")
	marker=Label3D.new()
	marker.text="哨站密函"
	marker.position=pickup_point+Vector3.UP*0.9
	marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	marker.pixel_size=0.012
	marker.font_size=24
	add_child(marker)
	var exit_marker := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius=1.1
	ring.outer_radius=1.18
	ring.rings=24
	ring.ring_segments=6
	exit_marker.mesh=ring
	exit_marker.material_override=art.material("a0bbaa")
	exit_marker.position=exit_point+Vector3.UP*0.04
	add_child(exit_marker)
	var exit_label := Label3D.new()
	exit_label.text="营地委托 · E 接取/交付"
	exit_label.position=exit_point+Vector3.UP*0.15
	exit_label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	exit_label.font_size=20
	exit_label.pixel_size=0.012
	add_child(exit_label)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud=Label.new()
	hud.position=Vector2(18,108)
	hud.add_theme_font_size_override("font_size",18)
	hud.add_theme_color_override("font_shadow_color",Color.BLACK)
	hud.add_theme_constant_override("shadow_offset_x",2)
	hud.add_theme_constant_override("shadow_offset_y",2)
	layer.add_child(hud)
func interact() -> bool:
	if player.hp<=0: return inform("已倒下，按 R 重新挑战")
	if player.global_position.distance_to(exit_point)<2.1:
		if not accepted:
			accepted=true
			inform("已接取委托：到高地取得密函")
			return true
		if completed and not claimed:
			first_reward=not progress.rewarded
			if progress.rewarded or progress.grant_reward():
				claimed=true
				inform("交付完成，按 I 查看背包与奖励")
				player.hp=player.max_hp
				return true
		return inform("奖励已领取，按 I 打开背包" if claimed else "先到高地取得密函，再回营地交付" if not completed else "背包已满，请腾出位置后交付")
	if carried or completed: return inform("密函已在身上，返回营地按 E 交付")
	if player.global_position.distance_to(pickup_point)>1.4: return inform("请靠近高地上的密函小箱子，再按 E")
	var ray := PhysicsRayQueryParameters3D.create(player.global_position+Vector3.UP*0.6,pickup_point+Vector3.UP*0.5,1)
	if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return inform("密函被障碍物挡住了，请绕到箱子旁")
	accepted=true
	carried=true
	inform("已取得密函，返回营地按 E 交付")
	relic.hide()
	marker.hide()
	player.effects.sound("alert",player.global_position)
	return true
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_E: interact()
func _physics_process(_delta: float) -> void:
	message_time=maxf(0,message_time-_delta)
	marker.text="哨站密函 · E 取得" if player.global_position.distance_to(pickup_point)<1.8 else "哨站密函"
	player.safe_zone=player.global_position.distance_to(exit_point)<2.1
	if player.safe_zone and player.hp>0: player.hp=player.max_hp
	if carried and player.hp>0 and player.global_position.distance_to(exit_point)<1.5: completed=true
	hud.text="已领奖 · I 打开背包换装；R 再挑战（保留装备）" if claimed else "密函已带回 · E 交付领奖" if completed else "已取得密函 → 返回营地" if carried else "目标：前往高地取得密函（E） · 无需清空敌人" if accepted else "营地委托：按 E 接取密函任务 · I 背包"

	if message_time>0: hud.text+="\n"+message
func inform(text: String) -> bool:
	message=text
	message_time=3.0
	return false
