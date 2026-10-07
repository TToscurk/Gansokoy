extends SceneTree
## 人間之里 V2 P7 R3：Riverbank Stonework Gate（護岸石砌築清理）
## 使用者 2026-09-28 指定四項：
##   1 每段護岸 stone coverage 不得有明顯空窗
##   2 可見比例過低的石塊 FAIL（40–70 % 為目標；< 40 %＝只露一角／被切掉一半以上）
##   3 浮空或過度外露 FAIL
##   4 玩家 1.7 m 視角沿河抽查（--render；不只看俯視圖）
##
## 量測方式：不依賴 mesh 繞向／法線正負（前兩版探針曾在這點上互相矛盾），改用
##   由「石面取樣點往外（朝河）半球方向打射線、只看地形是否擋住」求可見比例。
##   可見比例 0＝整顆埋在坡裡，1＝整個迎水面都露出來。
##   另有：最低點離地（浮空）、背後是否貼坡（石列與坡面分離／背後空洞）、逐列層數。
##
## 用法：
##   godot --headless --path . --script res://tools/verify_village_v2_riverbank_stonework.gd [-- --json=<path>] [-- --neg=<case>] [-- --selftest]
##   godot --path . --resolution 1600x900 --script res://tools/verify_village_v2_riverbank_stonework.gd -- --render [--out=<dir>]

const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"

## 門檻
const VIS_MIN := 0.38          # 低於此＝只露一角／被切掉一半以上
const VIS_MAX := 0.90          # 高於此＝過度外露
const VIS_TGT_LO := 0.40       # 使用者目標帶
const VIS_TGT_HI := 0.70
const FLOAT_TOL := 0.05        # 最低點離地 > 5 cm＝浮空
const GAP_MAX := 2.0           # 護岸帶連續空窗上限（m）
const COURSE_MIN := 2
const COURSE_MAX := 4
const COURSE_FIT_H := 1.9      # 岸高 ≥ 此值才要求 2–4 層（低於此幾何上放不下兩層）
const COURSE_JUMP := 1.60      # 同一站內相鄰列高差上限（面板高 0.9 m，容許坡度變化；石列不得上下亂跳）
const BED_MAX := 0.30          # 石背到坡面距離上限（超過＝石列與坡面分離）
# 0.30 的依據：實測全村無缺陷時石背離坡最大 0.186 m（餘裕 38%）；
# 注入「整塊抬離坡面」的決定性負例量到 0.620 m，必須被抓到。
# 舊值 0.80 會讓該負例 PASS＝量尺形同虛設（2026-09-28 以 --neg=hole 驗證後收緊）。
const PROTRUDE_TOL := 0.02     # 地形突出石面（擋住石頭）容許
const COVER_VIS := 0.25        # 計入「這段有石」的最小可見比例

const TIGHT_KINDS: Array[String] = ["rev", "revb", "cap", "bld"]   # 護岸／笠石／巨石：嚴格
const LOOSE_KINDS: Array[String] = ["rev", "revb", "cap", "bld", "cob", "shig"]
const FLOAT_KINDS: Array[String] = ["rev", "revb", "cap", "bld", "cob", "shig", "step", "land", "curb", "flag"]

const NSAMPLE := 14
const RAY_LEN := 2.5

var fails := 0
var checks: Array = []
var lib: Dictionary
var items: Array
var S: RLib.TriSampler
var R: RLib.TriSampler
var space: PhysicsDirectSpaceState3D
var terrain_rid := RID()
var other: Array[RID] = []
var st_tag := {}          # tag -> {c:[x,z], s, cls, water, side}
var drop_by_tag := {}     # lib 診斷：某站哪些件因結構/地塊/路帶被刪（橋體佔位證據）
var segments: Array = []  # lib 護岸段（cls full／toe 的連續 s 區間）＝coverage 的「本應有石」範圍
var excl: Array = []      # lib 橋體排除區（沿水道 s 區間）＝橋下本無護岸，不得算空窗
var out_json := ""
var neg := ""
var selftest := false
var render := false
var outdir := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--json="):
			out_json = a.trim_prefix("--json=")
		elif a.begins_with("--neg="):
			neg = a.trim_prefix("--neg=")
		elif a.begins_with("--out="):
			outdir = a.trim_prefix("--out=")
		elif a == "--selftest":
			selftest = true
		elif a == "--nosettle":
			pass                     # lib.settle_enabled() 自己讀 cmdline，勿從 gate 指派 const
		elif a == "--render":
			render = true
	var started := Time.get_ticks_msec()
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	lib = RLib.load_lib()
	print("[RBSW] load %.1f s" % [float(Time.get_ticks_msec() - started) / 1000.0])
	var P: Dictionary = RLib.plan(v, L)
	print("[RBSW] plan %.1f s (%d items)" % [float(Time.get_ticks_msec() - started) / 1000.0, (P["items"] as Array).size()])
	items = P["items"]
	S = RLib.terrain_sampler(v)
	R = RLib.road_sampler(v)
	drop_by_tag = P["stats"].get("drop_by_tag", {})
	segments = P["stats"].get("segments", [])
	excl = P["stats"].get("excl", [])
	_index_stations(P["stats"].get("stations", []))
	await physics_frame
	await physics_frame
	space = root.get_world_3d().direct_space_state
	terrain_rid = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	for cs in v.get_node("Collision").find_children("*", "CollisionObject3D", true, false):
		var rid := (cs as CollisionObject3D).get_rid()
		if rid != terrain_rid and not other.has(rid):
			other.append(rid)
	_apply_neg()
	print("[RBSW] measure start %.1f s" % [float(Time.get_ticks_msec() - started) / 1000.0])
	var M: Array = _measure()
	print("[RBSW] measure end %.1f s" % [float(Time.get_ticks_msec() - started) / 1000.0])
	if selftest:
		_selftest(M)
	if render:
		await _render(v)
	else:
		_check(M)
	if selftest and neg == "" and not render:
		_negative_selftest()
	if out_json != "":
		var f := FileAccess.open(out_json, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"items": items.size(),
				"kinds": P["stats"].get("kinds", {}), "metrics": M,
				"settle": P["stats"].get("settle", null),
				"stations": P["stats"].get("stations", []),
				"segments": P["stats"].get("segments", []),
				"drop_by_tag": P["stats"].get("drop_by_tag", {}),
				"nudged": P["stats"].get("nudged", 0),
				"dropped": {"parcel": P["stats"].get("dropped_in_parcel", 0),
					"bridge": P["stats"].get("dropped_bridge", 0),
					"road": P["stats"].get("dropped_on_road", 0)}}, " ", false))
			f.close()
		print("[RBSW] → %s" % out_json)
	_print_result()
	v.free()
	quit(fails)


func _p(s: String) -> void:
	print(s)


func _res(key: String, ok: bool, msg: String) -> void:
	checks.append({"key": key, "result": "PASS" if ok else "FAIL"})
	if not ok:
		fails += 1
	_p("[RBSW] %s %-12s %s" % ["PASS" if ok else "FAIL", key, msg])


func _print_result() -> void:
	_p("[RBSW] 結果：%d 項失敗（共 %d 項）" % [fails, checks.size()])


# ───────────────────────── 站點索引 ─────────────────────────
## stats["stations"] 為每個水體依 L(0..n-1) 再 R(0..n-1) 的順序附加，與擺放時 tag 的索引一致
func _index_stations(arr: Array) -> void:
	var cnt := {}
	for s: Dictionary in arr:
		var w := String(s["water"])
		var side := "L" if float(s["side"]) < 0.0 else "R"
		var k := "%s|%s" % [w, side]
		var i := int(cnt.get(k, 0))
		cnt[k] = i + 1
		var c: Array = s["c"]
		st_tag["%s/%s/%d" % [w, side, i]] = {"c": Vector2(float(c[0]), float(c[1])), "s": float(s["s"]),
			"cls": String(s["cls"]), "water": w, "side": side, "bank_h": s.get("bank_h", null)}


# ───────────────────────── 反向案例 ─────────────────────────
func _apply_neg() -> void:
	if neg == "":
		return
	var idx := -1
	for i in items.size():
		if String(items[i]["k"]) == "rev":
			idx = i
			break
	if idx < 0:
		return
	var xf: Transform3D = items[idx]["xf"]
	var o := _outward(items[idx])
	if neg == "bury":
		items[idx]["xf"] = xf.translated(o * -0.9)
	elif neg == "float":
		items[idx]["xf"] = xf.translated(Vector3(0, 0.8, 0))
	elif neg == "detach":
		items[idx]["xf"] = xf.translated(o * 1.6)
	elif neg == "gap":
		# 決定性負例：移除同一水道同側「連續 4 站」的護岸石（沿河跨度 > GAP_MAX）。
		# 舊版只移除 1 站（約 1 m，小於 GAP_MAX 2.0 m）→ PASS 屬正確行為，等於沒有驗到這條規則。
		var t0 := String(items[idx]["tag"])
		var st0: Dictionary = st_tag.get(t0, {})
		var w0 := String(st0.get("water", ""))
		var sd0 := String(st0.get("side", ""))
		var pick := {t0: true}
		var cands: Array = []
		for kk: String in st_tag:
			var sd: Dictionary = st_tag[kk]
			if String(sd.get("water", "")) != w0 or String(sd.get("side", "")) != sd0:
				continue
			if not ["full", "toe"].has(String(sd.get("cls", ""))):
				continue
			cands.append([float(sd.get("s", 0.0)), kk])
		cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		var start := -1
		for i2 in cands.size():
			if String(cands[i2][1]) == t0:
				start = i2
				break
		if start >= 0:
			for j2 in range(start, mini(start + 4, cands.size())):
				pick[String(cands[j2][1])] = true
		var drop: Array = []
		for it: Dictionary in items:
			if pick.has(String(it["tag"])):
				drop.append(it)
		for d: Dictionary in drop:
			items.erase(d)
		print("[RBSW] neg=gap：移除 %d 站／%d 件（%s/%s，預期 coverage FAIL）" % [
			pick.size(), drop.size(), w0, sd0])
	elif neg == "hole":
		# 決定性負例：整塊抬離坡面（往外 1.2 m、往上 0.5 m）＝石背空洞／石列與坡面分離。
		# 舊的 detach（只有水平 1.6 m）實測仍落在地形上（浮空僅 0.009 m），不是真缺陷。
		items[idx]["xf"] = xf.translated(o * 1.2 + Vector3(0, 0.5, 0))
	elif neg == "course":
		# 決定性負例：挑一個「非橋體佔位」的人工護岸站，刪掉第 2 層以上 → 該站只剩單列。
		# 這不是橋擋住，所以 layers 必須 FAIL（驗證 _bridge_occupied 的豁免沒有吃掉真缺陷）。
		var busy := {}
		for kk: String in drop_by_tag:
			if _bridge_occupied(kk):
				busy[kk] = true
		var pick := ""
		for m: Dictionary in items:
			if not ["rev", "revb"].has(String(m["k"])) or m.get("row") == null:
				continue
			var t0 := String(m["tag"])
			if int(m["row"]) < 1 or busy.has(t0) or not st_tag.has(t0):
				continue
			var st0: Dictionary = st_tag[t0]
			# 必須挑「本來就會被 2–4 層規則檢查」的站：cls=full 且岸高 ≥ COURSE_FIT_H。
			# 否則 _layers 直接 skip 該站，刪掉上層也不會 FAIL，負例形同虛設。
			if String(st0.get("cls", "")) != "full":
				continue
			var bh0: Variant = st0.get("bank_h", null)
			if bh0 == null or float(bh0) < COURSE_FIT_H:
				continue
			pick = t0
			break
		if pick != "":
			var drop: Array = []
			for it: Dictionary in items:
				if String(it["tag"]) == pick and it.get("row") != null and int(it["row"]) >= 1:
					drop.append(it)
			for d2: Dictionary in drop:
				items.erase(d2)
			var bh1: Variant = (st_tag[pick] as Dictionary).get("bank_h", null)
			print("[RBSW] neg=course：站 %s（bank_h=%s）刪除 %d 件上層（預期 layers FAIL）" % [
				pick, ("?" if bh1 == null else "%.2f" % float(bh1)), drop.size()])
		else:
			print("[RBSW] neg=course：找不到合格的受驗站（負例無效）")
	elif neg == "merge":
		# 石列上下亂跳：把最後一片抬 1.2 m
		for i in range(items.size() - 1, -1, -1):
			if String(items[i]["k"]) == "rev":
				items[i]["xf"] = (items[i]["xf"] as Transform3D).translated(Vector3(0, 1.2, 0))
				break
	elif neg == "error":
		return


# ───────────────────────── 量測 ─────────────────────────
func _outward(it: Dictionary) -> Vector3:
	var tg := String(it["tag"])
	var o: Vector3 = (it["xf"] as Transform3D).origin
	if not st_tag.has(tg):
		return Vector3.ZERO
	var c: Vector2 = st_tag[tg]["c"]
	var d := Vector2(c.x - o.x, c.y - o.z)
	if d.length() < 0.05:
		return Vector3.ZERO
	d = d.normalized()
	return Vector3(d.x, 0, d.y)


func _measure() -> Array:
	var out: Array = []
	for idx in items.size():
		var it: Dictionary = items[idx]
		if not FLOAT_KINDS.has(String(it["k"])):
			continue
		out.append(_one(idx))
	return out


func _one(idx: int) -> Dictionary:
	var it: Dictionary = items[idx]
	var xf: Transform3D = it["xf"]
	var m: Mesh = lib.get(String(it["m"]))
	if m == null:
		return {"i": idx, "k": it["k"], "tag": it["tag"], "vis": null, "float_gap": null, "bed": null}
	var V: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var o3: Vector3 = xf.origin
	var out_h := _outward(it)
	# 可見比例＝「迎水面／朝上面」中位於地形之上的面積比例（與繞向無關；見 lib._exposure）
	var vis: Variant = null
	var bed: Variant = null
	if out_h != Vector3.ZERO:
		var e := RLib._exposure(m, xf, S, out_h)
		vis = snappedf(e, 0.001) if e >= 0.0 else null    # -1＝沒有足夠地形樣本可判定，不可算成「被埋」
		bed = _back_gap(m, xf, out_h)
	# 浮空：最低點離「地形或路面」的距離
	var wy := INF
	for pv: Vector3 in V:
		var wp := xf * pv
		var th := _surf(wp.x, wp.z)
		if is_nan(th):
			continue
		wy = minf(wy, wp.y - th)
	return {"i": idx, "k": it["k"], "m": it["m"], "tag": it["tag"],
		"o": [snappedf(o3.x, 0.01), snappedf(o3.y, 0.01), snappedf(o3.z, 0.01)],
		"s": st_tag.get(String(it["tag"]), {}).get("s", null),
		"vis": vis,
		"float_gap": (snappedf(wy, 0.001) if wy < INF else null),
		"row": it.get("row", null),
		"half": snappedf(m.get_aabb().size.x * xf.basis.get_scale().x * 0.5, 0.01),
		"bed": bed,
		"bed_ray": (_back_gap_ray(m, xf, out_h) if out_h != Vector3.ZERO else null)}


## 石背貼坡：量石背（朝岸內的面）到地形表面的淨空。
## 舊版用「水平射線往岸內」，但水平射線在岸頂／平坦地面永遠打不到地形（射線飛過地面），
## 會把貼在坡上的石頭誤判成背空洞。改用高度取樣：先量石背正下方，沒有樣本再往岸內取樣。
## 石背低於地形表面＝貼坡（0）；高於地形＝淨空距離；完全沒有地形樣本＝真·背空洞（null）。
func _back_gap(m: Mesh, xf: Transform3D, out_h: Vector3) -> Variant:
	var best := INF
	var step := maxi(1, (I_of(m).size() / 3) / NSAMPLE)
	var I: PackedInt32Array = I_of(m)
	var V: PackedVector3Array = V_of(m)
	var N: PackedVector3Array = N_of(m)
	for t in range(0, I.size(), 3 * step):
		if t + 2 >= I.size():
			break
		var wn := (xf.basis * ((N[I[t]] + N[I[t + 1]] + N[I[t + 2]]).normalized())).normalized()
		if wn.dot(out_h) >= -0.15:
			continue                                   # 只看石背（朝岸內）的面
		var c := (xf * V[I[t]] + xf * V[I[t + 1]] + xf * V[I[t + 2]]) / 3.0
		var cl := _back_clearance(c, out_h)
		if cl >= 0.0:
			best = minf(best, cl)
	if best == INF:
		return null
	return snappedf(best, 0.001)


func _back_clearance(c: Vector3, out_h: Vector3) -> float:
	for r: float in [0.0, 0.12, 0.28, 0.48]:
		var th := _surf(c.x - out_h.x * r, c.z - out_h.z * r)
		if is_nan(th):
			continue
		return maxf(c.y - th, 0.0)      # 石背在地形下＝0（貼坡）；在地形上＝淨空
	return -1.0


## 舊版水平射線法（保留僅供對照，不作為判定依據）
func _back_gap_ray(m: Mesh, xf: Transform3D, out_h: Vector3) -> Variant:
	var V: PackedVector3Array = V_of(m)
	var N: PackedVector3Array = N_of(m)
	var I: PackedInt32Array = I_of(m)
	var best := INF
	var step := maxi(1, (I.size() / 3) / NSAMPLE)
	for t in range(0, I.size(), 3 * step):
		if t + 2 >= I.size():
			break
		var p0 := xf * V[I[t]]
		var p1 := xf * V[I[t + 1]]
		var p2 := xf * V[I[t + 2]]
		var wn := (xf.basis * ((N[I[t]] + N[I[t + 1]] + N[I[t + 2]]).normalized())).normalized()
		if wn.dot(out_h) <= 0.25 and wn.y <= 0.25:
			continue
		var c := (p0 + p1 + p2) / 3.0
		var th := _surf(c.x, c.z)
		if not is_nan(th) and c.y <= th:
			continue
		var d := _ray(c + out_h * 0.03, -out_h, BED_MAX + 1.2)
		if d >= 0.0:
			best = minf(best, maxf(d - 0.03, 0.0))
	if best == INF:
		return null
	return snappedf(best, 0.001)


static func V_of(m: Mesh) -> PackedVector3Array:
	return m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


static func N_of(m: Mesh) -> PackedVector3Array:
	return m.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]


static func I_of(m: Mesh) -> PackedInt32Array:
	var a: Array = m.surface_get_arrays(0)
	return a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()


func _surf(x: float, z: float) -> float:
	var h := S.h(x, z)
	var r := R.h(x, z)
	if not is_nan(r) and (is_nan(h) or r > h):
		return r
	return h


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


# ───────────────────────── 檢查 ─────────────────────────
func _check(M: Array) -> void:
	_coverage(M)
	_visibility(M)
	_float(M)
	_bedding(M)
	_layers(M)


## 該站是否有護岸件因橋體（橋面／橋台／橋墩）佔位而被刪除（證據：lib 的 drop_by_tag）。
func _bridge_occupied(tg: String) -> bool:
	if not drop_by_tag.has(tg):
		return false
	for k: String in (drop_by_tag[tg] as Dictionary):
		if k.begins_with("rev:") and k.contains("bridge"):
			return true
	return false


func _by_kind(M: Array, kinds: Array) -> Array:
	var o: Array = []
	for m: Dictionary in M:
		if kinds.has(String(m["k"])) and m["vis"] != null:
			o.append(m)
	return o


func _coverage(M: Array) -> void:
	# 每 1 m 一格；格內有「可見護岸石」＝覆蓋。
	# 「本應有石」的範圍取自 lib 的護岸段（segments：cls full／toe 的連續 s 區間）。
	# 舊寫法只在「站點中心剛好落在該格」才計數，遇到沒有站點中心的格就 cur = 0.0 重置，
	# 導致連續空窗永遠算不到 GAP_MAX 以上（此規則形同虛設；2026-09-28 以 neg=gap 驗證後修正）。
	var bins := {}
	for m: Dictionary in M:
		if not ["rev", "revb"].has(String(m["k"])) or m["s"] == null or m["vis"] == null:
			continue
		if float(m["vis"]) < COVER_VIS:
			continue                      # 看不到的石頭不算覆蓋（等於空窗）
		var tg := String(m["tag"])
		if not st_tag.has(tg):
			continue
		var st: Dictionary = st_tag[tg]
		var s0 := float(st["s"])
		var hw := float(m.get("half", 1.2))
		if hw <= 0.0:
			hw = 1.2
		# 石頭以其實際沿河寬度標記佔用的格（面板寬 2.4 m，只記 1 格會嚴重低估覆蓋）
		for i in range(int(floor((s0 - hw) / 1.0)), int(floor((s0 + hw) / 1.0)) + 1):
			bins["%s|%s|%d" % [st["water"], st["side"], i]] = true
	# 橋體排除區（橋面／橋台佔位處）本就不放護岸石 → 標成已覆蓋，不算空窗。
	# 否則 Bridge_01 那種 9 m 橋面會被誤報成 10 m 空窗（2026-09-28 實測）。
	var nexcl := 0
	for e: Dictionary in excl:
		nexcl += 1
		var k2 := "%s|%s" % [String(e.get("water", "")), "L"]
		for sd2: String in ["L", "R"]:
			var kk := "%s|%s" % [String(e.get("water", "")), sd2]
			for i in range(int(floor(float(e.get("s0", 0.0)) / 1.0)),
					int(floor(float(e.get("s1", 0.0)) / 1.0)) + 1):
				bins["%s|%d" % [kk, i]] = true
	# 證據驅動的排除：某站護岸石「已置放後被橋體刪除」（drop_by_tag 有 rev:bridge*）
	# → 該站站位本就被橋台／橋面佔住，不得算成空窗。
	# 只按實際刪除紀錄排除，不做通則豁免；負例（移除非橋體站點）仍會 FAIL。
	var nocc := 0
	for tg2: String in drop_by_tag:
		var hit := false
		for kk2: String in (drop_by_tag[tg2] as Dictionary):
			if kk2.begins_with("rev:") and kk2.contains("bridge"):
				hit = true
				break
		if not hit or not st_tag.has(tg2):
			continue
		var st2: Dictionary = st_tag[tg2]
		var sw := float(st2["s"])
		var k3 := "%s|%s" % [String(st2["water"]), String(st2["side"])]
		for i in range(int(floor((sw - 1.2) / 1.0)), int(floor((sw + 1.2) / 1.0)) + 1):
			bins["%s|%d" % [k3, i]] = true
		nocc += 1
	var worst := 0.0
	var worst_k := ""
	var nseg := 0
	for sg: Dictionary in segments:
		if not ["full", "toe"].has(String(sg.get("cls", ""))):
			continue
		nseg += 1
		var k := "%s|%s" % [String(sg.get("water", "")),
			("L" if float(sg.get("side", 0.0)) < 0.0 else "R")]
		var i0 := int(floor(float(sg.get("s0", 0.0)) / 1.0))
		var i1 := int(floor(float(sg.get("s1", 0.0)) / 1.0))
		var cur := 0.0
		var cs := 0.0
		for i in range(i0, i1 + 1):
			if bins.has("%s|%d" % [k, i]):
				cur = 0.0
				continue
			if cur == 0.0:
				cs = float(i)
			cur += 1.0
			if cur > worst:
				worst = cur
				worst_k = "%s @%.0f m" % [k, cs]
	_res("coverage", worst < GAP_MAX,
		"護岸段最長連續空窗 %.1f m（上限 %.1f）%s；段數 %d；橋體排除區 %d、橋體刪除站 %d" % [worst, GAP_MAX, worst_k, nseg, nexcl, nocc])


func _visibility(M: Array) -> void:
	var tight := _by_kind(M, TIGHT_KINDS)
	var lo := 0
	var hi := 0
	var tgt := 0
	var worst := 1.0
	var worst_t := ""
	for m: Dictionary in tight:
		var v := float(m["vis"])
		if v < VIS_MIN:
			lo += 1
			if v < worst:
				worst = v
				worst_t = String(m["tag"])
		if v > VIS_MAX:
			hi += 1
		if v >= VIS_TGT_LO and v <= VIS_TGT_HI:
			tgt += 1
	var n := maxf(float(tight.size()), 1.0)
	_res("visibility", lo == 0 and hi == 0,
		"護岸／笠石／巨石 %d 顆：可見 <%.0f%% %d（%.0f%%）%s、>%.0f%% %d（%.0f%%）；落在 %.0f–%.0f%% 目標帶 %.0f%%" % [
			tight.size(), VIS_MIN * 100, lo, 100.0 * lo / n, ("" if worst_t == "" else "（最差 %s %.2f）" % [worst_t, worst]),
			VIS_MAX * 100, hi, 100.0 * hi / n, VIS_TGT_LO * 100, VIS_TGT_HI * 100, 100.0 * tgt / n])


func _float(M: Array) -> void:
	var bad := 0
	var worst := -INF
	var worst_t := ""
	for m: Dictionary in M:
		if m["float_gap"] == null:
			continue
		var g := float(m["float_gap"])
		if g > worst:
			worst = g
			worst_t = String(m["tag"])
		if g > FLOAT_TOL:
			bad += 1
	_res("no_float", bad == 0,
		"浮空（最低點離地 > %.2f m）%d 顆；最大 %.3f m（%s）" % [FLOAT_TOL, bad, worst, worst_t])


func _bedding(M: Array) -> void:
	var detached := 0
	var nb := 0
	var worst := 0.0
	var worst_t := ""
	for m: Dictionary in M:
		if not ["rev", "revb"].has(String(m["k"])):
			continue
		nb += 1
		if m["bed"] == null:
			detached += 1                       # 迎水面找不到後方地形 → 石背後空洞
			continue
		var b := float(m["bed"])
		if b > worst:
			worst = b
			worst_t = String(m["tag"])
	_res("bedding", detached == 0 and worst <= BED_MAX,
		"護岸面板 %d：背空洞 %d、石背離坡最大 %.3f m（上限 %.2f m）%s" % [
			nb, detached, worst, BED_MAX, ("" if worst_t == "" else "（%s）" % worst_t)])


func _layers(M: Array) -> void:
	# 用 lib 擺放時記錄的砌築列序（row）判定層數——不再由世界 Y 反推，
	# 否則緩坡站點會把同一列的不同高度誤算成多層。
	# 只驗「本應為多層砌石帶」的站點（cls == full）：toe＝僅護岸腳、nat＝自然岸不列入。
	var col := {}
	for m: Dictionary in M:
		if not ["rev", "revb"].has(String(m["k"])):
			continue
		var tg := String(m["tag"])
		if not st_tag.has(tg) or String(st_tag[tg]["cls"]) != "full":
			continue
		if m.get("row") == null:
			continue
		if not col.has(tg):
			col[tg] = {}
		(col[tg] as Dictionary)[int(m["row"])] = true
	var bad_lo := 0
	var bad_hi := 0
	var bad_jump := 0
	var skip := 0
	var hist := {}
	var bad_lo_tags: Array = []
	var bad_hi_tags: Array = []
	var occup := 0              # 橋體（橋面／橋台／橋墩）佔位而少列的站數
	var occup_tags: Array = []
	for tg: String in col:
		var st: Dictionary = st_tag.get(tg, {})
		var bh: Variant = st.get("bank_h", null)
		var n := (col[tg] as Dictionary).size()
		hist[n] = int(hist.get(n, 0)) + 1
		if bh == null or float(bh) < COURSE_FIT_H:
			skip += 1                  # 岸高不足兩層 → 幾何上放不下，不強制 2–4 層
			continue
		if n < COURSE_MIN:
			# 上層石已置放、但被橋體碰撞體（Deck／Abut／Pier）刪除（證據：drop_by_tag）。
			# 石頭若落在橋面體積內＝被橋擋住；硬要兩列等於把石頭塞進橋裡。
			# 這類不計入 2–4 層要求，但必須明示數量與站名；其餘站點照常嚴格驗。
			if _bridge_occupied(tg):
				occup += 1
				occup_tags.append("%s(n=%d)" % [tg, n])
			else:
				bad_lo += 1
				bad_lo_tags.append("%s(n=%d,bank_h=%.2f)" % [tg, n, float(bh)])
		if n > COURSE_MAX:
			bad_hi += 1
			bad_hi_tags.append(tg)
	_res("layers", bad_lo == 0 and bad_hi == 0 and bad_jump == 0,
		"人工護岸（岸高 ≥ %.1f m）%d 站：層數分布 %s；< %d 層 %d、> %d 層 %d；站內相鄰列高差 > %.2f m %d；岸高不足未強制 %d；橋體佔位未強制 %d" % [
			COURSE_FIT_H, col.size(), hist, COURSE_MIN, bad_lo, COURSE_MAX, bad_hi, COURSE_JUMP, bad_jump, skip, occup])
	if not occup_tags.is_empty():
		_p("[RBSW]   橋體佔位站點（已置放後被結構刪除）：%s" % ", ".join(occup_tags))
	if not bad_lo_tags.is_empty():
		_p("[RBSW]   層數不足站點：%s" % ", ".join(bad_lo_tags))
	if not bad_hi_tags.is_empty():
		_p("[RBSW]   層數過多站點：%s" % ", ".join(bad_hi_tags))


# ───────────────────────── 自檢 ─────────────────────────
## 位移一顆石頭，量測必須跟著動；否則量測無效
# ───────────────────────── 同一次 plan 驗證全部決定性負例 ─────────────────────────
func _negative_selftest() -> void:
	var original := items.duplicate(true)
	var base_checks := checks.duplicate(true)
	var base_fails := fails
	for case: String in ["bury", "float", "gap", "hole", "course"]:
		items = original.duplicate(true)
		neg = case
		_apply_neg()
		checks.clear()
		fails = 0
		_check(_measure())
		var expected: String = {"bury": "visibility", "float": "no_float", "gap": "coverage",
			"hole": "bedding", "course": "layers"}[case]
		var caught := false
		for result: Dictionary in checks:
			if result["key"] == expected and result["result"] == "FAIL":
				caught = true
				break
		print("[RBSW] %s negative %s → %s" % ["PASS" if caught else "FAIL", case, expected])
		if not caught:
			base_fails += 1
			base_checks.append({"key": "negative_" + case, "result": "FAIL"})
		else:
			base_checks.append({"key": "negative_" + case, "result": "PASS"})
	items = original
	neg = ""
	checks = base_checks
	fails = base_fails

func _selftest(M: Array) -> void:
	var pick := -1
	for m: Dictionary in M:
		if String(m["k"]) == "rev" and m["vis"] != null:
			pick = int(m["i"])
			break
	if pick < 0:
		_push_bad("selftest", "找不到可測的 rev")
		return
	var orig: Transform3D = items[pick]["xf"]
	var o := _outward(items[pick])
	var b0 := _one(pick)
	items[pick]["xf"] = orig.translated(o * -0.9)
	var b1 := _one(pick)      # 埋進去 → vis 必須下降
	items[pick]["xf"] = orig.translated(Vector3(0, 0.8, 0))
	var b2 := _one(pick)      # 抬起來 → float_gap 必須變大
	items[pick]["xf"] = orig
	var v0 := float(b0["vis"])
	var v1 := float(b1["vis"])
	var f0 := float(b0["float_gap"])
	var f2 := float(b2["float_gap"])
	var ok_bury := v1 < v0 - 0.15
	var ok_lift := f2 > f0 + 0.4
	var detail := "埋入 vis %.2f→%.2f %s；抬高 float %.2f→%.2f %s" % [
		v0, v1, "✓" if ok_bury else "✗", f0, f2, "✓" if ok_lift else "✗"]
	if ok_bury and ok_lift:
		_push_ok("selftest", detail)
	else:
		_push_bad("selftest", detail)


func _push_ok(key: String, msg: String) -> void:
	checks.append({"key": key, "result": "PASS"})
	_p("[RBSW] PASS %-12s %s" % [key, msg])


func _push_bad(key: String, msg: String) -> void:
	checks.append({"key": key, "result": "FAIL"})
	fails += 1
	_p("[RBSW] FAIL %-12s %s" % [key, msg])


# ───────────────────────── 1.7 m 玩家視角（第 4 項）─────────────────────────
## 沿河 1.7 m 鏡位：把 Debug／Portals 隱藏，逐橋引道與親水點拍照；
## 另外做「只顯示 Riverbank」與「同時顯示 Terrain」兩張，用像素差證明石頭真的露在地形之上（不是只有俯視圖看得到）。
func _render(v: Node3D) -> void:
	var paths := ["res://tools/shots/village_v2_p7_riverbank_review.json"]
	var dir := outdir if outdir != "" else "user://riversw"
	DirAccess.make_dir_recursive_absolute(dir)
	var shots: Array = []
	for p: String in paths:
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if j is Array:
			shots.append_array(j)
	var terr := v.get_node_or_null("Terrain") as Node3D
	var rb := v.get_node_or_null("Riverbank") as Node3D
	_p("[RBSW] 1.7 m 沿河抽查：%d 個鏡位 → %s" % [shots.size(), dir])
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = 70.0
	var done := 0
	for s: Dictionary in shots:
		var c: Array = s["cam"]
		var l: Array = s["look"]
		cam.global_position = Vector3(float(c[0]), float(c[1]), float(c[2]))
		cam.look_at_from_position(cam.global_position, Vector3(float(l[0]), float(l[1]), float(l[2])), Vector3.UP)
		await _shot(dir, String(s["name"]), terr, rb, cam)
		done += 1
	await _shot_points(dir)
	_push_ok("player_screenshot", "1.7 m 沿河鏡位 %d 張已輸出（含 stone-only／stone+terrain 對照）" % done)


func _shot(dir: String, nm: String, terr: Node3D, rb: Node3D, cam: Camera3D) -> void:
	for mode: int in [0, 1]:
		if terr != null:
			terr.visible = mode == 1
		var img := await _grab(cam)
		if img != null:
			img.save_png(dir + "/%s%s.png" % [nm, "_all" if mode == 1 else "_stone"])
		if terr != null:
			terr.visible = true


func _shot_points(dir: String) -> void:
	pass


func _grab(cam: Camera3D) -> Image:
	await RenderingServer.frame_post_draw
	var vp := root.get_viewport()
	var t := vp.get_texture()
	if t == null:
		return null
	var img := t.get_image()
	return img
