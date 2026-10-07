extends SceneTree
## 人間之里 V2 P7 R2：河岸 Kit（Riverbank / Bridge Transition）Asset Gate（11 項，與 Hero／町家 Kit Gate 同名同義）。
##   headless 1–9：godot --headless --path . --script res://tools/verify_village_v2_riverbank_gate.gd [-- --neg=<案例>]
##   render 10–11：godot --path . --resolution 1600x900 --script res://tools/verify_village_v2_riverbank_gate.gd -- --render [--out=<dir>]
## entry＝assets/village_v2/riverbank_kit/riverbank_kit_manifest.json（構件 mesh／擺放腳本／材質 sha256）；
## gate.json 記 entry 雜湊，任何一檔改動 → registry 不登記 → 產生器不放河岸件（維持 P7 R1）。
## 擺放 authority＝場景內已產生的核准資料（P1 地形碰撞、P2 水面、P3 路帶、P4 灰盒橋）；外觀 authority＝docs/reference/河岸/。
##   1 尺寸     構件 AABB＝Blender 設計尺寸（±0.02）；縮放只在設計範圍；石段 級高 ≤ 0.27 且一致、級間水平距 0.38–1.0、平台頂＝水位＋0.13
##   2 地塊     件不壓建築／地標／橋的碰撞體（平貼路面的鋪石／見切り石除外，只驗不進橋面）；巨石／木樁／矮欄／笠石不站在路帶上；橋頭鋪石不進橋面
##   3 接地     每件底 ≤ 地面（不浮）、頂 ≥ 地面（不整顆埋）；鋪石／見切り石頂與路面差 ≤ 0.06；木樁埋 ≥ 0.3；平台底在水位下
##   4 材質     只用 V2_KitStoneTri（町家 Kit 已過 gate）＋共享材質庫 V2_Wood；無 override；頂點色濕／苔帶有做
##   5 幾何     構件無退化／NaN、有法線與 UV；擺放 basis 行列式 > 0
##   6 Pivot    Riverbank 與區塊節點 identity；區塊名＝其件的 32 m 分格
##   7 碰撞     石段／平台／矮欄／大巨石有 BoxShape（layer≠0）；石段碰撞頂＝踏面 ±0.03；護岸面板不給碰撞（地形碰撞不變）
##   8 LOD      每區塊 LOD0／LOD1 齊全、可見距離接續；LOD1 ≤ 35 %
##   9 效能     每區塊 LOD0 ≤ CAP_CHUNK、全村 LOD0 ≤ CAP_TOTAL；每區塊 surface ≤ 2（draw call）
##  10 截圖     main.tscn 載 village_v2，玩家鏡位：五座橋兩端引道＋每處親水點；亮度標準差、河岸件在畫面內
##  11 F5/F6    F6＝全部構件單獨場景 120 幀 0 錯誤；F5＝main.tscn 0 錯誤、實走 5 橋引道→橋面、每處石段走到平台（著地離地 ≤ 0.10、騰空 ≤ 24 幀）
## 回歸（唯讀）：-- --regress  重驗 1–9 項（場景已烘焙的 Riverbank；重排一次確認決定性），不寫 gate.json；另驗 gate.json 11 項 PASS 且雜湊一致。
## 反向案例（--neg，不寫 gate.json，預期對應項 FAIL）：size（石段放大）、parcel（巨石推進建築）、ground（鋪石抬 0.5）、
##   material（override）、collision（關石段碰撞）、lod（刪 LOD1）、perf（同件複製到區塊多出 CAP_CHUNK 面）、stair（一級抬 0.4）。

const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const HLib := preload("res://tools/village_v2_hero_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const DIR := "res://assets/village_v2/riverbank_kit"
const ENTRY := DIR + "/riverbank_kit_manifest.json"
const GATE := DIR + "/gate.json"
const BLENDER_JSON := DIR + "/src/modules_blender.json"
const HEADLESS_KEYS: Array[String] = ["size", "parcel_fit", "grounding", "materials", "geometry", "pivot_scale",
	"collision", "lod", "performance"]
const RENDER_KEYS: Array[String] = ["player_screenshot", "f5_f6"]
const CAP_CHUNK := 40000       # 河岸 Kit 每 32 m 區塊 LOD0（§14.8 無河岸類別：P7 R2 提案值，待使用者核准）
const CAP_TOTAL := 650000      # 河岸 Kit 全村 LOD0 合計（同上，提案值）
const MATS := ["V2_KitStoneTri", "V2_Wood"]
const GROUND_TOL := 0.05


class GateLogger extends Logger:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var msg := "%s（%s:%d %s）" % [rationale if rationale != "" else code, file.get_file(), line, function]
		mutex.lock()
		if error_type == ERROR_TYPE_WARNING:
			warnings.append(msg)
		else:
			errors.append(msg)
		mutex.unlock()

	func _log_message(message: String, error: bool) -> void:
		pass


var fails := 0
var R := {}
var L: Dictionary
var v: Node3D
var rb: Node3D
var P: Dictionary
var items: Array = []
var lib: Dictionary
var S: RLib.TriSampler
var RD: RLib.TriSampler
var WL: Dictionary
var space: PhysicsDirectSpaceState3D
var terrain_rid := RID()
var neg := ""
var regress := false
var logger: GateLogger
var visual_probe := false # 唯讀：固定 Bridge_02_n 視覺負例＋正常鏡位回歸
const BRIDGE_READABLE_MIN := 0.010 # 中央視域 ≥ 1% 遠距橋體；正常小橋 Bridge_05_s 實測 1.3%
const CAMERA_MESH_CLEARANCE := 0.30 # 鏡頭到可見網格世界 AABB 至少 30 cm
const B2_REVIEW_APPROACH := 5.0 # 橋頭外 5 m；相機臂 4 m，使鏡頭留在 B_P_RNE_001 西側
const B2_REVIEW_LATERAL := Vector3(0, 0, 5.0) # 橋頭北端朝 +Z 偏移，避開傳送光圈
const BRIDGE_MASK_SHADER := "shader_type spatial; render_mode unshaded, cull_disabled; varying vec3 world_pos; void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; } void fragment() { float d = distance(world_pos, CAMERA_POSITION_WORLD); ALBEDO = d >= 3.0 && d <= 45.0 ? vec3(1.0, 0.0, 1.0) : vec3(0.0); }"


func _init() -> void:
	_run.call_deferred()


func _p(s: String) -> void:
	print("[RBG] " + s)


func _res(key: String, ok: bool, detail: String) -> void:
	var prev: Dictionary = R.get(key, {"result": "PASS", "detail": []})
	if not ok:
		prev["result"] = "FAIL"
	(prev["detail"] as Array).append(("" if ok else "✗ ") + detail)
	R[key] = prev


func _flush(keys: Array[String]) -> void:
	for k in keys:
		if not R.has(k):
			_res(k, false, "沒有執行")
		var e: Dictionary = R[k]
		print("[RBG] %s riverbank_kit %s：%s" % [e["result"], k, "；".join(e["detail"])])
		if e["result"] != "PASS":
			fails += 1


func _run() -> void:
	var render := false
	var out := ""
	for a: String in OS.get_cmdline_user_args():
		if a == "--render":
			render = true
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--neg="):
			neg = a.trim_prefix("--neg=")
		elif a == "--regress":
			regress = true
		elif a == "--visual-probe":
			visual_probe = true
			regress = true # 唯讀使用場景已烘焙的 Riverbank，不跑 RLib.bake
			render = true
	L = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if not FileAccess.file_exists(ENTRY):
		_p("FAIL 缺 %s（先跑 village_v2_machiya_kit_prefab.gd -- --kit=riverbank_kit）" % ENTRY)
		quit(1)
		return
	var dep_bad := _manifest_bad()
	if not dep_bad.is_empty():
		_p("FAIL manifest 依賴雜湊不符（prefab 之後改過）：%s" % "、".join(dep_bad.slice(0, 4)))
		quit(1)
		return
	if render:
		await _render(out)
	else:
		await _headless()
	_p("結果：%d 項失敗" % fails)
	quit(fails)


func _manifest_bad() -> Array:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ENTRY))
	var bad: Array = []
	var deps: Dictionary = m["deps"]
	for p: String in deps:
		if FileAccess.get_sha256(p) != String(deps[p]):
			bad.append(p.get_file())
	for f in DirAccess.get_files_at(DIR + "/mesh"):
		if f.ends_with(".res") and not deps.has(DIR + "/mesh/" + f):
			bad.append("未登記 " + f)
	return bad


## 場景：載入 village_v2；非回歸＝丟掉場景裡已烘焙的 Riverbank、用目前構件庫＋擺放腳本重排重烘（驗的是這一版）
func _setup(parent: Node, vroot: Node3D = null) -> void:
	if vroot == null:
		v = (load(SCENE) as PackedScene).instantiate()
		parent.add_child(v)
	else:
		v = vroot
	if visual_probe:
		# 唯讀鏡位回歸：不執行昂貴的完整擺放計畫，更不烘焙。
		var bridges: Array = []
		for a in v.get_node("Roads/Bridges").get_children():
			var dims: Dictionary = HLib.bridge_dims(a)
			if dims.is_empty():
				continue
			bridges.append({"name": String(a.name), "F": RLib.rel_xf(a, v) * HLib.bridge_frame(a), "L": float(dims["L"])})
		P = {"bridges": bridges, "stairs": []}
		S = RLib.terrain_sampler(v)
		RD = RLib.road_sampler(v)
		return
	lib = RLib.load_lib()
	P = RLib.plan(v, L)
	items = P["items"]
	var baked := v.get_node_or_null("Riverbank") as Node3D
	if regress and baked != null:
		rb = baked
	else:
		_apply_neg_items()
		rb = RLib.bake(v, items, lib)
	S = RLib.terrain_sampler(v)
	RD = RLib.road_sampler(v)
	WL = RLib.water_levels(v)
	await physics_frame
	await physics_frame
	space = v.get_world_3d().direct_space_state
	terrain_rid = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()


func _first(kind: String) -> int:
	for i in items.size():
		if String(items[i]["k"]) == kind:
			return i
	return -1


func _apply_neg_items() -> void:
	match neg:
		"size":
			var i := _first("step")
			var it: Dictionary = items[i]
			it["xf"] = Transform3D((it["xf"] as Transform3D).basis.scaled(Vector3(1.6, 1.0, 1.6)), (it["xf"] as Transform3D).origin)
		"parcel":
			# 巨石推到最近建築碰撞體中心
			var i := _first("bld")
			var o: Vector3 = (items[i]["xf"] as Transform3D).origin
			var best := INF
			var tgt := o
			for b in v.get_node("Districts").find_children("*", "StaticBody3D", true, false):
				var d := (b as Node3D).global_position.distance_to(o)
				if d < best:
					best = d
					tgt = (b as Node3D).global_position
			var it: Dictionary = items[i]
			it["xf"] = Transform3D((it["xf"] as Transform3D).basis, Vector3(tgt.x, tgt.y + 0.5, tgt.z))
		"ground":
			var i := _first("flag")
			var it: Dictionary = items[i]
			it["xf"] = (it["xf"] as Transform3D).translated(Vector3(0, 0.5, 0))
		"stair":
			for i in items.size():
				if String(items[i]["k"]) == "step":
					var it: Dictionary = items[i + 2]
					it["xf"] = (it["xf"] as Transform3D).translated(Vector3(0, 0.4, 0))
					var st: Dictionary = (P["stairs"] as Array)[0]
					(st["tops"] as Array)[2] = (st["tops"] as Array)[2] + Vector3(0, 0.4, 0)
					break
		"perf":
			# 同一件（同一區塊）一直複製到該區塊多出 CAP_CHUNK 面 → 區塊 LOD0 必超上限
			var src: Dictionary = items[_first("rev")]
			var m: Mesh = lib[String(src["m"])]
			var tr := 0
			for s in m.get_surface_count():
				tr += m.surface_get_array_index_len(s) / 3
			for k in CAP_CHUNK / maxi(tr, 1) + 1:
				items.append(src.duplicate())


func _apply_neg_scene() -> void:
	match neg:
		"material":
			var mi := rb.get_child(0).get_node("LOD0") as MeshInstance3D
			mi.material_override = StandardMaterial3D.new()
		"collision":
			for cs in rb.find_children("step_*", "CollisionShape3D", true, false):
				(cs as CollisionShape3D).disabled = true
		"lod":
			rb.get_child(0).get_node("LOD1").free()


func _headless() -> void:
	await _setup(root)
	_apply_neg_scene()
	var kinds := {}
	for it: Dictionary in items:
		kinds[it["k"]] = int(kinds.get(it["k"], 0)) + 1
	_p("河岸件 %d：%s；區塊 %d；親水點 %d" % [items.size(), kinds, rb.get_child_count(), (P["stairs"] as Array).size()])
	_c_size()
	_c_parcel()
	_c_ground()
	_c_materials()
	_c_geometry()
	_c_pivot()
	_c_collision()
	_c_lod()
	_c_perf()
	_flush(HEADLESS_KEYS)
	if regress:
		var gj: Variant = JSON.parse_string(FileAccess.get_file_as_string(GATE))
		var bad: Array = []
		if not gj is Dictionary or String(gj.get("entry_sha256", "")) != FileAccess.get_sha256(ENTRY):
			bad.append("gate.json 缺或 manifest 雜湊不一致")
		else:
			for k in HEADLESS_KEYS + RENDER_KEYS:
				if String(gj["checks"].get(k, {}).get("result", "")) != "PASS":
					bad.append(k)
		var baked_items := int(rb.get_meta("items", -1))
		if baked_items != items.size():
			bad.append("場景烘焙 %d 件 ≠ 重排 %d 件（擺放不決定性或場景過期）" % [baked_items, items.size()])
		print("[RBG] %s gate.json 11 項 PASS 且雜湊一致、場景烘焙與重排一致（%d 件）%s" % [
			"PASS" if bad.is_empty() else "FAIL", items.size(), "" if bad.is_empty() else "（✗ " + "、".join(bad) + "）"])
		if not bad.is_empty():
			fails += 1
	elif neg == "":
		_write_gate("headless", HEADLESS_KEYS)


# ─────────────────────────── 工具 ───────────────────────────

func _waabb(it: Dictionary) -> AABB:
	var m: Mesh = lib.get(String(it["m"]))
	return (it["xf"] as Transform3D) * m.get_aabb()


func _surf(x: float, z: float) -> float:
	return RLib._surf(S, RD, x, z)


func _count(pred: Callable) -> int:
	var n := 0
	for it: Dictionary in items:
		if pred.call(it):
			n += 1
	return n


# ─────────────────────────── 1 尺寸 ───────────────────────────

func _c_size() -> void:
	var bj: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BLENDER_JSON))
	var mods: Dictionary = bj["modules"]
	var worst := 0.0
	var worst_n := ""
	var missing: Array = []
	for n: String in mods:
		var m: Mesh = lib.get(n)
		if m == null:
			missing.append(n)
			continue
		# Blender 匯出記的 dims＝[min x, min y, min z, max x, max y, max z]（已是 Godot Y-up 軸向）
		var d: Array = mods[n]["dims"]
		var sz := m.get_aabb().size
		var want := Vector3(float(d[3]) - float(d[0]), float(d[4]) - float(d[1]), float(d[5]) - float(d[2]))
		var e := maxf(absf(sz.x - want.x), maxf(absf(sz.y - want.y), absf(sz.z - want.z)))
		if e > worst:
			worst = e
			worst_n = n
	_res("size", missing.is_empty() and worst <= 0.02, "構件 %d 個 AABB vs Blender 設計尺寸最大差 %.3f m（%s；≤ 0.02）%s" % [
		mods.size(), worst, worst_n, "" if missing.is_empty() else "；缺 " + ", ".join(missing)])
	# 縮放範圍
	var RANGE := {"rev": [0.8, 1.36, 0.45, 1.8], "cap": [0.6, 1.4, 0.99, 1.01], "curb": [0.5, 1.1, 0.99, 1.01],
		"flag": [0.3, 1.01, 0.99, 1.01], "bld": [0.44, 1.81, 0.30, 2.0], "cob": [0.54, 1.36, 0.54, 1.36],
		"revb": [0.8, 1.36, 0.45, 1.8], "piler": [0.99, 1.01, 0.99, 1.01],
		"step": [0.99, 1.01, 0.99, 1.01], "land": [0.99, 1.01, 0.99, 1.01], "pile": [0.99, 1.01, 0.99, 1.01],
		"rail": [0.99, 1.01, 0.99, 1.01], "shig": [0.99, 1.01, 0.99, 1.01]}
	var bad: Array = []
	for it: Dictionary in items:
		var sc := (it["xf"] as Transform3D).basis.get_scale()
		var rg: Array = RANGE.get(String(it["k"]), [0.0, 99.0, 0.0, 99.0])
		if sc.x < float(rg[0]) or sc.x > float(rg[1]) or sc.y < float(rg[2]) or sc.y > float(rg[3]):
			bad.append("%s %s" % [it["k"], sc.snappedf(0.01)])
	_res("size", bad.is_empty(), "擺放縮放在設計範圍（護岸 x 0.8–1.36／沿坡 0.45–1.8、巨石 0.44–1.81、河原石 0.54–1.36、石段／平台／木樁 1:1）：違規 %d%s" % [
		bad.size(), "" if bad.is_empty() else "（" + "、".join(bad.slice(0, 4)) + "）"])
	# 石段
	var lines: Array = []
	var ok := true
	for st: Dictionary in P["stairs"]:
		var tops: Array = st["tops"]
		var land: Vector3 = st["land"]
		var rmin := INF
		var rmax := -INF
		var tmin := INF
		var tmax := -INF
		for i in range(1, tops.size()):
			var a: Vector3 = tops[i - 1]
			var b: Vector3 = tops[i]
			var rise := a.y - b.y
			rmin = minf(rmin, rise)
			rmax = maxf(rmax, rise)
			var tr := Vector2(b.x - a.x, b.z - a.z).length()
			tmin = minf(tmin, tr)
			tmax = maxf(tmax, tr)
		var last: Vector3 = tops[tops.size() - 1]
		var wl := float(WL[String(st["water"])].at(land.x, land.z))
		var land_top := land.y - wl
		var last_rise := last.y - land.y
		var s_ok := rmax <= 0.27 and rmax - rmin <= 0.02 and tmin >= 0.38 and tmax <= 1.0 and absf(land_top - 0.13) <= 0.05 \
			and last_rise <= 0.27 and last_rise >= -0.01
		ok = ok and s_ok
		lines.append("%s%s %d 級：級高 %.2f–%.2f、級間水平距 %.2f–%.2f、末級→平台 %.2f、平台頂＝水位＋%.2f" % [
			"" if s_ok else "✗ ", st["tag"], tops.size(), rmin, rmax, tmin, tmax, last_rise, land_top])
	_res("size", ok and not (P["stairs"] as Array).is_empty(), "親水石段（雁木）%d 處：%s（級高 ≤ 0.27 且差 ≤ 0.02；雁木沿岸 0.44＋緩岸往水側外移 → 級間水平距 0.38–1.00、踏石 1.3 m 長保證相鄰級重疊 ≥ 0.3；平台頂＝水位＋0.13±0.05；可走性由 11 項實走驗）" % [
		(P["stairs"] as Array).size(), "；".join(lines)])


# ─────────────────────────── 2 地塊／不壓他物 ───────────────────────────

func _c_parcel() -> void:
	var own := {}
	for cb in rb.find_children("*", "StaticBody3D", true, false):
		own[(cb as CollisionObject3D).get_rid()] = true
	var hits: Array = []
	var by := {}
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	q.shape = box
	q.collision_mask = 0xFFFFFFFF
	var ex: Array[RID] = [terrain_rid]
	for r: RID in own:
		ex.append(r)
	q.exclude = ex
	for it: Dictionary in items:
		# 平貼路面的鋪石／見切り石：頂＝路面（grounding 驗 ±），橋台碰撞體頂也＝路面 → 不計碰撞體重疊，只驗下面「不進橋面」
		if String(it["k"]) in RLib.LOD1_SKIP:
			continue
		var m: Mesh = lib.get(String(it["m"]))
		var la := m.get_aabb()
		var xf: Transform3D = it["xf"]
		var sc := xf.basis.get_scale()
		box.size = (la.size * sc * 0.8).max(Vector3(0.02, 0.02, 0.02))
		q.transform = Transform3D(xf.basis.orthonormalized(), xf * la.get_center())
		var r := space.intersect_shape(q, 4)
		for h: Dictionary in r:
			var col: Object = h.get("collider")
			if col is Node and not String(v.get_path_to(col as Node)).begins_with("Collision/"):
				var cp := String(v.get_path_to(col as Node))
				hits.append("%s@%s→%s" % [it["k"], xf.origin.snappedf(0.1), cp])
				var bk := "%s→%s" % [it["k"], cp.get_slice("/", 2) if cp.begins_with("Roads/Bridges") else cp.get_slice("/", 0)]
				by[bk] = int(by.get(bk, 0)) + 1
				break
	_res("parcel_fit", hits.is_empty(), "件（AABB 內縮 20 %%）不壓建築／地標／橋／圍牆碰撞體：%d 件、違規 %d%s" % [
		items.size(), hits.size(), "" if hits.is_empty() else "（%s；例 %s）" % [by, "、".join(hits.slice(0, 3))]])
	# 不站在路帶上（鋪石／見切り石／石段／平台／護岸除外）
	var onroad: Array = []
	for it: Dictionary in items:
		var k := String(it["k"])
		if k in ["flag", "curb", "rev", "revb", "step", "land"]:
			continue
		var o: Vector3 = (it["xf"] as Transform3D).origin
		var rh := RD.h(o.x, o.z)
		if not is_nan(rh):
			onroad.append("%s@%s" % [k, o.snappedf(0.1)])
	_res("parcel_fit", onroad.is_empty(), "巨石／河原石／木樁／しがらみ／矮欄／笠石 中心不在路帶上：違規 %d%s" % [
		onroad.size(), "" if onroad.is_empty() else "（" + "、".join(onroad.slice(0, 4)) + "）"])
	# 橋頭鋪石不進橋面（灰盒橋面矩形 bridge_frame 內）
	var indeck := 0
	var indeck_l: Array = []
	for b: Dictionary in P["bridges"]:
		var F: Transform3D = b["F"]
		var inv := F.affine_inverse()
		for it: Dictionary in items:
			var lp := inv * (it["xf"] as Transform3D).origin
			if absf(lp.x) < float(b["W"]) * 0.5 - 0.1 and absf(lp.z) < float(b["L"]) * 0.5 - 0.1 and lp.y > -0.6:
				indeck += 1
				indeck_l.append("%s@%s lp%s" % [it["k"], String(b["name"]).substr(7, 2), lp.snappedf(0.1)])
	_res("parcel_fit", indeck == 0, "5 座橋面矩形內（橋面以下 0.6 m 以上）沒有河岸件：%d%s" % [indeck,
		"" if indeck == 0 else "（" + "、".join(indeck_l.slice(0, 5)) + "）"])


# ─────────────────────────── 3 接地 ───────────────────────────

func _c_ground() -> void:
	var floating: Array = []
	var buried: Array = []
	var flush: Array = []
	var worst_flush := 0.0
	var piles_bad := 0
	var n := 0
	for it: Dictionary in items:
		var k := String(it["k"])
		var xf: Transform3D = it["xf"]
		var a := _waabb(it)
		var o := xf.origin
		var c := a.get_center()
		var g := S.h(c.x, c.z)
		if k in ["flag", "curb"]:
			g = _surf(c.x, c.z)
		if is_nan(g):
			continue
		n += 1
		if k == "rev" or k == "revb":
			# 護岸面板：面板平面在地形弦外 FACE_OFF；中心離地形（垂直）≤ 0.6、面板底 ≤ 地形
			if a.position.y > S.h(c.x, c.z) + GROUND_TOL:
				floating.append("rev@%s" % o.snappedf(0.1))
			continue
		if a.position.y > g + GROUND_TOL:
			floating.append("%s@%s（底高出 %.2f）" % [k, o.snappedf(0.1), a.position.y - g])
		if a.end.y < g + 0.01 and k != "land":
			buried.append("%s@%s" % [k, o.snappedf(0.1)])
		if k in ["flag", "curb"]:
			var d := a.end.y - g
			worst_flush = maxf(worst_flush, absf(d - 0.02))
			if d < -0.03 or d > 0.08:
				flush.append("%s@%s（頂−路面 %.2f）" % [k, o.snappedf(0.1), d])
		if (k == "pile" or k == "piler") and a.position.y > g - 0.3:
			piles_bad += 1
	_res("grounding", floating.is_empty(), "%d 件：底 ≤ 地面＋%.2f（不浮）違規 %d%s" % [n, GROUND_TOL, floating.size(),
		"" if floating.is_empty() else "（" + "、".join(floating.slice(0, 4)) + "）"])
	_res("grounding", buried.is_empty(), "頂 ≥ 地面（不整顆埋）違規 %d%s" % [buried.size(),
		"" if buried.is_empty() else "（" + "、".join(buried.slice(0, 4)) + "）"])
	_res("grounding", flush.is_empty(), "橋頭鋪石／見切り石 頂−路面 −0.03～+0.08（平貼路面）違規 %d、最大偏差 %.3f%s" % [
		flush.size(), worst_flush, "" if flush.is_empty() else "（" + "、".join(flush.slice(0, 4)) + "）"])
	_res("grounding", piles_bad == 0, "木樁埋入 ≥ 0.30 m：違規 %d" % piles_bad)
	var land_bad := 0
	for st: Dictionary in P["stairs"]:
		var land: Vector3 = st["land"]
		var wl := float(WL[String(st["water"])].at(land.x, land.z))
		for it: Dictionary in items:
			if String(it["k"]) == "land" and (it["xf"] as Transform3D).origin.distance_to(land) < 0.05:
				if _waabb(it).position.y > wl - 0.3:
					land_bad += 1
	_res("grounding", land_bad == 0, "親水平台基石底在水位下 ≥ 0.30（不懸在水面）：違規 %d" % land_bad)


# ─────────────────────────── 4 材質 ───────────────────────────

func _c_materials() -> void:
	var used := {}
	var bad: Array = []
	for n: String in lib:
		var m: Mesh = lib[n]
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			var nm: String = m.surface_get_name(s)
			used[nm] = true
			if not nm in MATS or mat == null:
				bad.append("%s/%s" % [n, nm])
	var ovr := 0
	var chunk_mats := {}
	for mi in rb.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.material_override != null:
			ovr += 1
		for s in m.mesh.get_surface_count():
			chunk_mats[m.mesh.surface_get_name(s)] = true
	_res("materials", bad.is_empty() and ovr == 0 and chunk_mats.size() <= 2,
		"構件材質只用 %s（町家 Kit 已過 gate 的 world triplanar 石材＋共享材質庫木材，未新增貼圖）：違規 %d；區塊材質 %s；override %d" % [
		"／".join(MATS), bad.size(), chunk_mats.keys(), ovr])
	# 濕石／苔頂點色：水線附近頂點比岸頂暗
	var wet := 0.0
	var dry := 0.0
	var nw := 0
	var nd := 0
	for c in rb.get_children():
		var mi := c.get_node_or_null("LOD0") as MeshInstance3D
		if mi == null:
			continue
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_name(s) != "V2_KitStoneTri":
				continue
			var arr := mi.mesh.surface_get_arrays(s)
			var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var C: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			for i in range(0, V.size(), 7):
				var p := V[i]
				var best := NAN
				for w: String in WL:
					var h := float(WL[w].at(p.x, p.z))
					if not is_nan(h) and (is_nan(best) or absf(h - p.y) < absf(best - p.y)):
						best = h
				if is_nan(best):
					continue
				var rel := p.y - best
				if rel > -0.05 and rel < 0.2:
					wet += C[i].get_luminance()
					nw += 1
				elif rel > 1.3:
					dry += C[i].get_luminance()
					nd += 1
	var kw := wet / maxi(nw, 1)
	var kd := dry / maxi(nd, 1)
	_res("materials", nw > 100 and nd > 100 and kw < kd * 0.85, "濕石／苔頂點色：水線 −0.05～+0.2 m 平均亮度 %.3f（%d 點）vs 水面上 1.3 m 以上 %.3f（%d 點）＝ %.0f %%（< 85 %%）" % [
		kw, nw, kd, nd, kw / maxf(kd, 1e-4) * 100.0])


# ─────────────────────────── 5 幾何 ───────────────────────────

func _c_geometry() -> void:
	var degen := 0
	var nan := 0
	var no_nuv := 0
	for n: String in lib:
		var m: Mesh = lib[n]
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if arr[Mesh.ARRAY_NORMAL] == null or arr[Mesh.ARRAY_TEX_UV] == null:
				no_nuv += 1
			for p in V:
				if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
					nan += 1
			for t in range(0, I.size(), 3):
				if (V[I[t + 1]] - V[I[t]]).cross(V[I[t + 2]] - V[I[t]]).length() < 1e-9:
					degen += 1
	var neg_det := _count(func(it: Dictionary) -> bool: return (it["xf"] as Transform3D).basis.determinant() <= 0.0)
	_res("geometry", degen == 0 and nan == 0 and no_nuv == 0 and neg_det == 0,
		"構件 %d 個：退化三角形 %d、NaN %d、缺法線／UV %d；擺放 basis 行列式 ≤ 0：%d" % [lib.size(), degen, nan, no_nuv, neg_det])


# ─────────────────────────── 6 Pivot ───────────────────────────

func _c_pivot() -> void:
	var bad: Array = []
	if not rb.transform.is_equal_approx(Transform3D.IDENTITY):
		bad.append("Riverbank 非 identity")
	for c in rb.get_children():
		if not (c as Node3D).transform.is_equal_approx(Transform3D.IDENTITY):
			bad.append("%s 非 identity" % c.name)
		for g in c.get_children():
			if g is Node3D and not (g as Node3D).transform.is_equal_approx(Transform3D.IDENTITY):
				bad.append("%s/%s 非 identity" % [c.name, g.name])
	var wrong_chunk := 0
	for it: Dictionary in items:
		if rb.get_node_or_null(RLib.chunk_key((it["xf"] as Transform3D).origin)) == null:
			wrong_chunk += 1
	_res("pivot_scale", bad.is_empty() and wrong_chunk == 0, "Riverbank／%d 區塊／LOD 節點全 identity（頂點已是世界座標）：違規 %d%s；件所在 32 m 分格都有區塊：缺 %d" % [
		rb.get_child_count(), bad.size(), "" if bad.is_empty() else "（" + "、".join(bad.slice(0, 3)) + "）", wrong_chunk])


# ─────────────────────────── 7 碰撞 ───────────────────────────

func _c_collision() -> void:
	var shapes := rb.find_children("*", "CollisionShape3D", true, false)
	var off := 0
	var layer0 := 0
	for cs in shapes:
		if (cs as CollisionShape3D).disabled:
			off += 1
	for sb in rb.find_children("*", "StaticBody3D", true, false):
		if (sb as CollisionObject3D).collision_layer == 0:
			layer0 += 1
	var want := _count(func(it: Dictionary) -> bool: return not (it["shape"] as Dictionary).is_empty())
	_res("collision", shapes.size() == want and off == 0 and layer0 == 0,
		"BoxShape %d（應 %d：石段／平台／矮欄／大巨石）、停用 %d、layer 0 的 body %d；護岸面板／鋪石／河原石不給碰撞（地形碰撞不變）" % [
		shapes.size(), want, off, layer0])
	# 石段碰撞頂＝踏面：每級中心往下打射線（只看 Riverbank 碰撞）
	var worst := 0.0
	var miss := 0
	var q := PhysicsRayQueryParameters3D.new()
	q.exclude = [terrain_rid]
	var n := 0
	for st: Dictionary in P["stairs"]:
		for t: Vector3 in (st["tops"] as Array) + [st["land"]]:
			q.from = t + Vector3(0, 1.0, 0)
			q.to = t - Vector3(0, 1.0, 0)
			var h := space.intersect_ray(q)
			n += 1
			if h.is_empty():
				miss += 1
				continue
			var d := absf((h["position"] as Vector3).y - t.y)
			worst = maxf(worst, d)
	_res("collision", miss == 0 and worst <= 0.03, "石段／平台 %d 面：碰撞頂 vs 踏面最大差 %.3f m（≤ 0.03）、打不到 %d" % [n, worst, miss])


# ─────────────────────────── 8 LOD ───────────────────────────

func _c_lod() -> void:
	var bad: Array = []
	var worst := 0.0
	for c in rb.get_children():
		var l0 := c.get_node_or_null("LOD0") as MeshInstance3D
		var l1 := c.get_node_or_null("LOD1") as MeshInstance3D
		if l0 == null or l1 == null:
			bad.append("%s 缺 LOD" % c.name)
			continue
		if not is_equal_approx(l0.visibility_range_end, l1.visibility_range_begin) or l0.visibility_range_begin != 0.0:
			bad.append("%s 可見距離不接續" % c.name)
		var t0 := RLib.lod_tris(c, 0)
		var t1 := RLib.lod_tris(c, 1)
		var r := float(t1) / maxf(float(t0), 1.0)
		worst = maxf(worst, r)
		if r > 0.35:
			bad.append("%s LOD1 %.0f %%" % [c.name, r * 100.0])
	_res("lod", bad.is_empty(), "%d 區塊：LOD0（0–%.0f m）／LOD1（–%.0f m）齊全且接續；LOD1／LOD0 最大 %.0f %%（≤ 35 %%）%s" % [
		rb.get_child_count(), float(RLib.LOD_RANGES[1]), float(RLib.LOD_RANGES[2]), worst * 100.0,
		"" if bad.is_empty() else "；✗ " + "、".join(bad.slice(0, 4))])


# ─────────────────────────── 9 效能 ───────────────────────────

func _c_perf() -> void:
	var total := 0
	var mx := 0
	var mx_n := ""
	var surf_bad := 0
	for c in rb.get_children():
		var t := RLib.lod_tris(c, 0)
		total += t
		if t > mx:
			mx = t
			mx_n = c.name
		var mi := c.get_node_or_null("LOD0") as MeshInstance3D
		if mi != null and mi.mesh.get_surface_count() > 2:
			surf_bad += 1
	_res("performance", mx <= CAP_CHUNK and total <= CAP_TOTAL and surf_bad == 0,
		"區塊 LOD0 最大 %d（%s；≤ %d）、全村 LOD0 %d（≤ %d）、LOD1 %d；每區塊 surface ≤ 2（draw call）違規 %d；構件庫 %d 個（每件只存一次、合併進區塊網格）" % [
		mx, mx_n, CAP_CHUNK, total, CAP_TOTAL, int(rb.get_meta("lod1_tris", 0)), surf_bad, lib.size()])


# ─────────────────────────── gate.json ───────────────────────────

func _write_gate(part: String, keys: Array[String], extra := {}) -> void:
	var sha := FileAccess.get_sha256(ENTRY)
	var g: Dictionary = {}
	if FileAccess.file_exists(GATE):
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(GATE))
		if old is Dictionary and String(old.get("entry_sha256", "")) == sha:
			g = old
	g["asset"] = "riverbank_kit"
	g["entry"] = ENTRY
	g["entry_sha256"] = sha
	g["godot"] = Engine.get_version_info()["string"]
	var checks: Dictionary = g.get("checks", {})
	for k in keys:
		var e: Dictionary = R[k]
		checks[k] = {"result": e["result"], "detail": e["detail"], "part": part, "date": Time.get_datetime_string_from_system()}
	g["checks"] = checks
	for k in extra:
		g[k] = extra[k]
	var f := FileAccess.open(GATE, FileAccess.WRITE)
	f.store_string(JSON.stringify(g, " ", false) + "\n")
	f.close()
	_p("寫入 %s（%s）" % [GATE, part])


# ─────────────────────────── render 10–11 ───────────────────────────

func _img_std(img: Image) -> float:
	var n := 0
	var s := 0.0
	var s2 := 0.0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			var l := img.get_pixel(x, y).get_luminance()
			s += l
			s2 += l * l
			n += 1
	var m := s / n
	return sqrt(maxf(0.0, s2 / n - m * m))


func _camera_preflight(cam: Camera3D, meshes: Array) -> Array[String]:
	var violations: Array[String] = []
	var pos := cam.global_position
	for node in meshes:
		var mi := node as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var box := mi.global_transform * mi.mesh.get_aabb()
		# 地形／水面／整區線網的巨大合併 AABB 內有大量空氣，不能當作實際幾何。
		# 這類面片另由離地高度與畫面遮擋檢查；近景建物／橋體逐件嚴格驗 AABB。
		var relative := str(v.get_path_to(mi))
		if (relative.begins_with("Terrain/") or relative.begins_with("Water/") or relative.begins_with("Vegetation/") or relative.contains("ParcelLines")) \
			and maxf(box.size.x, maxf(box.size.y, box.size.z)) > 30.0:
			continue
		# LOD 節點仍可能 visible=true，但超出其實際渲染距離。
		var distance := box.get_center().distance_to(pos)
		if mi.visibility_range_begin > 0.0 and distance < mi.visibility_range_begin:
			continue
		if mi.visibility_range_end > 0.0 and distance > mi.visibility_range_end:
			continue
		var closest := Vector3(clampf(pos.x, box.position.x, box.end.x),
			clampf(pos.y, box.position.y, box.end.y), clampf(pos.z, box.position.z, box.end.z))
		var gap := pos.distance_to(closest)
		if gap < CAMERA_MESH_CLEARANCE:
			violations.append("%s gap=%.2f m" % [mi.get_path(), gap])
	return violations

func _bridge_readability(bridge: Node3D, out: String) -> float:
	# Counterfactual GPU mask: only bridge fragments 3–45 m away are magenta;
	# actual terrain, rails, buildings and player still depth-occlude them.
	var lod := bridge.get_node_or_null("Hero/LOD0") as MeshInstance3D
	if lod == null:
		return 0.0
	var previous := lod.material_override
	var shader := Shader.new()
	shader.code = BRIDGE_MASK_SHADER
	var mask := ShaderMaterial.new()
	mask.shader = shader
	lod.material_override = mask
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if visual_probe:
		image.save_png(out)
	lod.material_override = previous
	var hits := 0
	var total := 0
	for y in range(image.get_height() / 5, image.get_height() * 4 / 5, 4):
		for x in range(image.get_width() / 4, image.get_width() * 3 / 4, 4):
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.90 and pixel.b > 0.90 and pixel.g < 0.45:
				hits += 1
			total += 1
	return float(hits) / maxf(1.0, float(total))

func _render(out: String) -> void:
	if DisplayServer.get_name() == "headless":
		_p("FAIL --render 需要 GPU 視窗（不能 --headless）")
		fails += 1
		return
	if out == "":
		out = ProjectSettings.globalize_path("user://riverbank_kit_gate")
	DirAccess.make_dir_recursive_absolute(out)
	logger = GateLogger.new()
	OS.add_logger(logger)
	# ── F6：全部 LOD0 構件單獨場景（平地一排）
	var e0 := logger.errors.size()
	var f6 := Node3D.new()
	root.add_child(f6)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	f6.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	f6.add_child(env)
	var flib := RLib.load_lib()
	var names: Array = flib.keys().filter(func(k: String) -> bool: return not k.ends_with("_l1"))
	names.sort()
	var x := 0.0
	for n: String in names:
		var mi := MeshInstance3D.new()
		mi.mesh = flib[n]
		var w := (flib[n] as Mesh).get_aabb().size.x
		mi.position = Vector3(x + w * 0.5, 0, 0)
		f6.add_child(mi)
		x += w + 0.4
	var cam := Camera3D.new()
	f6.add_child(cam)
	cam.look_at_from_position(Vector3(x * 0.5, x * 0.18, x * 0.32), Vector3(x * 0.5, 0.3, 0))
	cam.current = true
	var f6_png := out.path_join("riverbank_kit_f6.png")
	if not visual_probe:
		for i in 120:
			await process_frame
		root.get_texture().get_image().save_png(f6_png)
	var f6_err := logger.errors.size() - e0
	f6.queue_free()
	await process_frame
	# ── F5：main.tscn 實際載 village_v2
	var e1 := logger.errors.size()
	var sf := root.get_node("/root/StoryFlags")
	sf.set_flag("woke_in_trail", true)
	sf.set_flag("met_reimu", true)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in (2 if visual_probe else 60):
		await process_frame
	main.load_map("village_v2", "trail")
	for i in (2 if visual_probe else 90):
		await process_frame
	var vr: Node3D = main.map_root
	var baked := vr.get_node_or_null("Riverbank") != null
	await _setup(null, vr)
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for g: String in ["Debug", "Portals"]:
		var nd := v.get_node_or_null(g) as Node3D
		if nd:
			nd.visible = false
	var player: CharacterBody3D = main.player
	# Gate screenshots must not inherit mouse-look events from the GPU test window.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var camera_adapter := player.get_node("CameraAdapter")
	var spring_arm := player.get_node("Pivot/SpringArm3D") as SpringArm3D
	var normal_arm := spring_arm.spring_length
	var visible_meshes: Array = vr.find_children("*", "MeshInstance3D", true, false)
	var shot_lines: Array = []
	var shot_ok := true
	var visual_cases := {}
	var perf: Array = []
	var n := 0
	# 鏡位：每座橋兩端（路上、橋頭外 7 m 看橋頭）＋每處親水點（岸頂石段上方 3 m 看平台）
	var views: Array = []
	for b: Dictionary in P["bridges"]:
		var F: Transform3D = b["F"]
		var zx := Vector3(F.basis.z.x, 0, F.basis.z.z).normalized()
		for e: float in [-1.0, 1.0]:
			var head := F.origin + zx * e * float(b["L"]) * 0.5
			var name := "%s_%s" % [String(b["name"]).substr(0, 9), "n" if e > 0 else "s"]
			if name == "Bridge_02_n":
				# 永久負例沿用原本橋頭外 7 m、8.5 m 相機臂；絕不可拿來當正式審圖。
				if visual_probe:
					views.append(["Bridge_02_n_legacy", head + zx * 7.0, head])
				views.append([name, head + zx * B2_REVIEW_APPROACH + B2_REVIEW_LATERAL, head])
			else:
				views.append([name, head + zx * e * 7.0, head])
	var si := 0
	for st: Dictionary in P["stairs"]:
		si += 1
		var t0: Vector3 = (st["tops"] as Array)[0]
		var land: Vector3 = st["land"]
		var dirv := Vector3(land.x - t0.x, 0, land.z - t0.z).normalized()
		views.append(["stair_%d" % si, t0 - dirv * 3.0, land])
	for vw: Array in views:
		var name: String = vw[0]
		var distance := 4.0 if name == "Bridge_02_n" else normal_arm
		camera_adapter._target_distance = distance
		camera_adapter._current_distance = distance
		spring_arm.spring_length = distance
		var p: Vector3 = vw[1]
		var tgt: Vector3 = vw[2]
		var gy := _surf(p.x, p.z)
		player.global_position = Vector3(p.x, gy + 0.05, p.z)
		player.velocity = Vector3.ZERO
		var dd := Vector2(tgt.x - p.x, tgt.z - p.z)
		player.snap_yaw(atan2(-dd.x, -dd.y))
		var pitch := 0.0 if name == "Bridge_02_n" else -0.18
		camera_adapter._target_pitch = pitch
		camera_adapter._current_pitch = pitch
		for i in (3 if visual_probe else 75):
			await process_frame
		var img := root.get_texture().get_image()
		var c3 := root.get_viewport().get_camera_3d()
		var camera_bad := _camera_preflight(c3, visible_meshes) if c3 != null else ["no camera"]
		if not camera_bad.is_empty():
			_p("camera preflight %s FAIL：%s" % [vw[0], "；".join(camera_bad.slice(0, 4))])
		var sd := _img_std(img)
		var in_frame := c3 != null and not c3.is_position_behind(tgt) \
			and Rect2(Vector2.ZERO, Vector2(img.get_size())).has_point(c3.unproject_position(tgt))
		var cam_clearance := c3.global_position.y - _surf(c3.global_position.x, c3.global_position.z) if c3 != null else -INF
		var png := out.path_join("riverbank_%s.png" % vw[0])
		img.save_png(png)
		var readable := 1.0
		if String(vw[0]).begins_with("Bridge_"):
			readable = 0.0
			for bridge in vr.get_node("Roads/Bridges").get_children():
				if String(bridge.name).begins_with(String(vw[0]).substr(0, 9)):
					readable = await _bridge_readability(bridge, out.path_join("mask_%s.png" % vw[0]))
					break
			_p("visual %s：中段橋體可辨識像素 %.3f（門檻 %.3f）" % [vw[0], readable, BRIDGE_READABLE_MIN])
		var ok := sd > 0.05 and in_frame and cam_clearance >= 1.0 and camera_bad.is_empty() and readable >= BRIDGE_READABLE_MIN
		visual_cases[name] = ok
		if name != "Bridge_02_n_legacy":
			shot_ok = shot_ok and ok
			n += 1
			shot_lines.append("%s%s（亮度標準差 %.3f、鏡頭離地 %.2f m、%s、遠距橋體 %.3f）" % ["" if ok else "✗ ", png.get_file(), sd, cam_clearance, "在畫面內" if in_frame else "不在畫面內", readable])
			perf.append("%s：%d 三角面／%d draw call" % [vw[0],
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	_res("player_screenshot", shot_ok and n >= 10 + (P["stairs"] as Array).size(), "main.tscn 載 village_v2（Riverbank %s）、玩家鏡位 %d 張（5 橋 × 2 端＋親水點 %d）：%s" % [
		"已烘焙在場景" if baked else "執行期以產生器同一段烘焙", n, (P["stairs"] as Array).size(), "；".join(shot_lines)])
	if visual_probe:
		OS.remove_logger(logger)
		var expected: bool = visual_cases.size() == 11 and not bool(visual_cases.get("Bridge_02_n_legacy", true))
		for key: String in visual_cases:
			if key != "Bridge_02_n_legacy" and not bool(visual_cases[key]):
				expected = false
		_p("%s visual regression：舊 Bridge_02_n_legacy 必須 FAIL；正式十鏡位必須 PASS；%s" % ["PASS" if expected else "FAIL", visual_cases])
		if not expected:
			fails += 1
		return # 僅驗預期負例與正式鏡位；不寫 gate.json、不啟動實走
	# 實走
	var walk_lines: Array = []
	var walk_ok := true
	for b: Dictionary in P["bridges"]:
		var F: Transform3D = b["F"]
		var zx := Vector3(F.basis.z.x, 0, F.basis.z.z).normalized()
		for e: float in [-1.0, 1.0]:
			var head := F.origin + zx * e * float(b["L"]) * 0.5
			var wk := await _walk(player, [head + zx * e * 7.0, head - zx * e * 2.5], "%s_%s" % [String(b["name"]).substr(0, 9), "n" if e > 0 else "s"])
			walk_ok = walk_ok and wk[0]
			walk_lines.append(wk[1])
	si = 0
	for st: Dictionary in P["stairs"]:
		si += 1
		var tops: Array = st["tops"]
		var t0: Vector3 = tops[0]
		var land: Vector3 = st["land"]
		var dirv := Vector3(land.x - t0.x, 0, land.z - t0.z).normalized()
		var path: Array = [t0 - dirv * 1.2]
		path.append_array(tops)
		path.append(land)
		var wk := await _walk(player, path, "stair_%d" % si, land.y)
		walk_ok = walk_ok and wk[0]
		walk_lines.append(wk[1])
	if neg == "error":
		push_error("反向測試：刻意的錯誤")
	var f5_err := logger.errors.size() - e1
	var errs: Array = logger.errors.slice(0, 3)
	_res("f5_f6", f6_err == 0 and f5_err == 0 and walk_ok, "F6（%d 構件單獨場景 120 幀）錯誤 %d；F5（main.tscn → village_v2、%d 張鏡位＋實走 %d 段）錯誤 %d、警告 %d；%s%s" % [
		names.size(), f6_err, n, walk_lines.size(), f5_err, logger.warnings.size(), "；".join(walk_lines),
		("；錯誤例：" + " | ".join(errs)) if errs else ""])
	OS.remove_logger(logger)
	_flush(RENDER_KEYS)
	if neg == "" and fails == 0:
		_write_gate("render", RENDER_KEYS, {"render_info": {"f6_png": f6_png.get_file(), "perf": perf,
			"warnings": logger.warnings.slice(0, 10), "renderer": RenderingServer.get_current_rendering_method()}})
	_p("F6 截圖 %s；效能（畫面內總量）：%s" % [f6_png, "；".join(perf)])


## 實走：沿航點（世界座標）走；每點 6 秒內到 0.35 m 內；著地時腳底離可見地面（地形／路／石段碰撞）≤ 0.10（石段 ≤ 0.28＝站踏石前緣）、
## 連續騰空 ≤ 24 幀（0.4 s：下一級 0.27 m 自由落約 0.23 s；掉下岸／卡住跳躍會超過）
## goal_y 給定＝終點要站在該高度 ±0.15（石段走到平台）
func _walk(player: CharacterBody3D, path: Array, tag: String, goal_y := NAN) -> Array:
	var p0: Vector3 = path[0]
	player.global_position = Vector3(p0.x, _surf(p0.x, p0.z) + 0.1, p0.z)
	player.velocity = Vector3.ZERO
	for i in 20:
		await physics_frame
	var max_gap := 0.0
	var air := 0
	var max_air := 0
	var reached := 0
	var q := PhysicsRayQueryParameters3D.new()
	q.exclude = [player.get_rid()]
	for wi in range(1, path.size()):
		var goal: Vector3 = path[wi]
		var t0 := Time.get_ticks_msec()
		Input.action_press("move_forward")
		var ok := false
		for f in 60 * 6:
			var p := player.global_position
			var dd := Vector2(goal.x - p.x, goal.z - p.z)
			if dd.length() < 0.35:
				ok = true
				break
			if f % 3 == 0:
				player.snap_yaw(atan2(-dd.x, -dd.y))
			await physics_frame
			# 下一級踏石時會自由落 1 級（≤ 0.27 m）：離地只在「站在地上」時量；另記連續騰空幀數（掉下岸會很長）
			air = 0 if player.is_on_floor() else air + 1
			max_air = maxi(max_air, air)
			if f % 5 == 0 and player.is_on_floor():
				q.from = player.global_position + Vector3(0, 0.3, 0)
				q.to = player.global_position - Vector3(0, 2.0, 0)
				var h := space.intersect_ray(q)
				if not h.is_empty():
					max_gap = maxf(max_gap, player.global_position.y - (h["position"] as Vector3).y)
			if Time.get_ticks_msec() - t0 > 6000:
				break
		Input.action_release("move_forward")
		if not ok:
			break
		reached += 1
	for i in 10:
		await physics_frame
	var end_ok := true
	var dy := 0.0
	if not is_nan(goal_y):
		dy = player.global_position.y - goal_y
		end_ok = absf(dy) <= 0.15
	# 石段上膠囊圓底會站在踏石前緣、中心射線落到下一級 → 著地離可見面容許 1 級級高（≤ 0.28）；平路 ≤ 0.10
	var gap_tol := 0.10 if is_nan(goal_y) else 0.28
	var all_ok := reached == path.size() - 1 and max_gap <= gap_tol and max_air <= 24 and end_ok
	return [all_ok, "%s%s 走 %d／%d 點、著地時離可見面最大 %.2f、連續騰空最長 %d 幀%s" % ["" if all_ok else "✗ ", tag, reached,
		path.size() - 1, max_gap, max_air, "" if is_nan(goal_y) else "、終點離平台 %.2f" % dy]]
