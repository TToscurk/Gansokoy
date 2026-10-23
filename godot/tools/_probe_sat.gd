extends SceneTree
## SAT 自我測試：_obb_unit_hit 與密取樣對照。
## 重點方向：密取樣說「相交」而 SAT 說「淨空」＝ SAT 漏檢（確定的 bug，會讓石頭被放進橋台）。
## 反方向（SAT 相交、取樣淨空）可接受：SAT 較精確，取樣本來就會漏。
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const N := 400


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260928
	var miss := 0
	var hit_sat := 0
	var hit_samp := 0
	var first_bad := ""
	for i in N:
		var hv := Vector3(rng.randf_range(0.05, 1.5), rng.randf_range(0.05, 1.5), rng.randf_range(0.05, 1.5))
		var pos := Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(-1.6, 1.6), rng.randf_range(-1.6, 1.6))
		var e := Vector3(rng.randf_range(0, TAU), rng.randf_range(0, TAU), rng.randf_range(0, TAU))
		var bs := Basis.from_euler(e).scaled(Vector3(rng.randf_range(0.6, 1.6), rng.randf_range(0.6, 1.6), rng.randf_range(0.6, 1.6)))
		var xf := Transform3D(bs, pos)
		var sat: bool = RLib._obb_unit_hit(bs.orthonormalized(), pos, hv * bs.get_scale(), Transform3D.IDENTITY)
		# 密取樣：OBB 內部 16^3 點
		var samp := false
		for ix in 16:
			for iy in 16:
				for iz in 16:
					var lp := Vector3(
						hv.x * lerpf(-1.0, 1.0, float(ix) / 15.0),
						hv.y * lerpf(-1.0, 1.0, float(iy) / 15.0),
						hv.z * lerpf(-1.0, 1.0, float(iz) / 15.0))
					var q := xf * lp
					if absf(q.x) <= 1.0 and absf(q.y) <= 1.0 and absf(q.z) <= 1.0:
						samp = true
						break
				if samp:
					break
			if samp:
				break
		if sat:
			hit_sat += 1
		if samp:
			hit_samp += 1
		if samp and not sat:
			miss += 1
			if first_bad == "":
				first_bad = "hv=%s pos=%s euler=%s" % [str(hv), str(pos), str(e)]
	print("[sat] 案例 %d：SAT 判相交 %d、密取樣判相交 %d" % [N, hit_sat, hit_samp])
	print("[sat] 取樣命中但 SAT 漏檢：%d  %s" % [miss, ("→ 首例 " + first_bad) if miss > 0 else "（0＝SAT 無此方向漏檢）"])
	print("[sat] 判定：%s" % ("PASS（SAT 未漏檢）" if miss == 0 else "FAIL（SAT 有漏檢，需修）"))
	quit(0 if miss == 0 else 1)
