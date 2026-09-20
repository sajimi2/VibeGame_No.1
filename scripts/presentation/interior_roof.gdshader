shader_type spatial;
render_mode cull_disabled, specular_disabled;
#include "res://scripts/presentation/environment_surface.gdshaderinc"
#include "res://scripts/presentation/art_surface.gdshaderinc"
#include "res://scripts/presentation/occlusion_depth.gdshaderinc"
uniform float reveal : hint_range(0.0,1.0) = 0.0;
uniform float roof_opacity : hint_range(0.0,1.0) = 1.0;
uniform vec2 dither_origin = vec2(0.0);
uniform vec2 reveal_center = vec2(0.5);
uniform vec2 viewport_size = vec2(1280.0,720.0);
uniform float reveal_radius = 115.0;
uniform float feather_width = 44.0;
uniform vec3 reveal_target;
uniform vec3 view_to_camera;
void vertex() {
	surface_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	surface_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
	// 屏幕像素坐标保证宽屏下仍是圆形；深度使用带身体余量的柔和过渡，近墙不切出硬角。
	float distance_to_player=length((SCREEN_UV-reveal_center)*viewport_size);
	float hole=(1.0-smoothstep(reveal_radius-feather_width,reveal_radius,distance_to_player))*reveal;
	// 整体淡化保留屋面残影，局部圆再减少覆盖率；像素裁切保持原深度与环境降采样顺序。
	float depth_weight=occlusion_foreground(dot(surface_position-reveal_target,view_to_camera));
	float coverage=roof_opacity*(1.0-hole*depth_weight);
	vec2 stable_pixel=floor(SCREEN_UV*viewport_size)-dither_origin;
	float threshold=fract(52.9829189*fract(dot(stable_pixel,vec2(0.06711056,0.00583715))));
	if (coverage<=threshold) discard;
	ALBEDO=art_surface_color(surface_color(surface_position,surface_normal),UV,UV2.x);
	ROUGHNESS=1.0;
}
void light() {
	float band=floor(max(dot(NORMAL,LIGHT),0.0)*4.0+0.5)/4.0;
	DIFFUSE_LIGHT+=band*ATTENUATION*LIGHT_COLOR/PI;
}
