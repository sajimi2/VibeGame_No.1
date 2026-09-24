shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec2 extent=vec2(1.0);
varying vec2 world_point;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){
	vec2 i=floor(p), f=fract(p);f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex(){world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz;}
void fragment(){
	// 稀疏、破边的根际腐殖土只负责接地过渡；不是新的碰撞或第二份投影。
	vec2 p=(floor(world_point*28.0)+.5)/28.0;
	vec2 local=(UV-.5)*2.0;
	float rim=length(local)+.24*(noise(p*3.2)-.5);
	float coverage=(1.0-smoothstep(.30,.96,rim))*(.13+.23*noise(p*2.0));
	ALBEDO=mix(vec3(.23,.24,.14),vec3(.33,.29,.17),noise(p*7.0));
	ALPHA=coverage;
}
