extends RefCounted


static func build(
		block: Callable,
		kitify: Callable,
		dump: Array,
		audit: Array[String]) -> Dictionary:
	block.call(201, {
		"name": "西外・本通北",
		"frontage": {"a": Vector2(-109.00, 22.80), "b": Vector2(-151.00, 22.80)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "b",
	})
	block.call(202, {
		"name": "西外・本通南",
		"frontage": {"a": Vector2(-151.00, 37.20), "b": Vector2(-109.00, 37.20)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "a",
	})
	block.call(203, {
		"name": "稗田南町",
		"frontage": {"a": Vector2(-99.00, 37.20), "b": Vector2(-57.00, 37.20)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "b",
	})
	block.call(101, {
		"name": "西北(R1)",
		"frontage": {"a": Vector2(10.00, 22.80), "b": Vector2(52.00, 22.80)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		# river_end 拿掉：這段西岸已經給鯢吞亭了（兩者都被推到同一條河法線上，
		# 彼此完全不知道對方存在 → 實測互穿 6.8m）。臨河的門面由鯢吞亭擔。
		"wrap": "L", "wrap_end": "a",
	})
	block.call(103, {
		"name": "東北・高壓",
		"frontage": {"a": Vector2(77.60, 23.40), "b": Vector2(100.60, 23.40)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_b_a", "machiya_b_b"], "setback": 0.4, "jog": [1.0, 1.8]},
				{"kinds": ["machiya_f_a", "machiya_f_b"], "gap": [2.6, 3.6], "lateral": 4.2},
		],
	})
	block.call(206, {
		"name": "東・本通北",
		"frontage": {"a": Vector2(107.65, 22.80), "b": Vector2(151.50, 22.80)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "b",
	})
	block.call(208, {
		"name": "東・本通南",
		"frontage": {"a": Vector2(107.65, 37.20), "b": Vector2(151.50, 37.20)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "b",
	})
	var c209 := {
		"name": "本通西・北",
		"frontage": {"a": Vector2(-5.50, -129.90), "b": Vector2(-5.50, -83.90)},
		"into": Vector2(-1.0000, 0.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "a",
	}
	block.call(209, kitify.call(c209))
	var c210 := {
		"name": "本通東・北",
		"frontage": {"a": Vector2(5.50, -83.90), "b": Vector2(5.50, -129.70)},
		"into": Vector2(1.0000, 0.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "b",
	}
	block.call(210, kitify.call(c210))
	block.call(211, {
		"name": "本通西・南",
		"frontage": {"a": Vector2(-5.50, 90.10), "b": Vector2(-5.50, 136.10)},
		"into": Vector2(-1.0000, 0.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "a",
	})
	block.call(212, {
		"name": "本通西・南外",
		"frontage": {"a": Vector2(-5.50, 143.90), "b": Vector2(-5.50, 186.00)},
		"into": Vector2(-1.0000, 0.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
	})
	block.call(213, {
		"name": "本通東・南外",
		"frontage": {"a": Vector2(5.50, 186.00), "b": Vector2(5.50, 143.90)},
		"into": Vector2(1.0000, 0.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
		],
	})
	var c214 := {
		"name": "本通西・北端",
		"frontage": {"a": Vector2(-5.50, -162.00), "b": Vector2(-5.50, -138.90)},
		"into": Vector2(-1.0000, 0.0000),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.8]},
		],
	}
	block.call(214, kitify.call(c214))
	var c215 := {
		"name": "本通東・北端",
		"frontage": {"a": Vector2(5.50, -138.90), "b": Vector2(5.50, -162.00)},
		"into": Vector2(1.0000, 0.0000),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.8]},
		],
	}
	block.call(215, kitify.call(c215))
	block.call(216, {
		"name": "北在・西",
		"frontage": {"a": Vector2(-55.65, -83.90), "b": Vector2(-97.00, -83.90)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.8]},
		],
	})
	block.call(217, {
		"name": "北在・西外",
		"frontage": {"a": Vector2(-107.65, -83.90), "b": Vector2(-142.00, -83.90)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.8]},
		],
	})
	block.call(218, {
		"name": "寺子屋西町",
		"frontage": {"a": Vector2(-97.00, -76.10), "b": Vector2(-57.00, -76.10)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "b",
	})
	block.call(219, {
		"name": "西外・北町",
		"frontage": {"a": Vector2(-107.65, -28.65), "b": Vector2(-145.00, -28.65)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
		],
	})
	block.call(220, {
		"name": "西外・南町",
		"frontage": {"a": Vector2(-145.00, -21.35), "b": Vector2(-107.65, -21.35)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
		],
	})
	block.call(221, {
		"name": "市場西・北",
		"frontage": {"a": Vector2(-55.65, 81.10), "b": Vector2(-97.00, 81.10)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
		],
	})
	block.call(222, {
		"name": "市場西・南",
		"frontage": {"a": Vector2(-97.00, 88.90), "b": Vector2(-55.65, 88.90)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "a",
	})
	block.call(223, {
		"name": "西外・南",
		"frontage": {"a": Vector2(-107.65, 136.10), "b": Vector2(-149.00, 136.10)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.8]},
		],
	})
	block.call(224, {
		"name": "西外・在",
		"frontage": {"a": Vector2(-142.00, 143.90), "b": Vector2(-107.65, 143.90)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.8]},
		],
	})
	block.call(225, {
		"name": "南町・西北",
		"frontage": {"a": Vector2(-55.65, 136.10), "b": Vector2(-97.00, 136.10)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
		],
	})
	block.call(226, {
		"name": "南在・西",
		"frontage": {"a": Vector2(-97.00, 143.90), "b": Vector2(-55.65, 143.90)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.8]},
		],
	})
	block.call(227, {
		"name": "東外・北町",
		"frontage": {"a": Vector2(107.65, -28.65), "b": Vector2(149.00, -28.65)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
		],
	})
	block.call(228, {
		"name": "東外・南町",
		"frontage": {"a": Vector2(149.00, -21.35), "b": Vector2(107.65, -21.35)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
		],
	})
	block.call(229, {
		"name": "東外・北",
		"frontage": {"a": Vector2(107.65, 81.10), "b": Vector2(149.00, 81.10)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
		],
	})
	block.call(230, {
		"name": "東外・南",
		"frontage": {"a": Vector2(149.00, 88.90), "b": Vector2(107.65, 88.90)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
		],
	})
	block.call(231, {
		"name": "東外・在",
		"frontage": {"a": Vector2(107.65, 136.10), "b": Vector2(145.00, 136.10)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.8]},
		],
	})
	block.call(302, {
		"name": "河西・北町",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(70.29, -129.00), "b": Vector2(65.55, -84.00)},
		"into": Vector2(-0.9945, -0.1048),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.6]},
		],
		"riverside": true,
	})
	block.call(303, {
		"name": "河西・橋北",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(49.51, -21.35), "b": Vector2(50.32, 1.00)},
		"into": Vector2(-0.9993, 0.0364),
		"rows": [
				{"kinds": ["machiya_f_a"], "setback": 0.8, "jog": [1.0, 1.6]},
		],
		"riverside": true,
	})
	block.call(305, {
		"name": "河西・橋南",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(63.30, 58.00), "b": Vector2(64.28, 82.00)},
		"into": Vector2(-0.9992, 0.0407),
		"rows": [
				{"kinds": ["machiya_f_a"], "setback": 0.8, "jog": [1.0, 1.6]},
		],
		"riverside": true,
	})
	block.call(104, {
		"name": "東南・低開",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(83.32, 41.80), "b": Vector2(90.03, 63.80)},
		"into": Vector2(0.9565, -0.2917),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 2.2, "jog": [1.2, 2.0]},
		],
		"riverside": true,
	})
	block.call(307, {
		"name": "河東・橋南",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(90.02, 64.01), "b": Vector2(89.78, 80.01)},
		"into": Vector2(0.9999, 0.0154),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.6]},
		],
		"riverside": true,
	})
	block.call(308, {
		"name": "河東・南",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(87.17, 88.94), "b": Vector2(75.89, 122.04)},
		"into": Vector2(0.9465, 0.3227),
		"rows": [
				{"kinds": ["machiya_f_a"], "setback": 0.8, "jog": [1.0, 1.6]},
		],
		"riverside": true,
	})
	block.call(309, {
		"name": "河西・最南",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(44.30, 145.97), "b": Vector2(43.59, 173.97)},
		"into": Vector2(-0.9997, -0.0255),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.6]},
		],
		"riverside": true,
	})
	block.call(310, {
		"name": "河東・最南",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(70.24, 143.90), "b": Vector2(68.67, 172.00)},
		"into": Vector2(0.9984, 0.0557),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.6]},
		],
		"riverside": true,
	})
	block.call(311, {
		"name": "河東・鈴奈庵對岸",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(88.15, -76.10), "b": Vector2(74.53, -42.00)},
		"into": Vector2(0.9287, 0.3707),
		"rows": [
				{"kinds": ["machiya_f_a"], "setback": 0.8, "jog": [1.0, 1.6]},
		],
		"riverside": true,
	})
	block.call(312, {
		"name": "河東・橋北",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(73.36, -21.35), "b": Vector2(73.92, -6.00)},
		"into": Vector2(0.9993, -0.0370),
		"rows": [
				{"kinds": ["machiya_f_a"], "setback": 0.8, "jog": [1.0, 1.6]},
		],
		"riverside": true,
	})
	var nh := 0
	for e in dump:
		if String(e[0]).begins_with("machiya"):
			nh += 1
	audit.append("街區 → 町家 %d 棟" % nh)
	return {
		"209": c209,
		"210": c210,
		"214": c214,
		"215": c215,
	}
