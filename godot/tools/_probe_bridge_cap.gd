extends SceneTree
## 診斷：違規件 cap@(347.8, 1.0, -123.9) 為什麼通過 lib 的橋體淨空檢查、
## 卻被 gate 的物理查詢判為壓到 Bridge_01 的 Hero/Collision。
## 目的：區分「lib 量尺漏檢（離散取樣太疏）」與「保留邏輯漏洞」。
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const TARGET := Vector3(347.8, 1.0, -123.9)


func _init() -> void:
	var ps: PackedScene = load(SCENE)
	if ps == null:
		print("[bc] 場景載入失敗")
		quit(1)
		return
	var vroot: Node3D = ps.instantiate()
	get_root().add_child(vroot)
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var P: Dictionary = RLib.plan(vroot, L)
	var items: Array = P["items"]
	var boxes: Array = RLib._bridge_boxes(vroot)
	var brs: Array = P["bridges"]
	print("[bc] items=%d boxes=%d brs=%d" % [items.size(), boxes.size(), brs.size()])

	var bi := -1
	var bd := 1e9
	for i in items.size():
		var o: Vector3 = (items[i]["xf"] as Transform3D).origin
		var d := o.distance_to(TARGET)
		if d < bd:
			bd = d
			bi = i
	var it: Dictionary = items[bi]
	var xf: Transform3D = it["xf"]
	print("[bc] 最近件 idx=%d k=%s m=%s tag=%s" % [bi, String(it["k"]), String(it["m"]), String(it["tag"])])
	var sc0: Vector3 = xf.basis.get_scale()
	print("[bc]   origin (%.3f, %.3f, %.3f)  距目標 %.4f m   scale %s" % [
		xf.origin.x, xf.origin.y, xf.origin.z, bd, str(sc0)])
	print("[bc] _bridge_hit → '%s'" % RLib._bridge_hit(it, boxes, brs))
	print("[bc] _hits_bridge → %s" % str(RLib._hits_bridge(it, boxes, brs)))

	# 逐 box 用同款取樣（離散點）與「連續 OBB」兩種量尺比對，找出是哪一種漏掉
	var hv: Vector3 = RLib.HALF.get(String(it["k"]), Vector3(0.5, 0.5, 0.5))
	var cv: Vector3 = RLib.CEN.get(String(it["k"]), Vector3.ZERO)
	var sc := xf.basis.get_scale()
	var hits_disc := 0
	var hits_cont := 0
	var nearest := ""
	var nd := 1e9
	for bx: Array in boxes:
		if (bx[1] as Vector3).distance_to(xf.origin) > float(bx[2]) + (hv * sc).length():
			continue
		var nm := String(bx[3]) if bx.size() > 3 else "?"
		var inv: Transform3D = bx[0]
		# 連續量尺：OBB 8 角 + 中心
		var cont := false
		for cx: float in [-1.0, 1.0]:
			for cy: float in [-1.0, 1.0]:
				for cz: float in [-1.0, 1.0]:
					var p := xf * (cv + Vector3(hv.x * cx, hv.y * cy, hv.z * cz))
					var q: Vector3 = inv * p
					if absf(q.x) < 1.0 and absf(q.y) < 1.0 and absf(q.z) < 1.0:
						cont = true
		if cont:
			hits_cont += 1
			nearest = nm
		# 離散量尺：與 _bridge_hit 完全相同
		var nx := clampi(int(ceil(hv.x * sc.x * 1.6 / 0.25)), 2, 12)
		var ny := clampi(int(ceil(hv.y * sc.y * 1.6 / 0.25)), 2, 12)
		var disc := false
		for ix in nx + 1:
			for iy in ny + 1:
				for sz: float in [-0.8, 0.0, 0.8]:
					var p := xf * (cv + Vector3(hv.x * lerpf(-0.8, 0.8, float(ix) / nx), hv.y * lerpf(-0.8, 0.8, float(iy) / ny), hv.z * sz))
					var q: Vector3 = inv * p
					if absf(q.x) < 1.0 and absf(q.y) < 1.0 and absf(q.z) < 1.0:
						disc = true
		if disc:
			hits_disc += 1
	print("[bc] 重疊統計：離散取樣(現行 _bridge_hit) 命中 %d 個 box；連續 OBB 命中 %d 個（最近 %s）" % [
		hits_disc, hits_cont, nearest])
	quit()
