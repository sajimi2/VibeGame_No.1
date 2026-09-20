// 人物附近的厚墙/斜屋面会穿过中心深度，不能用一个硬平面把透视圆切成折角。
// 为身体与墙厚留出 0.85m 完全透视余量，再用 1m 深度过渡接回后方场景。
float occlusion_foreground(float signed_depth) {
	return smoothstep(-1.85,-0.85,signed_depth);
}
