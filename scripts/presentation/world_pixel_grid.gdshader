shader_type canvas_item;
uniform sampler2D world_frame:hint_screen_texture,filter_nearest,repeat_disable;
uniform vec2 logical_size=vec2(640.0,360.0);
void fragment(){
	// 同一个世界像素只能取一个颜色，禁止双线性和块间插值；UI在之后绘制。
	vec2 cell=(floor(SCREEN_UV*logical_size)+.5)/logical_size;
	COLOR=vec4(texture(world_frame,cell).rgb,1.0);
}
