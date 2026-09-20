extends Resource
## 绘画路线唯一的白天阴影样式；资产只给体量，不自行覆盖方向、颜色或浓度。
@export var offset_per_height:=Vector2(.20,-.54)
@export var tint:=Color(.09,.16,.11)
@export_range(0.0,1.0) var opacity:=.22
@export var feather:=.18
@export var pixels_per_meter:=28.0
@export var max_sway:=.12

func apply(material: ShaderMaterial) -> void:
	material.set_shader_parameter("strength",opacity)
	material.set_shader_parameter("shadow_color",tint)
	material.set_shader_parameter("feather",feather)
	material.set_shader_parameter("pixels_per_meter",pixels_per_meter)

## 人物仍用实时姿态投影，但光线方向和强度必须与环境美术投影使用同一来源。
func apply_sun(sun: DirectionalLight3D) -> void:
	sun.look_at(sun.global_position+Vector3(offset_per_height.x,-1,offset_per_height.y),Vector3.FORWARD)
	sun.shadow_opacity=opacity
