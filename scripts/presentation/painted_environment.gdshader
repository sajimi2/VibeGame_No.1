shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://scripts/presentation/wall_reveal.gdshaderinc"
// 图片已包含画好的明暗；只做透明裁切和既有透视，不再次叠加三维照明。
uniform sampler2D painting : source_color, filter_nearest, repeat_disable;
uniform bool is_roof = false;
uniform bool is_support = false;
uniform float reveal = 0.0;
uniform float roof_opacity = 1.0;
uniform vec2 reveal_center;
uniform vec2 viewport_size = vec2(1280.0,720.0);
uniform vec2 dither_origin;
uniform float reveal_radius = 115.0;
uniform float feather_width = 44.0;
uniform vec3 reveal_target;
uniform vec3 view_to_camera;
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	wall_world_position = world_position;
}
void fragment() {
	vec4 color = texture(painting,UV);
	if (color.a < 0.5) discard;
	if (is_roof) {
		float distance_to_player = length((SCREEN_UV-reveal_center)*viewport_size);
		float hole = (1.0-smoothstep(reveal_radius-feather_width,reveal_radius,distance_to_player))*reveal;
		float weight = occlusion_foreground(dot(world_position-reveal_target,view_to_camera));
		float coverage = roof_opacity*(1.0-hole*weight);
		vec2 pixel = floor(SCREEN_UV*viewport_size)-dither_origin;
		float threshold = fract(52.9829189*fract(dot(pixel,vec2(0.06711056,0.00583715))));
		if (coverage<=threshold) discard;
	} else if (!is_support && wall_pixel_hidden(SCREEN_UV)) discard;
	ALBEDO = color.rgb;
}
