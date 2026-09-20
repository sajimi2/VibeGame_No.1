shader_type spatial;
render_mode cull_disabled, specular_disabled;
#include "res://scripts/presentation/environment_surface.gdshaderinc"
#include "res://scripts/presentation/art_surface.gdshaderinc"
// 分层插画实验只隐藏已有墙的外表面；内表面、碰撞和独立阴影代理仍保留。
uniform bool painted_hide_exterior = false;
#ifdef WALL_REVEAL_PASS
#include "res://scripts/presentation/wall_reveal.gdshaderinc"
#endif
void vertex() {
#ifdef WALL_REVEAL_PASS
	wall_world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
#endif
	surface_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	surface_normal = normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
	if (painted_hide_exterior && UV2.x > 0.5) discard;
#ifdef WALL_REVEAL_PASS
	if (wall_pixel_hidden(SCREEN_UV)) discard;
#endif
	ALBEDO = art_surface_color(surface_color(surface_position,surface_normal),UV,UV2.x,surface_position);
	ROUGHNESS = 1.0;
	if (soft_edges) {
		vec2 cell = floor(surface_position.xz*12.0);
		float patch = fract(sin(dot(cell,vec2(12.9898,78.233)))*43758.5453);
		vec2 edge_uv = art_uv_present ? COLOR.rg : UV;
		float edge = min(min(edge_uv.x,1.0-edge_uv.x),min(edge_uv.y,1.0-edge_uv.y));
		float region=art_region_weight(surface_position);
		if (art_projection_enabled && art_edge_blend>0.0 && region>0.0) {
			// 土路边缘逐步露出下层草地，图案仍锁在世界格点，不随相机重新抖动。
			if (smoothstep(0.0,mix(0.06,art_edge_blend,region),edge)<=patch) discard;
		} else if (edge < 0.025+patch*0.035) discard;
	}
}
void light() {
	float amount = max(dot(NORMAL,LIGHT),0.0);
	float band = banded ? floor(amount*4.0+0.5)/4.0 : amount;
	DIFFUSE_LIGHT += band*ATTENUATION*LIGHT_COLOR/PI;
}
