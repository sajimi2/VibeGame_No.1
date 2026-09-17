extends "res://scripts/tactical/height_lab.gd"
## A larger combat space; the original height lab stays available separately.
const Sample = preload("res://scripts/tactical/outpost_sample.gd")
func spawn_point() -> Vector3: return Vector3(-10,0.1,20)
func objective_point() -> Vector3: return Vector3(7,2.2,-20)
func navigation_bounds() -> Rect2: return Rect2(-23,-31,46,54)
func level_title() -> String: return "荒堡战场 / 夺回密函"
func combat_hint() -> String:
	if not is_instance_valid(objective): return " "
	return "带信返回南侧营火 · E 交付" if objective.carried else " "
func enemy_layout() -> Array:
	return [
		{"position":Vector3(-9,0,9)},
		{"position":Vector3(1,0,-2)},
		{"position":Vector3(-7,0,-7),"ranged":true},
		{"position":Vector3(7,0,-10)},
		{"position":Vector3(9,2.2,-21),"ranged":true}]
func _build_environment() -> void:
	get_node("Ground/Visual").material_override=material("grass")
	# Grounded walls and rocks in the .tscn can be positioned in the editor.
	natural_ledge("FortRise",Vector3(8,0,-22),PackedVector2Array([
		Vector2(-6,-3),Vector2(-4,-5.3),Vector2(1,-5),Vector2(5.5,-3.8),
		Vector2(6,1),Vector2(4.5,3),Vector2(2.5,4),Vector2(-2.5,4),Vector2(-5.5,2.8)]),2.2)
	ramp("FortAccess",Vector3(8,0,-10),5,8,2.2)
	# A low side shelf permits changing shooting height without a long detour.
	natural_ledge("FlankShelf",Vector3(-12,0,-17),PackedVector2Array([
		Vector2(-3,-2),Vector2(1,-3),Vector2(3,0),Vector2(2,2),Vector2(-2,2)]),0.8)
	ramp("FlankAccess",Vector3(-12,0,-12),3,3,0.8)
	# Broad, broken earth patches mark fighting ground without labeled paths.
	for spec in [Vector4(-9,0,9,5),Vector4(0,0,-3,7),Vector4(8,0,-10,5)]:
		Sample.patch(self,Vector3(spec.x,0.018,spec.z),Vector2(spec.w,spec.w*0.7),Color("64664f"),int(spec.x*7+spec.z*13))
		Sample.patch(self,Vector3(spec.x+0.4,0.020,spec.z-0.3),Vector2(spec.w*0.65,spec.w*0.5),Color("706951"),int(spec.z*17))
	# A few perimeter trees retain the approved pixel silhouette.
	for point in [Vector3(-21,0,18),Vector3(-20,0,4),Vector3(-21,0,-12),Vector3(-20,0,-26),Vector3(-3,0,-29),Vector3(20,0,-25),Vector3(21,0,-12),Vector3(21,0,1),Vector3(19,0,18),Vector3(4,0,21)]: tree(point)
	for x in [-24.5,24.5]:
		var bound := box("WorldEdge",Vector3(x,2,-4),Vector3(1,5,57),"soil")
		bound.get_child(1).hide()
	for z in [-32.5,24.5]:
		var bound := box("WorldEdge",Vector3(0,2,z),Vector3(50,5,1),"soil")
		bound.get_child(1).hide()
	# Irregular rock silhouettes make the physical perimeter visible.
	for x in [-23,23]:
		for z in [-27,-19,-11,-3,5,13,21]: edge_rock(Vector3(x,0,z),Vector3(3.5,2.5,8.2),abs(x*3+z))
	for x in [-18,-10,-2,6,14,22]: edge_rock(Vector3(x,0,-31),Vector3(8.2,2.7,3.4),80+x)
	camp()
func tree(point: Vector3) -> void:
	var trunk := box("Tree",point+Vector3.UP,Vector3(0.55,2,0.55),"wood")
	trunk.get_child(1).hide()
	var sprite := Sprite3D.new()
	sprite.texture=Art.tree()
	sprite.pixel_size=0.075
	sprite.position=point
	sprite.offset=Vector2(0,30)
	sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut=SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sprite)
	Lighting.tree_shadow(self,point)
	var canopy := box("Canopy",point+Vector3(0,2.7,0),Vector3(2.8,2.8,0.15),"grass",4)
	canopy.get_child(1).hide()
func camp() -> void:
	var art=preload("res://scripts/tactical/weapon_art.gd")
	Sample.patch(self,Vector3(-10,0.022,20),Vector2(2.3,1.8),Color("786f55"),80)
	art.block(self,Vector3(0.8,0.08,1.5),Vector3(-8.4,0.04,20.4),"637a73")
	art.block(self,Vector3(0.8,0.2,0.3),Vector3(-8.4,0.12,19.7),"ac9775")
	for i in 8:
		var angle := i*TAU/8
		art.block(self,Vector3(0.3,0.17,0.25),Vector3(-11.6+cos(angle)*0.5,0.08,20+sin(angle)*0.5),"68685b")
	art.block(self,Vector3(0.4,0.2,0.4),Vector3(-11.6,0.18,20),"d39348")

func edge_rock(point: Vector3, size: Vector3, seed_value: int) -> void:
	var prop=preload("res://scripts/tactical/battle_prop.gd").new()
	prop.position=point
	prop.extent=size
	prop.variation=seed_value
	add_child(prop)
