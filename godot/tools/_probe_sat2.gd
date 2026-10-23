extends SceneTree
## 決定性診斷：找出「lib._bridge_hit 說淨空、但實際與碰撞盒重疊」的每一件，
## 並列出最近碰撞盒的名稱與距離 → 區分兩種根因：
##   (a) 該碰撞盒根本不在 _bridge_boxes 清單裡（清單漏收，例如非 CollisionShape3D）
##   (b) 盒子在清單裡但 SAT 漏檢（幾何 bug）
## 另做合成自測：SAT vs 密取樣，確認 SAT 本身無漏檢。
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"


func _init() -> void:
	_sat_selftest()
	_scan()
	quit()


func _sat_selftest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260928
	var miss := 0
	var hs := 0
	var hp := 0
	for i in 300:
		var hv := Vector3(rng.randf_range(0.05, 1.5), rng.randf_range(0.05, 1.5), rng.randf_range(0.05, 1.5))
		var pos := Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(-1.6, 1.6), rng.randf_range(-1.6, 1.6))
		var e := Vector3(rng.randf_range(0, TAU), rng.randf_range(0, TAU), rng.randf_range(0, TAU))
		var bs := Basis.from_euler(e).scaled(Vector3(rng.randf_range(0.6, 1.6), rng.randf_range(0.6, 1.6), rng.randf_range(0.6, 1.6)))
		var sat: bool = RLib._obb_unit_hit(bs.orthonormalized(), pos, hv, Transform3D.IDENTITY)
		var samp := false
		for ix in 12:
			for iy in 12:
				for iz in 12:
					var p := pos + bs * Vector3(
						hv.x * lerpf(-1.0, 1.0, float(ix) / 11.0),
						hv.y * lerpf(-1.0, 1.0, float(iy) / 11.0),
						hv.z * lerpf(-1.0, 1.0, float(iz) / 11.0))
					if absf(p.x) <= 1.0 and absf(p.y) <= 1.0 and absf(p.z) <= 1.0:
						samp = true
						break
				if samp:
					break
			if samp:
				break
		if sat:
			hs += 1
		if samp:
			hp += 1
		if samp and not sat:
			miss += 1
	print("[sat2] 合成自測 300 例：SAT 相交 %d、密取樣相交 %d、取樣命中但 SAT 漏檢 %d → %s" % [
		hs, hp, miss, "SAT 可用" if miss == 0 else "SAT 有漏檢"])


func _scan() -> void:
	var ps: PackedScene = load(SCENE)
	if ps == null:
		print("[sat2] 場景載入失敗")
		return
	var vroot: Node3D = ps.instantiate()
	get_root().add_child(vroot)
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var P: Dictionary = RLib.plan(vroot, L)
	var items: Array = P["items"]
	var boxes: Array = RLib._bridge_boxes(vroot)
	print("[sat2] items=%d boxes=%d" % [items.size(), boxes.size()])
	var miss := 0
	var shown := 0
	for it: Dictionary in items:
		if RLib._bridge_hit(it, boxes, P["bridges"]) != "":
			continue
		var xf: Transform3D = it["xf"]
		var ma: AABB = RLib.mesh_aabb(String(it["m"]))
		var sc := xf.basis.get_scale()
		var half := ma.size * sc * 0.8 * 0.5
		var cw: Vector3 = xf * ma.get_center()
		var inv_rot := xf.basis.orthonormalized()
		var near := ""
		var nd := 1e9
		var hit_box := ""
		for bx: Array in boxes:
			var d: float = (bx[1] as Vector3).distance_to(cw)
			if d < nd:
				nd = d
				near = String(bx[3]) if bx.size() > 3 else "?"
			if d > float(bx[2]) + half.length() + 0.5:
				continue
			if RLib._obb_unit_hit(inv_rot, cw, half, bx[0] as Transform3D):
				hit_box = String(bx[3]) if bx.size() > 3 else "?"
				break
		if hit_box != "":
			miss += 1
			if shown < 8:
				shown += 1
				print("[sat2] 漏檢 k=%s m=%s tag=%s o=(%.2f,%.2f,%.2f) 壓到 %s；最近盒 %s 距 %.2f m" % [
					String(it["k"]), String(it["m"]), String(it["tag"]),
					xf.origin.x, xf.origin.y, xf.origin.z, hit_box, near, nd])
	print("[sat2] _bridge_hit 說淨空、SAT 說壓到：%d 件" % miss)
