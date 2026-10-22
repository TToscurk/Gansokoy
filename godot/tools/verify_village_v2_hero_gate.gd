extends SceneTree
## 人間之里 V2：P5 Hero／地標資產 Asset Gate（11 項；總計畫 P5、規劃 §14）。
##
##   1–9 項（headless，寫 res://assets/village_v2/<id>/gate.json 的 headless 部分）：
##     godot --headless --path godot --script res://tools/verify_village_v2_hero_gate.gd -- --asset=<id>
##   10–11 項（玩家視角截圖、F5/F6；需要 GPU 視窗，寫 gate.json 的 render 部分）：
##     godot --path godot --script res://tools/verify_village_v2_hero_gate.gd -- --asset=<id> --render --out=<png 目錄>
##   共享材質庫（4 項：授權、2K、VRAM 壓縮、.tres 有效）：-- --matlib
##   回歸（唯讀）：-- --all        registry v2_assets 每件重驗 1–9 項（場景裡已烘焙的 Hero）
##   反向測試（唯讀）：-- --asset=<id> --neg=<scale|float|greybox|trimesh|material|lod|parcel|winding|error>
##
## 1 尺寸     實測 LOD0（射線量牆、屋脊、簷、柱、淨空）對 P4 灰盒紀錄／P0 地標規格；人物比例（門、通行淨空）。
## 2 地塊     地面接觸件在自己的地塊內、不壓其他地塊、不壓道路；鳥居＝台座在路面外、道路斷面落在柱間淨寬內。
## 3 接地     每個接地件底面低於地形最低點、埋深不超過容許值；灰盒已退場（不可見、碰撞停用），
##            接地件正下方第一個碰撞體是地形（不是灰盒）＝禁止墊在灰盒上；入口段差。
## 4 材質     每個 surface 的材質都是 asset.json 登記的共享庫／Hero atlas；貼圖 ≤ 2K、VRAM 壓縮、albedo_k 一致。
## 5 幾何     面數 ≤ §14.8 預算；無退化面／NaN；有法線、UV、切線；三角形繞向與法線一致（不會被背面剔除吃掉）。
## 6 Pivot/Scale  縮放 1、LOD 節點 identity；原點＝灰盒原點（footprint 中心＋最高地面）或 P0 地標原點；正面朝向。
## 7 碰撞     只有 box／cylinder／convex（禁止 trimesh）、數量 ≤ 8；膠囊（r 0.3、h 1.7）入口站得住、進不去台基、
##            步行帶走得過；三個高度的周邊射線：可見網格不能比碰撞面突出 > 0.15 m（玩家不會穿進模型）；步行帶頭頂淨空。
## 8 LOD      3 級、距離首尾相接、面數遞減且 ≤ 35 %／10 %、外形 AABB 一致、最後一級可見距離涵蓋整張圖。
## 9 效能     §14.8 預算表（不信資產自報）、surface 數、碰撞數、貼圖 VRAM 估算。
## 10 玩家視角截圖  main.tscn 實際載 village_v2、玩家鏡頭；截圖非空白、資產在畫面內、鏡頭到資產無遮擋。
## 11 F5/F6   F6＝資產單獨場景跑 120 幀；F5＝main.tscn 載圖＋玩家實走撞建築／穿鳥居；全程 Logger 錯誤 0。
## 截圖的「好不好看」不在 gate 範圍：視覺只到 ART_REVIEW，ART_APPROVED 只有使用者能給。

const HLib := preload("res://tools/village_v2_hero_lib.gd")
const PLib := preload("res://tools/village_v2_parcel_lib.gd")
const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const PARCELS := "res://maps/village_v2/gen/parcels.json"
const GREYBOX := "res://maps/village_v2/gen/greybox.json"
const MATLIB := "res://assets/village_v2/_matlib/matlib.json"
const V2_DIR := "res://assets/village_v2/"
const HEADLESS_KEYS: Array[String] = ["size", "parcel_fit", "grounding", "materials", "geometry", "pivot_scale",
	"collision", "lod", "performance"]
const RENDER_KEYS: Array[String] = ["player_screenshot", "f5_f6"]
const MATLIB_KEYS: Array[String] = ["license", "texture_size", "vram_compressed", "tres_valid"]
## §14.8（使用者 2026-09-24 核准）LOD0 上限；gate 以此為準，不信 asset.json 自報
const BUDGET_LOD0 := {"鈴奈庵": 60000, "霧雨店": 60000, "鯢吞亭": 100000, "寺子屋": 100000, "龍神像": 100000,
	"稗田邸": 150000, "鳥居": 5000, "火見櫓": 20000, "水車": 15000, "町家": 25000,
	"社殿": 60000, "水渠橋": 15000, "龍神橋": 30000}   # 橋：使用者 2026-09-28 核准（P7 R2）
const MAX_MATS := 5
const MAX_SHAPES := 8
const TEX_MAX := 2048
const CAP_R := 0.3
const CAP_H := 1.7
const POKE_TOL := 0.15      # 可見網格比碰撞面突出的容許（m）
const CELL := 0.5


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
var R := {}                 # key → {result, detail}
var S: Dictionary           # asset.json
var gs: Dictionary          # asset.json gate_spec
var L: Dictionary
var v: Node3D               # VillageV2 根
var hero: Node3D
var anchor: Node3D
var hero_rid: RID
var space: PhysicsDirectSpaceState3D
var terrain_rid: RID
var f0 := PackedVector3Array()   # LOD0 三角面（hero 局部）
var cells := {}                  # Vector2i → PackedInt32Array（f0 三角形起始索引）
var col_x := {}                  # i → PackedInt32Array（沿 z 射線用）
var col_z := {}                  # j → PackedInt32Array（沿 x 射線用）
var neg := ""
var logger: GateLogger


func _init() -> void:
	_run.call_deferred()


func _p(s: String) -> void:
	print("[HERO] " + s)


func _res(key: String, ok: bool, detail: String) -> void:
	var prev: Dictionary = R.get(key, {"result": "PASS", "detail": []})
	if not ok:
		prev["result"] = "FAIL"
	(prev["detail"] as Array).append(("" if ok else "✗ ") + detail)
	R[key] = prev


func _flush(keys: Array[String], label: String) -> void:
	for k in keys:
		if not R.has(k):
			_res(k, false, "沒有執行")
		var e: Dictionary = R[k]
		print("[HERO] %s %s %s：%s" % [e["result"], label, k, "；".join(e["detail"])])
		if e["result"] != "PASS":
			fails += 1


func _run() -> void:
	var id := ""
	var render := false
	var out := ""
	var all := false
	var matlib := false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--asset="):
			id = a.trim_prefix("--asset=")
		elif a == "--render":
			render = true
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--neg="):
			neg = a.trim_prefix("--neg=")
		elif a == "--all":
			all = true
		elif a == "--matlib":
			matlib = true
	L = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if matlib:
		_matlib()
	elif all:
		await _all()
	elif id == "":
		_p("FAIL 缺 -- --asset=<id>／--matlib／--all")
		fails += 1
	elif render:
		await _render(id, out)
	else:
		await _headless(id, neg == "")
	_p("結果：%d 項失敗" % fails)
	quit(fails)


# ─────────────────────────── 共用 ───────────────────────────

func _load_spec(id: String) -> bool:
	var s: Variant = JSON.parse_string(FileAccess.get_file_as_string(V2_DIR + id + "/asset.json"))
	if not s is Dictionary:
		_p("FAIL 讀不到 %s%s/asset.json" % [V2_DIR, id])
		fails += 1
		return false
	S = s
	gs = HLib.instances(S)[0]   # 單一放置＝gate_spec 本身（加 landmark 鍵）；多點（instances）＝第一筆
	return true


func _gate_path(id: String) -> String:
	return V2_DIR + id + "/gate.json"


func _write_gate(id: String, part: String, keys: Array[String], entry: String, extra := {}) -> void:
	var path := _gate_path(id)
	var sha := FileAccess.get_sha256(entry)
	var g: Dictionary = {}
	if FileAccess.file_exists(path):
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if old is Dictionary and String(old.get("entry_sha256", "")) == sha:
			g = old   # 同一版 .scn：保留另一部分（headless／render）的結果
	g["asset"] = id
	g["entry"] = entry
	g["entry_sha256"] = sha
	g["godot"] = Engine.get_version_info()["string"]
	var checks: Dictionary = g.get("checks", {})
	for k in keys:
		var e: Dictionary = R[k]
		checks[k] = {"result": e["result"], "detail": e["detail"], "part": part,
			"date": Time.get_datetime_string_from_system()}
	g["checks"] = checks
	for k in extra:
		g[k] = extra[k]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(g, " ", false) + "\n")
	f.close()
	_p("寫入 %s（%s）" % [path, part])


func _xf() -> Transform3D:
	return hero.global_transform


## 建築量體：P4 灰盒 body（greybox 放置）或 P0 地標 building（anchor 放置的建築，R3 寺子屋起）。
## 回傳 {w, d, zf（正面牆 z）, plinth}；鳥居等非建築回傳 {}。
func _bld() -> Dictionary:
	if gs.has("body"):
		var B: Dictionary = gs["body"]
		return {"w": float(B["w"]), "d": float(B["d"]), "zf": float(B["d"]) * 0.5, "plinth": float(B["plinth"])}
	if gs.has("building"):
		# zf＝入口面（玄關前緣）；主屋牆仍以原點為中心（w × d）
		var B2: Dictionary = gs["building"]
		return {"w": float(B2["w"]), "d": float(B2["d"]), "zf": float(B2.get("zf", float(B2["d"]) * 0.5)),
			"plinth": float(B2["plinth"])}
	return {}


func _to_local(p: Vector3) -> Vector3:
	return hero.global_transform.affine_inverse() * p


## 世界 XZ → 第一個非 hero 的碰撞面高度（玩家實際站的面）；exclude_terrain_only=true 只認地形
var player_rid := RID()   # render 模式：地面射線排除玩家膠囊（否則量到膠囊頂）

## 地面＝玩家會站上的靜態環境（2026-10-22）。玩家 CharacterBody3D 用預設遮罩 layer 1（村莊環境碰撞全在 layer 1）→ ENV_MASK；
## 會動的物體不是地面：NPC 身體（AnimatableBody3D／CharacterBody3D）、布料代理、RigidBody3D。
## 阿求袖子模擬 floor_collision 在 layer 20 放 WorldBoundaryShape3D（無限平面，y＝NPC 根高 1.69）→ 全村地面被量成 1.69，
## 入口段差／頭頂淨空 12 FAIL（實測：只跳過該平面 → 0 FAIL）。
const ENV_MASK := 1


func _is_env(o: Object) -> bool:
	return not (o is AnimatableBody3D or o is CharacterBody3D or o is RigidBody3D or o is PhysicalBone3D)


func _ground(x: float, z: float, terrain_only := false) -> float:
	var ex: Array[RID] = [hero_rid]
	if player_rid.is_valid():
		ex.append(player_rid)
	for i in 16:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -80.0, z), ENV_MASK)
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return NAN
		if not _is_env(hit["collider"]):
			ex.append(hit["rid"])
			continue
		if not terrain_only or hit["rid"] == terrain_rid:
			return float(hit["position"].y)
		ex.append(hit["rid"])
	return NAN


func _first_collider(x: float, z: float) -> Object:
	var ex: Array[RID] = [hero_rid]
	for i in 16:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -80.0, z), ENV_MASK)
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return null
		if _is_env(hit["collider"]):
			return hit["collider"]
		ex.append(hit["rid"])
	return null


## 世界射線只打 hero 碰撞；回傳距離（打不到 INF）
func _col_dist(from: Vector3, to: Vector3) -> float:
	var ex: Array[RID] = []
	for i in 16:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return INF
		if hit["rid"] == hero_rid:
			return from.distance_to(hit["position"])
		ex.append(hit["rid"])
	return INF


func _capsule_hits_hero(p: Vector3) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = CAP_R
	cap.height = CAP_H
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, CAP_H * 0.5 + 0.03, 0))
	for h in space.intersect_shape(q, 32):
		if h["rid"] == hero_rid:
			return true
	return false


func _index_faces() -> void:
	f0 = _lod_faces(0)
	cells.clear()
	col_x.clear()
	col_z.clear()
	var cx := {}
	var cz := {}
	for t in range(0, f0.size(), 3):
		var a := f0[t]
		var b := f0[t + 1]
		var c := f0[t + 2]
		for i in range(floori(minf(a.x, minf(b.x, c.x)) / CELL), floori(maxf(a.x, maxf(b.x, c.x)) / CELL) + 1):
			for j in range(floori(minf(a.z, minf(b.z, c.z)) / CELL), floori(maxf(a.z, maxf(b.z, c.z)) / CELL) + 1):
				var k := Vector2i(i, j)
				if not cells.has(k):
					cells[k] = []   # Array（參考型別）；PackedInt32Array 是值型別，取出來 append 不會寫回
				(cells[k] as Array).append(t)
			if not cx.has(i):
				cx[i] = {}
			(cx[i] as Dictionary)[t] = true
		for j in range(floori(minf(a.z, minf(b.z, c.z)) / CELL), floori(maxf(a.z, maxf(b.z, c.z)) / CELL) + 1):
			if not cz.has(j):
				cz[j] = {}
			(cz[j] as Dictionary)[t] = true
	for i in cx:
		col_x[i] = PackedInt32Array((cx[i] as Dictionary).keys())
	for j in cz:
		col_z[j] = PackedInt32Array((cz[j] as Dictionary).keys())


func _tris_along_z(x: float) -> PackedInt32Array:
	var i := floori(x / CELL)
	var out: PackedInt32Array = col_x.get(i, PackedInt32Array()).duplicate()
	if absf(x - i * CELL) < 0.01:
		out.append_array(col_x.get(i - 1, PackedInt32Array()))
	return out


func _tris_along_x(z: float) -> PackedInt32Array:
	var j := floori(z / CELL)
	var out: PackedInt32Array = col_z.get(j, PackedInt32Array()).duplicate()
	if absf(z - j * CELL) < 0.01:
		out.append_array(col_z.get(j - 1, PackedInt32Array()))
	return out


func _tris_at(x: float, z: float) -> PackedInt32Array:
	return PackedInt32Array(cells.get(Vector2i(floori(x / CELL), floori(z / CELL)), []))


## 每一級 LOD 的 MeshInstance3D：本體 LOD<li>＋轉動部件（asset.json rotors，R4 水車起）底下的 LOD<li>
func _lod_mis(li: int, h: Node3D = null) -> Array:
	var top := h if h != null else hero
	var out: Array = []
	var mi := top.get_node_or_null("LOD%d" % li)
	if mi != null:
		out.append(mi)
	for rt: Dictionary in S.get("rotors", []):
		var r := top.get_node_or_null("%s/LOD%d" % [rt["name"], li])
		if r != null:
			out.append(r)
	return out


## n 相對 top 的 transform；轉動部件一律取靜止姿勢（只留 yaw、位置），量測不隨動畫相位變
func _rel(n: Node3D, top: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != top:
		var c3 := c as Node3D
		var lt := c3.transform
		if c3.has_meta("rotor"):
			lt = Transform3D(Basis(Vector3.UP, c3.rotation.y), c3.position)
		t = lt * t
		c = c.get_parent()
	return t


## LOD<li> 三角面（top 局部）；沒有轉動部件時＝LOD<li>.mesh.get_faces()（R1–R3 行為不變）
func _lod_faces(li: int, h: Node3D = null) -> PackedVector3Array:
	var top := h if h != null else hero
	var out := PackedVector3Array()
	for mi: MeshInstance3D in _lod_mis(li, top):
		var xf := _rel(mi, top)
		var fs := mi.mesh.get_faces()
		if xf.is_equal_approx(Transform3D.IDENTITY):
			out.append_array(fs)
		else:
			for p in fs:
				out.append(xf * p)
	return out


func _lod_aabb(li: int, h: Node3D = null) -> AABB:
	var fs := _lod_faces(li, h)
	var ab := AABB(fs[0], Vector3.ZERO)
	for p in fs:
		ab = ab.expand(p)
	return ab


## 水面高度：水面網格（P2 MainRiver／Canal）離 xz 最近的頂點 y
func _water_y(name: String, x: float, z: float) -> float:
	var best := INF
	var by := NAN
	for mi in v.find_children(name, "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var gx := m.global_transform
		for p: Vector3 in m.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var w := gx * p
			var d := Vector2(w.x - x, w.z - z).length()
			if d < best:
				best = d
				by = w.y
	return by


## 世界 xz 最近的水道中心線方向（layout water；name＝MainRiver／Canal）
func _water_dir(name: String, x: float, z: float) -> Vector2:
	var pts: Array = L["water"][name]["pts"]
	var best := INF
	var dir := Vector2.ZERO
	for i in pts.size() - 1:
		var a := Vector2(float(pts[i][0]), float(pts[i][1]))
		var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
		var q := Geometry2D.get_closest_point_to_segment(Vector2(x, z), a, b)
		var d := q.distance_to(Vector2(x, z))
		if d < best:
			best = d
			dir = (b - a).normalized()
	return dir


## hero 局部線段對 LOD0 的第一個交點距離（INF＝沒打到）
func _vis_dist(from: Vector3, to: Vector3, tris: PackedInt32Array) -> float:
	var best := INF
	for t in tris:
		var hit: Variant = Geometry3D.segment_intersects_triangle(from, to, f0[t], f0[t + 1], f0[t + 2])
		if hit != null:
			best = minf(best, from.distance_to(hit))
	return best


func _world_poly(rect: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for c in [[rect[0], rect[1]], [rect[2], rect[1]], [rect[2], rect[3]], [rect[0], rect[3]]]:
		var w := _xf() * Vector3(float(c[0]), 0.0, float(c[1]))
		out.append(Vector2(w.x, w.z))
	return out


func _poly_area(polys: Array) -> float:
	var a := 0.0
	for p in polys:
		a += PLib.area(p)
	return a


# ─────────────────────────── headless 1–9 ───────────────────────────

func _headless(id: String, write: bool) -> void:
	if not _load_spec(id):
		return
	var scn := load(String(S["scene"])) as PackedScene
	# gate_spec.instances（R4 水車起）：同一件資產的每個放置點各跑一次 1–9 項，結果併在同一份 gate.json
	var gss := HLib.instances(S)
	for gi in gss.size():
		gs = gss[gi]
		v = (load(SCENE) as PackedScene).instantiate()
		root.add_child(v)
		hero = HLib.place(v, S, scn, false, gi)
		if hero == null:
			_p("FAIL 放置失敗")
			fails += 1
			return
		anchor = hero.get_parent() as Node3D
		if neg != "":
			_apply_neg()
		await physics_frame
		await physics_frame
		space = v.get_world_3d().direct_space_state
		terrain_rid = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
		hero_rid = (hero.get_node("Collision") as CollisionObject3D).get_rid()
		_index_faces()
		_p("%s：%s 放在 %s（%s），原點 %s、LOD0 %d 三角面%s" % [id, S["scene"], gs["anchor"], gs["placement"],
			hero.global_position, f0.size() / 3, ("、反向測試 --neg=" + neg) if neg != "" else ""])
		if gss.size() > 1:
			for k in HEADLESS_KEYS:
				_res(k, true, "【%s】" % String(gs["anchor"]).get_file())
		_c_size()
		_c_parcel()
		_c_ground()
		_c_materials()
		_c_geometry()
		_c_pivot()
		_c_collision()
		_c_lod()
		_c_perf()
		v.queue_free()
		await process_frame
	_flush(HEADLESS_KEYS, id)
	if write:
		_write_gate(id, "headless", HEADLESS_KEYS, String(S["scene"]))


func _apply_neg() -> void:
	var g0: Node = anchor.get_node_or_null(String(gs["replaces"])) if String(gs.get("replaces", "")) != "" else null
	match neg:
		"scale":
			hero.scale = Vector3.ONE * 1.1
		"float":
			hero.position.y += 0.3
		"parcel":
			# 町家地塊前緣只留 1–2 m → 3 m 就出界；地標地塊（寺子屋 yard 4 m、前庭道具到地塊邊 3.9 m）要 8 m 才真的出界
			# aux 附屬棟（body 放置）：正面前有 2.5–9 m 院子、背面離地塊線只有 margin 0.45 → 往後推 3 m 才真的出界
			if String(gs["placement"]) == "body":
				hero.position -= hero.basis.z * 3.0
			elif gs.has("bridge"):
				hero.position += hero.basis.x * 3.0   # 橋：往側面推 3 m（道路斷面跑出欄杆內淨寬）
			elif gs.has("water_ref"):
				hero.position -= hero.basis.x * 3.0   # 水車：往岸上推 3 m（輪子離開水道）
			else:
				hero.position += hero.basis.z * (8.0 if gs.has("building") else 3.0)
		"greybox":
			if String(gs["placement"]) in ["body", "bridge"]:
				# aux／橋：灰盒就是 anchor 本身 → 把它的網格與碰撞恢復，資產墊高 0.4 m
				for c in anchor.find_children("*", "", true, false):
					if hero.is_ancestor_of(c) or c == hero:
						continue
					if c is MeshInstance3D:
						(c as MeshInstance3D).visible = true
					elif c is CollisionShape3D:
						(c as CollisionShape3D).disabled = false
				(anchor as CollisionObject3D).collision_layer = 1
				hero.position.y += 0.4
			elif g0 == null:
				# 產生器已不建 placeholder（anchor 型）：另建一個 1 × 10 × 1 m 有碰撞的灰盒柱，模擬「墊在灰盒上」
				var sb := StaticBody3D.new()
				sb.name = String(gs["replaces"]) if String(gs.get("replaces", "")) != "" else "NegGreybox"
				var gm := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(1.0, 10.0, 1.0)
				gm.mesh = bm
				gm.position.y = 5.0
				sb.add_child(gm)
				var gc := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = bm.size
				gc.shape = bs
				gc.position.y = 5.0
				sb.add_child(gc)
				anchor.add_child(sb)
				hero.position.y += 0.4
			else:
				(g0 as Node3D).visible = true
				for c in g0.find_children("*", "", true, false):
					if c is MeshInstance3D:
						(c as MeshInstance3D).visible = true
					elif c is CollisionShape3D:
						(c as CollisionShape3D).disabled = false
				if g0 is CollisionObject3D:
					(g0 as CollisionObject3D).collision_layer = 1
				hero.position.y += 0.4   # 墊在灰盒台基上
		"trimesh":
			var cs := CollisionShape3D.new()
			cs.shape = (hero.get_node("LOD0") as MeshInstance3D).mesh.create_trimesh_shape()
			hero.get_node("Collision").add_child(cs)
		"material":
			var mi := hero.get_node("LOD0") as MeshInstance3D
			var m2 := mi.mesh.duplicate() as ArrayMesh
			m2.surface_set_material(0, StandardMaterial3D.new())
			mi.mesh = m2
		"lod":
			(hero.get_node("LOD1") as MeshInstance3D).visibility_range_begin += 15.0
		"wallgap":
			# 稗田邸圍牆：關掉東牆碰撞 → 宅邸邊界封閉（碰撞缺口）必須 FAIL
			for c in hero.get_node("Collision").find_children("*", "CollisionShape3D", true, false):
				if String(c.name).ends_with("E") and not String(c.name).contains("S_"):
					(c as CollisionShape3D).disabled = true
		"deckgap":
			# P7 R2 橋：關掉橋面碰撞 → 橋面走不上去（碰撞＝可見橋面、膠囊站得住）必須 FAIL
			var dk := hero.get_node_or_null("Collision/Deck") as CollisionShape3D
			if dk != null:
				dk.disabled = true
		"winding":
			var mi := hero.get_node("LOD0") as MeshInstance3D
			var src := mi.mesh as ArrayMesh
			var m2 := ArrayMesh.new()
			for si in src.get_surface_count():
				var arr := src.surface_get_arrays(si)
				if si == 0:
					var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
					for t in range(0, idx.size(), 3):
						var tmp := idx[t + 1]
						idx[t + 1] = idx[t + 2]
						idx[t + 2] = tmp
					arr[Mesh.ARRAY_INDEX] = idx
				m2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				m2.surface_set_material(si, src.surface_get_material(si))
			mi.mesh = m2
	_p("反向測試：已套用 %s" % neg)


## 1 尺寸
func _c_size() -> void:
	var ab: AABB = _lod_aabb(0)
	var sz: Dictionary = gs["size"]
	var sc := hero.global_transform.basis.get_scale()
	var xh := maxf(absf(ab.position.x), absf(ab.end.x)) * sc.x
	var top := ab.end.y * sc.y
	var ok := xh <= float(sz["x_half_max"]) + 0.005 and ab.position.z * sc.z >= float(sz["z_min"]) - 0.005 \
		and ab.end.z * sc.z <= float(sz["z_max"]) + 0.005 and top >= float(sz["top"][0]) - 0.005 \
		and top <= float(sz["top"][1]) + 0.005 and absf(ab.position.y * sc.y - float(sz["bottom"])) <= 0.02
	_res("size", ok, "LOD0 外框 x ±%.2f（≤ %.2f）、z %.2f～%.2f（容許 %.2f～%.2f）、頂 %.2f（%.2f～%.2f）、底 %.2f（%.2f）" % [
		xh, sz["x_half_max"], ab.position.z * sc.z, ab.end.z * sc.z, sz["z_min"], sz["z_max"], top,
		sz["top"][0], sz["top"][1], ab.position.y * sc.y, sz["bottom"]])
	# 射線量測（hero 局部；乘上實際縮放換成公尺）
	if gs.has("body"):
		var B: Dictionary = gs["body"]
		var rec := _gb_record()
		var spec_ok := not rec.is_empty() and absf(float(B["w"]) - float(rec["width_m"])) <= 0.02 \
			and absf(float(B["d"]) - float(rec["depth_m"])) <= 0.02 and absf(float(B["eave"]) - float(rec["eave_m"])) <= 0.02 \
			and absf(float(B["ridge"]) - float(rec["ridge_m"])) <= 0.02 and absf(float(B["plinth"]) - float(rec["plinth_m"])) <= 0.02
		_res("size", spec_ok, "規格＝P4 灰盒 %s：面寬 %.2f／縱深 %.2f／簷 %.2f／屋脊 %.2f／台基 %.2f m" % [
			gs["p4_id"], rec.get("width_m", -1), rec.get("depth_m", -1), rec.get("eave_m", -1), rec.get("ridge_m", -1),
			rec.get("plinth_m", -1)])
		# 射線位置：預設是町家尺寸 Hero（R1–R6）；小建築（P6 aux 納屋／土藏）由 body.probe 指定，避開門、窗、庇
		var pr: Dictionary = B.get("probe", {})
		var y := float(pr.get("y", 1.537))
		var yf := float(pr.get("yf", 3.313))
		var pz := float(pr.get("z", 0.313))
		var pbx := float(pr.get("xb", -1.037))
		var pfx := float(pr.get("xf", -4.037))
		var xr := 20.0 - _vis_dist(Vector3(20, y, pz), Vector3(-20, y, pz), _tris_along_x(pz))
		var xl := -20.0 + _vis_dist(Vector3(-20, y, pz), Vector3(20, y, pz), _tris_along_x(pz))
		var zb := -20.0 + _vis_dist(Vector3(pbx, y, -20), Vector3(pbx, y, 20), _tris_along_z(pbx))
		var zfr := 20.0 - _vis_dist(Vector3(pfx, yf, 20), Vector3(pfx, yf, -20), _tris_along_z(pfx))
		var ridge := 30.0 - _vis_dist(Vector3(0.137, 30, 0.043), Vector3(0.137, -5, 0.043), _tris_at(0.137, 0.043))
		# 簷口：平入＝背面（x pfx、z −ze）；妻入（body.roof＝tsuma）＝右側（x ＋ze、z pz）
		var tsuma := String(B.get("roof", "hira")) == "tsuma"
		var ze := (float(B["w"]) if tsuma else float(B["d"])) * 0.5 + float(rec.get("ov_eave_m", 0.45)) - 0.05
		var ex := ze if tsuma else pfx
		var ez := pz if tsuma else -ze
		var eave := 30.0 - _vis_dist(Vector3(ex, 30, ez), Vector3(ex, -5, ez), _tris_at(ex, ez))
		var w := (xr - xl) * sc.x
		var d := (zfr - zb) * sc.z
		var ee := eave * sc.y
		var rr := ridge * sc.y
		var ok2 := absf(w - float(rec["width_m"])) <= 0.10 and absf(d - float(rec["depth_m"])) <= 0.10 \
			and rr >= float(sz["top"][0]) - 0.1 and rr <= float(sz["top"][1]) + 0.005 \
			and absf(ee - float(rec["eave_edge_m"])) <= 0.15
		_res("size", ok2, "射線實測：牆面寬 %.2f（P4 %.2f）、牆縱深 %.2f（P4 %.2f）、屋脊頂 %.2f（屋脊 %.2f）、%s簷口 %.2f（P4 簷口 %.2f）m" % [
			w, rec["width_m"], d, rec["depth_m"], rr, rec["ridge_m"], "側面" if tsuma else "背面", ee, rec["eave_edge_m"]])
	if gs.has("building"):
		# anchor 放置的建築（沒有 P4 灰盒）：規格對 P0 地標量體（size＝寬×高×深，只能小於等於）與自身 building 規格
		var Bb: Dictionary = gs["building"]
		var lm := _lm(_lm_id())
		var ls: Array = lm.get("size", [0, 0, 0])
		var pr: Dictionary = Bb["probe"]
		var py := float(pr["y"])
		var xr := 30.0 - _vis_dist(Vector3(30, py, float(pr["z"])), Vector3(-30, py, float(pr["z"])), _tris_along_x(float(pr["z"])))
		var xl := -30.0 + _vis_dist(Vector3(-30, py, float(pr["z"])), Vector3(30, py, float(pr["z"])), _tris_along_x(float(pr["z"])))
		var zb := -30.0 + _vis_dist(Vector3(float(pr["x"]), py, -30), Vector3(float(pr["x"]), py, 30), _tris_along_z(float(pr["x"])))
		var zfr := 30.0 - _vis_dist(Vector3(float(pr["x"]), py, 30), Vector3(float(pr["x"]), py, -30), _tris_along_z(float(pr["x"])))
		var ridge := 30.0 - _vis_dist(Vector3(0.137, 30, 0.043), Vector3(0.137, -5, 0.043), _tris_at(0.137, 0.043))
		var ze := float(Bb["d"]) * 0.5 + float(Bb["ov_eave"]) - 0.05
		var eave := 30.0 - _vis_dist(Vector3(float(pr["x"]), 30, -ze), Vector3(float(pr["x"]), -5, -ze), _tris_at(float(pr["x"]), -ze))
		var w := (xr - xl) * sc.x
		var d := (zfr - zb) * sc.z
		var gx := float(pr["gx"])
		var zg := 30.0 - _vis_dist(Vector3(gx, py, 30), Vector3(gx, py, -30), _tris_along_z(gx))
		var zgb := -30.0 + _vis_dist(Vector3(gx, py, -30), Vector3(gx, py, 30), _tris_along_z(gx))
		var d_tot := (zg - zgb) * sc.z
		var top_all := ab.end.y * sc.y
		var p0_ok := ls.size() == 3 and w <= float(ls[0]) + 0.005 and d_tot <= float(ls[2]) + 0.005 \
			and top_all <= float(ls[1]) + 0.005
		_res("size", p0_ok, "P0 地標量體 %s（寬×高×深）：主屋牆寬 %.2f、含玄關總深 %.2f（射線 x %.2f）、最高點 %.2f m，都不超過" % [
			ls, w, d_tot, gx, top_all])
		var ok3 := absf(w - float(Bb["w"])) <= 0.10 and absf(d - float(Bb["d"])) <= 0.10 \
			and absf(ridge * sc.y - float(Bb["ridge"])) <= 0.35 and absf(eave * sc.y - float(Bb["eave_edge"])) <= 0.15
		_res("size", ok3, "射線實測：牆面寬 %.2f（規格 %.2f）、牆縱深 %.2f（%.2f）、屋脊頂 %.2f（棟 %.2f）、背面簷口 %.2f（%.2f）m" % [
			w, Bb["w"], d, Bb["d"], ridge * sc.y, Bb["ridge"], eave * sc.y, Bb["eave_edge"]])
	if gs.has("door_clear"):
		var dc: Dictionary = gs["door_clear"]
		var zf := float(_bld()["zf"])
		var zr := zf - 0.031
		var sill := 1.213 - _vis_dist(Vector3(0.037, 1.213, zr), Vector3(0.037, -1, zr), _tris_at(0.037, zr))
		var lintel := 1.213 + _vis_dist(Vector3(0.037, 1.213, zr), Vector3(0.037, 6, zr), _tris_at(0.037, zr))
		var hw_r := _vis_dist(Vector3(0.037, 1.213, zr), Vector3(4, 1.213, zr), _tris_along_x(zr))
		var hw_l := _vis_dist(Vector3(0.037, 1.213, zr), Vector3(-4, 1.213, zr), _tris_along_x(zr))
		var dh := (lintel - sill) * sc.y
		var dw := (hw_r + hw_l) * sc.x
		_res("size", dh >= float(dc["min_h"]) and dw >= float(dc["min_w"]) and dh <= 2.6,
			"人物比例：入口淨高 %.2f m（門檻 %.2f→鴨居 %.2f；≥ %.2f，1.7 m 人）、淨寬 %.2f m（≥ %.2f）" % [
				dh, sill, lintel, dc["min_h"], dw, dc["min_w"]])
	if gs.has("water_ref"):
		# 水車（R4）：輪半徑、輪寬由轉動部件 LOD0 外框量；半徑不超過 P0 地標 r
		var lmw := _lm(_lm_id())
		for rt: Dictionary in S.get("rotors", []):
			var rm := hero.get_node_or_null("%s/LOD0" % rt["name"]) as MeshInstance3D
			if rm == null:
				_res("size", false, "缺轉動部件 %s/LOD0" % rt["name"])
				continue
			var rb := rm.mesh.get_aabb()
			var rr := maxf(maxf(absf(rb.position.y), absf(rb.end.y)), maxf(absf(rb.position.z), absf(rb.end.z)))
			var pv: Array = rt["pivot"]
			_res("size", rr <= float(lmw.get("r", 0.0)) + 0.005 and absf(rb.size.y - rb.size.z) <= 0.05,
				"輪（%s）半徑 %.2f m（P0 %s r %.1f，不超過）、輪寬 %.2f m、輪心離原點（水面）%.2f m、軸向 %s" % [
					rt["name"], rr, _lm_id(), float(lmw.get("r", -1.0)), rb.size.x, float(pv[1]), rt["axis"]])
	if gs.has("span"):
		var sp: Dictionary = gs["span"]
		var y := 1.537
		var inr := _vis_dist(Vector3(0, y, 0), Vector3(20, y, 0), _tris_along_x(0.0))
		var inl := _vis_dist(Vector3(0, y, 0), Vector3(-20, y, 0), _tris_along_x(0.0))
		var outr := 20.0 - _vis_dist(Vector3(20, y, 0), Vector3(0, y, 0), _tris_along_x(0.0))
		var outl := -20.0 + _vis_dist(Vector3(-20, y, 0), Vector3(0, y, 0), _tris_along_x(0.0))
		var axis := ((outr + inr) * 0.5 - (outl - inl) * 0.5) * sc.x
		var clear := (inr + inl) * sc.x
		# 垂直射線避開接縫（x＝0、z＝0 常是三角形共邊，邊上命中會被兩側都判不中）
		var nuki := _vis_dist(Vector3(0.137, 0.3, 0.043), Vector3(0.137, 30, 0.043), _tris_at(0.137, 0.043)) + 0.3
		var kas := 40.0 - _vis_dist(Vector3(0.137, 40, 0.043), Vector3(0.137, -5, 0.043), _tris_at(0.137, 0.043))
		var lm := _lm(_lm_id())
		_res("size", absf(axis - float(sp["axis_m"])) <= 0.05 and clear >= float(sp["clear_min"])
			and nuki * sc.y >= float(gs["walkway"]["min_clear"]) and absf(float(lm.get("span", -1)) - float(sp["axis_m"])) <= 0.01
			and kas * sc.y >= float(lm.get("h", 0)) and kas * sc.y <= float(sz["top"][1]) + 0.005,
			"射線實測：柱心距 %.2f m（P0 span %.1f）、柱間淨寬 %.2f（≥ %.1f）、通行淨高（貫下）%.2f（≥ %.1f）、笠木中央頂 %.2f（P0 h %.1f～%.2f）" % [
				axis, lm.get("span", -1), clear, sp["clear_min"], nuki * sc.y, gs["walkway"]["min_clear"], kas * sc.y,
				lm.get("h", -1), sz["top"][1]])
	if gs.has("wall"):
		_c_size_wall()
	if gs.has("bridge"):
		_c_size_bridge()


## hero 局部 (lx, lz) 由上往下第一個 LOD0 可見面的局部 y（NAN＝沒打到）。橋板之間有 2 cm 縫 → 取 lz ±0.07 三點最高
func _deck_vis(lx: float, lz: float) -> float:
	var best := NAN
	for dz: float in [0.0, -0.07, 0.07]:
		var d := _vis_dist(Vector3(lx, 12.0, lz + dz), Vector3(lx, -12.0, lz + dz), _tris_at(lx, lz + dz))
		if d != INF and (is_nan(best) or 12.0 - d > best):
			best = 12.0 - d
	return best


## 世界 (x, z) 由上往下第一個 hero 碰撞面的世界 y（NAN＝沒打到）
func _hero_top(x: float, z: float) -> float:
	var d := _col_dist(Vector3(x, 400.0, z), Vector3(x, -80.0, z))
	return 400.0 - d if d != INF else NAN


## layout 水道中心線（MainRiver／Canal／Streams[].name）
func _water_line(name: String) -> PackedVector2Array:
	var W: Dictionary = L["water"]
	var pts: Array = []
	if W.has(name) and W[name] is Dictionary:
		pts = W[name]["pts"]
	else:
		for s: Dictionary in W.get("Streams", []):
			if String(s["name"]) == name:
				pts = s["pts"]
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


## P7 R2 正式橋（gate_spec.bridge）：規格＝P4 灰盒橋（長、寬、兩端高差；不信 asset.json 自報）＋P0 橋長 ±10 %；
## LOD0 射線實測橋長、橋端與地形高差、縱坡（10 m 視窗）、拱度、欄杆內淨寬 vs 道路寬、欄杆高、結構底離水面（淨空）。
func _c_size_bridge() -> void:
	var B: Dictionary = gs["bridge"]
	var xf := _xf()
	var oy := xf.origin.y
	var dims := HLib.bridge_dims(anchor)
	var sp := TLib.bridge_span(L, String(anchor.name))
	var bl := float(B["L"])
	_res("size", not dims.is_empty() and not sp.is_empty() and absf(float(dims["L"]) - bl) <= 0.05
		and absf(float(dims["dh"]) - float(B["dh"])) <= 0.02 and absf(float(dims["W"]) - float(B["W"])) <= 0.02
		and bl >= float(sp[1]) - 0.005 and bl <= float(sp[2]) + 0.005,
		"規格＝P4 灰盒橋 %s：長 %.2f／寬 %.2f／兩端高差 %+.3f m（asset.json %.2f／%.2f／%+.3f）；P0 橋長 %.1f（容許 %.2f～%.2f）" % [
			anchor.name, dims.get("L", -1), dims.get("W", -1), dims.get("dh", 0), bl, B["W"], B["dh"],
			sp[0] if sp else -1.0, sp[1] if sp else -1.0, sp[2] if sp else -1.0])
	# 沿中線（x 0.137 避開接縫）每 0.1 m 量橋面頂
	var zs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var lz := -bl * 0.5 - 1.0
	while lz <= bl * 0.5 + 1.0:
		var y := _deck_vis(0.137, lz)
		if not is_nan(y):
			zs.append(lz)
			ys.append(y)
		lz += 0.1
	if zs.size() < 10:
		_res("size", false, "橋面射線沒打到（%d 點）" % zs.size())
		return
	var lm := zs[zs.size() - 1] - zs[0]
	_res("size", absf(lm - bl) <= 0.15 and lm >= float(sp[1]) - 0.1 and lm <= float(sp[2]) + 0.1,
		"射線實測橋面長 %.2f m（z %.2f～%.2f；灰盒 %.2f、P0 容許 %.2f～%.2f）" % [lm, zs[0], zs[zs.size() - 1], bl, sp[1], sp[2]])
	# 橋端與地形高差（橋面端點 vs 橋端外 0.5 m 地形）
	var worst_end := 0.0
	var ends: Array = []
	for e in 2:
		var ze := zs[0] if e == 0 else zs[zs.size() - 1]
		var ye := oy + (ys[0] if e == 0 else ys[ys.size() - 1])
		var g := xf * Vector3(0.137, 0, ze + (-0.5 if e == 0 else 0.5))
		var gy := _ground(g.x, g.z, true)
		var d := absf(ye - gy) if not is_nan(gy) else INF
		worst_end = maxf(worst_end, d)
		ends.append("%s端 橋面 %.2f／地形 %.2f（%.2f）" % ["−z" if e == 0 else "+z", ye, gy, d])
	_res("size", worst_end <= float(B["end_tol"]), "橋端與地形高差：%s；最大 %.2f m（≤ %.2f）" % ["、".join(ends), worst_end, B["end_tol"]])
	# 縱坡：10 m 視窗（道路縱坡 gate 同一口徑）＋1 m 局部
	var g10 := 0.0
	var g1 := 0.0
	for i in zs.size():
		for j in range(i + 1, zs.size()):
			var dz := zs[j] - zs[i]
			if absf(dz - 10.0) < 0.05 or (absf(dz - 1.0) < 0.05):
				var gg := absf(ys[j] - ys[i]) / dz
				if dz > 5.0:
					g10 = maxf(g10, gg)
				else:
					g1 = maxf(g1, gg)
	var ymax := -INF
	var zmax := 0.0
	for i in ys.size():
		var lin := ys[0] + (ys[ys.size() - 1] - ys[0]) * (zs[i] - zs[0]) / lm
		if ys[i] - lin > ymax:
			ymax = ys[i] - lin
			zmax = zs[i]
	_res("size", g10 <= float(B["grade_max"]) and g1 <= 0.20 and absf(ymax - float(B["rise"])) <= 0.06,
		"橋面縱坡：10 m 視窗最大 %.1f%%（≤ %.0f%%）、1 m 局部最大 %.1f%%（≤ 20%%）；拱度（扣兩端連線）%.2f m @ z %.1f（規格 %.2f）" % [
			g10 * 100.0, float(B["grade_max"]) * 100.0, g1 * 100.0, ymax, zmax, B["rise"]])
	# 欄杆：內淨寬（橋面上 0.5 m 水平射線）≥ 道路寬；架木頂離橋面
	var zc := 0.37
	var yc := _deck_vis(0.137, zc)
	var inr := _vis_dist(Vector3(0.137, yc + 0.5, zc), Vector3(12, yc + 0.5, zc), _tris_along_x(zc))
	var inl := _vis_dist(Vector3(0.137, yc + 0.5, zc), Vector3(-12, yc + 0.5, zc), _tris_along_x(zc))
	var clear := inr + inl
	var xr := float(B["rail_x"])
	var rt := 12.0 - _vis_dist(Vector3(xr, 12.0, zc), Vector3(xr, -12.0, zc), _tris_at(xr, zc))
	var rh := rt - yc
	_res("size", clear >= 2.0 * float(B["road_hw"]) and clear <= float(B["W"]) and rh >= 0.85 and rh <= 1.10,
		"欄杆內淨寬 %.2f m（道路寬 %.1f、橋寬 %.1f）、架木頂離橋面 %.2f m（0.85～1.10）" % [clear, 2.0 * float(B["road_hw"]), B["W"], rh])
	# 結構底離水面（水面上方、避開河中支撐 ±0.9 m）
	var fb_min := INF
	var fb_at := 0.0
	var n_w := 0
	for i in range(0, zs.size(), 5):
		var z := zs[i]
		var near := false
		for s: float in B["supports"]:
			near = near or absf(z - s) < 0.9
		if near:
			continue
		var w := xf * Vector3(0.137, 0, z)
		var wy := _water_y(String(B["water_node"]), w.x, w.z)
		var gy := _ground(w.x, w.z, true)
		if is_nan(wy) or is_nan(gy) or gy >= wy - 0.05:
			continue
		n_w += 1
		for lx: float in [0.137, float(B["W"]) * 0.25, -float(B["W"]) * 0.25]:
			var d := _vis_dist(Vector3(lx, wy - oy, z), Vector3(lx, 12.0, z), _tris_at(lx, z))
			if d < fb_min:
				fb_min = d
				fb_at = z
	_res("size", n_w > 0 and fb_min >= float(B["freeboard_min"]),
		"結構底離 %s 水面：%d 站最小 %.2f m @ z %.1f（≥ %.2f；河中支撐 ±0.9 m 除外）" % [B["water_node"], n_w, fb_min, fb_at, B["freeboard_min"]])


## P6 稗田邸圍牆（gate_spec.wall）：沿每段牆心線每 step m 實測——牆頂離地高、牆厚（離地 1.0 m 兩側水平射線）、
## 封閉（可見網格與碰撞都不能有缺口；只留大宅門開口）；門旁銜接對大宅門 Hero LOD0 實測瓦頂高差與牆面齊平。
func _c_size_wall() -> void:
	var W: Dictionary = gs["wall"]
	var xf := _xf()
	var oy := xf.origin.y
	var stp := float(W["step"])
	var n_st := 0
	var gaps_v := 0
	var gaps_c := 0
	var g_ex := ""
	var hmin := INF
	var hmax := -INF
	var tmin := INF
	var tmax := -INF
	var h_ex := ""
	for sd: Dictionary in W["sides"]:
		var p0 := Vector2(float(sd["from"][0]), float(sd["from"][1]))
		var p1 := Vector2(float(sd["to"][0]), float(sd["to"][1]))
		var L := p0.distance_to(p1)
		var d := (p1 - p0) / L
		var nrm := Vector2(-d.y, d.x)
		var t := float(sd.get("skip0", 0.0))
		var t_end := L - float(sd.get("skip1", 0.0))
		while t <= t_end + 0.001:
			var c := p0 + d * t
			n_st += 1
			var w := xf * Vector3(c.x, 0, c.y)
			var gl := _ground(w.x, w.z, true) - oy
			var top := 30.0 - _vis_dist(Vector3(c.x + 0.013, 30, c.y + 0.017), Vector3(c.x + 0.013, -5, c.y + 0.017),
				_tris_at(c.x + 0.013, c.y + 0.017))
			var hh := top - gl
			if hh < hmin:
				h_ex = "%s t %.1f" % [sd["name"], t]
			hmin = minf(hmin, hh)
			hmax = maxf(hmax, hh)
			var y := gl + 1.0
			var tris := _tris_along_z(c.x) if absf(nrm.y) > 0.5 else _tris_along_x(c.y)
			var a := Vector3(c.x + nrm.x * 1.5, y, c.y + nrm.y * 1.5)
			var b := Vector3(c.x - nrm.x * 1.5, y, c.y - nrm.y * 1.5)
			var d1 := _vis_dist(a, b, tris)
			var d2 := _vis_dist(b, a, tris)
			if d1 == INF or d2 == INF:
				gaps_v += 1
				g_ex = "%s t %.2f 可見缺口" % [sd["name"], t]
			elif t >= 0.6 and t <= L - 0.6:   # 端部（轉角、門旁）射線會進到相鄰段牆端，不量厚度
				var th := 3.0 - d1 - d2
				tmin = minf(tmin, th)
				tmax = maxf(tmax, th)
			if not _capsule_hits_hero(Vector3(w.x, gl + oy, w.z)):
				gaps_c += 1
				g_ex = "%s t %.2f 碰撞缺口" % [sd["name"], t]
			t += stp
	_res("size", hmin >= float(W["h_min"]) and hmax <= float(W["h_max"]) and tmin >= float(W["t_min"]) and tmax <= float(W["t_max"]),
		"圍牆 %d 站（每 %.1f m）射線實測：牆頂離地 %.2f～%.2f m（%.2f～%.2f；最低在 %s）、離地 1.0 m 牆厚 %.2f～%.2f m（%.2f～%.2f，含柱）" % [
			n_st, stp, hmin, hmax, W["h_min"], W["h_max"], h_ex, tmin, tmax, W["t_min"], W["t_max"]])
	_res("size", gaps_v == 0 and gaps_c == 0, "宅邸邊界封閉（除大宅門開口）：%d 站中 可見網格缺口 %d、碰撞缺口 %d%s" % [
		n_st, gaps_v, gaps_c, ("，例 " + g_ex) if g_ex != "" else ""])
	# 門旁銜接：大宅門 Hero（同一地標）LOD0 換到本資產局部
	var gh := anchor.get_node_or_null("Hero") as Node3D
	if gh == null:
		_res("size", false, "找不到大宅門 Hero（%s/Hero），無法驗門旁銜接" % anchor.name)
		return
	var gt := xf.affine_inverse() * gh.global_transform
	var gf := PackedVector3Array()
	for q in _lod_faces(0, gh):
		gf.append(gt * q)
	var jx := float(W["junction_x"])
	var lines: Array = []
	var ok := true
	for sg: float in [-1.0, 1.0]:
		var xg := sg * (jx - 0.08)
		var xw := sg * (jx + 0.10)
		var tg := 30.0 - _ray_faces(Vector3(xg, 30, 0.017), Vector3(xg, -5, 0.017), gf)
		var tw := 30.0 - _vis_dist(Vector3(xw, 30, 0.017), Vector3(xw, -5, 0.017), _tris_at(xw, 0.017))
		var wj := xf * Vector3(xw, 0, 0)
		var gl := _ground(wj.x, wj.z, true) - oy
		var fg := 2.0 - _ray_faces(Vector3(xg, gl + 1.0, 2.0), Vector3(xg, gl + 1.0, -2.0), gf)
		var fw := 2.0 - _vis_dist(Vector3(xw, gl + 1.0, 2.0), Vector3(xw, gl + 1.0, -2.0), _tris_along_z(xw))
		# 接縫：x＝±jx 兩側 1 cm，前後牆面都要有網格（大宅門或圍牆任一），且牆面在灰泥面 ±3 cm
		var seam := 0
		for xs: float in [sg * (jx - 0.01), sg * (jx + 0.01)]:
			for zz: float in [2.0, -2.0]:
				var hv := minf(_ray_faces(Vector3(xs, gl + 1.0, zz), Vector3(xs, gl + 1.0, 0.0), gf),
					_vis_dist(Vector3(xs, gl + 1.0, zz), Vector3(xs, gl + 1.0, 0.0), _tris_along_z(xs)))
				if hv == INF or absf(absf(zz) - hv - float(W["plaster_half"])) > 0.03:
					seam += 1
		var okj := absf(tg - tw) <= 0.03 and absf(fg - fw) <= 0.01 and seam == 0
		ok = ok and okj
		lines.append("%s 側：瓦頂 大宅門袖牆 %.3f／圍牆 %.3f（差 %.3f ≤ 0.03）、牆面 z %.3f／%.3f（差 %.3f ≤ 0.01）、接縫前後牆面缺 %d" % [
			"西" if sg < 0 else "東", tg, tw, absf(tg - tw), fg, fw, absf(fg - fw), seam])
	_res("size", ok, "門旁銜接（x ±%.2f 接大宅門袖牆端）：%s" % [jx, "；".join(lines)])


## 射線打任意三角面列表（局部座標），回傳距離（打不到 INF）
func _ray_faces(from: Vector3, to: Vector3, fs: PackedVector3Array) -> float:
	var best := INF
	var lo := Vector3(minf(from.x, to.x), minf(from.y, to.y), minf(from.z, to.z)) - Vector3.ONE * 0.01
	var hi := Vector3(maxf(from.x, to.x), maxf(from.y, to.y), maxf(from.z, to.z)) + Vector3.ONE * 0.01
	for t in range(0, fs.size(), 3):
		var a := fs[t]
		var b := fs[t + 1]
		var c := fs[t + 2]
		if maxf(a.x, maxf(b.x, c.x)) < lo.x or minf(a.x, minf(b.x, c.x)) > hi.x \
				or maxf(a.z, maxf(b.z, c.z)) < lo.z or minf(a.z, minf(b.z, c.z)) > hi.z:
			continue
		var hit: Variant = Geometry3D.segment_intersects_triangle(from, to, a, b, c)
		if hit != null:
			best = minf(best, from.distance_to(hit))
	return best


## 2 地塊
func _c_parcel() -> void:
	var PJ: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PARCELS))
	var own := PackedVector2Array()
	var others: Array = []
	# 稗田邸圍牆（P6）：範圍＝P0 district（gate_spec.district）；同一宅邸的地塊（estate_parcels）不算「其他地塊」
	var estate: Array = gs.get("estate_parcels", [])
	for r in PJ["parcels"]:
		if String(r["id"]) == String(gs["parcel"]):
			own = TLib.pts(r["footprint"])
		elif not estate.has(String(r["id"])):
			others.append([String(r["id"]), TLib.pts(r["footprint"])])
	if gs.has("district"):
		own = PackedVector2Array()
		for q: Array in L["districts"][String(gs["district"])]["poly"]:
			own.append(Vector2(float(q[0]), float(q[1])))
	var roads: Array = []
	for r in PLib.network(L):
		for poly in Geometry2D.offset_polyline(r["pts"], float(r["hw"]), Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
			roads.append([String(r["name"]), poly])
	var bad: Array = []
	var worst_out := 0.0
	var road_hit := 0.0
	var shoulder: Array = []   # 使用者裁示允許壓路肩的接地件（ground.road_ok）：報量、上限另驗
	for g: Dictionary in gs["ground"]:
		var wp := _world_poly(g["rect"])
		if not own.is_empty():
			var outside := _poly_area(Geometry2D.clip_polygons(wp, own))
			if outside > 0.005:
				bad.append("%s 出地塊 %.3f m²" % [g["name"], outside])
			worst_out = maxf(worst_out, outside)
		for o in others:
			var a := _poly_area(Geometry2D.intersect_polygons(wp, o[1]))
			if a > 0.005:
				bad.append("%s 壓到 %s %.3f m²" % [g["name"], o[0], a])
		for rr in roads:
			var a := _poly_area(Geometry2D.intersect_polygons(wp, rr[1]))
			if a > 0.005:
				var rok: Variant = g.get("road_ok", "")
				if (rok is Array and (rok as Array).has(String(rr[0]))) or String(rok) == String(rr[0]):
					shoulder.append("%s 壓 %s 路肩 %.2f m²" % [g["name"], rr[0], a])
					continue
				bad.append("%s 壓到道路 %s %.3f m²" % [g["name"], rr[0], a])
				road_hit += a
	_res("parcel_fit", bad.is_empty(), "%d 個地面接觸件：%s地塊外 %.3f m²、壓道路 %.3f m²、壓其他地塊 0%s%s" % [
		gs["ground"].size(), ("在 " + (("district " + String(gs["district"])) if gs.has("district") else String(gs["parcel"]))
			+ (("（同宅邸地塊 " + "、".join(estate) + " 不算他人地塊）") if estate else "") + " 內、") if not own.is_empty() else "（地標，無地塊）",
		worst_out, road_hit, ("；（使用者裁示允許）" + "、".join(shoulder)) if shoulder else "",
		("；" + "、".join(bad.slice(0, 4))) if bad else ""])
	if not own.is_empty():
		# 整棟 LOD0（含屋簷）投影：不得伸進任何道路／巷道
		var verts := PackedVector2Array()
		var xf := _xf()
		for t in range(0, f0.size(), 3):
			var w := xf * f0[t]
			verts.append(Vector2(w.x, w.z))
		var in_road := 0
		var ex := ""
		for p in verts:
			for rr in roads:
				if Geometry2D.is_point_in_polygon(p, rr[1]):
					in_road += 1
					ex = "%s (%.2f, %.2f)" % [rr[0], p.x, p.y]
					break
		_res("parcel_fit", in_road == 0, "LOD0 全部頂點（含屋簷、庇）不進道路：%d 點%s" % [in_road, ("，例 " + ex) if ex != "" else ""])
		if gs.has("district"):
			var outd := 0
			for p in verts:
				if not Geometry2D.is_point_in_polygon(p, own):
					outd += 1
			_res("parcel_fit", outd == 0, "LOD0 全部頂點（含瓦頂出簷）在 district %s 內：界外 %d 點" % [gs["district"], outd])
	elif gs.has("water_ref"):
		# 水車（R4）：輪子（外框投影）整個在水渠水面範圍內，不壓道路
		var wpts: Array = L["water"][String(gs["water_ref"])]["pts"]
		var cl := PackedVector2Array()
		for p in wpts:
			cl.append(Vector2(float(p[0]), float(p[1])))
		var hw := float(L["water"][String(gs["water_ref"])]["half_w"])
		var polys := Geometry2D.offset_polyline(cl, hw, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
		var outside := 0.0
		var in_road := 0.0
		for rt: Dictionary in S.get("rotors", []):
			var rb := (hero.get_node("%s/LOD0" % rt["name"]) as MeshInstance3D).mesh.get_aabb()
			var pv: Array = rt["pivot"]
			var rc := [float(pv[0]) + rb.position.x, float(pv[2]) + rb.position.z, float(pv[0]) + rb.end.x, float(pv[2]) + rb.end.z]
			var wp := _world_poly(rc)
			var area := PLib.area(wp)
			var inside := 0.0
			for poly in polys:
				inside += _poly_area(Geometry2D.intersect_polygons(wp, poly))
			outside += maxf(0.0, area - inside)
			for rr in roads:
				in_road += _poly_area(Geometry2D.intersect_polygons(wp, rr[1]))
		_res("parcel_fit", outside <= 0.005 and in_road <= 0.005, "輪子外框投影在 %s 水面（半寬 %.1f m）內：水面外 %.3f m²、壓道路 %.3f m²" % [
			gs["water_ref"], hw, outside, in_road])
	elif gs.has("span"):
		# 鳥居：道路斷面必須落在柱間淨寬內（沿柱心線）
		var xf := _xf()
		var inner := float(gs["span"]["axis_m"]) * 0.5 - 0.5
		var a3 := xf * Vector3(-30, 0, 0)
		var b3 := xf * Vector3(30, 0, 0)
		var line := PackedVector2Array([Vector2(a3.x, a3.z), Vector2(b3.x, b3.z)])
		var worst := 0.0
		var names: Array = []
		for rr in roads:
			for seg in Geometry2D.intersect_polyline_with_polygon(line, rr[1]):
				names.append(rr[0])
				for p in seg:
					var lp := _to_local(Vector3(p.x, xf.origin.y, p.y))
					worst = maxf(worst, absf(lp.x))
		var clear_half := inner
		var sp: Dictionary = gs["span"]
		if sp.has("shoulder_max"):
			# 使用者 2026-09-25（參道鳥居）：維持 P0 柱心距、柱腳壓路肩——台座內緣以內的淨寬 ≥ clear_min，
			# 壓路肩量＝道路斷面半寬 − 台座內緣（每側），≤ shoulder_max
			var ih := float(sp["inner_half"])
			var over := worst - ih
			_res("parcel_fit", ih * 2.0 >= float(sp["clear_min"]) and over <= float(sp["shoulder_max"]) + 0.001,
				"柱心線上的道路斷面 %s：半寬 %.2f m；台座內緣 ±%.2f → 中間淨寬 %.2f m（≥ %.1f）；台座壓路肩每側 %.2f m（≤ %.2f，使用者裁示）" % [
					"、".join(names), worst, ih, ih * 2.0, sp["clear_min"], maxf(over, 0.0), sp["shoulder_max"]])
		else:
			_res("parcel_fit", worst <= clear_half + 0.001, "柱心線上的道路斷面 %s：離中心最遠 %.2f m ≤ 柱內緣 %.2f m（道路整寬從兩柱之間通過）" % [
				"、".join(names), worst, clear_half])


func _gb_record() -> Dictionary:
	var GJ: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GREYBOX))
	for b in GJ["buildings"]:
		if String(b["id"]) == String(gs["p4_id"]):
			return b
	return {}


## 本次驗的 P0 地標 id（instances 可逐筆覆寫；預設 asset.json landmark）
func _lm_id() -> String:
	return String(gs.get("landmark", S["landmark"]))


func _lm(id: String) -> Dictionary:
	for e in L["landmarks"]:
		if String(e["id"]) == id:
			return e
	return {}


## 3 接地
func _c_ground() -> void:
	var xf := _xf()
	var oy := xf.origin.y
	var bad: Array = []
	var lines: Array = []
	var not_terrain := 0
	var nt_ex := ""
	for g: Dictionary in gs["ground"]:
		var rc: Array = g["rect"]
		var nu := maxi(2, int(ceil((float(rc[2]) - float(rc[0])) / 0.25)))
		var nw := maxi(2, int(ceil((float(rc[3]) - float(rc[1])) / 0.25)))
		var lo := INF
		var hi := -INF
		for i in nu + 1:
			for j in nw + 1:
				var lx := lerpf(float(rc[0]), float(rc[2]), float(i) / nu)
				var lz := lerpf(float(rc[1]), float(rc[3]), float(j) / nw)
				var w := xf * Vector3(lx, 0, lz)
				var h := _ground(w.x, w.z, true)
				if is_nan(h):
					continue
				lo = minf(lo, h)
				hi = maxf(hi, h)
				var col: Object = _first_collider(w.x, w.z)
				if col != null and (col as CollisionObject3D).get_rid() != terrain_rid:
					var n := col as Node
					if anchor.is_ancestor_of(n) or String(n.get_parent().name) == "Buildings":
						not_terrain += 1
						nt_ex = "%s 下方是 %s" % [g["name"], n.get_path()]
		var bw := oy + float(g["bottom"]) * xf.basis.get_scale().y
		var tw := oy + float(g["top"]) * xf.basis.get_scale().y
		var emb := lo - bw
		var ok := bw <= lo - 0.01 and emb <= float(g["embed_max"]) + (hi - lo) + 0.005 and tw >= hi + 0.02
		if not ok:
			bad.append("%s 底 %.2f／地面 %.2f～%.2f／頂 %.2f" % [g["name"], bw, lo, hi, tw])
		lines.append("%s 埋 %.2f" % [g["name"], emb])
	_res("grounding", bad.is_empty(), "%d 個接地件都落在地形上（底低於地形最低點、埋深 ≤ 容許＋高低差、頂露出）：%s%s" % [
		gs["ground"].size(), "、".join(lines), ("；✗ " + "、".join(bad)) if bad else ""])
	_res("grounding", not_terrain == 0, "接地件正下方第一個碰撞體是地形：%d 點不是%s" % [not_terrain,
		("（" + nt_ex + "）") if nt_ex != "" else ""])
	# 被取代的灰盒／placeholder：不可見、碰撞停用（禁止把資產墊在灰盒上）
	var body_mode := String(gs["placement"]) in ["body", "bridge"]   # 橋（P7 R2）：灰盒＝anchor 本身，同 aux
	var ph: Node = anchor if body_mode else anchor.get_node_or_null(String(gs["replaces"]))
	var vis := 0
	var live := 0
	if body_mode:
		# aux：灰盒＝anchor 本身；它自己的網格／Shape（不含 Hero 子樹）都要退場、collision_layer 0
		for c in anchor.find_children("*", "", true, false):
			if c == hero or hero.is_ancestor_of(c):
				continue
			if c is MeshInstance3D and (c as MeshInstance3D).visible:
				vis += 1
			elif c is CollisionShape3D and not (c as CollisionShape3D).disabled:
				live += 1
		if (anchor as CollisionObject3D).collision_layer != 0:
			live += 1
	for nm: String in ([] if body_mode else [String(gs["replaces"])] + Array(gs.get("also_retire", []))):
		if nm == "":
			continue   # replaces 空字串＝沒有 placeholder（稗田邸圍牆：掛在大宅門地標下的第二件）
		var pn: Node = anchor.get_node_or_null(nm)
		if pn == null:
			continue
		for c in pn.find_children("*", "", true, false) + [pn]:
			if c is MeshInstance3D and (c as MeshInstance3D).visible:
				vis += 1
			elif c is CollisionShape3D and not (c as CollisionShape3D).disabled:
				live += 1
			if c is CollisionObject3D and (c as CollisionObject3D).collision_layer != 0:
				live += 1
	_res("grounding", vis == 0 and live == 0, "被取代的 %s：%s（可見網格 %d、有效碰撞 %d）" % [
		String(anchor.name) + " 灰盒" if body_mode else gs["replaces"],
		"已移除" if ph == null else "保留節點（P4 gate 紀錄用）但已退場", vis, live])
	# 水車（R4）：輪下緣泡進水渠水面、不碰渠底（沿輪寬取 5 點）
	if gs.has("water_ref"):
		for rt: Dictionary in S.get("rotors", []):
			var rb := (hero.get_node("%s/LOD0" % rt["name"]) as MeshInstance3D).mesh.get_aabb()
			var pv: Array = rt["pivot"]
			var bot := xf * Vector3(float(pv[0]), float(pv[1]) + rb.position.y, float(pv[2]))
			var wy := _water_y(String(gs["water_ref"]), bot.x, bot.z)
			var bed := INF
			for k in 5:
				var lx := float(pv[0]) + lerpf(rb.position.x, rb.end.x, k / 4.0)
				var w := xf * Vector3(lx, 0, float(pv[2]))
				bed = minf(bed, bot.y - _ground(w.x, w.z, true))
			var dip := wy - bot.y
			var wr: Array = gs.get("dip", [0.15, 0.6])
			_res("grounding", dip >= float(wr[0]) and dip <= float(wr[1]) and bed >= 0.10,
				"輪下緣 y %.2f：泡進 %s 水面 %.2f m（%.2f～%.2f）、離渠底最近 %.2f m（≥ 0.10）" % [
					bot.y, gs["water_ref"], dip, float(wr[0]), float(wr[1]), bed])
	# 入口段差（有台基的建築）；多段石段（gate_spec.steps）另走 _entry_steps
	if not _bld().is_empty() and gs.has("entry") and gs.has("steps"):
		_entry_steps(xf)
	elif not _bld().is_empty() and gs.has("entry"):
		var step: Dictionary = {}
		for g: Dictionary in gs["ground"]:
			if String(g["name"]) == "踏石":
				step = g
		var e := xf * Vector3(float(gs["entry"][0]), 0, float(gs["entry"][1]))
		var eg := _ground(e.x, e.z)
		var st := oy + float(step.get("top", 0.0))
		var pl := oy + float(_bld()["plinth"])
		var r1 := st - eg
		var r2 := pl - st
		_res("grounding", r1 >= 0.0 and r1 <= 0.30 and r2 >= 0.0 and r2 <= 0.30,
			"入口段差：路面 %.2f → 踏石 %.2f（%.2f m）→ 台基 %.2f（%.2f m），每階 ≤ 0.30" % [eg, st, r1, pl, r2])


## 多段石段（W9 丘腳社寺起）：gate_spec.steps＝各段踏面中心（局部 x, z）。踏面高由 LOD0 實測：
## 自台基頂上方 0.3 m 往下第一個可見面（避開向拝屋根、屋簷）。路面 → 各段 → 台基頂，每階 0～0.30 m（與單一踏石同門檻）。
func _entry_steps(xf: Transform3D) -> void:
	var e := xf * Vector3(float(gs["entry"][0]), 0, float(gs["entry"][1]))
	var eg := _ground(e.x, e.z) - xf.origin.y
	var pl := float(_bld()["plinth"])
	var from_y := pl + 0.3
	var seq: Array = [eg]
	for s: Array in gs["steps"]:
		var lx := float(s[0])
		var lz := float(s[1])
		var dv := _vis_dist(Vector3(lx, from_y, lz), Vector3(lx, -5.0, lz), _tris_at(lx, lz))
		seq.append(NAN if dv == INF else from_y - dv)
	seq.append(pl)
	var ok := true
	var worst := 0.0
	var tops: Array = []
	for i in range(1, seq.size()):
		var r := float(seq[i]) - float(seq[i - 1])
		if is_nan(r) or r < 0.0 or r > 0.30:
			ok = false
		if not is_nan(r):
			worst = maxf(worst, r)
		tops.append("%.2f" % float(seq[i]))
	_res("grounding", ok, "入口石段 %d 段（LOD0 實測踏面，局部）：路面 %.2f → %s（最後＝台基頂），每階 0～0.30（最大 %.2f m）" % [
		(gs["steps"] as Array).size(), eg, " → ".join(tops), worst])


## 4 材質
func _c_materials() -> void:
	var mats: Dictionary = S["materials"]
	var ML: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MATLIB))
	var k := float(ML["albedo_k"])
	var bad: Array = []
	var used := {}
	var ks := {}
	for li in 3:
		for mi: MeshInstance3D in _lod_mis(li):
			for si in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(si)
				if mi.get_surface_override_material(si) != null or mi.material_override != null:
					bad.append("LOD%d surface %d 有 override 材質" % [li, si])
				if m == null or not mats.values().has(m.resource_path) or not mats.has(m.resource_name):
					bad.append("LOD%d surface %d 材質 %s 不在登記清單" % [li, si, m.resource_path if m else "null"])
					continue
				used[m.resource_path] = m
	var tex_info: Array = []
	for path: String in used:
		if not (path.begins_with(V2_DIR + "_matlib/") or path.begins_with(V2_DIR + String(S["id"]) + "/")):
			bad.append("%s 不在共享庫或本資產目錄" % path)
		var m := used[path] as StandardMaterial3D
		if m == null:
			bad.append("%s 不是 StandardMaterial3D" % path)
			continue
		# 反照率換算：材質庫登記的 albedo_k（飽和漆色個別調高、原因記在 matlib note）；Hero atlas 用全域值
		var km := float(ML["materials"].get(m.resource_name, {}).get("albedo_k", k))
		ks[m.resource_name] = km
		if not m.vertex_color_use_as_albedo or not m.albedo_color.is_equal_approx(Color(km, km, km, 1.0)):
			bad.append("%s albedo_color %s（應 %.2f）或未用頂點色" % [path, m.albedo_color, km])
		for prop in ["albedo_texture", "normal_texture", "roughness_texture", "emission_texture"]:
			var t := m.get(prop) as Texture2D
			if t == null:
				continue
			var e := _tex_check(t, prop == "normal_texture")
			if e != "":
				bad.append(e)
			tex_info.append(t.resource_path.get_file())
	_res("materials", bad.is_empty() and used.size() <= MAX_MATS,
		"%d 個材質（≤ %d）全是登記的共享庫／Hero atlas、albedo_k 與材質庫登記一致 %s、%d 張貼圖 ≤ %d²、VRAM 壓縮%s" % [
			used.size(), MAX_MATS, ks, tex_info.size(), TEX_MAX, ("；" + "、".join(bad.slice(0, 4))) if bad else ""])


## 貼圖：≤ 2K、2 的次方、.import VRAM 壓縮（法線要 normal_map=1）、匯入檔存在
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
		return "%s 未 VRAM 壓縮（compress/mode=%s）" % [p.get_file(), cf.get_value("params", "compress/mode", "?")]
	if normal and int(cf.get_value("params", "compress/normal_map", 0)) != 1:
		return "%s 法線貼圖未標 normal_map" % p.get_file()
	var dests: Array = cf.get_value("deps", "dest_files", [])
	for d: String in dests:
		if not FileAccess.file_exists(d):
			return "%s 匯入檔不存在 %s" % [p.get_file(), d]
	return ""


## Texture2DArray（2d_array_texture 匯入）：須 VRAM 壓縮、有 mipmap、匯入檔存在。
func _layered_check(p: String) -> String:
	var cf := ConfigFile.new()
	if cf.load(p + ".import") != OK:
		return "%s 沒有 .import" % p.get_file()
	if String(cf.get_value("remap", "importer", "")) != "2d_array_texture":
		return "%s 匯入器不是 2d_array_texture" % p.get_file()
	if int(cf.get_value("params", "compress/mode", -1)) != 2:
		return "%s 未 VRAM 壓縮（compress/mode=%s）" % [p.get_file(), cf.get_value("params", "compress/mode", "?")]
	if not bool(cf.get_value("params", "mipmaps/generate", false)):
		return "%s 未產生 mipmap" % p.get_file()
	var dests: Array = cf.get_value("deps", "dest_files", [])
	if dests.is_empty():
		return "%s 尚未匯入（無 dest_files）" % p.get_file()
	for d: String in dests:
		if not FileAccess.file_exists(d):
			return "%s 匯入檔不存在 %s" % [p.get_file(), d]
	return ""


## 5 幾何
func _c_geometry() -> void:
	var lines: Array = []
	var ok := true
	for li in 3:
		var mis := _lod_mis(li)
		if mis.is_empty():
			ok = false
			continue
		var tris := 0
		var degen := 0
		var nan := 0
		var flip := 0
		var miss := PackedStringArray()
		for mi: MeshInstance3D in mis:
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var nn: Variant = arr[Mesh.ARRAY_NORMAL]
				var uv: Variant = arr[Mesh.ARRAY_TEX_UV]
				var tg: Variant = arr[Mesh.ARRAY_TANGENT]
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				if nn == null or (nn as PackedVector3Array).size() != vv.size():
					miss.append("s%d 法線" % si)
				if uv == null or (uv as PackedVector2Array).size() != vv.size():
					miss.append("s%d UV" % si)
				if tg == null or (tg as PackedFloat32Array).size() != vv.size() * 4:
					miss.append("s%d 切線" % si)
				var n3: PackedVector3Array = nn if nn != null else PackedVector3Array()
				var cnt := idx.size() if not idx.is_empty() else vv.size()
				for t in range(0, cnt, 3):
					var i0 := idx[t] if not idx.is_empty() else t
					var i1 := idx[t + 1] if not idx.is_empty() else t + 1
					var i2 := idx[t + 2] if not idx.is_empty() else t + 2
					var a := vv[i0]
					var b := vv[i1]
					var c := vv[i2]
					tris += 1
					if not (a.is_finite() and b.is_finite() and c.is_finite()):
						nan += 1
						continue
					var cr := (b - a).cross(c - a)
					if cr.length() < 1e-7:
						degen += 1
						continue
					if not n3.is_empty():
						# Godot 正面＝順時針（從正面看）：幾何法線 (b−a)×(c−a) 與頂點法線反向
						var vn := n3[i0] + n3[i1] + n3[i2]
						if vn.length() > 1e-6 and cr.normalized().dot(vn.normalized()) > 0.2:
							flip += 1
		var lok := degen == 0 and nan == 0 and flip == 0 and miss.is_empty()
		ok = ok and lok
		lines.append("LOD%d %d 面：退化 %d、NaN %d、繞向反 %d%s" % [li, tris, degen, nan, flip,
			("、缺 " + ",".join(miss)) if not miss.is_empty() else ""])
	var mb: Dictionary = S.get("measured_blender", {})
	var t0 := f0.size() / 3
	var cap := int(BUDGET_LOD0.get(String(S["budget_class"]), 0))
	_res("geometry", ok and t0 <= cap and int(mb.get("LOD0", -1)) == t0,
		"%s；LOD0 %d ≤ §14.8「%s」上限 %d；與 Blender 建置紀錄 %d 一致" % [
			"、".join(lines), t0, S["budget_class"], cap, mb.get("LOD0", -1)])


## 6 Pivot/Scale
func _c_pivot() -> void:
	var xf := _xf()
	var sc := xf.basis.get_scale()
	var ok_s := sc.is_equal_approx(Vector3.ONE) and xf.basis.determinant() > 0.0
	var ident := true
	for n in ["LOD0", "LOD1", "LOD2", "Collision"]:
		var c := hero.get_node_or_null(n) as Node3D
		if c == null or not c.transform.is_equal_approx(Transform3D.IDENTITY):
			ident = false
	for rt: Dictionary in S.get("rotors", []):   # 轉動部件：LOD 子節點 identity（節點本身在 pivot）
		for li in 3:
			var c := hero.get_node_or_null("%s/LOD%d" % [rt["name"], li]) as Node3D
			if c == null or not c.transform.is_equal_approx(Transform3D.IDENTITY):
				ident = false
	_res("pivot_scale", ok_s and ident, "縮放 %s（應 1,1,1）、LOD／Collision 節點 identity：%s" % [sc, "是" if ident else "否"])
	var ab: AABB = _lod_aabb(0)
	var y_ok := ab.position.y <= 0.0 and ab.end.y > 0.0
	if String(gs["placement"]) in ["greybox", "body"]:
		var rec := _gb_record()
		var fp := TLib.pts(rec["footprint"])
		var c := (fp[0] + fp[1] + fp[2] + fp[3]) * 0.25
		var o := xf.origin
		var fd := Vector2(float(rec["front_dir"][0]), float(rec["front_dir"][1])).normalized()
		var hz := Vector2(xf.basis.z.x, xf.basis.z.z).normalized()
		var dang := rad_to_deg(acos(clampf(fd.dot(hz), -1.0, 1.0)))
		_res("pivot_scale", Vector2(o.x, o.z).distance_to(c) <= 0.02 and absf(o.y - float(rec["base_h"])) <= 0.02
			and dang <= 1.0 and y_ok,
			"原點 (%.2f, %.2f, %.2f)＝P4 footprint 中心 (%.2f, %.2f)、base_h %.2f；+z 與 P4 正面方向差 %.2f°；原點在底面（LOD0 y %.2f～%.2f）" % [
				o.x, o.y, o.z, c.x, c.y, rec["base_h"], dang, ab.position.y, ab.end.y])
	elif String(gs["placement"]) == "bridge":
		# P7 R2 橋：原點＝灰盒橋箱頂中心（HLib.bridge_frame）、只有 yaw（橋面縱斷做在網格裡，不靠傾斜節點）
		var want := anchor.global_transform * HLib.bridge_frame(anchor)
		var o := xf.origin
		var tilt := rad_to_deg(xf.basis.y.normalized().angle_to(Vector3.UP))
		var dyaw := rad_to_deg(xf.basis.z.normalized().angle_to(want.basis.z.normalized()))
		_res("pivot_scale", o.distance_to(want.origin) <= 0.02 and tilt <= 0.1 and dyaw <= 0.5 and y_ok,
			"原點 (%.2f, %.2f, %.2f)＝灰盒橋 %s 箱頂中心 (%.2f, %.2f, %.2f)（差 %.3f m）；傾斜 %.2f°（應 0）、+z 與灰盒道路方向差 %.2f°；LOD0 y %.2f～%.2f" % [
				o.x, o.y, o.z, anchor.name, want.origin.x, want.origin.y, want.origin.z, o.distance_to(want.origin), tilt, dyaw,
				ab.position.y, ab.end.y])
	elif gs.has("water_ref"):
		# 水車（R4）：xz＝P0 地標原點；y＝水渠水面（原點在水面，輪下緣泡水）；+z＝水渠流向
		var o := xf.origin
		var a0 := anchor.global_position
		var wy := _water_y(String(gs["water_ref"]), o.x, o.z)
		var wd := _water_dir(String(gs["water_ref"]), o.x, o.z)
		var want := rad_to_deg(atan2(wd.x, wd.y))
		var yaw := rad_to_deg(xf.basis.get_euler().y)
		var dy := absf(wrapf(yaw - want, -180.0, 180.0))
		_res("pivot_scale", Vector2(o.x, o.z).distance_to(Vector2(a0.x, a0.z)) <= 0.02 and absf(o.y - wy) <= 0.03 and dy <= 1.0 and y_ok,
			"原點 xz＝P0 地標 %s (%.2f, %.2f)；原點 y %.3f＝%s 水面 %.3f（差 %.3f）；+z 與水流方向差 %.2f°（yaw %.1f°）；LOD0 y %.2f～%.2f" % [
				_lm_id(), o.x, o.z, o.y, gs["water_ref"], wy, o.y - wy, dy, yaw, ab.position.y, ab.end.y])
	else:
		var lm := _lm(_lm_id())
		var yaw := rad_to_deg(xf.basis.get_euler().y)
		var dy := absf(wrapf(yaw - float(lm.get("yaw", 0.0)), -180.0, 180.0))
		var o := xf.origin
		_res("pivot_scale", o.is_equal_approx(anchor.global_position) and dy <= 0.5 and y_ok,
			"原點＝P0 地標 %s 原點 (%.2f, %.2f, %.2f)、yaw %.1f°（P0 %.1f°）；原點在底面（LOD0 y %.2f～%.2f）" % [
				_lm_id(), o.x, o.y, o.z, yaw, lm.get("yaw", 0.0), ab.position.y, ab.end.y])


## 7 碰撞
func _c_collision() -> void:
	var shapes: Array = []
	var bad_type: Array = []
	for c in hero.find_children("*", "CollisionShape3D", true, false):
		var cs := c as CollisionShape3D
		shapes.append(cs)
		if cs.disabled or not (cs.shape is BoxShape3D or cs.shape is CylinderShape3D or cs.shape is ConvexPolygonShape3D):
			bad_type.append("%s（%s%s）" % [cs.name, cs.shape.get_class() if cs.shape else "null", "、停用" if cs.disabled else ""])
	var bodies := hero.find_children("*", "CollisionObject3D", true, false)
	_res("collision", bad_type.is_empty() and shapes.size() <= MAX_SHAPES and shapes.size() == S["collision"].size()
		and bodies.size() == 1, "%d 個簡化形狀（≤ %d；asset.json 列 %d）、%d 個碰撞體、只有 box／cylinder／convex：%s" % [
			shapes.size(), MAX_SHAPES, S["collision"].size(), bodies.size(),
			"是" if bad_type.is_empty() else "否 " + "、".join(bad_type)])
	var xf := _xf()
	if gs.has("bridge"):
		_c_collision_bridge(xf)
	else:
		_c_collision_walk(xf)
	_c_collision_poke(xf)


## P7 R2 橋：橋面碰撞＝可見橋面（膠囊站得住、腳底與可見橋板差 ≤ 0.10）、欄杆擋得住（橋面上 0.5／1.0 m 往外射線）
func _c_collision_bridge(xf: Transform3D) -> void:
	var B: Dictionary = gs["bridge"]
	var bl := float(B["L"])
	var hw := float(B["road_hw"]) - CAP_R
	var n := 0
	var miss := 0
	var stuck := 0
	var worst := 0.0
	var ex := ""
	var lz := -bl * 0.5 + 0.2
	while lz <= bl * 0.5 - 0.2 + 0.001:
		for lx: float in [-hw, 0.0, hw]:
			n += 1
			var w := xf * Vector3(lx, 0, lz)
			var ct := _hero_top(w.x, w.z)
			var vy := _deck_vis(lx, lz)
			if is_nan(ct) or is_nan(vy):
				miss += 1
				ex = "(%.2f, %.2f) 沒有橋面碰撞" % [lx, lz]
				continue
			var d := absf(ct - (xf.origin.y + vy))
			if d > worst:
				worst = d
				if d > 0.10:
					ex = "(%.2f, %.2f) 碰撞 %.2f／可見 %.2f" % [lx, lz, ct, xf.origin.y + vy]
			if _capsule_hits_hero(Vector3(w.x, ct + 0.02, w.z)):
				stuck += 1
				ex = "(%.2f, %.2f) 膠囊卡住" % [lx, lz]
		lz += 0.5
	_res("collision", miss == 0 and stuck == 0 and worst <= 0.10,
		"橋面 %d 點（道路寬內 x ±%.2f、每 0.5 m）：有碰撞 %d、膠囊站得住 %d、碰撞頂與可見橋板差最大 %.3f m（≤ 0.10）%s" % [
			n, hw, n - miss, n - miss - stuck, worst, ("；✗ " + ex) if ex != "" and (miss or stuck or worst > 0.10) else ""])
	var rn := 0
	var rbad := 0
	var rex := ""
	var xr := float(B["rail_x"])
	lz = -bl * 0.5 + 0.6
	while lz <= bl * 0.5 - 0.6:
		var vy := _deck_vis(0.137, lz)
		if not is_nan(vy):
			for sx: float in [-1.0, 1.0]:
				for hh: float in [0.5, 1.0]:
					rn += 1
					var a := xf * Vector3(0.0, vy + hh, lz)
					var b := xf * Vector3(sx * (xr + 1.0), vy + hh, lz)
					var d := _col_dist(a, b)
					if d == INF or d > xr + 0.20:
						rbad += 1
						rex = "z %.1f %s側 離橋面 %.1f m" % [lz, "右" if sx > 0 else "左", hh]
		lz += 1.0
	_res("collision", rn > 0 and rbad == 0, "欄杆擋得住：橋面上 0.5／1.0 m 往兩側 %d 條射線，在 x ±%.2f 內打到碰撞的 %d 條%s" % [
		rn, xr + 0.20, rn - rbad, ("；✗ " + rex) if rex != "" else ""])


func _c_collision_walk(xf: Transform3D) -> void:
	# 膠囊：入口站得住、台基內進不去、步行帶走得過
	var e := xf * Vector3(float(gs["entry"][0]), 0, float(gs["entry"][1]))
	var e_hit := _capsule_hits_hero(Vector3(e.x, _ground(e.x, e.z), e.z))
	var ins := xf * Vector3(float(gs["inside"][0]), 0, float(gs["inside"][1]))
	var i_hit := _capsule_hits_hero(Vector3(ins.x, xf.origin.y + 0.4, ins.z))
	var wk: Dictionary = gs["walkway"]
	var rc: Array = wk["rect"]
	var x0 := float(rc[0]) + CAP_R
	var x1 := float(rc[2]) - CAP_R
	var z0 := float(rc[1]) + CAP_R
	var z1 := float(rc[3]) - CAP_R
	if z1 < z0:
		z0 = (float(rc[1]) + float(rc[3])) * 0.5
		z1 = z0
	if x1 < x0:
		x0 = (float(rc[0]) + float(rc[2])) * 0.5
		x1 = x0
	var stp := float(wk["step"])
	var n_w := 0
	var blocked := 0
	var b_ex := ""
	var min_clear := INF
	var head_bad := 0
	var lx := x0
	while lx <= x1 + 0.001:
		var lz := z0
		while lz <= z1 + 0.001:
			var w := xf * Vector3(lx, 0, lz)
			var gy := _ground(w.x, w.z)
			n_w += 1
			if _capsule_hits_hero(Vector3(w.x, gy, w.z)):
				blocked += 1
				b_ex = "(%.2f, %.2f)" % [lx, lz]
			var gl := gy - xf.origin.y
			var up := _vis_dist(Vector3(lx, gl + 0.05, lz), Vector3(lx, gl + 30.0, lz), _tris_at(lx, lz)) + 0.05
			min_clear = minf(min_clear, up)
			if up < float(wk["head"]):
				head_bad += 1
			lz += maxf(stp, 0.05) if z1 > z0 else 1.0
		lx += stp
	_res("collision", not e_hit and i_hit and blocked == 0, "膠囊 r %.1f／h %.1f：入口站點%s碰撞、台基內%s擋住、步行帶 %d 點被擋 %d%s" % [
		CAP_R, CAP_H, "無" if not e_hit else "✗有", "有" if i_hit else "✗沒", n_w, blocked,
		("（例 " + b_ex + "）") if b_ex != "" else ""])
	_res("collision", head_bad == 0 and min_clear >= float(wk["min_clear"]),
		"步行帶頭頂淨空：%d 點中 %d 點 < %.2f m；最低淨空 %.2f m（≥ %.2f）" % [n_w, head_bad, wk["head"], min_clear, wk["min_clear"]])


func _c_collision_poke(xf: Transform3D) -> void:
	# 周邊射線：可見網格不可比碰撞面突出 > POKE_TOL（三個高度，四個方向）
	var ab: AABB = _lod_aabb(0)
	var rays := 0
	var poke := 0
	var worst := 0.0
	var w_ex := ""
	var R0 := 3.0
	for side in 4:
		var along_z := side < 2
		var sgn := 1.0 if side % 2 == 0 else -1.0
		var lo := ab.position.x if along_z else ab.position.z
		var hi := ab.end.x if along_z else ab.end.z
		var s := lo + 0.05
		while s <= hi:
			var outer := (ab.end.z + R0 if sgn > 0 else ab.position.z - R0) if along_z else (ab.end.x + R0 if sgn > 0 else ab.position.x - R0)
			var inner := 0.0
			var edge := Vector3(s, 0, outer) if along_z else Vector3(outer, 0, s)
			var we := xf * edge
			# 地形高（terrain_only）：外側起點落在鄰棟碰撞頂上時（P6 aux 與鄰家牆距 < 0.5 m），不可把鄰家屋頂當地面
			var gl := _ground(we.x, we.z, true) - xf.origin.y
			if is_nan(gl):
				s += 0.2
				continue
			var tris := _tris_along_z(s) if along_z else _tris_along_x(s)
			# 玩家膠囊是 0–1.7 m 的直立柱：這一列上任何高度的碰撞面先擋到身體，就碰不到後面的網格
			var dc := INF
			for ch: float in [0.3, 0.6, 1.0, 1.3, 1.6]:
				var ca := Vector3(s, gl + ch, outer) if along_z else Vector3(outer, gl + ch, s)
				var cb := Vector3(s, gl + ch, inner) if along_z else Vector3(inner, gl + ch, s)
				dc = minf(dc, _col_dist(xf * ca, xf * cb))
			for hh: float in [0.3, 1.0, 1.6]:
				var y: float = gl + hh
				var a := Vector3(s, y, outer) if along_z else Vector3(outer, y, s)
				var b := Vector3(s, y, inner) if along_z else Vector3(inner, y, s)
				var dv := _vis_dist(a, b, tris)
				if dv == INF:
					continue
				# 命中點在玩家膠囊頂（離該處地面 1.7 m）以上＝屋簷／瓦頂懸挑，身體碰不到（P6 稗田邸圍牆：沿牆擦過的簷口列）
				var hp: Vector3 = xf * (a + (b - a).normalized() * dv)
				var gh := _ground(hp.x, hp.z, true)
				if not is_nan(gh) and hp.y - gh > 1.7:
					continue
				rays += 1
				var d := (dc - dv) if dc != INF else absf(outer - inner) - dv
				if d > POKE_TOL:
					poke += 1
					if d > worst:
						worst = d
						w_ex = "%s 面 %s=%.2f 高 %.1f 突出 %.2f m" % [["前", "後", "右", "左"][side], "x" if along_z else "z", s, hh, d]
			s += 0.2
	_res("collision", rays > 0 and poke == 0, "周邊 %d 條射線（離地 0.3／1.0／1.6 m；碰撞取同一列 0.3–1.6 m 最先擋到身體處）：可見網格比碰撞面突出 > %.2f m 的 %d 條%s" % [
		rays, POKE_TOL, poke, ("，最大 " + w_ex) if w_ex != "" else ""])


## 8 LOD
func _c_lod() -> void:
	var ranges: Array = S["lod_ranges_m"]
	var ok := true
	var lines: Array = []
	var t := []
	var ab0: AABB
	for li in 3:
		var mi := hero.get_node_or_null("LOD%d" % li) as MeshInstance3D
		if mi == null:
			ok = false
			lines.append("缺 LOD%d" % li)
			continue
		for rm: MeshInstance3D in _lod_mis(li).slice(1):   # 轉動部件：距離與本體同級
			if not is_equal_approx(rm.visibility_range_begin, mi.visibility_range_begin) or not is_equal_approx(rm.visibility_range_end, mi.visibility_range_end):
				ok = false
				lines.append("%s 距離與本體 LOD%d 不同" % [rm.get_path(), li])
		var n := _lod_faces(li).size() / 3
		t.append(n)
		var b := mi.visibility_range_begin
		var e := mi.visibility_range_end
		if not is_equal_approx(b, float(ranges[li])) or not is_equal_approx(e, float(ranges[li + 1])):
			ok = false
			lines.append("LOD%d 距離 %.0f–%.0f ≠ 規格 %s–%s" % [li, b, e, ranges[li], ranges[li + 1]])
		if li > 0:
			var prev := hero.get_node("LOD%d" % (li - 1)) as MeshInstance3D
			if not is_equal_approx(prev.visibility_range_end, b):
				ok = false
				lines.append("LOD%d–%d 距離不相接（%.1f vs %.1f）" % [li - 1, li, prev.visibility_range_end, b])
			var ab := _lod_aabb(li)
			var dp := (ab.position - ab0.position).abs()
			var de := (ab.end - ab0.end).abs()
			var dmax := maxf(maxf(dp.x, maxf(dp.y, dp.z)), maxf(de.x, maxf(de.y, de.z)))
			if dmax > 0.25:
				ok = false
				lines.append("LOD%d 外框與 LOD0 差 %.2f m" % [li, dmax])
		else:
			ab0 = _lod_aabb(0)
	var bud: Dictionary = S["budget"]
	if t.size() == 3:
		var r1 := float(t[1]) / float(t[0])
		var r2 := float(t[2]) / float(t[0])
		if not (t[0] > t[1] and t[1] > t[2]) or r1 > float(bud["lod1_ratio"]) + 1e-6 or r2 > float(bud["lod2_ratio"]) + 1e-6:
			ok = false
		lines.append("面數 %d → %d（%.1f %%，≤ %.0f %%）→ %d（%.1f %%，≤ %.0f %%）" % [t[0], t[1], r1 * 100.0,
			float(bud["lod1_ratio"]) * 100.0, t[2], r2 * 100.0, float(bud["lod2_ratio"]) * 100.0])
	# 最後一級：涵蓋到地圖框四角（離開最遠處也不會突然消失）
	var F: Dictionary = L["frame"]
	var o := _xf().origin
	var far := 0.0
	for c in [Vector2(F["x0"], F["z0"]), Vector2(F["x1"], F["z0"]), Vector2(F["x0"], F["z1"]), Vector2(F["x1"], F["z1"])]:
		far = maxf(far, Vector2(o.x, o.z).distance_to(c))
	var last := float(ranges[3])
	if last != 0.0 and last < far:
		ok = false
	lines.append("距離 %s m、最後一級 %s（地圖框最遠 %.0f m）" % [ranges, "不裁切" if last == 0.0 else "%.0f m" % last, far])
	_res("lod", ok, "；".join(lines))


## 9 效能
func _c_perf() -> void:
	var cls := String(S["budget_class"])
	var cap := int(BUDGET_LOD0.get(cls, 0))
	var t0 := f0.size() / 3
	var bud: Dictionary = S["budget"]
	var surf := 0
	for li in 3:
		var used_s := {}
		for mi: MeshInstance3D in _lod_mis(li):
			for si in mi.mesh.get_surface_count():
				used_s[mi.mesh.surface_get_material(si)] = true
		surf = maxi(surf, used_s.size())   # 每級材質數（轉動部件與本體共用材質：draw call 仍 ≤ 材質數×節點數）
	var shapes := hero.find_children("*", "CollisionShape3D", true, false).size()
	# 貼圖 VRAM 估算（DXT1/BC1 0.5 B/px；BC3/BC7/法線 1 B/px；mip ×1.33）
	var own_mb := 0.0
	var shared_mb := 0.0
	var seen := {}
	for li in 3:
		for mi: MeshInstance3D in _lod_mis(li):
			for si in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(si) as StandardMaterial3D
				if m == null:
					continue
				for prop in ["albedo_texture", "normal_texture", "roughness_texture", "emission_texture"]:
					var t := m.get(prop) as Texture2D
					if t == null or seen.has(t.resource_path):
						continue
					seen[t.resource_path] = true
					var bpp := 1.0 if (prop == "normal_texture" or t.resource_path.ends_with(".png")) else 0.5
					var mb := t.get_width() * t.get_height() * bpp * 1.333 / 1048576.0
					if t.resource_path.begins_with(V2_DIR + "_matlib/"):
						shared_mb += mb
					else:
						own_mb += mb
	_res("performance", int(bud["lod0"]) == cap and t0 <= cap and surf <= MAX_MATS and shapes <= MAX_SHAPES and own_mb <= 8.0,
		"§14.8「%s」LOD0 上限 %d（asset.json 自報 %d）：實測 %d（%.0f %%）；每級 surface ≤ %d（實測 %d）；碰撞 %d ≤ %d；貼圖 VRAM 估算：本資產專屬 %.1f MB（≤ 8）、共用材質庫 %.1f MB（全村共用一次）" % [
			cls, cap, bud["lod0"], t0, 100.0 * t0 / maxf(1.0, cap), MAX_MATS, surf, shapes, MAX_SHAPES, own_mb, shared_mb])


# ─────────────────────────── render 10–11 ───────────────────────────

func _render(id: String, out: String) -> void:
	if not _load_spec(id):
		return
	if DisplayServer.get_name() == "headless":
		_p("FAIL --render 需要 GPU 視窗（不能 --headless）")
		fails += 1
		return
	if out == "":
		out = ProjectSettings.globalize_path("user://hero_gate")
	DirAccess.make_dir_recursive_absolute(out)
	logger = GateLogger.new()
	OS.add_logger(logger)
	# ── F6：資產單獨場景
	var e0 := logger.errors.size()
	var f6 := Node3D.new()
	root.add_child(f6)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	f6.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	f6.add_child(env)
	var inst := (load(String(S["scene"])) as PackedScene).instantiate() as Node3D
	f6.add_child(inst)
	var ab: AABB = _lod_aabb(0, inst)
	var cam := Camera3D.new()
	f6.add_child(cam)
	var rad := ab.size.length() * 0.9
	cam.look_at_from_position(ab.get_center() + Vector3(0.55, 0.35, 1.0).normalized() * rad, ab.get_center())
	cam.current = true
	for i in 120:
		await process_frame
	var f6_png := out.path_join("%s_f6.png" % id)
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
	v = main.map_root
	hero = HLib.place(v, S, load(String(S["scene"])) as PackedScene, false)
	anchor = hero.get_parent() as Node3D
	var baked: bool = hero.owner == v
	await physics_frame
	await physics_frame
	space = v.get_world_3d().direct_space_state
	hero_rid = (hero.get_node("Collision") as CollisionObject3D).get_rid()
	terrain_rid = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var dbg: Node = v.get_node_or_null("Debug")
	if dbg:
		dbg.visible = false
	var player: CharacterBody3D = main.player
	player_rid = player.get_rid()
	var shot_lines: Array = []
	var shot_ok := true
	var perf: Array = []
	var walk_ok := true
	var walk_lines: Array = []
	var n_shots := 0
	# gate_spec.instances（R4 水車起）：每個放置點各拍、各走；單一放置的資產只跑一輪（R1–R3 行為不變）
	var gss := HLib.instances(S)
	for gi in gss.size():
		if gi > 0:
			gs = gss[gi]
			hero = HLib.place(v, S, load(String(S["scene"])) as PackedScene, false, gi)
			anchor = hero.get_parent() as Node3D
			baked = baked and hero.owner == v
			await physics_frame
			hero_rid = (hero.get_node("Collision") as CollisionObject3D).get_rid()
		var res := await _render_one(player, id, out, gss.size() > 1)
		shot_ok = shot_ok and res[0]
		shot_lines.append_array(res[1])
		perf.append_array(res[2])
		n_shots += int(res[3])
		walk_ok = walk_ok and res[4]
		walk_lines.append(res[5])
	var rot := await _rotor_check()
	_res("player_screenshot", shot_ok and n_shots >= 3 * gss.size(), "main.tscn 載 village_v2（Hero %s）、玩家鏡頭 %d 張：%s" % [
		"已烘焙在場景" if baked else "執行期以產生器同一段放置", n_shots, "；".join(shot_lines)])
	if neg == "error":
		push_error("反向測試：刻意的錯誤")
	var f5_err := logger.errors.size() - e1
	var errs: Array = logger.errors.slice(0, 3)
	_res("f5_f6", f6_err == 0 and f5_err == 0 and walk_ok and rot[0], "F6（資產單獨場景 120 幀）錯誤 %d；F5（main.tscn → village_v2、%d 張鏡位＋實走）錯誤 %d、警告 %d；%s%s%s" % [
		f6_err, n_shots, f5_err, logger.warnings.size(), "；".join(walk_lines), rot[1], ("；錯誤例：" + " | ".join(errs)) if errs else ""])
	OS.remove_logger(logger)
	_flush(RENDER_KEYS, id)
	if neg == "":
		_write_gate(id, "render", RENDER_KEYS, String(S["scene"]),
			{"render_info": {"f6_png": f6_png.get_file(), "perf": perf, "warnings": logger.warnings.slice(0, 10),
				"renderer": RenderingServer.get_current_rendering_method()}})
	_p("F6 截圖 %s；效能（畫面內總量，非本資產）：%s" % [f6_png, "；".join(perf)])


## 轉動部件（asset.json rotors）：F5 實際跑 1 秒，量 rotor 節點角度變化 ≈ 2π／period_s（±25 %）
func _rotor_check() -> Array:
	var rts: Array = S.get("rotors", [])
	if rts.is_empty():
		return [true, ""]
	var lines: Array = []
	var ok := true
	for rt: Dictionary in rts:
		var rn := hero.get_node_or_null(String(rt["name"])) as Node3D
		var ap := hero.get_node_or_null("RotorAnim") as AnimationPlayer
		if rn == null or ap == null:
			ok = false
			lines.append("✗ 缺 %s 或 RotorAnim" % rt["name"])
			continue
		if neg == "nospin":
			ap.stop()   # 反向測試：輪子不轉 → f5_f6 必須 FAIL
		var ax := String(rt["axis"])
		var a0: float = rn.rotation[ax]
		var t0 := Time.get_ticks_msec()
		for i in 60:
			await process_frame
		var dt := (Time.get_ticks_msec() - t0) / 1000.0
		var da := absf(wrapf(float(rn.rotation[ax]) - a0, -PI, PI))
		var want := TAU / float(rt["period_s"]) * dt
		var r_ok := ap.is_playing() and ap.current_animation == "spin" and absf(da - want) <= want * 0.25
		ok = ok and r_ok
		lines.append("%s轉動：%s 在 %.2f s 內轉 %.1f°（應 %.1f°，一圈 %.0f s；AnimationPlayer %s 播 spin）" % [
			"" if r_ok else "✗ ", rt["name"], dt, rad_to_deg(da), rad_to_deg(want), float(rt["period_s"]),
			"正在" if ap.is_playing() else "沒有"])
	return [ok, "；" + "；".join(lines)]


## 單一放置點的玩家鏡位＋實走。回傳 [鏡位全過, 鏡位說明, 效能, 張數, 實走過, 實走說明]
func _render_one(player: CharacterBody3D, id: String, out: String, tag: bool) -> Array:
	var xf := hero.global_transform
	var center := xf * _lod_aabb(0).get_center()
	var shots := _shot_spots(xf)
	var shot_lines: Array = []
	var shot_ok := true
	var perf: Array = []
	var pre := (String(gs["anchor"]).get_file() + "_") if tag else ""
	for s: Array in shots:
		var p: Vector3 = s[1]
		var tgt: Vector3 = s[2] if s.size() > 2 else center
		var gy := _ground(p.x, p.z)
		player.global_position = Vector3(p.x, gy + 0.05, p.z)
		player.velocity = Vector3.ZERO
		var d := Vector2(tgt.x - p.x, tgt.z - p.z)
		player.snap_yaw(atan2(-d.x, -d.y))
		for i in 75:
			await process_frame
		var img := root.get_texture().get_image()
		var png := out.path_join("%s_%s%s.png" % [id, pre, s[0]])
		img.save_png(png)
		var c3 := root.get_viewport().get_camera_3d()
		var sd := _img_std(img)
		var in_frame := c3 != null and not c3.is_position_behind(tgt) \
			and Rect2(Vector2.ZERO, Vector2(img.get_size())).has_point(c3.unproject_position(tgt))
		var occ := ""
		if c3 != null:
			var q := PhysicsRayQueryParameters3D.create(c3.global_position, tgt)
			q.exclude = [player.get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and hit["rid"] != hero_rid:
				occ = String((hit["collider"] as Node).name)
		var ok := sd > 0.03 and in_frame and occ == ""
		shot_ok = shot_ok and ok
		shot_lines.append("%s%s（亮度標準差 %.3f、%s、%s）" % ["" if ok else "✗ ", png.get_file(), sd,
			"資產在畫面內" if in_frame else "資產不在畫面內", "鏡頭到資產無遮擋" if occ == "" else "被 %s 擋" % occ])
		perf.append("%s%s：%d 三角面／%d draw call" % [pre, s[0],
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	# F5 實走：朝資產走 4 秒 → 必須被碰撞擋在外面（鳥居：穿過去）
	var walk := await _walk(player, xf)
	return [shot_ok and shots.size() >= 3, shot_lines, perf, shots.size(), walk[0], pre + String(walk[1])]


## 玩家鏡位：[名稱, 世界 XZ（Vector3，y 由地面決定）]
func _shot_spots(xf: Transform3D) -> Array:
	var out: Array = []
	if gs.has("shots"):
		# 資產自訂鏡位（局部 xz）：R4 龍神像／水車／參道鳥居；R5 山頂社殿（建築，但正面下坡、兩側是北丘林）、火見櫓（市場內）
		for s: Array in gs["shots"]:
			# 第 4、5 欄（P6 稗田邸圍牆起）：看向的局部 xz（離原點 1.2 m 高）；沒有＝看 LOD0 外框中心
			if s.size() >= 5:
				out.append([s[0], xf * Vector3(float(s[1]), 0, float(s[2])), xf * Vector3(float(s[3]), 1.2, float(s[4]))])
			else:
				out.append([s[0], xf * Vector3(float(s[1]), 0, float(s[2]))])
	elif not _bld().is_empty():
		var zf := float(_bld()["zf"])
		for s in [["front", 0.0, 9.0], ["front_l", 28.0, 12.0], ["front_r", -28.0, 12.0], ["street_far", 55.0, 26.0]]:
			var dir := Vector3(sin(deg_to_rad(float(s[1]))), 0, cos(deg_to_rad(float(s[1]))))
			out.append([s[0], xf * (Vector3(0, 0, zf) + dir * _clear_dist(xf, zf, dir, float(s[2])))])
	else:
		for s in [["south", 0.0, 16.0], ["north", 180.0, 14.0], ["south_far", 0.0, 34.0]]:
			var dir := Vector3(sin(deg_to_rad(float(s[1]))), 0, cos(deg_to_rad(float(s[1]))))
			out.append([s[0], xf * (dir * float(s[2]))])
	return out


## 斜向鏡位在窄街上會越過對街、連同後方 3P 相機（約 4.5 m）一起塞進對面建築 → 畫面被別棟屋頂整片擋住（R2 鯢吞亭 front_l）。
## 從正面 1 m 外、離地 1.6 m 沿視線方向打射線（排除本資產、玩家、地形），把距離縮到「擋到的地方 − 5 m」，下限 5 m。
func _clear_dist(xf: Transform3D, zf: float, dir: Vector3, want: float) -> float:
	if space == null:
		return want
	var a := xf * (Vector3(0, 1.6, zf + 1.0))
	var b := xf * (Vector3(0, 1.6, zf + 1.0) + dir * (want + 5.0))
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = [hero_rid, player_rid, terrain_rid]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return want
	# 鏡頭在玩家後方 SpringArm 5 m；SpringArm 只躲碰撞體，對面屋簷（無碰撞、出簷 1–1.5 m）會蓋住鏡頭
	# → 擋點往回退 arm 5 m＋屋簷餘裕 3 m（R3 寺子屋 front_l／street_far 鏡頭鑽進對街屋簷下）
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


## F5 實走：建築＝從正面 3 m 朝台基走 4 秒，結束時不在台基內、腳下離地 ≤ 0.3；鳥居＝從南 12 m 走到北 10 m。
func _walk(player: CharacterBody3D, xf: Transform3D) -> Array:
	var start: Vector3
	var goal: Vector3
	var bd := _bld()
	var wk: Dictionary = gs.get("walk", {})
	if not wk.is_empty():
		# 資產自訂實走（R4 龍神像／水車）：from → to 走 4 秒，結束時不得在 box（局部 x0,z0,x1,z1）內
		start = xf * Vector3(float(wk["from"][0]), 0, float(wk["from"][1]))
		goal = xf * Vector3(float(wk["to"][0]), 0, float(wk["to"][1]))
		bd = {"box": wk["box"]} if wk.has("box") else {"cross": true}
	elif not bd.is_empty():
		start = xf * Vector3(0.9, 0, float(bd["zf"]) + 3.0)
		goal = xf * Vector3(0.9, 0, 0)
	else:
		start = xf * Vector3(0, 0, 12.0)
		goal = xf * Vector3(0, 0, -10.0)
	player.global_position = Vector3(start.x, _ground(start.x, start.z) + 0.05, start.z)
	player.velocity = Vector3.ZERO
	for i in 20:
		await physics_frame
	var max_gap := 0.0
	var t0 := Time.get_ticks_msec()
	var crossing := bd.has("cross")   # P7 R2 橋：from → to 走過橋面（腳下是橋碰撞，不是河床）
	var min_y := INF
	Input.action_press("move_forward")
	for f in 60 * (16 if crossing else 8):   # 龍神橋 52 m／步行約 4 m/s → 8 秒不夠
		var p := player.global_position
		var d := Vector2(goal.x - p.x, goal.z - p.z)
		if d.length() < 1.5:
			break
		if f % 6 == 0:
			player.snap_yaw(atan2(-d.x, -d.y))
		await physics_frame
		if f % 20 == 0:
			var g := _ground(p.x, p.z)
			if crossing:
				var ht := _hero_top(p.x, p.z)
				if not is_nan(ht) and (is_nan(g) or ht > g):
					g = ht
				min_y = minf(min_y, p.y)
			if not is_nan(g):
				max_gap = maxf(max_gap, absf(player.global_position.y - g))
		if not crossing and not bd.is_empty() and Time.get_ticks_msec() - t0 > 4000:
			break
	Input.action_release("move_forward")
	for i in 6:
		await physics_frame
	var lp := _to_local(player.global_position)
	if crossing:
		var gz := _to_local(goal).z
		var floor_y := minf(_ground(start.x, start.z), _ground(goal.x, goal.z)) - 0.5
		var okc := absf(lp.z - gz) < 2.0 and max_gap <= 0.35 and min_y >= floor_y
		return [okc, "實走：局部 z %.1f → %.1f 過橋，到達局部 (%.2f, %.2f)（%s）、最大離腳下面 %.2f m、最低 y %.2f（≥ 兩端路面低者 −0.5 = %.2f，沒掉進水道）" % [
			float(wk["from"][1]), float(wk["to"][1]), lp.x, lp.z, "過橋" if absf(lp.z - gz) < 2.0 else "✗ 沒走過去",
			max_gap, min_y, floor_y]]
	if bd.has("box"):
		var bx: Array = bd["box"]
		var ins := lp.x > float(bx[0]) + 0.05 and lp.x < float(bx[2]) - 0.05 and lp.z > float(bx[1]) + 0.05 and lp.z < float(bx[3]) - 0.05
		var okb := not ins and max_gap <= 0.35
		return [okb, "實走：局部 (%.1f, %.1f) → (%.1f, %.1f) 走 4 秒，停在局部 (%.2f, %.2f)（%s）、最大離地 %.2f m" % [
			float(wk["from"][0]), float(wk["from"][1]), float(wk["to"][0]), float(wk["to"][1]), lp.x, lp.z,
			"✗ 穿進資產" if ins else "被擋在外", max_gap]]
	if not bd.is_empty():
		var hw := float(bd["w"]) * 0.5
		var hd := float(bd["d"]) * 0.5
		var inside := absf(lp.x) < hw - 0.05 and absf(lp.z) < hd - 0.05
		var ok := not inside and max_gap <= 0.35
		return [ok, "實走：正面 3 m 外朝台基走 4 秒，停在局部 z %.2f（牆面 %.2f，%s）、最大離地 %.2f m" % [
			lp.z, hd, "✗ 穿進建築" if inside else "被擋在外", max_gap]]
	var ok2 := lp.z < -8.0 and max_gap <= 0.35
	return [ok2, "實走：南 12 m → 北 10 m 穿過鳥居，到達局部 z %.2f（%s）、最大離地 %.2f m" % [
		lp.z, "穿過" if ok2 else "✗ 沒穿過", max_gap]]


# ─────────────────────────── 材質庫 ───────────────────────────

func _matlib() -> void:
	var ML: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MATLIB))
	var lic_bad: Array = []
	var size_bad: Array = []
	var vram_bad: Array = []
	var tres_bad: Array = []
	var n_tex := 0
	var k := float(ML["albedo_k"])
	for name: String in ML["materials"]:
		var e: Dictionary = ML["materials"][name]
		var src: Dictionary = e.get("source", {})
		if String(src.get("license", "")) != "CC0" or String(src.get("url", "")) == "":
			lic_bad.append(name)
		var km := float(e.get("albedo_k", k))
		var m := load(String(e["tres"])) as StandardMaterial3D
		if m == null or m.resource_name != name or not m.albedo_color.is_equal_approx(Color(km, km, km, 1.0)) \
				or not m.vertex_color_use_as_albedo or m.albedo_texture == null or m.normal_texture == null \
				or m.roughness_texture == null:
			tres_bad.append(name)
		for slot: String in e["files"]:
			var t := load(String(e["files"][slot])) as Texture2D
			n_tex += 1
			if t == null:
				size_bad.append("%s 讀不到" % e["files"][slot])
				continue
			if t.get_width() != TEX_MAX or t.get_height() != TEX_MAX:
				size_bad.append("%s %d×%d" % [t.resource_path.get_file(), t.get_width(), t.get_height()])
			var err := _tex_check(t, slot == "normal")
			if err != "":
				vram_bad.append(err)
	# P7 地面材質（matlib.json ground 段）：各層 CC0＋原檔雜湊；兩張 Texture2DArray 層數＝登記層數、
	# 每層 ≤ TEX_MAX 且 2 的次方（albedo 須＝TEX_MAX）；VRAM 壓縮；shader 可載入且 uniform 齊全。
	if ML.has("ground"):
		var G: Dictionary = ML["ground"]
		var nl: int = (G["layers"] as Array).size()
		for lname: String in G["layers"]:
			var li: Dictionary = G["layer_info"].get(lname, {})
			var ls: Dictionary = li.get("source", {})
			if String(ls.get("license", "")) != "CC0" or String(ls.get("url", "")) == "" or (ls.get("sha256", {}) as Dictionary).is_empty():
				lic_bad.append("ground/" + lname)
		if String(G["noise"].get("license", "")) != "CC0":
			lic_bad.append("ground/noise")
		for key: String in G["arrays"]:
			var ta := load(String(G["arrays"][key])) as TextureLayered
			n_tex += 1
			if ta == null:
				size_bad.append("%s 讀不到" % G["arrays"][key])
				continue
			var tw := ta.get_width()
			var th := ta.get_height()
			if ta.get_layers() != nl:
				size_bad.append("%s 層數 %d（登記 %d）" % [String(G["arrays"][key]).get_file(), ta.get_layers(), nl])
			if tw > TEX_MAX or th > TEX_MAX or tw & (tw - 1) != 0 or th & (th - 1) != 0 or (key == "albedo" and tw != TEX_MAX):
				size_bad.append("%s %d×%d" % [String(G["arrays"][key]).get_file(), tw, th])
			var err := _layered_check(String(G["arrays"][key]))
			if err != "":
				vram_bad.append(err)
		var nt := load(String(G["noise"]["path"])) as Texture2D
		n_tex += 1
		if nt == null:
			size_bad.append("%s 讀不到" % G["noise"]["path"])
		else:
			var err := _tex_check(nt, false)
			if err != "":
				vram_bad.append(err)
		var sh := load(String(G["shader"])) as Shader
		if sh == null:
			tres_bad.append("ground.gdshader 讀不到")
		else:
			var names := {}
			for u: Dictionary in sh.get_shader_uniform_list():
				names[String(u["name"])] = true
			for need in ["albedo_arr", "nrh_arr", "noise_tex", "ground_k", "mode", "use_vertex_weights"]:
				if not names.has(need):
					tres_bad.append("ground.gdshader 缺 uniform %s" % need)
			if not sh.get_code().contains("ground_k = %s" % String.num(float(G["albedo_k"]))):
				tres_bad.append("ground.gdshader ground_k 與 matlib.json albedo_k（%s）不一致" % G["albedo_k"])
		# 產物雜湊（shader／兩張 array／雜訊）：手改任何一個都不得 PASS
		var fsha: Dictionary = G.get("files_sha256", {})
		if fsha.is_empty():
			tres_bad.append("ground 缺 files_sha256")
		for fp: String in fsha:
			if FileAccess.get_sha256(fp) != String(fsha[fp]):
				tres_bad.append("%s 雜湊與 matlib.json 不符" % fp.get_file())
	var n_mat_tex := n_tex
	var ground_note := ""
	if ML.has("ground"):
		ground_note = "；地面 %d 層（CC0）：Texture2DArray %d 張（albedo %d²、nrh %d²）＋雜訊 %d²" % [
			(ML["ground"]["layers"] as Array).size(), (ML["ground"]["arrays"] as Dictionary).size(),
			int(ML["ground"]["size"]["albedo"]), int(ML["ground"]["size"]["nrh"]), int(ML["ground"]["noise"]["size"])]
		n_mat_tex = n_tex - (ML["ground"]["arrays"] as Dictionary).size() - 1
	R.clear()
	_res("license", lic_bad.is_empty(), "%d 組材質來源全是 Poly Haven CC0 且有 URL／原檔雜湊%s%s" % [ML["materials"].size(),
		ground_note, ("；✗ " + "、".join(lic_bad)) if lic_bad else ""])
	_res("texture_size", size_bad.is_empty(), "%d 張材質貼圖全是 %d²%s%s" % [n_mat_tex, TEX_MAX, ground_note,
		("；✗ " + "、".join(size_bad)) if size_bad else ""])
	_res("vram_compressed", vram_bad.is_empty(), "全部 VRAM 壓縮（法線標 normal_map）、匯入檔存在%s" % [
		("；✗ " + "、".join(vram_bad.slice(0, 4))) if vram_bad else ""])
	_res("tres_valid", tres_bad.is_empty(), ".tres 可載入、albedo_k＝材質庫登記值（預設 %.2f）、頂點色、三張貼圖齊全%s" % [k,
		("；✗ " + "、".join(tres_bad)) if tres_bad else ""])
	_flush(MATLIB_KEYS, "_matlib")
	var path := V2_DIR + "_matlib/gate.json"
	var checks := {}
	for kk in MATLIB_KEYS:
		checks[kk] = {"result": R[kk]["result"], "detail": R[kk]["detail"], "date": Time.get_datetime_string_from_system()}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"asset": "_matlib", "entry": MATLIB, "entry_sha256": FileAccess.get_sha256(MATLIB),
		"godot": Engine.get_version_info()["string"], "checks": checks}, " ", false) + "\n")
	f.close()
	_p("寫入 " + path)


# ─────────────────────────── 回歸 ───────────────────────────

func _all() -> void:
	var reg := HLib.registry()
	var n := 0
	for a: Dictionary in reg.get("v2_assets", []):
		if String(a.get("kind", "")) in ["material_library", "kit"]:   # kit 由 verify_village_v2_machiya_kit_gate.gd --regress 重驗
			continue
		n += 1
		R.clear()
		await _headless(String(a["id"]), false)
		var gj: Variant = JSON.parse_string(FileAccess.get_file_as_string(_gate_path(String(a["id"]))))
		var same := gj is Dictionary and String(gj.get("entry_sha256", "")) == FileAccess.get_sha256(String(a["entry"]))
		print("[HERO] %s %s：gate.json 與目前 .scn 雜湊%s" % ["PASS" if same else "FAIL", a["id"], "一致" if same else "不一致"])
		if not same:
			fails += 1
	print("[HERO] v2_assets hero／landmark %d 件重驗完成" % n)
