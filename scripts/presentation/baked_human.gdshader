shader_type spatial;
#ifdef OCCLUSION_PASS
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec4 occlusion_color : source_color = vec4(0.55,0.57,0.59,1.0);
#else
render_mode unshaded, cull_disabled, depth_draw_always;
#endif
uniform sampler2D color_atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D depth_atlas : filter_nearest, repeat_disable;
uniform vec4 frame_rect;
uniform vec4 depth_rect;
uniform vec4 tint : source_color = vec4(1.0);
uniform float opacity = 1.0;
uniform vec3 depth_axis = vec3(0.0,0.0,1.0);
varying vec3 view_position;
void vertex() {
	view_position = (MODELVIEW_MATRIX * vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	vec4 color = texture(color_atlas,frame_rect.xy+UV*frame_rect.zw);
	if (color.a < 0.5) discard;
	float pattern = mod(floor(FRAGCOORD.x)*3.0+floor(FRAGCOORD.y)*5.0,16.0)/16.0;
	if (opacity <= pattern) discard;
	// 两种显示共用烘焙表面深度，不能用整张纸片平面的深度判断手脚是否被挡。
	vec2 data = texture(depth_atlas,depth_rect.xy+UV*depth_rect.zw).rg;
	float offset = (dot(data,vec2(65280.0,255.0))/65535.0-0.5)*6.0;
	vec3 surface_view = view_position+depth_axis*offset;
	vec4 clip = PROJECTION_MATRIX*vec4(surface_view,1.0);
	ALPHA = 1.0;
#ifdef OCCLUSION_PASS
	// 读取屋顶开孔/裁切后的真实环境深度：只覆盖被遮住的像素，露出的部分直接丢弃。
	float depth = textureLod(scene_depth,SCREEN_UV,0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV,depth)*2.0-1.0;
#else
	vec3 ndc = vec3(SCREEN_UV*2.0-1.0,depth);
#endif
	vec4 obstacle = INV_PROJECTION_MATRIX*vec4(ndc,1.0);
	if (surface_view.z >= obstacle.z/obstacle.w-0.025) discard;
	// 灰色先绘制，正常身体随后覆盖可见部分；上下身重叠不会反复叠透明度或盖住露出的手。
	ALBEDO = occlusion_color.rgb;
#else
	ALBEDO = color.rgb*tint.rgb;
#endif
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	DEPTH = clip.z/clip.w*0.5+0.5;
#else
	DEPTH = clip.z/clip.w;
#endif
}
