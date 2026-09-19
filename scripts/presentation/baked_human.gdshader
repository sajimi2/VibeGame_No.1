shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D color_atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D depth_atlas : filter_nearest, repeat_disable;
uniform vec4 frame_rect;
uniform vec4 depth_rect;
uniform vec4 tint : source_color = vec4(1.0);
uniform float opacity = 1.0;
uniform vec3 depth_axis = vec3(0.0,0.0,1.0);
uniform bool outline_only = false;
uniform sampler2D other_atlas : source_color, filter_nearest, repeat_disable;
uniform vec4 other_rect;
uniform vec2 other_shift;
uniform vec2 other_scale = vec2(1.0);
uniform vec2 frame_pixels = vec2(64.0);
varying vec3 view_position;
float coverage(vec2 uv) {
	float a = 0.0;
	if (all(greaterThanEqual(uv,vec2(0.0))) && all(lessThanEqual(uv,vec2(1.0)))) {
		a=texture(color_atlas,frame_rect.xy+uv*frame_rect.zw).a;
	}
	vec2 other_uv=uv*other_scale+other_shift;
	if (all(greaterThanEqual(other_uv,vec2(0.0))) && all(lessThanEqual(other_uv,vec2(1.0)))) {
		a=max(a,texture(other_atlas,other_rect.xy+other_uv*other_rect.zw).a);
	}
	return a;
}
void vertex() {
	view_position = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 at = frame_rect.xy + UV * frame_rect.zw;
	vec4 color = texture(color_atlas, at);
	// 固定像素格有序消隐，保持深度写入；不把整个角色切换到透明排序通道。
	float pattern = mod(floor(FRAGCOORD.x)*3.0+floor(FRAGCOORD.y)*5.0,16.0)/16.0;
	if (opacity <= pattern) { discard; }
	if (outline_only) {
		float around = 0.0;
		vec2 texel = vec2(1.0)/frame_pixels;
		around = max(around, coverage(UV + vec2(texel.x,0.0)));
		around = max(around, coverage(UV - vec2(texel.x,0.0)));
		around = max(around, coverage(UV + vec2(0.0,texel.y)));
		around = max(around, coverage(UV - vec2(0.0,texel.y)));
		// 先合并两层透明轮廓，腰部重叠边不能被描成一圈黄线。
		if (coverage(UV) > 0.5 || around < 0.5) { discard; }
		ALBEDO = vec3(1.0,0.89,0.63);
	} else {
		if (color.a < 0.5) { discard; }
		ALBEDO = color.rgb*tint.rgb;
	}
	// 上下身纸片各自恢复真实表面深度；层级由形体决定，不强行把手或武器置顶。
	vec2 data = texture(depth_atlas, depth_rect.xy+UV*depth_rect.zw).rg;
	float offset = (dot(data,vec2(65280.0,255.0))/65535.0-0.5)*6.0;
	vec4 clip = PROJECTION_MATRIX*vec4(view_position+depth_axis*offset,1.0);
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		DEPTH = clip.z/clip.w*0.5+0.5;
	#else
		DEPTH = clip.z/clip.w;
	#endif
}
