extends SceneTree
## 人間之里 V2 P6：模組化町家 Kit 的 Asset Gate（11 項，與 Hero Gate 同名同義；Kit 一次驗全部套用的町家）。
##   headless 1–9：godot --headless --path . --script res://tools/verify_village_v2_machiya_kit_gate.gd [-- --neg=<案例>]
##   render 10–11：godot --path . --resolution 1600x900 --script res://tools/verify_village_v2_machiya_kit_gate.gd -- --render [--out=<dir>]
## entry＝assets/village_v2/machiya_kit/machiya_kit_manifest.json（構件 mesh／組裝腳本／材質／atlas 全部 sha256）；
## gate.json 記 entry 雜湊，任何一檔改動 → registry 不登記 → 產生器維持 P4 灰盒。
## 尺寸 authority＝P4 灰盒紀錄（greybox.json）；每棟都驗，彙總最差值。
##   1 尺寸     牆面／背面／屋面（P4 屋根面）／屋脊射線實測 vs P4；LOD0 外框在 P4 量體＋出簷內；入口淨高 ≥ 1.90、淨寬 ≥ 1.20
##              R3：屋根型（兩坡勾配 ≤ 0.45、兩側簷高＝P4）→ 前後坡各一條射線驗 Kit 自己的屋根面，且棟高 ≤ P4 屋脊、
##              屋根面處處不高於 P4 屋根面（勾配 ≤ P4）；入口退縮時量測點跟著退
##   2 地塊     台基在自己地塊內；整棟 LOD0 外框（含屋簷、庇）不進道路、不壓鄰地
##   3 接地     台基底＝ground_lo−embed、頂＝地板 0.32；台基四角＋中心地形都在台基高度區間內（不浮、不整棟埋）
##   4 材質     只用共享材質庫＋Kit atlas（≤ 5）、無 override、albedo_k 一致、貼圖 ≤ 2K VRAM 壓縮
##   5 幾何     構件無退化三角形／NaN、有法線與 UV；構件縮放只在設計方向（開間 x ±12 %、屋面 y＝z 同比）
##   6 Pivot    Kit 節點 identity、灰盒節點位置＝P4（中心、base、朝向），正面構件在 +z 牆面
##   7 碰撞     沿用 P4 灰盒 BoxShape（尺寸＝P4、啟用、layer≠0）；牆體構件不突出碰撞面 > 0.15 m
##   8 LOD      LOD0／1／2 齊全、可見距離接續；LOD1 ≤ 35 %、LOD2 ≤ 10 %；外框與 LOD0 差 ≤ 0.6 m
##   9 效能     每棟 LOD0 ≤ §14.8「町家」25000；每棟材質 ≤ 5、碰撞 1；Kit 專屬貼圖 VRAM ≤ 8 MB；全村總量報告
##  10 截圖     main.tscn 載 village_v2，代表棟（類型×平入／妻入＋店先）玩家鏡位各 3 張：亮度標準差、在畫面內、無遮擋
##  11 F5/F6    F6＝代表棟單獨場景 120 幀 0 錯誤；F5＝main.tscn 0 錯誤、實走被碰撞擋在外、不浮空
## 回歸（唯讀）：-- --regress  重驗 1–9 項（場景已烘焙的 Kit），不寫 gate.json；另驗 gate.json 11 項 PASS 且 manifest 雜湊一致。
## 反向案例（--neg，不寫 gate.json，預期對應項 FAIL）：size（牆外推）、parcel（整棟推出地塊）、ground（抬高 0.5）、
##   material（override）、collision（關碰撞）、lod（刪 LOD2）、perf（LOD0 複製 3 份）。

const KLib := preload("res://tools/village_v2_machiya_kit_lib.gd")
const GLib := preload("res://tools/village_v2_greybox_lib.gd")
const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const PLib := preload("res://tools/village_v2_parcel_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const PARCELS := "res://maps/village_v2/gen/parcels.json"
const GREYBOX := "res://maps/village_v2/gen/greybox.json"
const MATLIB := "res://assets/village_v2/_matlib/matlib.json"
const DIR := "res://assets/village_v2/machiya_kit"
const ENTRY := DIR + "/machiya_kit_manifest.json"
const GATE := DIR + "/gate.json"
const HEADLESS_KEYS: Array[String] = ["size", "parcel_fit", "grounding", "materials", "geometry", "pivot_scale",
	"collision", "lod", "performance"]
const RENDER_KEYS: Array[String] = ["player_screenshot", "f5_f6"]
const CAP_LOD0 := 25000        # §14.8「町家」（使用者 2026-09-24 核准）
const MAX_MATS := 5
const TEX_MAX := 2048
const POKE_TOL := 0.15
const FRONT_OUT := 0.25      # 無庇棟：出格子／柱等正面細部可出牆面的上限
const WALL_PREFIX := ["f1_", "u_", "bk_", "sd_", "sdo_", "post_", "fp_", "fb_", "rt_", "rtu", "base"]
const MATS := ["res://assets/village_v2/_matlib/V2_Wood.tres", "res://assets/village_v2/_matlib/V2_Plaster.tres",
	"res://assets/village_v2/_matlib/V2_Kawara.tres", DIR + "/V2_KitStoneTri.tres", DIR + "/V2_MachiyaKit.tres"]


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
var GB: Dictionary
var recs: Array = []           # machiya 灰盒紀錄
var bodies := {}               # id → StaticBody3D
var kits := {}                 # id → Kit Node3D
var v: Node3D
var space: PhysicsDirectSpaceState3D
var terrain_rid := RID()
var player_rid := RID()
var neg := ""
var regress := false
var logger: GateLogger


func _init() -> void:
	_run.call_deferred()


func _p(s: String) -> void:
	print("[KIT] " + s)


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
		print("[KIT] %s machiya_kit %s：%s" % [e["result"], k, "；".join(e["detail"])])
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
	L = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	GB = JSON.parse_string(FileAccess.get_file_as_string(GREYBOX))
	for b: Dictionary in GB["buildings"]:
		if String(b["kind"]) == "machiya":
			recs.append(b)
	if not FileAccess.file_exists(ENTRY):
		_p("FAIL 缺 %s（先跑 village_v2_machiya_kit_prefab.gd）" % ENTRY)
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


## 場景：載入 village_v2，套 Kit（已烘焙就直接用）
func _setup(parent: Node, vroot: Node3D = null) -> void:
	if vroot == null:
		v = (load(SCENE) as PackedScene).instantiate()
		parent.add_child(v)
	else:
		v = vroot
	var lib := KLib.load_lib()
	var embed := float(L["greybox"]["embed"])
	for b: Dictionary in recs:
		var body := v.get_node_or_null("Districts/%s/Buildings/%s" % [b["district"], b["id"]]) as StaticBody3D
		if body == null:
			continue
		bodies[b["id"]] = body
		if not regress:
			# 非回歸：場景裡已烘焙的舊 Kit 丟掉，用目前構件庫＋組裝腳本重組（驗的是這一版）
			var old := body.get_node_or_null("Kit")
			if old != null:
				body.remove_child(old)
				old.free()
		kits[b["id"]] = KLib.apply(body, b, lib, embed)
	await physics_frame
	await physics_frame
	space = v.get_world_3d().direct_space_state
	terrain_rid = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()


func _apply_neg() -> void:
	if neg == "":
		return
	var b0: Dictionary = recs[0]
	var k0: Node3D = kits[b0["id"]]
	var l0 := k0.get_node("LOD0") as Node3D
	match neg:
		"size":
			for mi: MeshInstance3D in l0.get_children():
				if String(mi.name).begins_with("sd_"):
					mi.position.x *= 1.1
		"parcel":
			k0.position.z += 3.0
		"ground":
			k0.position.y += 0.5
		"material":
			(l0.get_child(0) as MeshInstance3D).material_override = StandardMaterial3D.new()
		"collision":
			(bodies[b0["id"]].get_node("Shape") as CollisionShape3D).disabled = true
		"lod":
			k0.get_node("LOD2").free()
		"perf":
			for i in 3:
				for mi: MeshInstance3D in l0.get_children():
					if mi.get_meta("neg_dup", false):
						continue
					var d := mi.duplicate() as MeshInstance3D
					d.set_meta("neg_dup", true)
					l0.add_child(d)


func _headless() -> void:
	await _setup(root)
	_apply_neg()
	_p("%d 棟町家（P4 machiya）套 Kit：%d" % [recs.size(), kits.size()])
	_res("size", kits.size() == recs.size(), "P4 machiya %d 棟、套 Kit %d 棟" % [recs.size(), kits.size()])
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
		var baked := 0
		for id: String in kits:
			if (bodies[id] as Node).get_node_or_null("Kit") != null and (kits[id] as Node).owner != null:
				baked += 1
		print("[KIT] %s gate.json 11 項 PASS 且雜湊一致%s；場景已烘焙 Kit %d／%d 棟" % [
			"PASS" if bad.is_empty() else "FAIL", "" if bad.is_empty() else "（✗ " + "、".join(bad) + "）", baked, recs.size()])
		if not bad.is_empty():
			fails += 1
	elif neg == "":
		_write_gate("headless", HEADLESS_KEYS)


# ─────────────────────────── 工具 ───────────────────────────

func _mis(kit: Node3D, lod: int) -> Array:
	var g := kit.get_node_or_null("LOD%d" % lod)
	return [] if g == null else g.get_children()


## 一棟 LOD0 三角形（body 局部座標）
func _faces(kit: Node3D, lod := 0) -> PackedVector3Array:
	var out := PackedVector3Array()
	var kx := kit.transform
	for mi: MeshInstance3D in _mis(kit, lod):
		var xf := kx * (mi.get_parent() as Node3D).transform * mi.transform
		for p in mi.mesh.get_faces():
			out.append(xf * p)
	return out


func _aabb(kit: Node3D, lod := 0, only := []) -> AABB:
	var a := AABB()
	var first := true
	for mi: MeshInstance3D in _mis(kit, lod):
		if not only.is_empty():
			var hit := false
			for pre: String in only:
				hit = hit or String(mi.name).begins_with(pre)
			if not hit:
				continue
		var b: AABB = kit.transform * (mi.get_parent() as Node3D).transform * mi.transform * mi.mesh.get_aabb()
		a = b if first else a.merge(b)
		first = false
	return a


## 射線對三角形：回傳 from 到第一個交點的距離（無交點 INF）
func _ray(f: PackedVector3Array, from: Vector3, to: Vector3) -> float:
	var best := INF
	for t in range(0, f.size(), 3):
		var h: Variant = Geometry3D.segment_intersects_triangle(from, to, f[t], f[t + 1], f[t + 2])
		if h != null:
			best = minf(best, from.distance_to(h))
	return best


func _tris(kit: Node3D, lod: int) -> int:
	var t := 0
	for mi: MeshInstance3D in _mis(kit, lod):
		t += mi.mesh.get_faces().size() / 3
	return t


func _worst(arr: Array, n := 3) -> String:
	return "、".join(arr.slice(0, n))


# ─────────────────────────── 1 尺寸 ───────────────────────────

func _c_size() -> void:
	var bad: Array = []
	var dmax := {"side": 0.0, "back": 0.0, "roof": 0.0, "ridge": 0.0, "box": 0.0}
	var door_h := INF
	var door_w := INF
	for b: Dictionary in recs:
		var kit: Node3D = kits.get(b["id"])
		if kit == null:
			continue
		var w := float(b["width_m"])
		var d := float(b["depth_m"])
		var hira := String(b["roof"]) == "hira"
		var ove := float(b["ov_eave_m"])
		var ovg := float(b["ov_gable_m"])
		var ridge := float(b["ridge_m"])
		var f := _faces(kit)
		var id := String(b["id"])
		# 牆面：側牆 x＝±w/2、背面 z＝−d/2（y 1.5、避開柱位取 3 個點取最小）
		var sx := INF
		for zz in [-0.37, 0.41, 1.13]:
			sx = minf(sx, 30.0 - _ray(f, Vector3(30, 1.5, zz), Vector3(0, 1.5, zz)))
		var bz := INF
		for xx in [-0.53, 0.29, 0.77]:
			bz = minf(bz, 30.0 - _ray(f, Vector3(xx, 1.5, -30), Vector3(xx, 1.5, 0)))
		var e_side := absf(sx - w * 0.5)
		var e_back := absf(bz - d * 0.5)
		# 屋面：R3 屋根型（kit meta：兩坡勾配 pa／pb、棟位置 cr、棟高 H）。前後坡簷側中段各一條垂直射線 → Kit 屋根面＋瓦厚；
		# 屋根座標（棟沿 rx、A 坡朝 +rz）→ 建物座標：平入 rx＝+x、rz＝+z；妻入 rx＝+z、rz＝−x。
		var half := (d if hira else w) * 0.5
		var ps: Array = kit.get_meta("roof_ps", [KLib.P, KLib.P])
		var cr := float(kit.get_meta("roof_cr", 0.0))
		var H := float(kit.get_meta("roof_h", ridge))
		var e_roof := -INF
		var e_roof_lo := INF
		for side in [0, 1]:
			var sg := 1.0 if side == 0 else -1.0
			var hz := cr + sg * (half + sg * -cr + ove * 0.5 - 0.3)     # 屋根座標 z（離棟水平 half∓cr＋ove/2−0.3）
			var pv := Vector3(0.137, 40, hz) if hira else Vector3(-hz, 40, 0.137)
			var ry := 40.0 - _ray(f, pv, Vector3(pv.x, -5, pv.z))
			var want := H - float(ps[side]) * absf(hz - cr)
			e_roof = maxf(e_roof, ry - want)       # 瓦面在 Kit 屋根面上方 0～0.2
			e_roof_lo = minf(e_roof_lo, ry - want)
		var pr := Vector3(0.043, 40, cr + 0.043) if hira else Vector3(-cr + 0.043, 40, 0.043)
		var top := 40.0 - _ray(f, pr, Vector3(pr.x, -5, pr.z))   # 棟線上（離棟心 0.043）
		var e_ridge := top - H       # 棟（熨斗瓦＋冠瓦）0.2～0.4
		var e_h := H - ridge         # 棟高不高於 P4 屋脊
		var pmax: float = maxf(float(ps[0]), float(ps[1]))
		dmax["drop"] = maxf(float(dmax.get("drop", 0.0)), ridge - H)
		# 外框：與 P4 灰盒網格（Foundation／Building_Main／Roof／Hisashi／Door，已隱藏但仍在）外框比，各向超出量
		var ab := _aabb(kit)
		var gb := _gb_aabb(bodies[b["id"]])
		var ex := [gb.position.x - ab.position.x, ab.end.x - gb.end.x, gb.position.z - ab.position.z, ab.end.z - gb.end.z]
		var e_box: float = ex.max()
		var e_top := ab.end.y - ridge     # R3：最高點（棟瓦／煙出し／本卯建）離 P4 屋脊 ≤ 0.55（R2 煙出し 0.48 同級）
		dmax["top"] = maxf(float(dmax.get("top", -INF)), e_top)
		var ok := e_side <= 0.06 and e_back <= 0.06 and e_roof_lo >= -0.02 and e_roof <= 0.2 and e_ridge >= 0.15 \
			and e_ridge <= 0.4 and e_box <= 0.06 and e_h <= 0.001 and pmax <= KLib.P + 1e-4 and e_top <= 0.55
		if not ok:
			bad.append("%s 側 %.2f／背 %.2f／屋面 %+.2f..%+.2f／棟 %+.2f／棟高−P4 %+.2f／勾配 %.2f／頂 %+.2f／外框 %+.2f（−x %+.2f +x %+.2f −z %+.2f +z %+.2f）" % [
				id, e_side, e_back, e_roof_lo, e_roof, e_ridge, e_h, pmax, e_top, e_box, ex[0], ex[1], ex[2], ex[3]])
		dmax["side"] = maxf(dmax["side"], e_side)
		dmax["back"] = maxf(dmax["back"], e_back)
		dmax["roof"] = maxf(dmax["roof"], maxf(absf(e_roof), absf(e_roof_lo)))
		dmax["ridge"] = maxf(dmax["ridge"], e_ridge)
		dmax["box"] = maxf(dmax["box"], e_box)
		# 入口：Kit 入口開間中心、開口內 0.3 m（通行路徑；暖簾是布，不算淨高），地板上往上到第一個面（淨高）；y 1.0 往左右（淨寬）
		var dx := float(kit.get_meta("door_cx", 0.0))
		var z0 := d * 0.5 - float(kit.get_meta("door_rec", 0.0)) - 0.3
		var up := _ray(f, Vector3(dx, KLib.FL + 0.05, z0), Vector3(dx, 6, z0)) + 0.05
		var lw := _ray(f, Vector3(dx, 1.0, z0), Vector3(dx - 3, 1.0, z0))
		var rw := _ray(f, Vector3(dx, 1.0, z0), Vector3(dx + 3, 1.0, z0))
		door_h = minf(door_h, up)
		door_w = minf(door_w, lw + rw)
		if up < 1.90 or lw + rw < 1.20:
			bad.append("%s 入口淨高 %.2f／淨寬 %.2f" % [id, up, lw + rw])
	_res("size", bad.is_empty(), "射線實測 %d 棟 vs P4：側牆差最大 %.3f m、背牆差最大 %.3f（≤ 0.06）；瓦面離 Kit 屋根面（前後坡各一）最大 %.2f（0～0.20）；棟瓦高出棟線最大 %.2f（0.15～0.40）；R3 棟高全部 ≤ P4 屋脊（最多降 %.2f m）、勾配 ≤ P4 0.45、兩側簷高＝P4；最高點離 P4 屋脊最大 %+.2f（≤ 0.55）；外框超出 P4 灰盒網格外框（含屋根、庇）最大 %+.3f（≤ 0.06）%s" % [
		recs.size(), dmax["side"], dmax["back"], dmax["roof"], dmax["ridge"], float(dmax.get("drop", 0.0)), float(dmax.get("top", 0.0)), dmax["box"], ("；" + _worst(bad)) if bad else ""])
	_res("size", door_h >= 1.90 and door_w >= 1.20, "人物比例：入口開間最小淨高 %.2f m（≥ 1.90，1.7 m 人）、最小淨寬 %.2f m（≥ 1.20）" % [door_h, door_w])


# ─────────────────────────── 2 地塊 ───────────────────────────

func _c_parcel() -> void:
	var PJ: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PARCELS))
	var polys := {}
	for r in PJ["parcels"]:
		polys[String(r["id"])] = TLib.pts(r["footprint"])
	var roads: Array = []
	for r in PLib.network(L):
		for poly in Geometry2D.offset_polyline(r["pts"], float(r["hw"]), Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
			roads.append([String(r["name"]), poly])
	var bad: Array = []
	var worst_out := 0.0
	var worst_road := 0.0
	var worst_nb := 0.0
	for b: Dictionary in recs:
		var kit: Node3D = kits.get(b["id"])
		if kit == null:
			continue
		var body: Node3D = bodies[b["id"]]
		var own: PackedVector2Array = polys.get(String(b["parcel"]), PackedVector2Array())
		var base := _aabb(kit, 0, ["base"])
		var fp := _rect(body.global_transform, base)
		var outside := _area(Geometry2D.clip_polygons(fp, own))
		var hull := _rect(body.global_transform, _aabb(kit))
		var ghull := _rect(body.global_transform, _gb_aabb(body))
		var road := 0.0
		for rr in roads:
			road += _area(Geometry2D.intersect_polygons(hull, rr[1])) - _area(Geometry2D.intersect_polygons(ghull, rr[1]))
		var nb := 0.0
		var hb := _box2(hull)
		for pid: String in polys:
			if pid == String(b["parcel"]):
				continue
			var pp: PackedVector2Array = polys[pid]
			if not hb.intersects(_box2(pp)):
				continue
			nb = maxf(nb, _area(Geometry2D.intersect_polygons(hull, pp)) - _area(Geometry2D.intersect_polygons(ghull, pp)))
		worst_out = maxf(worst_out, outside)
		worst_road = maxf(worst_road, road)
		worst_nb = maxf(worst_nb, nb)
		if outside > 0.005 or road > 0.05 or nb > 0.05:
			bad.append("%s 台基出地塊 %.3f／外框多壓路 %.3f／多壓鄰地 %.3f m²" % [b["id"], outside, road, nb])
	_res("parcel_fit", bad.is_empty(), "%d 棟：台基出自己地塊最大 %.3f m²（≤ 0.005）；整棟 LOD0 外框（含屋簷、庇）比 P4 灰盒外框多壓道路最大 %.3f m²（≤ 0.05）、多壓鄰地最大 %.3f m²（≤ 0.05；P4 屋簷本來就可出牆線）%s" % [
		recs.size(), worst_out, worst_road, worst_nb, ("；" + _worst(bad)) if bad else ""])


## P4 灰盒網格外框（body 局部；網格被 Kit 隱藏但節點保留）
func _gb_aabb(body: Node3D) -> AABB:
	var a := AABB()
	var first := true
	for nm: String in KLib.GB_MESHES:
		var mi := body.get_node_or_null(nm) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var bb: AABB = mi.transform * mi.mesh.get_aabb()
		a = bb if first else a.merge(bb)
		first = false
	return a


func _rect(xf: Transform3D, a: AABB) -> PackedVector2Array:
	var out := PackedVector2Array()
	for c in [Vector3(a.position.x, 0, a.position.z), Vector3(a.end.x, 0, a.position.z), Vector3(a.end.x, 0, a.end.z),
			Vector3(a.position.x, 0, a.end.z)]:
		var w: Vector3 = xf * c
		out.append(Vector2(w.x, w.z))
	return out


func _box2(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r


func _area(polys: Array) -> float:
	var a := 0.0
	for p: PackedVector2Array in polys:
		var s := 0.0
		for i in p.size():
			s += p[i].cross(p[(i + 1) % p.size()])
		a += absf(s) * 0.5
	return a


# ─────────────────────────── 3 接地 ───────────────────────────

func _terrain(x: float, z: float) -> float:
	var ex: Array[RID] = []
	for i in 16:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -80.0, z))
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return NAN
		if hit["rid"] == terrain_rid:
			return float(hit["position"].y)
		ex.append(hit["rid"])
	return NAN


func _c_ground() -> void:
	var embed := float(L["greybox"]["embed"])
	var bad: Array = []
	var worst_float := -INF
	var worst_bot := 0.0
	for b: Dictionary in recs:
		var kit: Node3D = kits.get(b["id"])
		if kit == null:
			continue
		var body: Node3D = bodies[b["id"]]
		var base := _aabb(kit, 0, ["base"])
		var want_bot := float(b["ground_lo"]) - embed - float(b["base_h"])
		var e_bot := absf(base.position.y - want_bot)
		var e_top := absf(base.end.y - KLib.FL)
		worst_bot = maxf(worst_bot, maxf(e_bot, e_top))
		var xf := body.global_transform
		var ok := e_bot <= 0.01 and e_top <= 0.01
		for c in [Vector3(base.position.x + 0.05, 0, base.position.z + 0.05), Vector3(base.end.x - 0.05, 0, base.position.z + 0.05),
				Vector3(base.end.x - 0.05, 0, base.end.z - 0.05), Vector3(base.position.x + 0.05, 0, base.end.z - 0.05),
				Vector3(base.get_center().x, 0, base.get_center().z)]:
			var wp: Vector3 = xf * c
			var gy := _terrain(wp.x, wp.z) - xf.origin.y
			# 地形在台基高度區間內：台基底在地形下（不浮），台基頂在地形上（不整棟埋）
			var fl := base.position.y - gy          # > 0 ＝台基底浮在地形上
			worst_float = maxf(worst_float, fl)
			if is_nan(gy) or fl > 0.0 or gy > base.end.y - 0.02:
				ok = false
		if not ok:
			bad.append(String(b["id"]))
	_res("grounding", bad.is_empty(), "%d 棟台基：底＝P4 ground_lo−embed、頂＝地板 0.32（差最大 %.3f m ≤ 0.01）；四角＋中心地形都在台基高度區間內，台基底最淺埋 %.2f m（< 0 ＝在地形下）%s" % [
		recs.size(), worst_bot, worst_float, ("；✗ " + _worst(bad, 6)) if bad else ""])


# ─────────────────────────── 4 材質 ───────────────────────────

func _c_materials() -> void:
	var ML: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MATLIB))
	var k := float(ML["albedo_k"])
	var bad: Array = []
	var used := {}
	var seen_mesh := {}
	for id: String in kits:
		for li in 3:
			for mi: MeshInstance3D in _mis(kits[id], li):
				if mi.material_override != null:
					bad.append("%s %s 有 material_override" % [id, mi.name])
				for si in mi.mesh.get_surface_count():
					if mi.get_surface_override_material(si) != null:
						bad.append("%s %s surface %d override" % [id, mi.name, si])
				if seen_mesh.has(mi.mesh):
					continue
				seen_mesh[mi.mesh] = true
				for si in mi.mesh.get_surface_count():
					var m := mi.mesh.surface_get_material(si)
					if m == null or not MATS.has(m.resource_path):
						bad.append("%s 材質 %s 不在白名單" % [mi.mesh.resource_path.get_file(), m.resource_path if m else "null"])
						continue
					used[m.resource_path] = m
	var tex: Array = []
	for path: String in used:
		var m := used[path] as StandardMaterial3D
		var km := float(ML["materials"].get(m.resource_name, {}).get("albedo_k", k))
		if not m.vertex_color_use_as_albedo or not m.albedo_color.is_equal_approx(Color(km, km, km, 1.0)):
			bad.append("%s albedo_color %s（應 %.2f）" % [path.get_file(), m.albedo_color, km])
		for prop in ["albedo_texture", "normal_texture", "roughness_texture", "emission_texture"]:
			var t := m.get(prop) as Texture2D
			if t == null:
				continue
			var e := _tex_check(t, prop == "normal_texture")
			if e != "":
				bad.append(e)
			if not tex.has(t.resource_path.get_file()):
				tex.append(t.resource_path.get_file())
	_res("materials", bad.is_empty() and used.size() <= MAX_MATS, "%d 個材質（≤ %d）：%s；全是共享材質庫／Kit atlas、無 override、albedo_k 一致；%d 張貼圖 ≤ %d²、VRAM 壓縮%s" % [
		used.size(), MAX_MATS, ", ".join(used.keys().map(func(p): return String(p).get_file())), tex.size(), TEX_MAX,
		("；" + _worst(bad, 4)) if bad else ""])


func _tex_check(t: Texture2D, normal: bool) -> String:
	var p := t.resource_path
	var w := t.get_width()
	var h := t.get_height()
	if w > TEX_MAX or h > TEX_MAX or w & (w - 1) != 0 or h & (h - 1) != 0:
		return "%s 尺寸 %d×%d" % [p.get_file(), w, h]
	var cf := ConfigFile.new()
	if cf.load(p + ".import") != OK:
		return "%s 沒有 .import" % p.get_file()
	if int(cf.get_value("params", "compress/mode", -1)) != 2:
		return "%s 未 VRAM 壓縮" % p.get_file()
	if normal and int(cf.get_value("params", "compress/normal_map", 0)) != 1:
		return "%s 法線貼圖未標 normal_map" % p.get_file()
	return ""


# ─────────────────────────── 5 幾何 ───────────────────────────

func _c_geometry() -> void:
	var bad: Array = []
	var degen := 0
	var n_mesh := 0
	var seen := {}
	var kx_lo := INF
	var kx_hi := -INF
	var sc_bad := 0
	for id: String in kits:
		for li in 3:
			for mi: MeshInstance3D in _mis(kits[id], li):
				var nm := String(mi.name)
				var s := mi.transform.basis.get_scale()
				if li == 0 and (nm.begins_with("f1_") or nm.begins_with("u_") or nm.begins_with("bk_")):
					kx_lo = minf(kx_lo, s.x)
					kx_hi = maxf(kx_hi, s.x)
					if absf(s.y - 1.0) > 1e-4 or absf(s.z - 1.0) > 1e-4:
						sc_bad += 1
				elif li == 0 and (nm.begins_with("rf_") or nm.begins_with("vg_")):
					if absf(s.y - s.z) > 1e-4 or s.y < 0.85 or s.y > 1.15:
						sc_bad += 1
				elif li == 0 and (nm.begins_with("gb_") or nm.begins_with("gbh_")):
					if absf(s.x - s.y) > 1e-4 or s.x < 0.85 or s.x > 1.15:
						sc_bad += 1
				elif li == 0 and nm.begins_with("udh_"):
					if s.x < 0.9 or s.x > 1.1 or absf(s.y - 1.0) > 1e-4 or absf(s.z - 1.0) > 1e-4:
						sc_bad += 1
				if seen.has(mi.mesh):
					continue
				seen[mi.mesh] = true
				n_mesh += 1
				for si in mi.mesh.get_surface_count():
					var arr := mi.mesh.surface_get_arrays(si)
					if arr[Mesh.ARRAY_NORMAL] == null or arr[Mesh.ARRAY_TEX_UV] == null:
						bad.append("%s 缺法線或 UV" % mi.mesh.resource_path.get_file())
				var f := mi.mesh.get_faces()
				for t in range(0, f.size(), 3):
					var a := f[t]
					if not (a.is_finite() and f[t + 1].is_finite() and f[t + 2].is_finite()):
						bad.append("%s 有 NaN" % mi.mesh.resource_path.get_file())
						break
					if (f[t + 1] - a).cross(f[t + 2] - a).length() < 1e-7:
						degen += 1
	var kx_ok := kx_lo >= 0.88 and kx_hi <= 1.12
	_res("geometry", bad.is_empty() and degen == 0 and kx_ok and sc_bad == 0, "%d 個共用構件 mesh：退化三角形 %d、NaN／缺法線 UV %d；開間 x 縮放 %.3f～%.3f（±12 %% 內）、屋面／螻羽 y＝z 同比、妻壁 x＝y 同比（違規 %d）%s" % [
		n_mesh, degen, bad.size(), kx_lo, kx_hi, sc_bad, ("；" + _worst(bad)) if bad else ""])


# ─────────────────────────── 6 Pivot / Scale ───────────────────────────

func _c_pivot() -> void:
	var bad: Array = []
	var worst := 0.0
	for b: Dictionary in recs:
		var kit: Node3D = kits.get(b["id"])
		if kit == null:
			continue
		var body: Node3D = bodies[b["id"]]
		var fp := TLib.pts(b["footprint"])
		var c := (fp[0] + fp[1] + fp[2] + fp[3]) * 0.25
		var gp := body.global_position
		var dv := Vector2(float(b["front_dir"][0]), float(b["front_dir"][1]))
		var e := maxf(Vector2(gp.x, gp.z).distance_to(c), absf(gp.y - float(b["base_h"])))
		var yaw_e := absf(wrapf(body.rotation.y - GLib.yaw_of(dv), -PI, PI))
		var fz := INF
		for mi: MeshInstance3D in _mis(kit, 0):
			if String(mi.name).begins_with("f1_"):
				fz = minf(fz, absf(mi.position.z + float(mi.get_meta("rec", 0.0)) - float(b["depth_m"]) * 0.5))
		worst = maxf(worst, e)
		if not kit.transform.is_equal_approx(Transform3D.IDENTITY) or e > 0.02 or yaw_e > 0.002 or fz > 0.001:
			bad.append("%s 位置差 %.3f／朝向差 %.4f／正面構件離牆 %.3f" % [b["id"], e, yaw_e, fz])
	_res("pivot_scale", bad.is_empty(), "%d 棟：Kit 節點 identity（原點＝P4 灰盒原點：footprint 中心、base 高、+z 正面）；灰盒節點與 P4 紀錄位置差最大 %.3f m、朝向一致；正面構件都在 +z 牆面（R3 退縮開間＝牆面−退縮深）%s" % [
		recs.size(), worst, ("；" + _worst(bad)) if bad else ""])


# ─────────────────────────── 7 碰撞 ───────────────────────────

func _c_collision() -> void:
	var embed := float(L["greybox"]["embed"])
	var bad: Array = []
	var poke := 0.0
	for b: Dictionary in recs:
		var kit: Node3D = kits.get(b["id"])
		if kit == null:
			continue
		var body := bodies[b["id"]] as StaticBody3D
		var shapes := body.find_children("*", "CollisionShape3D", false, false)
		var cs := body.get_node_or_null("Shape") as CollisionShape3D
		var w := float(b["width_m"])
		var d := float(b["depth_m"])
		var eave := float(b["eave_m"])
		var bot := float(b["ground_lo"]) - embed - float(b["base_h"])
		if cs == null or cs.disabled or body.collision_layer == 0 or shapes.size() != 1 or not cs.shape is BoxShape3D:
			bad.append("%s 碰撞缺／停用／layer 0" % b["id"])
			continue
		var sz := (cs.shape as BoxShape3D).size
		# greybox.json 的 width／depth 已四捨五入到 0.01 m → 容差 0.011
		if (sz - Vector3(w, eave - bot, d)).abs()[(sz - Vector3(w, eave - bot, d)).abs().max_axis_index()] > 0.011 \
				or absf(cs.position.y - (eave + bot) * 0.5) > 0.011:
			bad.append("%s 碰撞尺寸 %s ≠ P4" % [b["id"], sz])
		var box := AABB(cs.position - sz * 0.5, sz)
		var wa := _aabb(kit, 0, WALL_PREFIX)
		var p := maxf(maxf(box.position.x - wa.position.x, wa.end.x - box.end.x), maxf(box.position.z - wa.position.z, wa.end.z - box.end.z))
		poke = maxf(poke, p)
		if p > POKE_TOL:
			bad.append("%s 牆體突出碰撞 %.2f m" % [b["id"], p])
	_res("collision", bad.is_empty(), "%d 棟：沿用 P4 灰盒 BoxShape（1 個、啟用、layer≠0、尺寸＝P4 寬×(簷−台基底)×深）；牆體構件（含出格子）突出碰撞面最大 %.3f m（≤ %.2f）%s" % [
		recs.size(), poke, POKE_TOL, ("；" + _worst(bad)) if bad else ""])


# ─────────────────────────── 8 LOD ───────────────────────────

func _c_lod() -> void:
	var bad: Array = []
	var r1 := 0.0
	var r2 := 0.0
	var dab := 0.0
	for id: String in kits:
		var kit: Node3D = kits[id]
		var t := []
		var ok := true
		for li in 3:
			var mis := _mis(kit, li)
			if mis.is_empty():
				ok = false
				continue
			t.append(_tris(kit, li))
			for mi: MeshInstance3D in mis:
				if not is_equal_approx(mi.visibility_range_begin, float(KLib.LOD_RANGES[li])) \
						or not is_equal_approx(mi.visibility_range_end, float(KLib.LOD_RANGES[li + 1])):
					ok = false
		if not ok or t.size() < 3:
			bad.append("%s LOD 缺或可見距離不接續" % id)
			continue
		r1 = maxf(r1, float(t[1]) / t[0])
		r2 = maxf(r2, float(t[2]) / t[0])
		var a0 := _aabb(kit, 0)
		for li in [1, 2]:
			var a := _aabb(kit, li)
			var dd := maxf((a.position - a0.position).abs()[(a.position - a0.position).abs().max_axis_index()],
				(a.end - a0.end).abs()[(a.end - a0.end).abs().max_axis_index()])
			dab = maxf(dab, dd)
			if dd > 0.6:
				bad.append("%s LOD%d 外框差 %.2f" % [id, li, dd])
	_res("lod", bad.is_empty() and r1 <= 0.35 and r2 <= 0.10, "%d 棟 LOD0／1／2 齊全、可見距離 %s m 接續（margin %.0f）；LOD1／LOD0 最大 %.1f %%（≤ 35）、LOD2／LOD0 最大 %.1f %%（≤ 10）；LOD1／2 外框與 LOD0 差最大 %.2f m（≤ 0.6）%s" % [
		kits.size(), KLib.LOD_RANGES, KLib.LOD_MARGIN, r1 * 100, r2 * 100, dab, ("；" + _worst(bad)) if bad else ""])


# ─────────────────────────── 9 效能 ───────────────────────────

func _c_perf() -> void:
	var mx := 0
	var mx_id := ""
	var sum := 0
	var nodes := 0
	var mats_max := 0
	var meshes := {}
	for id: String in kits:
		var t := _tris(kits[id], 0)
		sum += t
		if t > mx:
			mx = t
			mx_id = id
		var ms := {}
		for li in 3:
			for mi: MeshInstance3D in _mis(kits[id], li):
				nodes += 1
				meshes[mi.mesh] = true
				for si in mi.mesh.get_surface_count():
					ms[mi.mesh.surface_get_material(si)] = true
		mats_max = maxi(mats_max, ms.size())
	var own_mb := 0.0
	for f in ["machiya_kit_atlas.png", "machiya_kit_emit.png"]:
		var t := load(DIR + "/" + f) as Texture2D
		own_mb += t.get_width() * t.get_height() * 1.0 * 1.333 / 1048576.0
	var mesh_kb := 0
	for f in DirAccess.get_files_at(DIR + "/mesh"):
		mesh_kb += FileAccess.get_file_as_bytes(DIR + "/mesh/" + f).size() / 1024
	_res("performance", mx <= CAP_LOD0 and mats_max <= MAX_MATS and own_mb <= 8.0,
		"§14.8「町家」LOD0 上限 %d：每棟實測最大 %d（%s，%.0f %%）、平均 %d；每棟材質 ≤ %d（實測 %d）、碰撞 1；Kit 專屬貼圖 VRAM 估算 %.1f MB（≤ 8）；全村 %d 棟 LOD0 合計 %d 三角面（同時可見受 LOD 距離 40 m 限制）、Kit MeshInstance %d 個、共用構件 mesh %d 個（磁碟 %d KB，只存一次）" % [
			CAP_LOD0, mx, mx_id, 100.0 * mx / CAP_LOD0, sum / maxi(1, kits.size()), MAX_MATS, mats_max, own_mb, kits.size(), sum,
			nodes, meshes.size(), mesh_kb])


# ─────────────────────────── gate.json ───────────────────────────

func _write_gate(part: String, keys: Array[String], extra := {}) -> void:
	var sha := FileAccess.get_sha256(ENTRY)
	var g: Dictionary = {}
	if FileAccess.file_exists(GATE):
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(GATE))
		if old is Dictionary and String(old.get("entry_sha256", "")) == sha:
			g = old
	g["asset"] = "machiya_kit"
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

## 代表棟：每個（類型, 屋根）取第一棟＋店先（有庇）的總二階／厨子二階各一
func _samples() -> Array:
	var out: Array = []
	var seen := {}
	for b: Dictionary in recs:
		var k := "%s_%s_%s" % [b["type"], b["roof"], "shop" if float(b["hisashi_m"]) > 0.0 else "res"]
		if seen.has(k):
			continue
		seen[k] = true
		out.append(b)
	return out


func _render(out: String) -> void:
	if DisplayServer.get_name() == "headless":
		_p("FAIL --render 需要 GPU 視窗（不能 --headless）")
		fails += 1
		return
	if out == "":
		out = ProjectSettings.globalize_path("user://machiya_kit_gate")
	DirAccess.make_dir_recursive_absolute(out)
	logger = GateLogger.new()
	OS.add_logger(logger)
	var samples := _samples()
	# ── F6：代表棟單獨場景（平地一排）
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
	var lib := KLib.load_lib()
	var x := 0.0
	var span := 0.0
	for b: Dictionary in samples:
		var rb := b.duplicate()
		rb["base_h"] = 0.0
		rb["ground_lo"] = 0.0
		var k := KLib.build(rb, lib, float(L["greybox"]["embed"]))
		k.position = Vector3(x + float(b["width_m"]) * 0.5, 0, 0)
		f6.add_child(k)
		x += float(b["width_m"]) + 1.2
	span = x
	var cam := Camera3D.new()
	f6.add_child(cam)
	cam.look_at_from_position(Vector3(span * 0.5, 7, span * 0.75), Vector3(span * 0.5, 3, 0))
	cam.current = true
	for i in 120:
		await process_frame
	var f6_png := out.path_join("machiya_kit_f6.png")
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
	for i in 60:
		await process_frame
	main.load_map("village_v2", "trail")
	for i in 90:
		await process_frame
	var vr: Node3D = main.map_root
	var baked := vr.find_children("Kit", "Node3D", true, false).size()
	await _setup(null, vr)
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var dbg: Node = v.get_node_or_null("Debug")
	if dbg:
		dbg.visible = false
	var player: CharacterBody3D = main.player
	player_rid = player.get_rid()
	var shot_lines: Array = []
	var shot_ok := true
	var walk_lines: Array = []
	var walk_ok := true
	var perf: Array = []
	var n := 0
	for b: Dictionary in samples:
		var body: StaticBody3D = bodies[b["id"]]
		var xf := body.global_transform
		var d := float(b["depth_m"])
		var center := xf * Vector3(0, float(b["eave_m"]) * 0.5, 0)
		var occ_faces := _occluders(body.global_position, String(b["id"]))
		# 候選鏡位（角度×距離）：取第一個「亮度標準差 > 0.05、目標在畫面內、相機→目標不穿過他棟／地標三角面、相機不在他棟網格內」的
		for s in [["front", [0.0, 10.0, -10.0], 7.0], ["front_l", [28.0, 18.0, 40.0], 10.0], ["front_r", [-28.0, -18.0, -40.0], 10.0]]:
			var img: Image
			var c3: Camera3D
			var sd := 0.0
			var in_frame := false
			var occ := ""
			var tries := 0
			var found := false
			for ang: float in s[1]:
				var dir := Vector3(sin(deg_to_rad(ang)), 0, cos(deg_to_rad(ang)))
				var want := _clear_dist(xf, d * 0.5, dir, float(s[2]), body.get_rid())
				for dist in [want, want - 2.0, 4.0]:
					if dist < 3.5 and tries > 0 and dist != 4.0:
						continue
					tries += 1
					var p := xf * (Vector3(0, 0, d * 0.5) + dir * maxf(3.5, dist))
					var gy := _terrain(p.x, p.z)
					player.global_position = Vector3(p.x, gy + 0.05, p.z)
					player.velocity = Vector3.ZERO
					var dd := Vector2(center.x - p.x, center.z - p.z)
					player.snap_yaw(atan2(-dd.x, -dd.y))
					for i in 75:
						await process_frame
					img = root.get_texture().get_image()
					c3 = root.get_viewport().get_camera_3d()
					sd = _img_std(img)
					in_frame = c3 != null and not c3.is_position_behind(center) \
						and Rect2(Vector2.ZERO, Vector2(img.get_size())).has_point(c3.unproject_position(center))
					occ = "" if c3 == null else _tri_block(occ_faces, c3.global_position, center)
					if sd > 0.05 and in_frame and occ == "":
						found = true
						break
				if found:
					break
			var png := out.path_join("machiya_kit_%s_%s.png" % [b["id"], s[0]])
			img.save_png(png)
			var ok := sd > 0.05 and in_frame and occ == ""
			shot_ok = shot_ok and ok
			n += 1
			shot_lines.append("%s%s（%s %s／%s，第 %d 個候選，亮度標準差 %.3f、%s、%s）" % ["" if ok else "✗ ", png.get_file(), b["type"], b["roof"],
				"店先" if float(b["hisashi_m"]) > 0.0 else "住宅", tries, sd, "在畫面內" if in_frame else "不在畫面內",
				"無遮擋" if occ == "" else "被 %s 擋" % occ])
			perf.append("%s_%s：%d 三角面／%d draw call" % [b["id"], s[0],
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
		var wk := await _walk(player, body, b)
		walk_ok = walk_ok and wk[0]
		walk_lines.append(wk[1])
	_res("player_screenshot", shot_ok and n >= 3 * samples.size(), "main.tscn 載 village_v2（Kit %s）、代表棟 %d 棟 × 3 張＝%d 張：%s" % [
		"已烘焙在場景 %d 棟" % baked if baked > 0 else "執行期以產生器同一段套用", samples.size(), n, "；".join(shot_lines)])
	if neg == "error":
		push_error("反向測試：刻意的錯誤")
	var f5_err := logger.errors.size() - e1
	var errs: Array = logger.errors.slice(0, 3)
	_res("f5_f6", f6_err == 0 and f5_err == 0 and walk_ok, "F6（代表 %d 棟單獨場景 120 幀）錯誤 %d；F5（main.tscn → village_v2、%d 張鏡位＋%d 棟實走）錯誤 %d、警告 %d；%s%s" % [
		samples.size(), f6_err, n, samples.size(), f5_err, logger.warnings.size(), "；".join(walk_lines),
		("；錯誤例：" + " | ".join(errs)) if errs else ""])
	OS.remove_logger(logger)
	_flush(RENDER_KEYS)
	if neg == "":
		_write_gate("render", RENDER_KEYS, {"render_info": {"f6_png": f6_png.get_file(), "perf": perf,
			"warnings": logger.warnings.slice(0, 10), "renderer": RenderingServer.get_current_rendering_method()}})
	_p("F6 截圖 %s；效能（畫面內總量）：%s" % [f6_png, "；".join(perf)])


## 目標 40 m 內的他棟 Kit LOD0＋地標 Hero LOD0 三角面（世界座標），[名, AABB, faces]
func _occluders(c: Vector3, self_id: String) -> Array:
	var out: Array = []
	var groups: Array = []
	for id: String in kits:
		if id != self_id and (bodies[id] as Node3D).global_position.distance_to(c) < 40.0:
			groups.append([id, (kits[id] as Node3D).get_node("LOD0")])
	for lm in v.get_node("Landmarks").get_children():
		for h in lm.find_children("LOD0", "Node3D", true, false):
			if (h as Node3D).global_position.distance_to(c) < 60.0:
				groups.append([String(lm.name), h])
	for g in groups:
		var faces := PackedVector3Array()
		var box := AABB()
		var first := true
		for mi in (g[1] as Node).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var gx := m.global_transform
			for q in m.mesh.get_faces():
				faces.append(gx * q)
			var ab: AABB = gx * m.mesh.get_aabb()
			box = ab if first else box.merge(ab)
			first = false
		if not faces.is_empty():
			out.append([g[0], box, faces])
	return out


## 相機→目標線段穿過哪一棟的三角面（"" ＝無遮擋）；相機在他棟網格裡也會在這裡被抓到（線段必穿其殼）
func _tri_block(occ: Array, from: Vector3, to: Vector3) -> String:
	for o in occ:
		if not (o[1] as AABB).grow(0.05).intersects_segment(from, to):
			continue
		var f: PackedVector3Array = o[2]
		for t in range(0, f.size(), 3):
			if Geometry3D.segment_intersects_triangle(from, to, f[t], f[t + 1], f[t + 2]) != null:
				return String(o[0])
	return ""


## 斜向鏡位在窄街上會越過對街：從正面 1 m 外沿視線打射線（排除本棟、玩家、地形），距離縮到擋點 −8 m（SpringArm 5 m＋屋簷 3 m），下限 5 m
func _clear_dist(xf: Transform3D, zf: float, dir: Vector3, want: float, self_rid: RID) -> float:
	var a := xf * (Vector3(0, 1.6, zf + 1.0))
	var b := xf * (Vector3(0, 1.6, zf + 1.0) + dir * (want + 5.0))
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = [self_rid, player_rid, terrain_rid]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return want
	return clampf(a.distance_to(hit["position"]) + 1.0 - 8.0, 5.0, want)


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


## 實走：正面 3 m 外朝台基走 4 秒 → 停在牆外、不浮空
func _walk(player: CharacterBody3D, body: Node3D, b: Dictionary) -> Array:
	var xf := body.global_transform
	var d := float(b["depth_m"])
	var w := float(b["width_m"])
	var start := xf * Vector3(0.9, 0, d * 0.5 + 3.0)
	var goal := xf * Vector3(0.9, 0, 0)
	player.global_position = Vector3(start.x, _terrain(start.x, start.z) + 0.05, start.z)
	player.velocity = Vector3.ZERO
	for i in 20:
		await physics_frame
	var max_gap := 0.0
	var t0 := Time.get_ticks_msec()
	Input.action_press("move_forward")
	for f in 60 * 8:
		var p := player.global_position
		var dd := Vector2(goal.x - p.x, goal.z - p.z)
		if f % 6 == 0:
			player.snap_yaw(atan2(-dd.x, -dd.y))
		await physics_frame
		if f % 20 == 0:
			var g := _terrain(p.x, p.z)
			if not is_nan(g):
				max_gap = maxf(max_gap, absf(player.global_position.y - g))
		if Time.get_ticks_msec() - t0 > 4000:
			break
	Input.action_release("move_forward")
	for i in 6:
		await physics_frame
	var lp := xf.affine_inverse() * player.global_position
	var inside := absf(lp.x) < w * 0.5 - 0.05 and absf(lp.z) < d * 0.5 - 0.05
	var ok := not inside and max_gap <= 0.35
	return [ok, "%s 實走：正面 3 m 外朝台基走 4 秒，停在局部 z %.2f（牆面 %.2f，%s）、最大離地 %.2f m" % [
		b["id"], lp.z, d * 0.5, "✗ 穿進建築" if inside else "被擋在外", max_gap]]
