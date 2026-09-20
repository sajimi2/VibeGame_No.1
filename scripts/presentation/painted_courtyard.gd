extends Node3D
## 资产目录持有图片/尺寸，layout 持有摆放；这里只装配物件和装饰，不控制玩家或 UI。
const Prop=preload("res://scripts/presentation/illustrated_prop.gd")
const FOLDER="res://assets/environment/experiments/painted_courtyard/"
var props: Array[Node3D]=[]
var flowers: Array[Node3D]=[]
var ambience: Node3D

func _ready() -> void:
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

func set_artwork(value: bool) -> void:
	for prop in props: prop.set_artwork(value)
	for prop in flowers: prop.set_artwork(value)

func show_collisions(value: bool) -> void:
	for prop in props: prop.show_collision(value)
