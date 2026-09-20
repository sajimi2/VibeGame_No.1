// 只供普通环境的显示变体使用；阴影代理仍用原材质，物理碰撞完全不变。
#include "res://scripts/presentation/occlusion_depth.gdshaderinc"
uniform float wall_reveal = 0.0;
uniform float wall_coverage = 0.22;
uniform vec2 wall_center;
uniform vec2 wall_viewport = vec2(1280.0,720.0);
uniform vec2 wall_dither_origin;
uniform float wall_radius = 115.0;
uniform float wall_feather = 44.0;
uniform float wall_clear_core = 0.27;
uniform vec3 wall_target;
uniform vec3 wall_to_camera;
varying vec3 wall_world_position;
bool wall_pixel_hidden(vec2 screen_uv) {
	if (wall_reveal <= 0.0) return false;
	float distance_to_player = length((screen_uv-wall_center)*wall_viewport);
	float depth_weight = occlusion_foreground(dot(wall_world_position-wall_target,wall_to_camera));
	float ring_start = wall_radius-wall_feather;
	float core = min(wall_radius*wall_clear_core,ring_start*0.9);
	// 中心全透 → 淡墙残影 → 圆外正常墙体，两段连续过渡不在人物身上留下网点。
	float inner_coverage = wall_coverage*smoothstep(core,ring_start,distance_to_player);
	float hole = (1.0-smoothstep(ring_start,wall_radius,distance_to_player))*wall_reveal*depth_weight;
	float coverage = mix(1.0,inner_coverage,hole);
	vec2 pixel = floor(screen_uv*wall_viewport)-wall_dither_origin;
	float threshold = fract(52.9829189*fract(dot(pixel,vec2(0.06711056,0.00583715))));
	return coverage <= threshold;
}
