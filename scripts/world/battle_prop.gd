@tool
extends StaticBody3D
## Scene-placeable original assets. Mesh and collision share the same triangles.
@export_enum("Boulder", "Broken wall") var kind: int = 0:
	set(value):
		kind=value
		request_rebuild()
@export var extent := Vector3(3,2.6,2.5):
	set(value):
		extent=value
		request_rebuild()
@export var variation := 11:
	set(value):
		variation=value
		request_rebuild()
var queued := false

func request_rebuild() -> void:
	if is_inside_tree() and not queued:
		queued=true
		rebuild.call_deferred()
func _ready() -> void: rebuild()
func rebuild() -> void:
	queued=false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	collision_layer=13
	collision_mask=0
	var rng := RandomNumberGenerator.new()
	rng.seed=variation
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	if kind==0: rock(surface,rng)
	else: ruin(surface,rng)
	surface.generate_normals()
	var mesh := surface.commit()
	var visual := MeshInstance3D.new()
	visual.name="StoneVisual"
	visual.mesh=mesh
	visual.material_override=stone_material()
	add_child(visual)
	var collider := CollisionShape3D.new()
	collider.name="StoneCollision"
	collider.shape=mesh.create_trimesh_shape()
	add_child(collider)
	add_to_group("battle_cover")

func stone_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo=true
	mat.diffuse_mode=BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_triplanar=true
	mat.uv1_scale=Vector3.ONE*0.45
	var image := Image.create(32,32,false,Image.FORMAT_RGB8)
	for y in 32:
		for x in 32:
			var cx := int(x/2)
			var cy := int(y/2)
			var field := sin(cx*0.48+sin(cy*0.37)*1.7)+cos(cy*0.54+sin(cx*0.28))
			var color := Color("e1e5db") if field< -1.25 else Color("f3f5ef") if field>1.2 else Color.WHITE
			# Sparse connected mineral seams, rather than a repeated checkerboard.
			if kind==0 and x>9 and x<24 and y==int(17+sin(x*0.28)*3): color=Color("c9cfc1")
			image.set_pixel(x,y,color)
	mat.albedo_texture=ImageTexture.create_from_image(image)
	return mat

func triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color)
	for point in [a,b,c]: surface.add_vertex(point)
func rock(surface: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var rings: Array[PackedVector3Array]=[]
	var n := 9
	for level in 3:
		var ring := PackedVector3Array()
		for i in n:
			var angle := i*TAU/n
			var radius: float = rng.randf_range(0.85,1.1)*[0.92,1.0,0.56][level]
			var y: float=[0.0,extent.y*0.42,extent.y*0.87][level]
			if level>0: y+=rng.randf_range(-0.10,0.10)*extent.y
			ring.append(Vector3(cos(angle)*extent.x*0.5*radius,y,sin(angle)*extent.z*0.5*radius))
		rings.append(ring)
	for level in 2:
		for i in n:
			var j := (i+1)%n
			var color := Color("74796f").lightened(rng.randf_range(-0.08,0.07))
			triangle(surface,rings[level][i],rings[level+1][i],rings[level+1][j],color)
			triangle(surface,rings[level][i],rings[level+1][j],rings[level][j],color.darkened(0.025))
	var cap := Vector3(extent.x*0.07,extent.y,extent.z*0.04)
	for i in n:
		var j := (i+1)%n
		triangle(surface,cap,rings[2][j],rings[2][i],Color("838777") if i%3 else Color("697a55"))
		triangle(surface,Vector3.ZERO,rings[0][i],rings[0][j],Color("52554d"))
func ruin(surface: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var columns := maxi(3,roundi(extent.x/0.66))
	var width := extent.x/columns
	for column in columns:
		var falloff := 0.3+0.7*absf(cos((float(column)/columns+0.12)*PI))
		var rows := maxi(1,roundi(extent.y/0.4*falloff)+rng.randi_range(-1,1))
		for row in rows:
			var center := Vector3(-extent.x*0.5+width*(column+0.5),0.2+row*0.4,0)
			var size := Vector3(width*0.985,0.393,extent.z)
			if row==rows-1:
				size.x*=rng.randf_range(0.72,0.95)
				size.y*=rng.randf_range(0.65,1.0)
				center.x+=rng.randf_range(-0.06,0.06)
			var block := BoxMesh.new()
			block.size=size
			var color := Color("737d7a").lightened(rng.randf_range(-0.10,0.05))
			var faces := block.get_faces()
			for i in range(0,faces.size(),3):
				# Dark mortar-colored edge strips are on the face, not white grid lines.
				triangle(surface,faces[i]+center,faces[i+1]+center,faces[i+2]+center,color)
	# Fallen stones remain low and visible; wide fighting gaps are left by layout.
	for i in 4:
		var cube := BoxMesh.new()
		cube.size=Vector3(0.3,0.18,0.3)
		var center := Vector3(rng.randf_range(-extent.x*0.5,extent.x*0.5),0.09,extent.z*0.5+0.22)
		var faces := cube.get_faces()
		for j in range(0,faces.size(),3): triangle(surface,faces[j]+center,faces[j+1]+center,faces[j+2]+center,Color("6c746d"))
