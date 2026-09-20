// 固定世界像素密度与主轴投影；颜色来自可编辑 PNG，不把随机噪声放进每帧 CPU。
uniform sampler2D surface_texture : source_color, filter_nearest, repeat_enable;
uniform float texels_per_meter = 25.0;
uniform bool soft_edges = false;
uniform bool banded = true;
varying vec3 surface_position;
varying vec3 surface_normal;
vec3 surface_color(vec3 p, vec3 n) {
	vec3 axis = abs(n);
	vec2 plane = axis.y > max(axis.x,axis.z) ? p.xz : (axis.x > axis.z ? p.zy : p.xy);
	return texture(surface_texture,(floor(plane*texels_per_meter)+0.5)/128.0).rgb;
}
