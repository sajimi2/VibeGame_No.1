shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://scripts/presentation/wall_reveal.gdshaderinc"
uniform sampler2D illustration : source_color, filter_nearest, repeat_disable;
uniform vec3 prop_origin;
uniform vec3 depth_size = vec3(1.0);
uniform vec3 to_camera;
uniform vec4 tint : source_color = vec4(1.0);
// 高分辨率原稿也按世界米制像素网格采样，不能比已有137px横墙更细。
uniform vec2 logical_size=vec2(0.0);
// 0=实物近似体积，1=树干深度面；无碰撞花草使用独立的不写深度材质。
uniform int depth_mode = 0;
varying vec3 card_world;
uniform vec3 sway_world;
uniform float foot_uv=1.0;
void vertex() {
	card_world = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	// 脚点以下保持固定，越接近顶部偏移越大；少量纵向分段只用于未来轻微风摆。
	card_world+=sway_world*smoothstep(0.0,1.0,clamp((foot_uv-UV.y)/max(foot_uv,.01),0.0,1.0));
	VERTEX=(inverse(MODEL_MATRIX)*vec4(card_world,1.0)).xyz;
}
void fragment() {
	vec2 sample_uv=logical_size.x>0.0 ? (floor(UV*logical_size)+.5)/logical_size : UV;
	vec4 color=texture(illustration,sample_uv);
	if (color.a<0.5) discard;
	// 用简单体积近似纸片的空间深度；美术轮廓仍完全由 alpha 决定，不画出盒子表面。
	vec3 center=prop_origin+vec3(0.0,depth_size.y*0.5,0.0);
	vec3 low=(center-depth_size*.5-card_world)/to_camera;
	vec3 high=(center+depth_size*.5-card_world)/to_camera;
	vec3 near_point=min(low,high);
	vec3 far_point=max(low,high);
	float enter=max(max(near_point.x,near_point.y),near_point.z);
	float leave=min(min(far_point.x,far_point.y),far_point.z);
	vec3 horizontal=normalize(vec3(to_camera.x,0.0,to_camera.z));
	float fallback=dot(prop_origin-card_world,horizontal)/dot(to_camera,horizontal);
	vec3 surface=card_world+to_camera*(leave>=enter ? leave : fallback);
	if (depth_mode==1) surface=card_world+to_camera*fallback;
	// 画中的根部、轮子和石墙斜向底沿可超出中心锚点；只移动深度，不裁掉这些接地像素。
	if (surface.y<prop_origin.y+0.012) surface+=to_camera*((prop_origin.y+0.012-surface.y)/to_camera.y);
	wall_world_position=surface;
	if (wall_pixel_hidden(SCREEN_UV)) discard;
	vec4 clip=PROJECTION_MATRIX*VIEW_MATRIX*vec4(surface,1.0);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	DEPTH=clip.z/clip.w*0.5+0.5;
#else
	DEPTH=clip.z/clip.w;
#endif
	ALBEDO=color.rgb*tint.rgb;
}
