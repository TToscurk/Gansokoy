// 全景天空＋地平線抬升
// 2:1 等距長方全景圖的山全畫在地平線帶（仰角 0°附近），站在村裡會被
// 近景丘陵整條遮掉。horizon_lift 把取樣方向往下偏，等於把圖裡的山
// 「抬」到丘陵天際線之上；低於抬升後地平線的部分反正被場景地面遮住。
shader_type sky;

uniform sampler2D panorama: source_color, filter_linear_mipmap, repeat_enable;
uniform float horizon_lift: hint_range(0.0, 0.35) = 0.14;
uniform float energy: hint_range(0.0, 2.0) = 1.0;

void sky() {
	vec3 dir = EYEDIR;
	vec3 d = normalize(vec3(dir.x, dir.y - horizon_lift, dir.z));
	vec2 uv = vec2(
		atan(d.x, -d.z) / (2.0 * PI) + 0.5,
		0.5 - asin(clamp(d.y, -1.0, 1.0)) / PI);
	COLOR = texture(panorama, uv).rgb * energy;
}
