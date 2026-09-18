shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D frame_color : source_color, filter_nearest, repeat_disable;
uniform sampler2D frame_depth : filter_nearest, repeat_disable;
uniform float depth_span = 6.0;
uniform bool dither_fade = false;
uniform bool packed_frame = false;
varying vec3 view_position;

void vertex() {
	view_position = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 color_uv = packed_frame ? vec2(UV.x * 0.5, UV.y) : UV;
	vec2 depth_uv = packed_frame ? vec2(UV.x * 0.5 + 0.5, UV.y) : UV;
	vec4 color = texture(frame_color, color_uv);
	float cutoff = 0.5;
	if (dither_fade) {
		// 刀光以固定像素格逐块消退，避免透明色带的平滑边缘；图案不随时间随机闪烁。
		vec2 cell = floor(UV * 128.0);
		cutoff = (mod(cell.x + cell.y, 2.0) * 2.0 + mod(cell.y, 2.0) + 0.5) / 4.0;
	}
	if (color.a < cutoff) { discard; }
	ALBEDO = color.rgb;
	// 纸片承载像素，深度仍取三维源表面，不能把整把刀强行置顶。
	vec2 packed_depth = texture(frame_depth, depth_uv).rg;
	float offset = (dot(packed_depth, vec2(65280.0, 255.0)) / 65535.0 - 0.5) * depth_span;
	vec4 clip = PROJECTION_MATRIX * vec4(view_position + vec3(0.0, 0.0, offset), 1.0);
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		DEPTH = clip.z / clip.w * 0.5 + 0.5;
	#else
		DEPTH = clip.z / clip.w;
	#endif
}
