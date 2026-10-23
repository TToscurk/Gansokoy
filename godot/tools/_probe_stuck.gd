extends SceneTree
## 暫用探針（不進版控）：對「最終仍在帶外」的護岸石，掃描 2D（沿河向外 × 垂直）
## 位移，回答一個問題：是否存在任何合法解（不浮空、石背仍有地形）能讓它落進 40–70 %。
## 若無 → 幾何死結，只能回報；若有 → 是我的求解器不夠好，該修。
## 用法：godot --headless --path . --script res://tools/_probe_stuck.gd -- --out=<path>

const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"

var S: RLib.TriSampler


func _init() -> void:
	var out_path := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.trim_prefix("--out=")
	var v := (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	var Lj: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var lib := RLib.load_lib()
	var P: Dictionary = RLib.plan(v, Lj)
	var items: Array = P["items"]
	S = RLib.terrain_sampler(v)
	var R := RLib.road_sampler(v)

	var st_by_key := {}
	var cnt := {}
	for st: Dictionary in P["stats"].get("stations", []):
		var w := String(st["water"])
		var side := "L" if float(st["side"]) < 0.0 else "R"
		var k := "%s|%s" % [w, side]
		var i := int(cnt.get(k, 0))
		cnt[k] = i + 1
		if not st_by_key.has(k):
			st_by_key[k] = []
		(st_by_key[k] as Array).append(st)

	var lines: Array = []
	lines.append("tag\tkind\trow\tvis_now\tbest_vis\tbest_move\trej_float\trej_back\tin_band_possible")
	var n_stuck := 0
	var n_possible := 0
	var n_float := 0
	var n_back := 0
	for it: Dictionary in items:
		if not RLib.SETTLE_KINDS.has(String(it["k"])):
			continue
		var m: Mesh = lib.get(String(it["m"]))
		if m == null:
			continue
		var o := RLib._outward_of(it, st_by_key)
		if o == Vector3.ZERO:
			continue
		var xf: Transform3D = it["xf"]
		var v0 := RLib._exposure(m, xf, S, o)
		if v0 < 0.0 or (v0 >= RLib.SETTLE_LO and v0 <= RLib.SETTLE_HI):
			continue
		n_stuck += 1
		var best := -1.0
		var best_mv := ""
		var rf := 0
		var rb := 0
		for oi in range(-14, 15):                       # 沿河向外 ±0.35 m
			var hd := float(oi) * 0.025
			for vi in range(-10, 11):                   # 垂直 ±0.25 m
				var sv := float(vi) * 0.025
				if absf(hd) > RLib.SETTLE_MOVE or absf(sv) > RLib.SETTLE_SINK:
					continue
				var off := o * hd + Vector3(0, -sv, 0)
				var txf := xf.translated(off)
				if RLib._lowest_gap(m, txf, S, R) > RLib.SETTLE_FLOAT:
					rf += 1
					continue
				if RLib._back_out(m, txf, S, o) > RLib.SETTLE_BACK:
					rb += 1
					continue
				var vv := RLib._exposure(m, txf, S, o)
				if vv < 0.0:
					continue
				# 偏好最接近帶中心且位移最小
				var cost := 0.0
				if vv < RLib.SETTLE_LO:
					cost = RLib.SETTLE_LO - vv
				elif vv > RLib.SETTLE_HI:
					cost = vv - RLib.SETTLE_HI
				if best < 0.0 or cost < 0.0:
					pass
				if _better(vv, hd, sv, best, best_mv):
					best = vv
					best_mv = "%.3f,%.3f" % [hd, sv]
		var inband := best >= RLib.SETTLE_LO and best <= RLib.SETTLE_HI
		if inband:
			n_possible += 1
		if rf > 0:
			n_float += 1
		if rb > 0:
			n_back += 1
		lines.append("%s\t%s\t%s\t%.2f\t%.2f\t%s\t%d\t%d\t%s" % [
			String(it["tag"]), String(it["k"]), str(it.get("row", -1)), v0, best, best_mv, rf, rb,
			"YES" if inband else "no"])
	lines.append("")
	lines.append("帶外石數 %d；其中掃描後可進帶 %d；曾因浮空被拒 %d；曾因石背無地形被拒 %d"
		% [n_stuck, n_possible, n_float, n_back])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines))
		f.close()
	print("[STUCK] → %s（帶外 %d、可進帶 %d）" % [out_path, n_stuck, n_possible])
	v.free()
	quit(0)


func _better(vv: float, hd: float, sv: float, best: float, best_mv: String) -> bool:
	if best < 0.0:
		return true
	var c_new := _cost(vv)
	var c_old := _cost(best)
	if c_new < c_old - 1e-9:
		return true
	if absf(c_new - c_old) <= 1e-9:
		return absf(hd) + absf(sv) < _mv_norm(best_mv) - 1e-9
	return false


func _cost(v: float) -> float:
	if v < RLib.SETTLE_LO:
		return RLib.SETTLE_LO - v
	if v > RLib.SETTLE_HI:
		return v - RLib.SETTLE_HI
	return 0.0


func _mv_norm(s: String) -> float:
	var p := s.split(",")
	if p.size() != 2:
		return 1e9
	return absf(float(p[0])) + absf(float(p[1]))
