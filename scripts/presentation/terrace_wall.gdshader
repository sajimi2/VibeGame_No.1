shader_type spatial;
render_mode unshaded,cull_disabled;
uniform sampler2D cliff : source_color,filter_nearest,repeat_disable;
uniform vec3 sun_direction=vec3(-.173,.867,.468);
uniform bool artwork=true;
uniform bool guides=false;
varying vec3 world;
varying vec3 world_normal;
varying float below_top;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);below_top=UV2.x;}
void fragment(){
	// 世界坐标连续采样跨过粗格接缝；镜像往返使母版两端不产生颜色跳变。
	float u=1.0-abs(fract(UV.x/16.0)*2.0-1.0);
	float v=below_top<.18 ? below_top/.18*.12 : .12+min((below_top-.18)/3.0,.88);
	vec3 paint=texture(cliff,vec2(u,v)).rgb;
	// 同一母版的左右壁跟随公共光向做不同明暗，不镜像出一套相反的光照。
	float shade=.79+.28*max(dot(normalize(world_normal),normalize(sun_direction)),0.0);
	ALBEDO=paint*shade;
	if(!artwork)ALBEDO=vec3(.26,.31,.35);
	if(guides){float edge=abs(fract(world.y*2.0)-.5);ALBEDO=mix(ALBEDO,vec3(.6,.9,.8),step(.47,edge)*.6);}
	ROUGHNESS=1.0;
}
