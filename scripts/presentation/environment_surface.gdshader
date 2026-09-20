shader_type spatial;
render_mode cull_disabled, specular_disabled;
#include "res://scripts/presentation/environment_surface.gdshaderinc"
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
#ifdef WALL_REVEAL_PASS
	if (wall_pixel_hidden(SCREEN_UV)) discard;
#endif
	ALBEDO = surface_color(surface_position,surface_normal);
	ROUGHNESS = 1.0;
	if (soft_edges) {
		vec2 cell = floor(surface_position.xz*12.0);
		float patch = fract(sin(dot(cell,vec2(12.9898,78.233)))*43758.5453);
		float edge = min(min(UV.x,1.0-UV.x),min(UV.y,1.0-UV.y));
		if (edge < 0.025+patch*0.035) discard;
	}
}
void light() {
	float amount = max(dot(NORMAL,LIGHT),0.0);
	float band = banded ? floor(amount*4.0+0.5)/4.0 : amount;
	DIFFUSE_LIGHT += band*ATTENUATION*LIGHT_COLOR/PI;
}
