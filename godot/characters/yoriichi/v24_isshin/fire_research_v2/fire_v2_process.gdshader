// FIRE_RESEARCH_V2 粒子運動（全部由腳本 emit_particle 手動發射到世界座標）。
// CUSTOM：x＝年齡（秒），y＝壽命（秒），z＝種子，w＝種類（0 刀路火舌、1 刀身小火、2 命中爆燃、3 火星）。
// 大火舌、小火、爆燃、火星各用不同的浮力、阻力與擾動：大火舌慢慢上浮、火星快而有重量。
shader_type particles;
render_mode disable_force, disable_velocity;

uniform float time_scale = 1.0;   // Hit Stop＝0：粒子照常被處理（新發射的不會遺失），但年齡與位置不前進

void start() {
	if (RESTART_CUSTOM) {
		ACTIVE = false;
	}
}

void process() {
	float dt = DELTA * time_scale;
	CUSTOM.x += dt;
	float age = CUSTOM.x / max(CUSTOM.y, 0.01);
	float k = CUSTOM.w;
	float s = CUSTOM.z;
	vec3 acc;
	float drag;
	if (k > 2.5) {          // 火星：受重力但被熱氣托住一點，左右擾動
		acc = vec3(sin(s * 41.0 + CUSTOM.x * 9.0) * 2.2, -3.2, cos(s * 37.0 + CUSTOM.x * 8.0) * 2.2);
		drag = 1.1;
	} else if (k > 1.5) {   // 命中爆燃：噴出後迅速減速、轉為上浮
		acc = vec3(0.0, 2.4, 0.0);
		drag = 6.5;
	} else if (k > 0.5) {   // 刀身小火：輕、往上竄
		acc = vec3(sin(s * 23.0 + CUSTOM.x * 6.0) * 0.6, 2.2, cos(s * 19.0 + CUSTOM.x * 5.0) * 0.6);
		drag = 3.2;
	} else {                // 刀路火舌：保留一點刀的速度後慢慢浮起
		acc = vec3(sin(s * 31.0 + CUSTOM.x * 4.0) * 0.5, 1.6, cos(s * 29.0 + CUSTOM.x * 4.5) * 0.5);
		drag = 4.0;
	}
	VELOCITY += acc * dt;
	VELOCITY *= exp(-drag * dt);
	TRANSFORM[3].xyz += VELOCITY * dt;
	if (k > 2.5) {          // 火星沿速度拉長（動態模糊感）；長度依速度，慢下來就變回小點
		float sp = length(VELOCITY);
		vec3 dir = sp > 0.01 ? VELOCITY / sp : vec3(0.0, 1.0, 0.0);
		TRANSFORM[1].xyz = dir * clamp(sp * 0.016, 0.018, 0.13);
	}
	if (age >= 1.0) {
		ACTIVE = false;
	}
}
