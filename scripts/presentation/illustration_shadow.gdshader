shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec2 foot_origin;
uniform vec4 lobes[16];
uniform vec4 contacts[4];
uniform int lobe_count=0;
uniform int contact_count=0;
uniform vec2 stem_end;
uniform float stem_radius=0.0;
uniform float strength=0.22;
uniform vec4 shadow_color : source_color = vec4(.09,.16,.11,1.0);
uniform float feather=.18;
uniform float pixels_per_meter=28.0;
uniform vec2 sway;
uniform vec2 polygon[16];
uniform int polygon_count=0;
varying vec2 world_point;
void vertex() { world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz; }
float lobe(vec2 p,vec4 shape) {
	float distance_to_edge=length((p-shape.xy)/max(shape.zw,vec2(.001)));
	return 1.0-smoothstep(-feather,0.0,(distance_to_edge-1.0)*min(shape.z,shape.w));
}
// 房屋由屋檐、屋脊和墙脚的投影凸包组成；世界米制柔边与小物件一致。
float hull(vec2 p) {
	float distance_to_edge=10000.0;
	bool positive=false;
	bool negative=false;
	for(int i=0;i<16;i++) {
		if(i>=polygon_count) break;
		vec2 a=polygon[i];
		vec2 edge=polygon[(i+1)%polygon_count]-a;
		vec2 v=p-a;
		float side=edge.x*v.y-edge.y*v.x;
		positive=positive || side>0.0;
		negative=negative || side<0.0;
		float t=clamp(dot(v,edge)/max(dot(edge,edge),.00001),0.0,1.0);
		distance_to_edge=min(distance_to_edge,length(v-edge*t));
	}
	if(positive && negative) return 0.0;
	return smoothstep(0.0,feather,distance_to_edge);
}
void fragment() {
	// 世界网格保持小像素台阶；多团树冠取并集，重叠处不叠出深色圆圈。
	vec2 p=(floor(world_point*pixels_per_meter)+.5)/pixels_per_meter-foot_origin;
	float body=0.0;
	for(int i=0;i<16;i++) { if(i>=lobe_count) break; body=max(body,lobe(p-sway,lobes[i])); }
	if(polygon_count>2) body=max(body,hull(p-sway));
	if(stem_radius>0.0) {
		float t=clamp(dot(p,stem_end)/max(dot(stem_end,stem_end),.001),0.0,1.0);
		body=max(body,1.0-smoothstep(stem_radius*.65,stem_radius,length(p-stem_end*t)));
	}
	float contact=0.0;
	for(int i=0;i<4;i++) { if(i>=contact_count) break; contact=max(contact,lobe(p,contacts[i])); }
	float alpha=max(body,contact)*strength;
	if(alpha<.015) discard;
	ALBEDO=shadow_color.rgb;
	ALPHA=alpha;
}
