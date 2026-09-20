@tool
extends Node3D
## 可复用环境构件，只生成美术网格；尺寸由场景显式提供，绝不改父节点碰撞/导航。
const Library=preload("res://scripts/presentation/environment_library.gd")
@export_enum("building", "wall", "tower", "crate", "wagon", "bridge") var kind: String="building":
	set(value): kind=value; request_rebuild()
@export var extent:=Vector3(4,3,.5):
	set(value): extent=value; request_rebuild()
@export var rise:=1.8:
	set(value): rise=value; request_rebuild()
@export var include_base:=false:
	set(value): include_base=value; request_rebuild()
var pending:=false
var surfaces: Dictionary={}
var oriented:=Basis.IDENTITY
func _ready() -> void: rebuild()
func request_rebuild() -> void:
	if is_inside_tree() and not pending:
		pending=true
		rebuild.call_deferred()

## 同材质构件合并网格；木板、窗框再多也不逐根创建节点或运行更新。
func block(center: Vector3, size: Vector3, material: String, basis:=Basis.IDENTITY) -> void:
	if minf(size.x,minf(size.y,size.z))<=0: return
	if not surfaces.has(material):
		var surface:=SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[material]=surface
	var mesh:=BoxMesh.new()
	mesh.size=size
	surfaces[material].append_from(mesh,0,Transform3D(oriented*basis,oriented*center))
func beam(a: Vector3,b: Vector3,width: float,material: String="timber") -> void:
	block((a+b)*.5,Vector3(width,a.distance_to(b),width),material,Basis(Quaternion(Vector3.UP,(b-a).normalized())))
func rebuild() -> void:
	pending=false
	for child in get_children():
		if child.has_meta("generated"):
			remove_child(child)
			child.queue_free()
	surfaces.clear()
	oriented=Basis.IDENTITY
	if include_base and kind!="bridge": block(Vector3.ZERO,extent,"plaster" if kind=="building" else "wood" if kind in ["crate","wagon"] else "masonry")
	if kind=="bridge": bridge()
	elif kind in ["crate","wagon"]: crate()
	elif kind=="tower": tower()
	else: wall()
	for id in surfaces:
		var visual:=MeshInstance3D.new()
		visual.name=id.capitalize()
		visual.set_meta("generated",true)
		# 木桥整组承托与支架保留；不把合并后的高木梁误当可透视墙面。
		if kind=="bridge": visual.set_meta("occlusion_role","support")
		visual.mesh=surfaces[id].commit()
		visual.material_override=Library.material(id)
		add_child(visual)

func wall() -> void:
	var size:=extent
	if extent.z>extent.x:
		oriented=Basis(Vector3.UP,PI/2)
		size=Vector3(extent.z,extent.y,extent.x)
	if kind=="building":
		# 木骨灰泥墙：石脚线、楼层梁与斜撑共用材质，门洞由场景已有分段留出。
		block(Vector3(0,-size.y*.5+.22,0),Vector3(size.x+.06,.44,size.z+.08),"masonry")
		for y in [size.y*.5-.1,-size.y*.5+.53]:
			block(Vector3(0,y,0),Vector3(size.x+.08,.17,size.z+.1),"timber")
		var count:=maxi(1,ceili(size.x/2.1))
		for i in count+1:
			var x: float=lerpf(-size.x*.5+.08,size.x*.5-.08,float(i)/count)
			# 端柱包住墙端并略高于墙芯；同平面的木材/灰泥会随相机移动争抢深度。
			if i==0: x-=.03
			elif i==count: x+=.03
			block(Vector3(x,0,0),Vector3(.16,size.y+.04,size.z+.1),"timber")
		for side in [-1,1]:
			var z: float=side*(size.z*.5+.045)
			for i in count:
				var x: float=-size.x*.5+(i+.5)*size.x/count
				if size.y>2:
					beam(Vector3(x-.7,-size.y*.3,z),Vector3(x+.7,size.y*.25,z),.1)
					if i%2==0 and size.x/count>1.5: window(Vector3(x,size.y*.1,z),side)
	else:
		block(Vector3(0,size.y*.5,0),Vector3(size.x+.12,.16,size.z+.12),"masonry")
		if size.y>2:
			for i in maxi(1,int(size.x/1.1)):
				block(Vector3(-size.x*.5+.42+i*1.1,size.y*.5+.22,0),Vector3(.56,.38,size.z+.04),"masonry")
func window(at: Vector3,side: int) -> void:
	block(at,Vector3(.58,.74,.08),"iron")
	for x in [-.32,0,.32]: block(at+Vector3(x,0,side*.045),Vector3(.055,.85,.07),"timber")
	for y in [-.41,.41]: block(at+Vector3(0,y,side*.06),Vector3(.73,.075,.16),"timber")
func tower() -> void:
	for y in [-extent.y*.4,extent.y*.3]: block(Vector3(0,y,0),Vector3(extent.x+.12,.18,extent.z+.12),"masonry")
	for x in [-1,1]:
		for z in [-1,1]: block(Vector3(x*extent.x*.46,0,z*extent.z*.46),Vector3(.24,extent.y,.24),"masonry")
	for z in [-1,1]:
		block(Vector3(0,extent.y*.14,z*(extent.z*.5+.012)),Vector3(.2,1.0,.045),"iron")
		block(Vector3(.55,-.1,z*(extent.z*.5+.05)),Vector3(.42,1.3,.045),"cloth")
func crate() -> void:
	for x in [-1,1]:
		for z in [-1,1]: block(Vector3(x*extent.x*.46,0,z*extent.z*.46),Vector3(.10,extent.y+.04,.10),"timber")
	for y in [-1,1]:
		block(Vector3(0,y*extent.y*.43,0),Vector3(extent.x+.06,.12,extent.z+.06),"timber")
	for z in [-1,1]: beam(Vector3(-extent.x*.43,-extent.y*.4,z*extent.z*.51),Vector3(extent.x*.43,extent.y*.4,z*extent.z*.51),.09)
	if kind=="wagon":
		for x in [-1,1]:
			for z in [-1,1]:
				var center:=Vector3(x*(extent.x*.5+.12),-extent.y*.2,z*extent.z*.35)
				for i in 8:
					var a:=center+Vector3(0,sin(i*TAU/8)*.43,cos(i*TAU/8)*.43)
					var b:=center+Vector3(0,sin((i+1)*TAU/8)*.43,cos((i+1)*TAU/8)*.43)
					beam(a,b,.10,"iron")
					beam(center,a,.075)

## 连续坡面仍是行走代理；板面顶点严格贴原坡，桥下不开放第二层可走空间。
func bridge() -> void:
	var length:=extent.z
	var width:=extent.x
	var angle:=atan2(rise,length)
	var slope:=Basis(Vector3.RIGHT,angle)
	var pieces:=maxi(2,ceili(length/.29))
	var spacing:=length/pieces
	for i in pieces:
		var t: float=(i+.5)/pieces
		block(Vector3(0,rise*t-.052,-length*t),Vector3(width,.1,spacing/cos(angle)-.012),"planks",slope)
	for side in [-1,1]:
		var x: float=side*(width*.5-.14)
		beam(Vector3(x,-.17,0),Vector3(x,rise-.17,-length),.18)
		var posts:=maxi(2,ceili(length/1.8))
		for i in range(1,posts+1):
			var t: float=float(i)/posts
			var floor_y:=rise*t
			beam(Vector3(x,-.08,-length*t),Vector3(x,floor_y+.8,-length*t),.12)
			if i>1: beam(Vector3(x,.05,-length*(t-1.0/posts)),Vector3(x,floor_y-.18,-length*t),.10)
		beam(Vector3(x,.78,0),Vector3(x,rise+.78,-length),.095)
