shader_type spatial;
render_mode specular_disabled;
uniform sampler2D meadow : source_color, filter_nearest, repeat_enable;
uniform sampler2D earth : source_color, filter_nearest, repeat_enable;
varying vec3 world_position;
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
float segment_distance(vec2 p,vec2 a,vec2 b) {
	vec2 v=b-a;
	return length(p-a-v*clamp(dot(p-a,v)/dot(v,v),0.0,1.0));
}
void fragment() {
	vec2 p=(floor(world_position.xz*24.0)+.5)/24.0;
	vec3 grass=texture(meadow,p/8.0).rgb;
	vec3 dirt=texture(earth,p/5.0).rgb;
	float path=min(segment_distance(p,vec2(0,2.7),vec2(0,6)),segment_distance(p,vec2(0,6),vec2(1.2,9)));
	path=min(path,segment_distance(p,vec2(1.2,9),vec2(.8,15)));
	path=min(path,segment_distance(p,vec2(0,6),vec2(-4.0,6.0)));
	float edge=.12*sin(p.x*3.0+p.y*1.5)+.1*sin(p.y*4.7-p.x);
	float blend=1.0-smoothstep(.55+edge,1.25+edge,path);
	// 保持路面安静、草地低对比，细小花草由独立无碰撞装饰提供。
	grass=mix(grass,vec3(.30,.37,.20),.60);
	ALBEDO=mix(grass,dirt*.93,blend);
	ROUGHNESS=1.0;
}
void light() {
	float band=floor(max(dot(NORMAL,LIGHT),0.0)*4.0+.5)/4.0;
	DIFFUSE_LIGHT+=band*ATTENUATION*LIGHT_COLOR/PI;
}
