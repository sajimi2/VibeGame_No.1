shader_type spatial;
render_mode cull_disabled;
uniform float opacity : hint_range(0.0,1.0) = 1.0;
uniform vec4 roof_color : source_color = vec4(0.25,0.31,0.35,1.0);

// 像素抖动渐隐保留真实深度和投影，避免半透明屋顶与角色深度纸片发生排序穿插。
void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / 2.0);
	float threshold = fract(52.9829189 * fract(dot(cell,vec2(0.06711056,0.00583715))));
	if (opacity <= threshold) discard;
	ALBEDO = roof_color.rgb;
	ROUGHNESS = 1.0;
}
