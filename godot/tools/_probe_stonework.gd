extends SceneTree
## 暫用探針（不進版控）：量測 P7 R2 護岸石，並自我驗證量測不是恆真。
## 指標以「石面沿自身法向往外／往內對地形打射線」判定，不用垂直高度差（陡坡上垂直取樣會誤判）。
## 用法：godot --headless --path . --script res://tools/_probe_stonework.gd [-- --json=<abs path>] [-- --selftest]

const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"

var S: RLib.TriSampler
var L: Dictionary
var lib: Dictionary
var items: Array
var P: Dictionary
var space: PhysicsDirectSpaceState3D
var terrain_rid := RID()
var other: Array[RID] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "C:/Users/B365/AppData/Local/hermes/cache/scratch/p7_rb3/stonework.json"
	var selftest := false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--json="):
			out = a.trim_prefix("--json=")
		elif a == "--selftest":
			selftest = true
	L = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	lib = RLib.load_lib()
	P = RLib.plan(v, L)
	items = P["items"]
	S = RLib.terrain_sampler(v)
	await physics_frame
	await physics_frame
	space = root.get_world_3d().direct_space_state
	var tc := v.get_node("Collision/TerrainCollision") as CollisionObject3D
	terrain_rid = tc.get_rid()
	for cs in v.get_node("Collision").find_children("*", "CollisionObject3D", true, false):
		var rid := (cs as CollisionObject3D).get_rid()
		if rid != terrain_rid and not other.has(rid):
			other.append(rid)
	var rep := {}
	rep["items"] = items.size()
	rep["kinds"] = P["stats"].get("kinds", {})
	rep["dropped"] = {"parcel": P["stats"].get("dropped_in_parcel"), "bridge": P["stats"].get("dropped_bridge"),
		"road": P["stats"].get("dropped_on_road")}
	rep["metrics"] = _metrics()
	rep["segments"] = _segments()
	if selftest:
		rep["selftest"] = _selftest()
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(rep, " ", false))
		f.close()
	print("[probe] → %s" % out)
	_summary(rep)
	v.free()
	quit(0 if not selftest or bool(rep["selftest"]["ok"]) else 1)


func _metrics() -> Array:
	var out: Array = []
	for idx in items.size():
		var k := String(items[idx]["k"])
		if not k in ["rev", "revb", "cap"]:
			continue
		out.append(_one(idx))
	return out


## 單顆護岸石：外露面（朝河／朝上）沿 +n3 打射線看地形是否擋在前方；沿 −n3 量石背到坡面距離
func _one(idx: int) -> Dictionary:
	var it: Dictionary = items[idx]
	var xf: Transform3D = it["xf"]
	var m: Mesh = lib[String(it["m"])]
	var n3 := xf.basis.z.normalized()
	var up := xf.basis.y.normalized()
	var a: Array = m.surface_get_arrays(0)
	var V: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var I: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var tot := 0.0
	var hid := 0.0
	var gap_min := INF
	var gap_sum := 0.0
	var gap_max := -INF
	var gn := 0
	var behind_hit := 0
	var fn := 0
	for t in range(0, I.size(), 3):
		var p0 := xf * V[I[t]]
		var p1 := xf * V[I[t + 1]]
		var p2 := xf * V[I[t + 2]]
		var ar := (p1 - p0).cross(p2 - p0).length() * 0.5
		if ar < 1e-9:
			continue
		var nn := (p1 - p0).cross(p2 - p0).normalized()
		if nn.dot(n3) < 0.25 and nn.dot(up) < 0.25:
			continue
		var c := (p0 + p1 + p2) / 3.0
		tot += ar
		fn += 1
		if _ray(c + n3 * 0.03, n3, 1.6) >= 0.0:
			hid += ar
		var d := _ray(c - n3 * 0.03, -n3, 2.0)
		if d >= 0.0:
			behind_hit += 1
			gap_min = minf(gap_min, d)
			gap_sum += d
			gap_max = maxf(gap_max, d)
			gn += 1
	var base := _waabb(it)
	return {"i": idx, "m": it["m"], "k": it["k"], "tag": it["tag"],
		"o": [snappedf(xf.origin.x, 0.01), snappedf(xf.origin.y, 0.01), snappedf(xf.origin.z, 0.01)],
		"vis": snappedf(1.0 - hid / maxf(tot, 1e-6), 0.001), "faces": fn,
		"gap_min": snappedf(gap_min, 0.001) if gap_min < INF else null,
		"gap_avg": snappedf(gap_sum / maxf(float(gn), 1.0), 0.001) if gn > 0 else null,
		"gap_max": snappedf(gap_max, 0.001) if gap_max > -INF else null,
		"behind_hit": behind_hit,
		"base_below": snappedf(S.h(base.get_center().x, base.get_center().z) - base.position.y, 0.001)}


## 沿 +dir 打射線，只接受地形；回傳距離（未命中 −1）
func _ray(from: Vector3, dir: Vector3, maxd: float) -> float:
	var q := PhysicsRayQueryParameters3D.new()
	q.from = from
	q.to = from + dir * maxd
	q.collision_mask = 0xFFFFFFFF
	q.exclude = other
	var h := space.intersect_ray(q)
	if h.is_empty():
		return -1.0
	var col := h["collider"] as CollisionObject3D
	if col == null or col.get_rid() != terrain_rid:
		return -1.0
	return from.distance_to(h["position"] as Vector3)


## 段：以既有 cls 的連續區間為段，段內逐站量「有沒有石」「幾層」「層距」
func _segments() -> Array:
	var rows := {}
	for idx in items.size():
		var it: Dictionary = items[idx]
		if not String(it["k"]) in ["rev", "revb", "cap"]:
			continue
		var tg := String(it["tag"])
		if not rows.has(tg):
			rows[tg] = []
		(rows[tg] as Array).append(float((it["xf"] as Transform3D).origin.y))
	var groups := {}
	for st: Dictionary in P["stats"].get("stations", []):
		var key := "%s|%s" % [st["water"], "L" if float(st["side"]) < 0 else "R"]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(st)
	var out: Array = []
	for key: String in groups:
		var arr: Array = groups[key]
		arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["s"]) < float(b["s"]))
		var samples: Array = []
		for i in arr.size():
			var st: Dictionary = arr[i]
			var cls := String(st["cls"])
			if cls == "none":
				continue
			var tg := "%s/%s/%d" % [st["water"], "L" if float(st["side"]) < 0 else "R", i]
			var ys: Array = rows.get(tg, [])
			var rec := {"s": snappedf(float(st["s"]), 0.1), "cls": cls, "n": ys.size()}
			if ys.size() > 0:
				ys.sort()
				var lay: Array = [ys[0]]
				for y: float in ys:
					if y - float(lay[lay.size() - 1]) > 0.30:
						lay.append(y)
				var gmax := 0.0
				for j in range(1, lay.size()):
					gmax = maxf(gmax, float(lay[j]) - float(lay[j - 1]))
				rec["layers"] = lay.size()
				rec["gap_max"] = snappedf(gmax, 0.01)
				rec["span"] = snappedf(float(lay[lay.size() - 1]) - float(lay[0]), 0.01)
				rec["y0"] = snappedf(float(ys[0]) - float(st["wl"]), 0.01)
				rec["y1"] = snappedf(float(ys[ys.size() - 1]) - float(st["wl"]), 0.01)
			samples.append(rec)
		out.append({"key": key, "n": samples.size(), "samples": samples, "gaps": _gaps(samples)})
	return out


func _gaps(samples: Array) -> Array:
	var g: Array = []
	var run := 0
	var s0 := 0.0
	for sv: Dictionary in samples:
		if String(sv["cls"]) == "nat":
			run = 0
			continue
		if int(sv["n"]) == 0:
			if run == 0:
				s0 = float(sv["s"])
			run += 1
		elif run > 0:
			g.append([snappedf(s0, 0.1), snappedf(float(sv["s"]), 0.1), snappedf(run * 0.1, 0.1)])
			run = 0
	if run > 0:
		g.append([snappedf(s0, 0.1), null, snappedf(run * 0.1, 0.1)])
	return g


func _waabb(it: Dictionary) -> AABB:
	var m: Mesh = lib.get(String(it["m"]))
	return (it["xf"] as Transform3D) * m.get_aabb()


## 反向案例：同一顆石以合成位移改狀態；量測必須跟著動，否則量測無效
func _selftest() -> Dictionary:
	var pick := -1
	for idx in items.size():
		if String(items[idx]["k"]) == "rev":
			pick = idx
			break
	if pick < 0:
		return {"ok": false, "why": "找不到 rev"}
	var orig: Transform3D = items[pick]["xf"]
	var res := {}
	var b0 := _one(pick)
	res["clean"] = {"vis": b0["vis"], "gap_min": b0["gap_min"]}
	var n3 := orig.basis.z.normalized()
	items[pick]["xf"] = orig.translated(n3 * 0.6)
	var b1 := _one(pick)
	res["float_out_0.6"] = {"vis": b1["vis"], "gap_min": b1["gap_min"]}
	items[pick]["xf"] = orig.translated(-n3 * 0.6)
	var b2 := _one(pick)
	res["bury_in_0.6"] = {"vis": b2["vis"], "gap_min": b2["gap_min"]}
	items[pick]["xf"] = orig
	var ok_float := (b0["gap_min"] != null and b1["gap_min"] != null and float(b1["gap_min"]) > float(b0["gap_min"]) + 0.3) \
		or float(b1["vis"]) > float(b0["vis"]) + 0.1
	var ok_bury := float(b2["vis"]) < float(b0["vis"]) - 0.1 \
		or (b2["gap_min"] != null and b0["gap_min"] != null and float(b2["gap_min"]) < float(b0["gap_min"]))
	res["ok"] = ok_float and ok_bury
	res["why"] = "float 需 vis↑或 gap↑、bury 需 vis↓或 gap↓"
	return res


func _summary(rep: Dictionary) -> void:
	var ms: Array = rep["metrics"]
	var lo := 0
	var hi := 0
	var nohit := 0
	var gap_hist := {}
	for m: Dictionary in ms:
		var v := float(m["vis"])
		if v < 0.40:
			lo += 1
		if v > 0.90:
			hi += 1
		if int(m["behind_hit"]) == 0:
			nohit += 1
		if m["gap_min"] != null:
			var bucket := snappedf(float(m["gap_min"]), 0.1)
			gap_hist[bucket] = int(gap_hist.get(bucket, 0)) + 1
	print("[probe] 護岸石 %d｜可見<40%% %d（%.0f%%）、>90%% %d；石背後完全找不到地形 %d" % [
		ms.size(), lo, 100.0 * lo / maxf(float(ms.size()), 1.0), hi, nohit])
	print("[probe] gap_min（石背到地形最近距離）分布 %s" % gap_hist)
	print("[probe] kinds %s；dropped %s" % [rep["kinds"], rep["dropped"]])
	var ngap := 0
	var worst := 0.0
	var worst_s := ""
	var lay_bad := 0
	var lay_n := 0
	var layhist := {}
	for seg: Dictionary in rep["segments"]:
		for g: Array in seg["gaps"]:
			ngap += 1
			if float(g[2]) > worst:
				worst = float(g[2])
				worst_s = "%s s=%s" % [seg["key"], g[0]]
		for sv: Dictionary in seg["samples"]:
			if String(sv["cls"]) == "nat":
				continue
			lay_n += 1
			var l2 := int(sv.get("layers", 0))
			layhist[l2] = int(layhist.get(l2, 0)) + 1
			if l2 < 2 or l2 > 4 or float(sv.get("gap_max", 0.0)) > 1.2:
				lay_bad += 1
	print("[probe] 段 %d；人工護岸空窗 %d、最長 %.1f m（%s）" % [rep["segments"].size(), ngap, worst, worst_s])
	print("[probe] 人工護岸站點 %d：層數分布 %s；不合（<2 或 >4 層或層距>1.2 m）%d" % [lay_n, layhist, lay_bad])
	if rep.has("selftest"):
		print("[probe] 自檢 %s（%s）" % ["PASS" if rep["selftest"]["ok"] else "FAIL", rep["selftest"]])
