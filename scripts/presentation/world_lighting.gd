extends Node3D
## 统一控制太阳光和树木投影；人物按自身当前帧投影，由 character_billboard 维护。
var sun: DirectionalLight3D
var environment: Environment
var hour := 10.5
var pixel_material: ShaderMaterial

## 接收关卡灯光和环境资源，并应用当前时刻的光照。
func setup(light: DirectionalLight3D, env: Environment) -> void:
	sun=light
	environment=env
	set_time_of_day(hour)

## 按小时更新太阳角度、能量、环境色与屏幕色调；当前没有自动时间循环。
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

## 创建只投影而不显示本体的网格代理，让纸片外观拥有立体阴影。
static func caster(parent: Node3D, mesh: Mesh, center: Vector3) -> MeshInstance3D:
	var proxy := MeshInstance3D.new()
	proxy.mesh=mesh
	proxy.position=center
	proxy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	parent.add_child(proxy)
	return proxy

## 用树干和树冠体积组合投影代理，挂到指定父节点下。
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

## 创建世界画面调色层并返回材质，让时间控制器更新统一色调。
static func pixel_pass(parent: Node) -> ShaderMaterial:
	# 在原始分辨率上统一调色，保留像素纹理细节。
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
