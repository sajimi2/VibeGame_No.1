extends Node3D
## 林地只拥有布局、道路与美术装配；任务事实/容器仍由篇章模块持有。
const Prop=preload("res://scripts/presentation/illustrated_prop.gd")
const ROOT="res://assets/environment/painted/woodpath/"
const MAIN=[Vector2(.8,14),Vector2(12,14),Vector2(20,10),Vector2(32,10),Vector2(42,8),Vector2(52,0),Vector2(60,-7)]
const SIDE=[Vector2(20,10),Vector2(22,0),Vector2(30,-9),Vector2(42,-17),Vector2(54,-17),Vector2(60,-7)]
const RETURN=[Vector2(60,-7),Vector2(66,3),Vector2(55,15),Vector2(42,8)]
const SPOTS={"steward":Vector3(-1,0,13.6),"healer":Vector3(-4.4,0,8.2),"stash":Vector3(2.4,0,14.7),"satchel":Vector3(60,0,-8),"chest":Vector3(63,0,-5),"cache":Vector3(42,0,-20),"trail":Vector3(29,0,-8),"sign":Vector3(18,0,12),"memorial":Vector3(53,0,15),"supply":Vector3(62.2,0,-16)}
@export_storage var authored_layout := false
var props: Array[Node3D]=[]
var catalog: Dictionary
var old_catalog: Dictionary
var old_baked: Dictionary

func _ready() -> void:
	if authored_layout:
		for child in find_children("*","Node3D",true,false):
			if child.get_script()==Prop: props.append(child)
		return
	catalog=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"unified/catalog.json"))
	old_catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/painted/courtyard/catalog.json")).assets
	old_baked=JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/painted/courtyard/baked.json"))
	# 道路和避让共用折线，树木不再按矩形阵列铺满地面。
	var rng:=RandomNumberGenerator.new()
	rng.seed=92351
	var tree_positions:Array[Vector2]=[]
	var variants=["tree_a","tree_b","tree_c"]
	var groves=[Vector2(13,4),Vector2(15,22),Vector2(28,20),Vector2(33,1),Vector2(39,-6),Vector2(23,-15),Vector2(36,-23),Vector2(53,-24),Vector2(68,-15),Vector2(72,2),Vector2(62,22),Vector2(47,23)]
	for cluster in groves:
		for i in 3:
			var point: Vector2=cluster+Vector2(rng.randf_range(-4,4),rng.randf_range(-3,3))
			if road_distance(point)<2.6 or near_spot(point,2.6): continue
			if tree_positions.any(func(p):return p.distance_to(point)<3.1): continue
			tree_positions.append(point)
			place(variants[(tree_positions.size()+i)%3],Vector3(point.x,0,point.y),rng.randf_range(.83,1.02))
	for item in [["cart",Vector3(30.8,0,-6.2),.8],["rock",Vector3(23,0,12.5),1.0],["rock",Vector3(36,0,5),1.2],["rock",Vector3(49,0,-12),1.1],["stump",Vector3(44,0,-19),.8],["rock",Vector3(53,0,17.3),1.15],["well",Vector3(66,0,-9),.8]]:
		place(item[0],item[1],item[2])
	# 两种墙向明确匹配世界轴；正门留宽口，西侧留可绕行的缺口。
	for p in [Vector3(55,0,-3),Vector3(66,0,-3),Vector3(55,0,-13),Vector3(66,0,-13)]: place("wall",p,.8)
	for p in [Vector3(52.8,0,-11),Vector3(52.8,0,-5),Vector3(67.8,0,-11),Vector3(67.8,0,-5)]: place("wall_z",p,1.0)
	place("waystation_ruin",Vector3(61,0,-16),1.0)
	# 碎叶和小草依附树根、石脚，空地保留呼吸空间，不再均匀撒花。
	for point in tree_positions:
		if rng.randf()<.6: place("litter",Vector3(point.x+.45,.03,point.y+.35),rng.randf_range(.65,1.05))
	_sign(Vector3(18,0,12))
	# 林缘以不可穿越的粗树带封边；隐藏实体在可见树带中，避免走进无内容平原。
	for border in [[Vector3(43,1,-28),Vector3(68,2,1)],[Vector3(43,1,28),Vector3(68,2,1)],[Vector3(77,1,0),Vector3(1,2,56)]]:
		var body:=StaticBody3D.new()
		body.position=border[0]
		body.collision_layer=1|8
		var shape:=CollisionShape3D.new()
		var box:=BoxShape3D.new()
		box.size=border[1]
		shape.shape=box
		body.add_child(shape)
		add_child(body)
	var x:=12.0
	while x<78:
		for z in [-28.0,28.0]:
			place(variants[rng.randi_range(0,2)],Vector3(x+rng.randf_range(-1.1,1.1),0,z+rng.randf_range(-1.3,1.3)),rng.randf_range(.82,1.08))
		x+=rng.randf_range(3.6,5.6)
	var z:=-24.0
	while z<28:
		place(variants[rng.randi_range(0,2)],Vector3(77+rng.randf_range(-.8,.8),0,z),rng.randf_range(.8,1.03))
		z+=rng.randf_range(3.7,5.5)

func place(id: String, point: Vector3, factor:=1.0) -> Node3D:
	# 旧横墙与巨石仍是低分辨率基准；新树/竖墙以同一28px/m采样接入。
	var spec: Dictionary=(catalog[id] if catalog.has(id) else old_catalog[id]).duplicate(true)
	var baked: Dictionary={"aspect":spec.aspect} if spec.has("aspect") else old_baked[id]
	var prop:=Prop.new()
	prop.name="Woodpath_"+id+str(props.size())
	prop.position=point
	add_child(prop)
	prop.setup(id,spec,baked,factor)
	props.append(prop)
	if id.begins_with("tree") or id in ["wall","wall_z","rock","stump"]: _footing(prop,id,factor)
	return prop

func bind_occlusion() -> void:
	for prop in props: prop.bind_occlusion()

static func road_distance(point: Vector2) -> float:
	var distance:=1000.0
	for route in [MAIN,SIDE,RETURN]:
		for i in route.size()-1: distance=minf(distance,point.distance_to(Geometry2D.get_closest_point_to_segment(point,route[i],route[i+1])))
	return distance

static func near_spot(point: Vector2, radius: float) -> bool:
	for p in SPOTS.values():
		if point.distance_to(Vector2(p.x,p.z))<radius: return true
	return false

static func road_segments() -> PackedVector4Array:
	var result:=PackedVector4Array()
	for route in [MAIN,SIDE,RETURN]:
		for i in route.size()-1: result.append(Vector4(route[i].x,route[i].y,route[i+1].x,route[i+1].y))
	result.resize(32)
	return result

func _sign(point: Vector3) -> void:
	var art=preload("res://scripts/presentation/weapon_art.gd")
	var sign:=Node3D.new()
	sign.position=point
	add_child(sign)
	art.block(sign,Vector3(.13,1.4,.13),Vector3.UP*.7,"635038")
	art.block(sign,Vector3(1.2,.3,.15),Vector3(0,1.15,0),"93754c")
	art.block(sign,Vector3(.9,.25,.15),Vector3(-.1,.8,0),"736044")

## 根际与墙脚薄层没有碰撞，只以不规则腐殖土打断“纸片插在地毯上”的硬接缝。
func _footing(prop: Node3D, id: String, factor: float) -> void:
	var patch:=MeshInstance3D.new()
	patch.name="GroundContact"
	var plane:=PlaneMesh.new()
	plane.size=(Vector2(5.2,1.1) if id=="wall" else Vector2(1.1,4.4) if id=="wall_z" else Vector2(2.1,1.65) if id=="rock" else Vector2(2.6,2.0))*factor
	patch.mesh=plane
	patch.position.y=.004
	patch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material:=ShaderMaterial.new()
	material.shader=preload("res://scripts/presentation/woodland_footing.gdshader")
	material.render_priority=-125
	patch.material_override=material
	prop.add_child(patch)
