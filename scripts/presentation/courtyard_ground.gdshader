shader_type spatial;
render_mode specular_disabled;
uniform sampler2D meadow : source_color, filter_nearest, repeat_enable;
uniform sampler2D earth : source_color, filter_nearest, repeat_enable;
uniform bool meadow_extension=false;
uniform bool woodpath_region=false;
// 仅局部校准实验启用：按相机平面投影采样，再反解回地面，避免斜地面像素被压扁。
uniform bool density_trial=false;
uniform vec4 density_bounds=vec4(59.0,-10.0,70.0,1.0);
uniform vec3 density_right=vec3(1.0,0.0,0.0);
uniform vec3 density_up=vec3(0.0,0.57,-0.82);
uniform float density_ppm=37.5;
uniform vec4 woodpath_segments[32];
uniform bool terrain_guides=false;
uniform float relief_strength : hint_range(0.0,1.0)=1.0;
uniform vec3 terrain_light=vec3(-.173, .867, .468);
uniform vec2 climb_path[17];
varying vec3 world_position;
varying vec3 world_normal;
varying float relief;
void vertex() {
	world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
	relief=meadow_extension ? smoothstep(8.0,14.0,world_position.x)*relief_strength : 0.0;
}
float segment_distance(vec2 p,vec2 a,vec2 b) {
	vec2 v=b-a;
	return length(p-a-v*clamp(dot(p-a,v)/dot(v,v),0.0,1.0));
}
// 四邻域独立偏移/翻向混合，消除每8米复制同一团草纹的周期。
float hash_ground(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise_ground(vec2 p){
	vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash_ground(i),hash_ground(i+vec2(1,0)),f.x),mix(hash_ground(i+vec2(0,1)),hash_ground(i+vec2(1,1)),f.x),f.y);
}
vec3 grass_cell(vec2 p,vec2 cell){
	float r=hash_ground(cell);
	vec2 q=p/8.0+vec2(r,hash_ground(cell+19.7))*7.0;
	if(r>.5)q=q.yx;
	if(r>.75)q.x=-q.x;
	q=(floor(q*224.0)+.5)/224.0;
	return texture(meadow,q).rgb;
}
vec3 woodland_grass(vec2 p){
	vec2 q=p/5.5, i=floor(q), f=fract(q); f=f*f*(3.0-2.0*f);
	vec3 c=mix(mix(grass_cell(p,i),grass_cell(p,i+vec2(1,0)),f.x),mix(grass_cell(p,i+vec2(0,1)),grass_cell(p,i+vec2(1,1)),f.x),f.y);
	// 大片阴湿/干草区低频变化，细节退后；避免仍像均匀铺满的地毯。
	float patch=noise_ground(p*.075+vec2(6,9));
	c=mix(c,vec3(.34,.39,.25),.22);
	c=mix(c,vec3(.43,.40,.27),smoothstep(.50,.78,patch)*.24);
	return c*(.88+.20*noise_ground(p*.19));
}
void fragment() {
	vec2 p=(floor(world_position.xz*24.0)+.5)/24.0;
	if(density_trial && world_position.x>=density_bounds.x && world_position.z>=density_bounds.y && world_position.x<=density_bounds.z && world_position.z<=density_bounds.w){
		vec2 projected=vec2(dot(world_position,density_right),dot(world_position,density_up));
		projected=(floor(projected*density_ppm)+.5)/density_ppm;
		vec2 b=projected-world_position.y*vec2(density_right.y,density_up.y);
		float det=density_right.x*density_up.z-density_right.z*density_up.x;
		p=vec2(b.x*density_up.z-density_right.z*b.y,density_right.x*b.y-b.x*density_up.x)/det;
	}
	vec3 grass=texture(meadow,p/8.0).rgb;
	vec3 dirt=texture(earth,p/5.0).rgb;
	float path=min(segment_distance(p,vec2(0,2.7),vec2(0,6)),segment_distance(p,vec2(0,6),vec2(1.2,9)));
	path=min(path,segment_distance(p,vec2(1.2,9),vec2(.8,15)));
	path=min(path,segment_distance(p,vec2(0,6),vec2(-4.0,6.0)));
	if(woodpath_region){
		for(int i=0;i<32;i++){
			vec4 line=woodpath_segments[i];
			if(length(line.xy-line.zw)>.01)path=min(path,segment_distance(p,line.xy,line.zw));
		}
	}
	if(meadow_extension && !woodpath_region) {
		path=min(path,segment_distance(p,vec2(.8,14),vec2(8,13)));
		float road_z=13.0+3.0*sin((clamp(p.x,8.0,40.0)-8.0)*.17);
		path=min(path,length(vec2(p.x-clamp(p.x,8.0,40.0),p.y-road_z)));
		if(relief_strength>0.0 && p.x>14.0 && p.x<25.0 && p.y>-1.0 && p.y<17.0) {
			// 支路从谷底绕上丘顶，作为连续的坡度参照；数据来自同一地形节点。
			float uphill=1000.0;
			for(int i=0;i<16;i++) uphill=min(uphill,segment_distance(p,climb_path[i],climb_path[i+1]));
			path=min(path,uphill+.30);
		}
	}
	float edge=.12*sin(p.x*3.0+p.y*1.5)+.1*sin(p.y*4.7-p.x);
	float blend=1.0-smoothstep(.55+edge,1.25+edge,path);
	// 保持路面安静、草地低对比，细小花草由独立无碰撞装饰提供。
	grass=mix(grass,vec3(.30,.37,.20),.60);
	if(meadow_extension && p.x>8.0) {
		// 宽幅色块辅助识别丘顶与谷地，细节仍用已验收草地素材，不画等高线。
		float hill=smoothstep(.1,2.9,world_position.y);
		grass=mix(grass,vec3(.40,.43,.23),hill*.32);
	}
	// 降低重复草纹的碎反差，让整面坡的明暗先被读到；高处偏干、谷地偏冷。
	vec3 calm_grass=mix(texture(meadow,p/8.0).rgb,vec3(.29,.36,.18),.76);
	float summit=smoothstep(.3,2.8,world_position.y);
	calm_grass=mix(calm_grass,vec3(.40,.41,.21),summit*.55);
	grass=mix(grass,calm_grass,relief);
	if(woodpath_region)grass=woodland_grass(p);
	ALBEDO=mix(grass,dirt*.93,blend);
	// 把真实坡向的宽幅差异带入底色，避免环境光和四档光照共同抹平缓坡。
	float facing=dot(normalize(world_normal),normalize(terrain_light));
	float form=clamp(1.0+(facing-normalize(terrain_light).y)*2.4,.64,1.16);
	ALBEDO*=mix(1.0,form,relief*mix(1.0,.65,blend));
	if(terrain_guides && p.x>=8.0 && p.x<=48.0 && p.y>=-20.0 && p.y<=28.0) {
		// F3 用一米网格观察连续坡面，仅改变显示，不改动碰撞。
		vec2 grid=abs(fract(world_position.xz)-.5);
		float line=smoothstep(.47,.49,max(grid.x,grid.y));
		ALBEDO=mix(ALBEDO,vec3(.55,.85,.74),line*.65);
	}
	ROUGHNESS=1.0;
}
void light() {
	float band=floor(max(dot(NORMAL,LIGHT),0.0)*4.0+.5)/4.0;
	band=mix(band,max(dot(NORMAL,LIGHT),0.0),relief);
	DIFFUSE_LIGHT+=band*ATTENUATION*LIGHT_COLOR/PI;
}
