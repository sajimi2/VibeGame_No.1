shader_type spatial;
render_mode specular_disabled;
uniform sampler2D meadow : source_color,filter_nearest,repeat_enable;
uniform sampler2D earth : source_color,filter_nearest,repeat_enable;
uniform vec4 roads[16];
uniform int road_count=0;
uniform bool artwork=true;
uniform bool guides=false;
varying vec3 world;
varying vec4 rim_edges;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;rim_edges=COLOR;}
float line_distance(vec2 p,vec2 a,vec2 b){vec2 d=b-a;return length(p-a-d*clamp(dot(p-a,d)/dot(d,d),0.0,1.0));}
void fragment(){
	vec2 p=(floor(world.xz*24.0)+.5)/24.0;
	vec3 grass=mix(texture(meadow,p/8.0).rgb,vec3(.30,.37,.20),.60);
	float path=1000.0;
	for(int i=0;i<16;i++){if(i>=road_count)break;path=min(path,line_distance(p,roads[i].xy,roads[i].zw));}
	float edge=.08*sin(p.x*3.0+p.y*1.5);
	float dirt=1.0-smoothstep(.5+edge,1.05+edge,path);
	ALBEDO=mix(grass,texture(earth,p/5.0).rgb*.93,dirt);
	// 只给外露边加草沿；同高格的边标志为零，1×2 和 L 形内部没有方格描边。
	vec2 local=fract((world.xz-vec2(8,-20))/4.0)*4.0;
	vec4 distances=vec4(local.y,4.0-local.x,4.0-local.y,local.x);
	float border=min(min(mix(100.0,distances.x,rim_edges.x),mix(100.0,distances.y,rim_edges.y)),min(mix(100.0,distances.z,rim_edges.z),mix(100.0,distances.w,rim_edges.w)));
	float fringe=.13+.045*sin(p.x*9.0+p.y*7.0);
	ALBEDO=mix(ALBEDO,grass*1.18,(1.0-smoothstep(fringe,fringe+.10,border))*.75);
	if(!artwork)ALBEDO=mix(vec3(.29,.39,.42),vec3(.66,.75,.67),clamp((world.y+1.0)/3.0,0.0,1.0));
	if(guides){vec2 grid=abs(fract((world.xz-vec2(8,-20))/4.0)-.5);ALBEDO=mix(ALBEDO,vec3(.6,.9,.8),step(.492,max(grid.x,grid.y))*.75);}
	ROUGHNESS=1.0;
}
void light(){float band=floor(max(dot(NORMAL,LIGHT),0.0)*4.0+.5)/4.0;DIFFUSE_LIGHT+=band*ATTENUATION*LIGHT_COLOR/PI;}
