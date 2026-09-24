shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform bool depth_pass = false;
uniform bool unlit = false;
uniform vec3 light_direction = vec3(0.3, 0.8, 0.5);
varying vec3 face_normal;
varying float relative_depth;

void vertex() {
	face_normal = MODEL_NORMAL_MATRIX * NORMAL;
	relative_depth = (MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	vec3 normal = normalize(face_normal);
	if (!unlit && normal.z <= 0.0) { discard; }
	// 刀光两次输出使用同一像素格消退，避免颜色孔洞与深度不一致。
	if (unlit) {
		vec2 cell = floor(FRAGCOORD.xy);
		float cutoff = (mod(cell.x + cell.y, 2.0) * 2.0 + mod(cell.y, 2.0) + 0.5) / 4.0;
		if (COLOR.a < cutoff) { discard; }
	}
	if (depth_pass) {
		float encoded = clamp(floor((relative_depth / 6.0 + 0.5) * 65535.0 + 0.5), 0.0, 65535.0);
		ALBEDO = vec3(floor(encoded / 256.0), mod(encoded, 256.0), 0.0) / 255.0;
	} else {
		float illumination = dot(normal, light_direction);
		float shade = (unlit || UV.x > 0.5) ? 1.0 : (illumination > 0.72 ? 1.05 : (illumination > 0.2 ? 0.88 : (illumination > -0.4 ? 0.68 : 0.48)));
		ALBEDO = clamp(floor(COLOR.rgb * shade * 31.0 + 0.5) / 31.0, vec3(0.0), vec3(1.0));
	}
}
