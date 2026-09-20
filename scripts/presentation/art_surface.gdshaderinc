// 美术图片只替换表面颜色；UV/遮罩由资产提供，几何深度、阴影和遮挡仍由原管线负责。
uniform bool art_projection_enabled = false;
uniform bool art_gray_preview = false;
uniform bool art_repeat = false;
uniform bool art_uv_present = false;
uniform vec4 art_tint : source_color = vec4(1.0);
uniform vec4 art_unmapped_color : source_color = vec4(0.0);
uniform float art_edge_blend = 0.0;
uniform sampler2D art_texture : source_color, filter_nearest, repeat_disable;
uniform vec2 art_texel_grid = vec2(160.0,128.0);
uniform bool art_region_enabled = false;
uniform vec4 art_region = vec4(0.0);
float art_region_weight(vec3 world_position) {
	if (!art_region_enabled) return 1.0;
	vec2 p=floor(world_position.xz*24.0)/24.0;
	float edge=min(min(p.x-art_region.x,p.y-art_region.y),min(art_region.z-p.x,art_region.w-p.y));
	return smoothstep(0.0,3.0,edge);
}
vec3 art_surface_color(vec3 fallback_color, vec2 uv, float exterior, vec3 world_position) {
	if (art_gray_preview) return vec3(0.402,0.397,0.347);
	if (!art_projection_enabled) return fallback_color;
	if (exterior < 0.5) return mix(fallback_color,art_unmapped_color.rgb,art_unmapped_color.a);
	// 离线大图按资产指定纹素网格取色，像素密度不随窗口或模型摆放位置改变。
	vec2 mapped = art_repeat ? fract(uv) : uv;
	vec2 pixel = clamp(floor(mapped*art_texel_grid),vec2(0.0),art_texel_grid-1.0);
	// 大地面只在样板区换图，边缘用世界锚定的粗网格混合，避免矩形色块和移动闪烁。
	float coverage=art_region_weight(world_position);
	return mix(fallback_color,texture(art_texture,(pixel+0.5)/art_texel_grid).rgb*art_tint.rgb,coverage);
}
