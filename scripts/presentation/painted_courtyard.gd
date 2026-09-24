extends Node3D
## 资产目录持有图片/尺寸，layout 持有摆放；这里只装配物件和装饰，不控制玩家或 UI。
const Prop=preload("res://scripts/presentation/illustrated_prop.gd")
const FOLDER="res://assets/environment/painted/courtyard/"
@export_storage var authored_layout := false
var props: Array[Node3D]=[]
var flowers: Array[Node3D]=[]
var ambience: Node3D

func _ready() -> void:
	if authored_layout:
		for child in find_children("*","Node3D",true,false):
			if child.get_script()==Prop:
				if child.asset_id=="flowers": flowers.append(child)
				else: props.append(child)
		ambience=preload("res://scripts/presentation/courtyard_ambience.gd").new()
		ambience.name="ButterfliesAndLeaves"
		add_child(ambience)
		ambience.setup(JSON.parse_string(FileAccess.get_file_as_string(FOLDER+"layout.json")))
		return
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FOLDER+"catalog.json"))
	var baked: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FOLDER+"baked.json"))
	var layout: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FOLDER+"layout.json"))
	for item in layout.props:
		var prop:=Prop.new()
		prop.name=item.name
		prop.position=Prop.vector(item.position)
		add_child(prop)
		prop.setup(item.id,catalog.assets[item.id],baked[item.id],float(item.get("scale",1)))
		props.append(prop)
	var rng:=RandomNumberGenerator.new()
	rng.seed=24
	for position in layout.flower_patches:
		var prop:=Prop.new()
		prop.name="Flowers%d"%flowers.size()
		prop.position=Vector3(position[0],.015,position[1])
		add_child(prop)
		prop.setup("flowers",catalog.assets.flowers,baked.flowers,rng.randf_range(.65,1.15))
		flowers.append(prop)
	ambience=preload("res://scripts/presentation/courtyard_ambience.gd").new()
	ambience.name="ButterfliesAndLeaves"
	add_child(ambience)
	ambience.setup(layout)

func bind_occlusion() -> void:
	for prop in props: prop.bind_occlusion()

## 连通草地复用目录画稿；树石避开主路，落点与独立阴影使用同一地表采样。
func extend_meadow(ground: StaticBody3D) -> void:
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FOLDER+"catalog.json"))
	var baked: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FOLDER+"baked.json"))
	var placements: Array=[
		["oak",Vector2(14,5),.85],["oak",Vector2(26,-5),1.0],
		["oak",Vector2(38,3),.9],["oak",Vector2(35,23),.8],
		["rock",Vector2(19,0),1.0],["rock",Vector2(30,18),.8],
		["stump",Vector2(15,18),.8],["rock",Vector2(39,17),.7]]
	for item in placements:
		var prop:=Prop.new()
		prop.name="MeadowProp%d"%props.size()
		var point: Vector2=item[1]
		prop.position=Vector3(point.x,ground.height_at(point),point.y)
		add_child(prop)
		prop.setup(item[0],catalog.assets[item[0]],baked[item[0]],item[2])
		prop.shadow.fit_ground(ground.height_at)
		props.append(prop)
	var rng:=RandomNumberGenerator.new()
	rng.seed=ground.terrain_seed
	for i in 65:
		var point:=Vector2(rng.randf_range(10,41),rng.randf_range(-9,23))
		if absf(point.y-ground.path_z(point.x))<1.8: continue
		if ground.distance_to_climb_path(point)<1.1: continue
		var prop:=Prop.new()
		prop.name="MeadowFlowers%d"%i
		prop.position=Vector3(point.x,ground.height_at(point)+.035,point.y)
		add_child(prop)
		prop.setup("flowers",catalog.assets.flowers,baked.flowers,rng.randf_range(.55,.95))
		# 花草按脚点的切平面计算深度，避免沿用水平面后只露出零碎叶尖。
		var dx: float=(ground.height_at(point+Vector2(.1,0))-ground.height_at(point-Vector2(.1,0)))/.2
		var dz: float=(ground.height_at(point+Vector2(0,.1))-ground.height_at(point-Vector2(0,.1)))/.2
		prop.art_material.set_shader_parameter("ground_normal",Vector3(-dx,1,-dz).normalized())
		flowers.append(prop)

func set_artwork(value: bool) -> void:
	for prop in props: prop.set_artwork(value)
	for prop in flowers: prop.set_artwork(value)

## 平台装饰放在水平格内部；不在坡道和崖沿放树，避免画稿脚点与地形跨层。
func extend_terraces(ground: StaticBody3D) -> void:
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FOLDER+"catalog.json"))
	var baked: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FOLDER+"baked.json"))
	var placements: Array=[["oak",Vector2(14,3),.85],["oak",Vector2(30,-5),.85],["oak",Vector2(42,5),.9],["oak",Vector2(10,23),.8],["rock",Vector2(14,-10),.8],["rock",Vector2(35,-10),.8],["stump",Vector2(27,-2),.7],["rock",Vector2(38,10),.65]]
	for item in placements:
		var prop:=Prop.new()
		prop.name="TerraceProp%d"%props.size()
		var p: Vector2=item[1]
		prop.position=Vector3(p.x,ground.height_at(p),p.y)
		add_child(prop)
		prop.setup(item[0],catalog.assets[item[0]],baked[item[0]],item[2])
		props.append(prop)
	var rng:=RandomNumberGenerator.new()
	rng.seed=241021
	for i in 60:
		var p:=Vector2(rng.randf_range(10,41),rng.randf_range(-11,23))
		var grid: Vector2=(p-ground.layout.ORIGIN)/ground.layout.CELL
		var cell:=Vector2i(floori(grid.x),floori(grid.y))
		if ground.layout.spec(cell).rise!=0: continue
		var local:=grid-Vector2(cell)
		if minf(minf(local.x,1.0-local.x),minf(local.y,1.0-local.y))<.18: continue
		var on_road:=false
		for path in ground.layout.roads():
			for j in path.size()-1:
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p,path[j],path[j+1]))<1.25: on_road=true
		if on_road: continue
		var prop:=Prop.new()
		prop.name="TerraceFlowers%d"%i
		prop.position=Vector3(p.x,ground.height_at(p)+.015,p.y)
		add_child(prop)
		prop.setup("flowers",catalog.assets.flowers,baked.flowers,rng.randf_range(.6,.9))
		flowers.append(prop)

func show_collisions(value: bool) -> void:
	for prop in props: prop.show_collision(value)
