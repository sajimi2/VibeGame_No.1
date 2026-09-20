shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 albedo_color : source_color = vec4(1.0);
void fragment() {
	vec4 color = texture(albedo_texture,UV);
	// 箭羽空白必须裁切，不让透明矩形写深度；箭身在环境合成之后按原精度显示。
	if (color.a < 0.5 || albedo_color.a <= 0.0) discard;
	ALBEDO = color.rgb*albedo_color.rgb;
	ALPHA = albedo_color.a;
}
