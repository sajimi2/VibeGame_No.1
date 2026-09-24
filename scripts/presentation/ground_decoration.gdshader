shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D illustration : source_color, filter_nearest, repeat_disable;
uniform vec3 prop_origin;
uniform vec3 ground_normal=vec3(0.0,1.0,0.0);
uniform vec3 to_camera;
varying vec3 world_point;
uniform vec3 sway_world;
uniform float foot_uv=1.0;
void vertex() {
	world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	world_point+=sway_world*smoothstep(0.0,1.0,clamp((foot_uv-UV.y)/max(foot_uv,.01),0.0,1.0));
	VERTEX=(inverse(MODEL_MATRIX)*vec4(world_point,1.0)).xyz;
}
void fragment() {
	vec4 color=texture(illustration,UV);
	if (color.a<.5) discard;
	// 只借地表深度避免穿过房屋，不写遮挡深度；人物随后绘制，花叶不染灰手脚。
	vec3 ground=world_point+to_camera*(dot(prop_origin-world_point,ground_normal)/max(.05,dot(to_camera,ground_normal)));
	vec4 clip=PROJECTION_MATRIX*VIEW_MATRIX*vec4(ground,1.0);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	DEPTH=clip.z/clip.w*.5+.5;
#else
	DEPTH=clip.z/clip.w;
#endif
	ALBEDO=color.rgb;
	ALPHA=1.0;
}
