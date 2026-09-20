// 美术图片只替换表面颜色；UV/遮罩由资产提供，几何深度、阴影和遮挡仍由原管线负责。
uniform bool art_projection_enabled = false;
uniform bool art_gray_preview = false;
uniform sampler2D art_texture : source_color, filter_nearest, repeat_disable;
uniform vec2 art_texel_grid = vec2(160.0,128.0);
vec3 art_surface_color(vec3 fallback_color, vec2 uv, float exterior) {
	if (art_gray_preview) return vec3(0.402,0.397,0.347);
	if (!art_projection_enabled || exterior < 0.5) return fallback_color;
	// 离线大图按资产指定纹素网格取色，像素密度不随窗口或模型摆放位置改变。
	vec2 pixel = clamp(floor(uv*art_texel_grid),vec2(0.0),art_texel_grid-1.0);
	return texture(art_texture,(pixel+0.5)/art_texel_grid).rgb;
}
