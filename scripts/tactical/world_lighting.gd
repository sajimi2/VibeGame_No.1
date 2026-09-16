extends Node3D
## Shared sun controls and invisible volumes for world-space sprite shadows.
var sun: DirectionalLight3D
var environment: Environment
var hour := 10.5
var pixel_material: ShaderMaterial
func setup(light: DirectionalLight3D, env: Environment) -> void:
	sun=light
	environment=env
	set_time_of_day(hour)
func set_time_of_day(value: float) -> void:
	hour = clampf(value,0,24)
	var daylight := maxf(0,sin((hour-6)/12*PI))
	var elevation := maxf(8,daylight*65)
	sun.rotation_degrees = Vector3(-elevation,(hour-12)*13,0)
	sun.light_energy = daylight*0.85
	sun.light_color = Color("e7ecdf").lerp(Color("efa56c"),1-daylight)
	environment.ambient_light_energy = lerpf(0.20,0.48,daylight)
	environment.ambient_light_color = Color("556785").lerp(Color("b9cbd4"),daylight)
	if is_instance_valid(pixel_material):
		var tint := Color("a4b5d4").lerp(Color.WHITE,daylight)
		if daylight>0 and daylight<0.6: tint=Color("edc8a7").lerp(Color.WHITE,daylight)
		pixel_material.set_shader_parameter("world_tint",tint)

static func caster(parent: Node3D, mesh: Mesh, center: Vector3) -> MeshInstance3D:
	var proxy := MeshInstance3D.new()
	proxy.mesh=mesh
	proxy.position=center
	proxy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	parent.add_child(proxy)
	return proxy
static func tree_shadow(parent: Node3D, position: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name="TreeWorldShadow"
	root.position=position
	parent.add_child(root)
	root.add_to_group("tree_world_shadows")
	var trunk := CylinderMesh.new()
	trunk.top_radius=0.13
	trunk.bottom_radius=0.23
	trunk.height=2.9
	trunk.radial_segments=8
	caster(root,trunk,Vector3(0,1.45,0))
	for center in [Vector3(-0.45,2.8,0),Vector3(0.55,3.15,0.1),Vector3(-0.15,3.8,0)]:
		var crown := SphereMesh.new()
		crown.radius=1.15
		crown.height=1.9
		crown.radial_segments=10
		crown.rings=4
		caster(root,crown,center)
	return root
static func actor_shadow(parent: Node3D) -> MeshInstance3D:
	var capsule := CapsuleMesh.new()
	capsule.radius=0.23
	capsule.height=1.65
	return caster(parent,capsule,Vector3(0,0.825,0))
static func pixel_pass(parent: Node) -> ShaderMaterial:
	# Apply shared color grading at native resolution; preserve sprite detail.
	var layer := CanvasLayer.new()
	layer.layer=0
	parent.add_child(layer)
	var screen := ColorRect.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code="shader_type canvas_item; uniform vec4 world_tint : source_color = vec4(1.0); uniform sampler2D scene_color : hint_screen_texture, filter_nearest; void fragment(){ COLOR=texture(scene_color,SCREEN_UV)*world_tint; }"
	var mat := ShaderMaterial.new()
	mat.shader=shader
	screen.material=mat
	layer.add_child(screen)
	return mat
