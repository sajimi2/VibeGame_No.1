shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never;
uniform sampler2D environment_frame : hint_screen_texture, filter_nearest;
const float pixel_block = 2.0;
uniform vec2 grid_origin = vec2(0.0);
vec3 source_pixel(ivec2 pixel) {
	return texelFetch(environment_frame,clamp(pixel,ivec2(0),textureSize(environment_frame,0)-ivec2(1)),0).rgb;
}
void vertex() {
	POSITION = vec4(VERTEX.xy,1.0,1.0);
}
void fragment() {
	// 屏幕副本只含先绘制的环境；后绘制的角色/武器不进入此采样，也不覆盖原环境深度。
	ivec2 base = ivec2(floor((SCREEN_UV*VIEWPORT_SIZE-grid_origin)/pixel_block)*pixel_block+grid_origin);
	// 整数寻址避开纹素边界上的最近邻歧义；每块先合并四个源像素，防止细缝被抽样漏掉。
	// 只在块内做面积平均，块与块不插值，也不混合历史帧；保留硬像素边缘和即时响应。
	ALBEDO = (source_pixel(base)+source_pixel(base+ivec2(1,0))+source_pixel(base+ivec2(0,1))+source_pixel(base+ivec2(1,1)))*0.25;
	ALPHA = 1.0;
}
