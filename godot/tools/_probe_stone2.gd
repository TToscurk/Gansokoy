extends SceneTree
## 暫用探針（不進版控）：P7 R2 護岸石 stonework cleanup 量測。
## 判準＝「面的重心在地形面之上／之下」的深度測試（與方向無關，避免 +Z／−Z 慣例誤判）。
##   vis      = 露出地形的面積 / 石頭總面積            （使用者要 40–70%）
##   top_vis  = 朝上面積中露出地形的比例                （「上表面／迎水面必須可見」）
##   dip      = 地形面高出石底多少（>0＝底部埋入，允許）
##   float_gap= 石頭最低點離地形面多少（>0.05＝浮空）
## 用法：godot --headless --path . --script res://tools/_probe_stone2.gd [-- --json=<abs>] [-- --selftest]

const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"

const KINDS: Array[String] = ["rev", "revb", "cap", "bld", "cob", "shig", "flag", "step", "land", "curb"]

var S: RLib.TriSampler
var lib: Dictionary
var items: Array


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "C:/Users/B365/AppData/Local/hermes/cache/scratch/p7_rb3/sw.json"
	var selftest := false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--json="):
			out = a.trim_prefix("--json=")
		elif a == "--selftest":
			selftest = true
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	lib = RLib.load_lib()
	var P: Dictionary = RLib.plan(v, L)
	items = P["items"]
	S = RLib.terrain_sampler(v)
	await physics_frame
	await physics_frame
	var rep := {}
	rep["items"] = items.size()
	rep["kinds"] = P["stats"].get("kinds", {})
	rep["metrics"] = _metrics()
	rep["stations"] = P["stats"].get("stations", [])
	rep["segments"] = P["stats"].get("segments", [])
	if selftest:
		rep["selftest"] = _selftest()
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(rep, " ", false))
		f.close()
	print("[sw] → %s" % out)
	_summary(rep)
	v.free()
	quit(0 if not selftest or bool(rep["selftest"]["ok"]) else 1)


func _metrics() -> Array:
	var out: Array = []
	for idx in items.size():
		var it: Dictionary = items[idx]
		if not KINDS.has(String(it["k"])):
			continue
		out.append(_one(idx))
	return out


## 單顆：逐三角面比對地形高度
func _one(idx: int) -> Dictionary:
	var it: Dictionary = items[idx]
	var xf: Transform3D = it["xf"]
	var m: Mesh = lib.get(String(it["m"]))
	if m == null:
		return {}
	var a: Array = m.surface_get_arrays(0)
	var V: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var I: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var n3 := xf.basis.z.normalized()
	var tot := 0.0
	var above := 0.0
	var top_tot := 0.0
	var top_above := 0.0
	var f_tot := 0.0            # 面板局部 +Z（設計上的可見面）
	var f_above := 0.0
	var b_tot := 0.0            # 面板局部 −Z（石背）
	var b_above := 0.0
	var deepest := -INF        # 埋最深的點（地形 − 點高）
	var highest_gap := -INF    # 露出最多的點（點高 − 地形）
	var wy := INF
	for t in range(0, I.size(), 3):
		var p0 := xf * V[I[t]]
		var p1 := xf * V[I[t + 1]]
		var p2 := xf * V[I[t + 2]]
		var cr := (p1 - p0).cross(p2 - p0)
		var ar := cr.length() * 0.5
		if ar < 1e-9:
			continue
		var c := (p0 + p1 + p2) / 3.0
		tot += ar
		var nz := cr.normalized().dot(n3)
		var th := S.h(c.x, c.z)
		var exposed := is_nan(th) or c.y > th
		if is_nan(th):
			above += ar
		if nz > 0.5:
			f_tot += ar
			if exposed:
				f_above += ar
		elif nz < -0.5:
			b_tot += ar
			if exposed:
				b_above += ar
		if is_nan(th):
			continue
		var up := absf(cr.normalized().y) > 0.4
		if up:
			top_tot += ar
		if c.y > th:
			above += ar
			if c.y - th > highest_gap:
				highest_gap = c.y - th
			if up:
				top_above += ar
		else:
			if th - c.y > deepest:
				deepest = th - c.y
	for pv: Vector3 in V:
		var wp := xf * pv
		var th2 := S.h(wp.x, wp.z)
		if is_nan(th2):
			continue
		wy = minf(wy, wp.y - th2)
	var az := xf * m.get_aabb()
	return {"i": idx, "m": it["m"], "k": it["k"], "tag": it["tag"],
		"o": [snappedf(xf.origin.x, 0.01), snappedf(xf.origin.y, 0.01), snappedf(xf.origin.z, 0.01)],
		"vis": snappedf(above / maxf(tot, 1e-6), 0.001),
		"front_exposed": (snappedf(f_above / maxf(f_tot, 1e-6), 0.001) if f_tot > 1e-6 else null),
		"back_exposed": (snappedf(b_above / maxf(b_tot, 1e-6), 0.001) if b_tot > 1e-6 else null),
		"top_vis": snappedf(top_above / maxf(top_tot, 1e-6), 0.001) if top_tot > 1e-6 else null,
		"dip": snappedf(deepest, 0.001) if deepest > -INF else null,
		"float_gap": snappedf(wy, 0.001) if wy < INF else null,
		"sz": [snappedf(az.size.x, 0.01), snappedf(az.size.y, 0.01), snappedf(az.size.z, 0.01)]}


## 反向案例：把一顆石頭往下推 0.5 m，vis 必須下降、dip 必須上升
func _selftest() -> Dictionary:
	var pick := -1
	for idx in items.size():
		if String(items[idx]["k"]) == "rev":
			pick = idx
			break
	if pick < 0:
		return {"ok": false, "why": "找不到 rev"}
	var orig: Transform3D = items[pick]["xf"]
	var b0 := _one(pick)
	items[pick]["xf"] = orig.translated(Vector3(0, -0.5, 0))
	var b1 := _one(pick)
	items[pick]["xf"] = orig.translated(Vector3(0, 0.5, 0))
	var b2 := _one(pick)
	items[pick]["xf"] = orig
	var ok_down: bool = float(b1["vis"]) < float(b0["vis"]) - 0.02
	var ok_up: bool = float(b2["vis"]) > float(b0["vis"]) + 0.02
	return {"ok": ok_down and ok_up, "clean_vis": b0["vis"], "down0.5_vis": b1["vis"], "up0.5_vis": b2["vis"],
		"why": "石頭下移 vis 必須下降、上移必須上升"}


func _summary(rep: Dictionary) -> void:
	var ms: Array = rep["metrics"]
	var hist := {}
	for m: Dictionary in ms:
		if m.is_empty():
			continue
		hist[String(m["k"])] = int(hist.get(String(m["k"]), 0)) + 1
	print("[sw] 件 %d；kinds %s" % [ms.size(), hist])
	for k: String in ["rev", "cap", "cob", "bld", "shig"]:
		var vs: Array = []
		var tv: Array = []
		for m: Dictionary in ms:
			if not m.is_empty() and String(m["k"]) == k:
				vs.append(float(m["vis"]))
				if m["top_vis"] != null:
					tv.append(float(m["top_vis"]))
		if vs.is_empty():
			continue
		vs.sort()
		tv.sort()
		var lo := 0
		var ok := 0
		for vv: float in vs:
			if vv < 0.40:
				lo += 1
			elif vv <= 0.70:
				ok += 1
		var tmed := float(tv[tv.size() / 2]) if not tv.is_empty() else -1.0
		print("[sw]   %-5s n=%4d vis 中位 %.3f｜<40%% %d（%.0f%%）、40–70%% %d（%.0f%%）｜top_vis 中位 %.3f" % [
			k, vs.size(), vs[vs.size() / 2], lo, 100.0 * lo / vs.size(), ok, 100.0 * ok / vs.size(), tmed])
	var fl := 0
	var over := 0
	for m: Dictionary in ms:
		if m.is_empty():
			continue
		if m["float_gap"] != null and float(m["float_gap"]) > 0.05:
			fl += 1
		if float(m["vis"]) > 0.90:
			over += 1
	print("[sw] 浮空（最低點離地 >0.05 m）%d；過度外露（vis>0.90）%d" % [fl, over])
	if rep.has("selftest"):
		print("[sw] 自檢 %s %s" % ["PASS" if rep["selftest"]["ok"] else "FAIL", rep["selftest"]])
