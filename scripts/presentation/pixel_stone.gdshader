shader_type spatial;
render_mode cull_disabled, specular_disabled;

// 石材只处理自身表面：纹理使用人物相近的世界像素密度，保留真实遮挡和太阳投影。
uniform sampler2D stone_texture : source_color, filter_nearest, repeat_enable;
uniform float texels_per_meter = 25.0;
uniform bool rock = false;
varying vec3 local_position;
varying vec3 local_normal;

void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 axis = abs(normalize(local_normal));
	// 使用主轴投影而非三向混合，避免像素纹理在斜面变糊。
	vec2 plane = axis.y > max(axis.x, axis.z) ? local_position.xz :
		(axis.x > axis.z ? local_position.zy : local_position.xy);
	vec2 pixel = floor(plane * texels_per_meter);
	ALBEDO = texture(stone_texture, (pixel + 0.5) / 64.0).rgb;
	// 向上面只略带苔色；体积交给分档光照，避免每个三角形都变成独立色块。
	if (rock && local_normal.y > 0.45) ALBEDO *= vec3(0.94, 1.0, 0.88);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float lambert = max(dot(NORMAL, LIGHT), 0.0);
	float band = floor(lambert * 4.0 + 0.25) / 4.0;
	DIFFUSE_LIGHT += band * ATTENUATION * LIGHT_COLOR / PI;
}
