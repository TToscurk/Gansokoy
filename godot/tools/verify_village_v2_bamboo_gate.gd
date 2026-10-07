extends SceneTree
## 人間之里 V2 P9 R3：竹 Kit（bamboo_kit）Asset Gate（11 項，與植被庫／Hero／町家／河岸 Kit Gate 同名同義）。
##   headless 1–9：godot --headless --path . --script res://tools/verify_village_v2_bamboo_gate.gd [-- --neg=<案例>｜--negatives]
##   render 10–11：godot --rendering-method forward_plus --path . --resolution 1600x900 --script res://tools/verify_village_v2_bamboo_gate.gd -- --render
## entry＝assets/village_v2/bamboo_kit/bamboo_kit_manifest.json（mesh／材質／貼圖／竹 prefab＋共用 veg shader 全部 sha256）；
## gate.json 記 entry 雜湊，任何一檔改動 → gate 失效。R1 植被庫 gate（verify_village_v2_veg_gate.gd）已封存不動，本檔另立。
## R3 竹 Kit 先獨立審圖（規格 §31.10：Asset Gate → ART_REVIEW → 核准後才放進西林與村緣）：地塊（2）與 F5 實走（11）
## 在正式擺放時才有對象，本 gate 驗審圖場景的對應項並明寫範圍。視覺只到 ART_REVIEW，ART_APPROVED 只有使用者能給。
##   1 尺寸     LOD0 AABB 高＝Blender 設計高（±2 %）、寬（±5 %）；竹稈高 6–20 m、筍 0.15–0.8 m；
##              稈徑（dbh）依種別：細 3–7 cm、成竹 7–12 cm、孟宗 12–20 cm（真竹／淡竹／孟宗實際徑級）
##   2 地塊     審圖場景 Live 列外框（XZ 內縮 15 %）不互穿；試作竹林稈距 ≥ 0.45 m（不疊稈）
##   3 接地     pivot＝稈基：碰撞圓柱底離原點 ≤ 0.05 m；最低頂點 −0.5～+0.03（稈只淺埋、不浮）；
##              無自帶土台：貼地 ≤ 0.15 m 朝上水平面 ≤ 0.2 m²（落葉地被另計：只能有卡片、最高 ≤ 0.05 m）
##   4 材質     只用 bamboo_kit/mat/BK_*.tres（ShaderMaterial、veg shader）；無 override；貼圖 ≤ 2K、VRAM 壓縮
##   5 幾何     無退化／NaN；有法線、UV、UV2（風∈[0,1]）、頂點色；風分層：稈平均 < 葉卡平均；竹有獨立 sway（材質 wind_speed ≠ 樹）
##   6 Pivot    prefab 根與 LOD 節點 transform＝identity（縮放 1）
##   7 碰撞     竹稈＝1 根圓柱（半徑 0.4–0.75×稈徑、可走過稈間）；筍／落葉 0；禁 trimesh；膠囊中心撞、半徑＋0.4 m 外不撞
##   8 LOD      竹稈 4 級／筍與落葉 3 級；LOD1 25–50 %、LOD2 6–20 %（≥ 6 面）；高度差 ≤ 8 %；換檔帶首尾相接
##   9 效能     LOD0 ≤ 類別上限（竹稈 4000／筍 500／落葉 200；竹林是數百稈群植，上限低於一般林 6000）；每級 surface ≤ 2；
##              Kit 貼圖 VRAM ≤ 32 MB
##  10 截圖     審圖截圖齊全（每稈 near／mid／up／top／lods，筍與落葉 near／top／lods，竹林 9 視角）且非空白（亮度標準差 > 0.03）
##  11 F6      審圖場景（含試作竹林）相機穿越 120 幀、Logger 錯誤 0（F5 實走＝核准後正式擺放）
## 反向案例（--neg，不寫 gate.json，預期對應項 FAIL）：slab（LOD0 加 3×3 m 土台）、lod（刪 LOD2）、collision（加 trimesh）、
##   material（override）、perf（LOD0 放大到上限＋1）、scale（根縮 1.1）、culm_d（稈徑放大 2.5 倍＝圓柱碰撞與尺寸不符）
## 回歸入口（唯讀、不寫 gate.json）：-- --regress（重驗 1–9 項＋gate.json 11 項 PASS 且 entry 雜湊一致）、-- --negatives（7 案一次跑完）
const BLib := preload("res://tools/village_v2_bamboo_lib.gd")
const DIR := "res://assets/village_v2/bamboo_kit"
const ENTRY := DIR + "/bamboo_kit_manifest.json"
const GATE := DIR + "/gate.json"
const REVIEW := DIR + "/review/bamboo_review.tscn"
const HEADLESS_KEYS: Array[String] = ["size", "parcel_fit", "grounding", "materials", "geometry", "pivot_scale",
	"collision", "lod", "perf"]
const RENDER_KEYS: Array[String] = ["player_screenshot", "f5_f6"]
const CAP := {"bamboo": 4000, "under": 500, "litter": 200}
const H_RANGE := {"bamboo": [6.0, 20.0], "under": [0.15, 0.8], "litter": [0.0, 0.05]}
## 稈徑（m）：id 前綴 → 範圍
const DBH_RANGE := {"take_thin": [0.03, 0.07], "take_thick": [0.12, 0.2], "take_": [0.07, 0.12]}
const SLAB_AREA := 0.2
const TEX_MAX := 2048
const VRAM_MAX_MB := 32.0
const MIN_SPACING := 0.45
## 竹 sway 與樹的差：veg_kit 葉材質 wind_speed 預設 1.0（R1 封存值）；竹材質必須 ≠
const TREE_WIND_SPEED := 1.0

var R := {}
var fails := 0
var neg := ""
var man: Dictionary
var trees: Dictionary
var regress := false
const NEG_EXPECT := {"slab": "grounding", "lod": "lod", "collision": "collision", "material": "materials",
	"perf": "perf", "scale": "size", "culm_d": "size"}


class _Log extends Logger:
	var n := 0
	func _log_error(_f: String, _file: String, _l: int, _c: String, _r: String, _e: bool, _t: int, _b: Array[ScriptBacktrace]) -> void:
		n += 1
	func _log_message(_m: String, _e: bool) -> void:
		pass


func _init() -> void:
	_run.call_deferred()


func _p(s: String) -> void:
	print("[BAMBOO] " + s)


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
		print("[BAMBOO] %s bamboo_kit %s：%s" % [e["result"], k, "；".join(e["detail"])])
		if e["result"] != "PASS":
			fails += 1


func _run() -> void:
	var render := false
	var negall := false
	for a: String in OS.get_cmdline_user_args():
		if a == "--render":
			render = true
		elif a == "--negatives":
			negall = true
		elif a == "--regress":
			regress = true
		elif a.begins_with("--neg="):
			neg = a.trim_prefix("--neg=")
	if not FileAccess.file_exists(ENTRY):
		_p("FAIL 缺 %s（先跑 village_v2_machiya_kit_prefab.gd -- --kit=bamboo_kit）" % ENTRY)
		quit(1)
		return
	var bad := _manifest_bad()
	if not bad.is_empty():
		_p("FAIL manifest 依賴雜湊不符（prefab 之後改過）：%s" % "、".join(bad.slice(0, 4)))
		quit(1)
		return
	man = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/src/modules_blender.json"))
	trees = man["trees"]
	if render:
		await _render()
	elif negall:
		await _negatives()
	else:
		await _headless()
	_p("結果：%d 項失敗" % fails)
	quit(fails)


func _manifest_bad() -> Array:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ENTRY))
	var out: Array = []
	var deps: Dictionary = m["deps"]
	for p: String in deps:
		if FileAccess.get_sha256(p) != String(deps[p]):
			out.append(p.get_file())
	for f in DirAccess.get_files_at(DIR + "/mesh"):
		if f.ends_with(".res") and not deps.has(DIR + "/mesh/" + f):
			out.append("未登記 " + f)
	return out


# ─────────────────────────── 載入（含反向案例） ───────────────────────────

func _load_tree(tid: String) -> Node3D:
	var t: Node3D = (load(BLib.TREE_DIR + "/%s.tscn" % tid) as PackedScene).instantiate()
	if neg == "" or tid != "take_mature":
		return t
	var l0 := t.get_node("LOD0") as MeshInstance3D
	match neg:
		"slab":
			var am := ArrayMesh.new()
			var src := l0.mesh as ArrayMesh
			for s in src.get_surface_count():
				var a := src.surface_get_arrays(s)
				if s == 0:
					var V: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
					var I: PackedInt32Array = a[Mesh.ARRAY_INDEX]
					var n0 := V.size()
					for c in [Vector3(-1.5, 0.02, -1.5), Vector3(1.5, 0.02, -1.5), Vector3(1.5, 0.02, 1.5), Vector3(-1.5, 0.02, 1.5)]:
						V.append(c)
					for key in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR, Mesh.ARRAY_TANGENT]:
						if a[key] == null:
							continue
						var arr: Variant = a[key]
						for k in 4:
							match key:
								Mesh.ARRAY_NORMAL: arr.append(Vector3.UP)
								Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2: arr.append(Vector2.ZERO)
								Mesh.ARRAY_COLOR: arr.append(Color.WHITE)
								Mesh.ARRAY_TANGENT: arr.append_array([1.0, 0.0, 0.0, 1.0])
						a[key] = arr
					I.append_array([n0, n0 + 2, n0 + 1, n0, n0 + 3, n0 + 2])
					a[Mesh.ARRAY_VERTEX] = V
					a[Mesh.ARRAY_INDEX] = I
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
				am.surface_set_material(s, src.surface_get_material(s))
			l0.mesh = am
		"lod":
			var l2 := t.get_node("LOD2")
			t.remove_child(l2)
			l2.free()
		"collision":
			var sb := t.get_node("Collision") as StaticBody3D
			var cs := CollisionShape3D.new()
			cs.shape = (l0.mesh as ArrayMesh).create_trimesh_shape()
			sb.add_child(cs)
		"material":
			l0.material_override = StandardMaterial3D.new()
		"perf":
			var am2 := (l0.mesh as ArrayMesh).duplicate() as ArrayMesh
			var arr2 := am2.surface_get_arrays(0)
			while _mesh_tris(am2) <= int(CAP["bamboo"]):
				am2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
			l0.mesh = am2
		"scale":
			t.scale = Vector3.ONE * 1.1
		"culm_d":
			# 稈徑 ×2.5（只放大碰撞圓柱與 manifest 稈徑 → 尺寸項的徑級檢查抓到；模擬錯把成竹做成巨竹）
			var cs2 := t.get_node("Collision").get_child(0) as CollisionShape3D
			var cy := (cs2.shape as CylinderShape3D).duplicate() as CylinderShape3D
			cy.radius *= 2.5
			cs2.shape = cy
	return t


func _mesh_tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		n += (idx.size() if idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


func _lods(t: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in t.get_children():
		if c is MeshInstance3D:
			out.append(c as MeshInstance3D)
	return out


func _maabb(mi: MeshInstance3D) -> AABB:
	return mi.transform * mi.mesh.get_aabb()


## 稈徑：LOD0 稈材質（BK_Culm）在離地 1.0–1.6 m 的頂點水平半徑中位數 ×2（實際幾何，不讀 manifest）
func _culm_d(t: Node3D) -> float:
	var l0 := t.get_node("LOD0") as MeshInstance3D
	var rs: Array[float] = []
	var cen := Vector2.ZERO
	var pts: Array[Vector3] = []
	for s in l0.mesh.get_surface_count():
		var mat := l0.mesh.surface_get_material(s)
		if mat == null or not mat.resource_path.contains("BK_Culm"):
			continue
		for v: Vector3 in (l0.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if v.y > 1.0 and v.y < 1.6:
				pts.append(v)
	if pts.is_empty():
		return 0.0
	for v in pts:
		cen += Vector2(v.x, v.z)
	cen /= pts.size()
	for v in pts:
		rs.append(Vector2(v.x, v.z).distance_to(cen))
	rs.sort()
	# 枝基也是稈材質但在枝下高以上；1.0–1.6 m 只有稈＋（若竹）筍皮（葉材質，不計）
	return rs[rs.size() / 2] * 2.0


func _dbh_range(tid: String) -> Array:
	for k: String in DBH_RANGE:
		if tid.begins_with(k):
			return DBH_RANGE[k]
	return [0.0, 1.0]


# ─────────────────────────── headless 1–9 ───────────────────────────

func _headless() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var loaded := {}
	for tid: String in trees:
		var t := _load_tree(tid)
		world.add_child(t)
		loaded[tid] = t
	_c_size(loaded)
	_c_parcel()
	_c_ground(loaded)
	_c_materials(loaded)
	_c_geometry(loaded)
	_c_pivot(loaded)
	await _c_collision(world)
	_c_lod(loaded)
	_c_perf(loaded)
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
		_p("%s gate.json 11 項 PASS 且 entry 雜湊一致%s" % ["PASS" if bad.is_empty() else "FAIL",
			"" if bad.is_empty() else "（✗ " + "、".join(bad) + "）"])
		if not bad.is_empty():
			fails += 1
	elif neg == "":
		_write_gate("headless", HEADLESS_KEYS)
	world.queue_free()


func _negatives() -> void:
	var missed: Array = []
	for c: String in NEG_EXPECT:
		neg = c
		R = {}
		fails = 0
		await _headless()
		var key: String = NEG_EXPECT[c]
		var hit := String(R.get(key, {}).get("result", "")) == "FAIL"
		_p("%s 反向 %s → %s 必須 FAIL（實際 %s）" % ["PASS" if hit else "FAIL", c, key, R.get(key, {}).get("result", "?")])
		if not hit:
			missed.append(c)
	neg = ""
	fails = missed.size()
	_p("反向案例 %d/%d 如預期 FAIL%s" % [NEG_EXPECT.size() - missed.size(), NEG_EXPECT.size(),
		"" if missed.is_empty() else "（漏抓：" + "、".join(missed) + "）"])


func _c_size(loaded: Dictionary) -> void:
	var worst_h := 0.0
	var worst_w := 0.0
	var bad: Array = []
	var ds: Array = []
	for tid: String in loaded:
		var info: Dictionary = trees[tid]
		var t: Node3D = loaded[tid]
		var a := t.transform * _maabb(t.get_node("LOD0") as MeshInstance3D)
		var H := float(info["height"])
		var eh := absf(a.end.y - H) / maxf(H, 0.01)
		var W := float(info["crown_w"])
		var ew := absf(maxf(a.size.x, a.size.z) - W) / maxf(W, 0.01)
		worst_h = maxf(worst_h, eh)
		worst_w = maxf(worst_w, ew)
		var cls := String(info["cls"])
		var rg: Array = H_RANGE[cls]
		var why := ""
		if eh > 0.02 or ew > 0.05:
			why = "高 %.2f／設計 %.2f、寬差 %.0f %%" % [a.end.y, H, ew * 100]
		elif H < float(rg[0]) or H > float(rg[1]):
			why = "高 %.2f 不在 %s %.2f–%.2f" % [H, cls, rg[0], rg[1]]
		if cls == "bamboo":
			# 稈徑：幾何量測＝manifest dbh（±10 %）＝碰撞直徑／0.4–0.75 對應；且落在種別徑級
			var d := _culm_d(t) * t.scale.x
			var dr := _dbh_range(tid)
			var cd := 0.0
			var sb := t.get_node_or_null("Collision")
			if sb and sb.get_child_count() > 0 and (sb.get_child(0) as CollisionShape3D).shape is CylinderShape3D:
				cd = ((sb.get_child(0) as CollisionShape3D).shape as CylinderShape3D).radius * 2.0
			ds.append("%s %.0f cm" % [tid.trim_prefix("take_"), d * 100])
			if d < float(dr[0]) or d > float(dr[1]) or absf(d - float(info["dbh_m"])) > float(info["dbh_m"]) * 0.1 \
					or cd > d * 1.6 or cd < d * 0.8:
				why += ("；" if why else "") + "稈徑 %.3f（種別 %.2f–%.2f、manifest %.3f、碰撞徑 %.3f）" % [d, dr[0], dr[1],
					float(info["dbh_m"]), cd]
		if why:
			bad.append("%s（%s）" % [tid, why])
	_res("size", bad.is_empty(), "%d 種：LOD0 高 vs 設計最大差 %.1f %%、寬最大差 %.1f %%；稈徑實測 %s；違規 %s" % [loaded.size(),
		worst_h * 100, worst_w * 100, "、".join(ds), "、".join(bad) if bad else "0"])


func _c_parcel() -> void:
	var rs: Node3D = (load(REVIEW) as PackedScene).instantiate()
	var rects: Array = []
	for t: Node3D in rs.get_node("Subjects/Live").get_children():
		var a := t.transform * _maabb(t.get_node("LOD0") as MeshInstance3D)
		var sh := a.size * 0.15
		rects.append([String(t.name), Rect2(Vector2(a.position.x + sh.x * 0.5, a.position.z + sh.z * 0.5),
			Vector2(a.size.x - sh.x, a.size.z - sh.z))])
	var hits: Array = []
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i][1] as Rect2).intersects(rects[j][1] as Rect2):
				hits.append("%s×%s" % [rects[i][0], rects[j][0]])
	# 試作竹林：稈基間距（只計竹稈；筍與落葉不計）
	var bases: Array[Vector2] = []
	for t: Node3D in rs.get_node("Subjects/Grove").get_children():
		var tid := String(t.get_meta("veg_id", ""))
		if tid.begins_with("take_") and tid != "take_litter":
			bases.append(Vector2(t.position.x, t.position.z))
	var close := 0
	var dmin := INF
	for i in bases.size():
		for j in range(i + 1, bases.size()):
			var d := bases[i].distance_to(bases[j])
			dmin = minf(dmin, d)
			if d < MIN_SPACING:
				close += 1
	rs.free()
	_res("parcel_fit", hits.is_empty() and close == 0, "R3 竹 Kit 先獨立審圖（核准後才放進西林與村緣；地塊／道路／建築屆時驗）；審圖 Live 列 %d 種外框（XZ 內縮 15 %%）互穿 %s；試作竹林 %d 稈最小稈距 %.2f m（≥ %.2f）違規 %d" % [
		rects.size(), "、".join(hits) if hits else "0", bases.size(), dmin, MIN_SPACING, close])


func _c_ground(loaded: Dictionary) -> void:
	var bad: Array = []
	var worst_slab := 0.0
	var wslab := "—"
	for tid: String in loaded:
		var t: Node3D = loaded[tid]
		var info: Dictionary = trees[tid]
		var cls := String(info["cls"])
		var m := (t.get_node("LOD0") as MeshInstance3D).mesh
		var miny := INF
		var maxy := -INF
		var slab := 0.0
		var culm_slab := 0.0
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var mat := m.surface_get_material(s)
			var culm := mat != null and mat.resource_path.contains("BK_Culm")
			for v in V:
				miny = minf(miny, v.y)
				maxy = maxf(maxy, v.y)
			var k := 0
			while k + 2 < I.size():
				var a := V[I[k]]
				var b := V[I[k + 1]]
				var c := V[I[k + 2]]
				var cr := (b - a).cross(c - a)
				var area := cr.length() * 0.5
				if area > 1e-6 and maxf(a.y, maxf(b.y, c.y)) < 0.15 and cr.normalized().y > 0.95:
					slab += area
					if culm:
						culm_slab += area
				k += 3
		var bad_here := ""
		if cls == "litter":
			# 落葉地被：只有卡片（葉材質）、全部貼地 ≤ 5 cm、不得有稈材質的水平面
			if maxy > 0.05 or culm_slab > 0.0 or miny < -0.01:
				bad_here = "落葉地被高 %.3f、稈材質水平面 %.2f m²" % [maxy, culm_slab]
		else:
			if slab > worst_slab:
				worst_slab = slab
				wslab = tid
			var col: Array = info.get("collision", [])
			var pv_off := 0.0
			if not col.is_empty():
				var ca: Array = col[0]["a"]
				pv_off = Vector2(float(ca[0]), float(ca[2])).length()
			var lo := -0.5 if cls == "bamboo" else -0.1
			if slab > SLAB_AREA or miny < lo or miny > 0.03 or pv_off > 0.05:
				bad_here = "土台面 %.2f m²、最低 %.2f、稈基偏 %.2f" % [slab, miny, pv_off]
		if bad_here:
			bad.append("%s（%s）" % [tid, bad_here])
	_res("grounding", bad.is_empty(), "pivot＝稈基：碰撞圓柱底離原點 ≤ 0.05 m；最低頂點 −0.5～+0.03（稈淺埋 0.25 m、不浮）；無自帶土台：貼地 ≤ 0.15 m 朝上水平面最大 %.3f m²（%s；上限 %.1f）；落葉地被只有貼地卡片 ≤ 5 cm；違規 %s" % [
		worst_slab, wslab, SLAB_AREA, "、".join(bad) if bad else "0"])


func _c_materials(loaded: Dictionary) -> void:
	var allowed := {}
	for k: String in BLib.material_paths():
		allowed[String(BLib.material_paths()[k])] = true
	var bad: Array = []
	var used := {}
	for tid: String in loaded:
		for mi in _lods(loaded[tid]):
			if mi.material_override != null:
				bad.append("%s/%s override" % [tid, mi.name])
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s)
				var p := mat.resource_path if mat else "（無）"
				if not allowed.has(p) or not (mat is ShaderMaterial):
					bad.append("%s/%s surf%d %s" % [tid, mi.name, s, p])
				else:
					used[p] = true
	var tex_bad: Array = []
	for p: String in used:
		var sm := load(p) as ShaderMaterial
		for pn in ["albedo_tex", "normal_tex"]:
			var tx := sm.get_shader_parameter(pn) as Texture2D
			if tx == null:
				tex_bad.append("%s %s 缺" % [p.get_file(), pn])
				continue
			if maxi(tx.get_width(), tx.get_height()) > TEX_MAX:
				tex_bad.append("%s %d px" % [tx.resource_path.get_file(), maxi(tx.get_width(), tx.get_height())])
			var img := tx.get_image()
			if img != null and not img.is_compressed():
				tex_bad.append("%s 未 VRAM 壓縮" % tx.resource_path.get_file())
	_res("materials", bad.is_empty() and tex_bad.is_empty(), "只用 bamboo_kit/mat 的 ShaderMaterial（%d 種實際使用：%s）、無 override：違規 %s；貼圖 ≤ %d、VRAM 壓縮：違規 %s" % [
		used.size(), "、".join(used.keys().map(func(x: String) -> String: return x.get_file().get_basename())),
		"、".join(bad.slice(0, 4)) if bad else "0", TEX_MAX, "、".join(tex_bad) if tex_bad else "0"])


func _c_geometry(loaded: Dictionary) -> void:
	var bad: Array = []
	var wt := 0.0
	var nt := 0
	var wl := 0.0
	var nl := 0
	for tid: String in loaded:
		if String(trees[tid]["cls"]) == "litter":
			# 落葉地被不吃風（UV2 全 0），不計入分層平均
			pass
		for mi in _lods(loaded[tid]):
			var m := mi.mesh
			for s in m.get_surface_count():
				var arr := m.surface_get_arrays(s)
				var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var N: Variant = arr[Mesh.ARRAY_NORMAL]
				var U: Variant = arr[Mesh.ARRAY_TEX_UV]
				var U2: Variant = arr[Mesh.ARRAY_TEX_UV2]
				var C: Variant = arr[Mesh.ARRAY_COLOR]
				if N == null or U == null or U2 == null or C == null:
					bad.append("%s/%s surf%d 缺屬性" % [tid, mi.name, s])
					continue
				var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var degen := 0
				var nan := 0
				var k := 0
				while k + 2 < I.size():
					var a := V[I[k]]
					var b := V[I[k + 1]]
					var c := V[I[k + 2]]
					if not (a.is_finite() and b.is_finite() and c.is_finite()):
						nan += 1
					elif (b - a).cross(c - a).length() < 1e-9:
						degen += 1
					k += 3
				var w_bad := 0
				var mat := m.surface_get_material(s)
				var leaf := mat != null and mat.resource_path.contains("BK_Leaf")
				var count := mi.name == "LOD0" and String(trees[tid]["cls"]) == "bamboo"
				for q in (U2 as PackedVector2Array):
					if q.x < -0.001 or q.x > 1.001:
						w_bad += 1
					if count:
						if leaf:
							wl += q.x
							nl += 1
						else:
							wt += q.x
							nt += 1
				if degen > 0 or nan > 0 or w_bad > 0:
					bad.append("%s/%s surf%d 退化 %d、NaN %d、風權重越界 %d" % [tid, mi.name, s, degen, nan, w_bad])
	var aw_t := wt / maxf(nt, 1)
	var aw_l := wl / maxf(nl, 1)
	# 竹的獨立 sway：竹材質 wind_speed ≠ 樹（R1 封存值 1.0）
	var sway: Array = []
	for k: String in BLib.material_paths():
		var sm := load(String(BLib.material_paths()[k])) as ShaderMaterial
		var ws: Variant = sm.get_shader_parameter("wind_speed")
		sway.append("%s %.2f" % [k, float(ws) if ws != null else TREE_WIND_SPEED])
		if ws == null or is_equal_approx(float(ws), TREE_WIND_SPEED):
			bad.append("%s 無獨立 sway（wind_speed＝樹）" % k)
	_res("geometry", bad.is_empty() and aw_t < aw_l, "全部 LOD 有法線／UV／UV2（風）／頂點色、無退化／NaN：違規 %s；風分層 LOD0 平均：稈 %.2f < 葉卡 %.2f；竹獨立 sway wind_speed（樹 %.1f）：%s" % [
		"、".join(bad.slice(0, 4)) if bad else "0", aw_t, aw_l, TREE_WIND_SPEED, "、".join(sway)])


func _c_pivot(loaded: Dictionary) -> void:
	var bad: Array = []
	for tid: String in loaded:
		var t: Node3D = loaded[tid]
		if not t.transform.basis.is_equal_approx(Basis.IDENTITY):
			bad.append("%s 根 basis≠identity" % tid)
		for mi in _lods(t):
			if not mi.transform.is_equal_approx(Transform3D.IDENTITY):
				bad.append("%s/%s" % [tid, mi.name])
	_res("pivot_scale", bad.is_empty(), "%d 種 prefab 根 basis／LOD 節點 transform＝identity（縮放 1；擺放時才給旋轉縮放）：違規 %s" % [
		loaded.size(), "、".join(bad) if bad else "0"])


func _c_collision(world: Node3D) -> void:
	var bad: Array = []
	var n_cyl := 0
	var probes := 0
	var i := 0
	var placed := []
	for t: Node3D in world.get_children():
		t.position = Vector3(i * 200.0, 0, 0)
		placed.append(t)
		i += 1
	await physics_frame
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	for t: Node3D in placed:
		var tid := String(t.name)
		var info: Dictionary = trees[tid]
		var sb := t.get_node_or_null("Collision") as StaticBody3D
		var shapes: Array = sb.get_children() if sb else []
		if String(info["cls"]) != "bamboo":
			if not shapes.is_empty():
				bad.append("%s 筍／落葉有碰撞" % tid)
			continue
		if shapes.size() != 1:
			bad.append("%s 碰撞數 %d（應 1）" % [tid, shapes.size()])
			continue
		var c0 := shapes[0] as CollisionShape3D
		if not (c0.shape is CylinderShape3D):
			bad.append("%s 形狀 %s" % [tid, c0.shape.get_class()])
			continue
		n_cyl += 1
		var r := (c0.shape as CylinderShape3D).radius
		var d := float(info["dbh_m"])
		if r < d * 0.4 or r > d * 0.75:
			bad.append("%s 碰撞半徑 %.3f vs 稈徑 %.3f" % [tid, r, d])
		var base := t.to_global(c0.position)
		base.y = t.global_position.y + 1.15
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cap
		q.transform = Transform3D(Basis.IDENTITY, base)
		var hit := space.intersect_shape(q, 1).size() > 0
		var miss_ok := true
		for a in 8:
			var dir := Vector3.RIGHT.rotated(Vector3.UP, a * PI * 0.25)
			q.transform = Transform3D(Basis.IDENTITY, base + dir * (r + 0.3 + 0.4))
			if space.intersect_shape(q, 1).size() > 0:
				miss_ok = false
		probes += 9
		if not hit or not miss_ok:
			bad.append("%s 膠囊探針（中心撞 %s、外圈不撞 %s）" % [tid, hit, miss_ok])
	_res("collision", bad.is_empty(), "竹稈 1 根圓柱（半徑 0.4–0.75×稈徑）、筍／落葉 0、無 trimesh；圓柱 %d；膠囊探針 %d 次（中心撞、半徑＋0.4 m 外不撞＝稈間可走）；違規 %s" % [
		n_cyl, probes, "、".join(bad) if bad else "0"])


func _c_lod(loaded: Dictionary) -> void:
	var bad: Array = []
	var r1s: Array = []
	var r2s: Array = []
	for tid: String in loaded:
		var info: Dictionary = trees[tid]
		var t: Node3D = loaded[tid]
		var ls := _lods(t)
		var want := 4 if String(info["cls"]) == "bamboo" else 3
		if ls.size() != want:
			bad.append("%s 級數 %d（應 %d）" % [tid, ls.size(), want])
			continue
		var tr: Array = []
		for mi in ls:
			tr.append(_mesh_tris(mi.mesh))
		var r1 := float(tr[1]) / float(tr[0])
		var r2 := float(tr[2]) / float(tr[0])
		r1s.append(r1)
		r2s.append(r2)
		var small := int(tr[0]) < 500
		var r_ok := (r1 >= 0.25 and r1 <= 0.5 and r2 >= 0.06 and r2 <= 0.2) if not small else (r1 < 0.6 and r2 <= 0.25 and r2 < r1)
		if not r_ok or int(tr[2]) < 6:
			bad.append("%s 面數 %s（LOD1 %.0f %%、LOD2 %.0f %%）" % [tid, tr, r1 * 100, r2 * 100])
		var h0 := _maabb(ls[0]).end.y
		for k in range(1, ls.size()):
			var hk := _maabb(ls[k]).end.y
			var tol := 0.15 if h0 < 2.5 else h0 * 0.08
			if absf(hk - h0) > tol:
				bad.append("%s LOD%d 高 %.2f vs %.2f" % [tid, k, hk, h0])
		for k in range(ls.size() - 1):
			var a: Vector4 = ls[k].get_instance_shader_parameter("lod_band")
			var b: Vector4 = ls[k + 1].get_instance_shader_parameter("lod_band")
			if absf(a.y - b.x) > 0.01 or absf(a.w - b.z) > 0.01 or a.y <= 0.0:
				bad.append("%s LOD%d→%d 換檔帶不接（%.1f／%.1f）" % [tid, k, k + 1, a.y, b.x])
			if ls[k].visibility_range_end < a.y + a.w * 0.5 or ls[k + 1].visibility_range_begin > b.x - b.z * 0.5:
				bad.append("%s LOD%d 粗剔除切到交叉帶" % [tid, k])
	r1s.sort()
	r2s.sort()
	_res("lod", bad.is_empty(), "%d 種：級數（竹稈 4／筍與落葉 3）、LOD1 %.0f–%.0f %%、LOD2 %.0f–%.0f %%（竹稈 25–50 %%／6–20 %%）、高度差 ≤ 8 %%、抖動換檔帶首尾相接：違規 %s" % [
		loaded.size(), float(r1s[0]) * 100, float(r1s[-1]) * 100, float(r2s[0]) * 100, float(r2s[-1]) * 100,
		"、".join(bad.slice(0, 6)) if bad else "0"])


func _c_perf(loaded: Dictionary) -> void:
	var bad: Array = []
	var total := 0
	var by := {}
	for tid: String in loaded:
		var info: Dictionary = trees[tid]
		var ls := _lods(loaded[tid])
		var t0 := _mesh_tris(ls[0].mesh)
		total += t0
		var cls := String(info["cls"])
		var cap := int(CAP[cls])
		by[cls] = maxi(int(by.get(cls, 0)), t0)
		if t0 > cap:
			bad.append("%s LOD0 %d > %d" % [tid, t0, cap])
		for mi in ls:
			if mi.mesh.get_surface_count() > 2:
				bad.append("%s/%s surface %d" % [tid, mi.name, mi.mesh.get_surface_count()])
	var vram := 0.0
	for f in DirAccess.get_files_at(DIR + "/tex"):
		if f.ends_with(".png") or f.ends_with(".jpg"):
			var tx := load(DIR + "/tex/" + f) as Texture2D
			if tx:
				vram += tx.get_width() * tx.get_height() * 1.0 * 1.33 / 1048576.0
	var parts: Array = []
	for k: String in by:
		parts.append("%s 最大 %d／%d" % [k, by[k], CAP[k]])
	_res("perf", bad.is_empty() and vram <= VRAM_MAX_MB, "LOD0 類別上限：%s；每級 surface ≤ 2；全庫 LOD0 合計 %d（每種一稈）；Kit 貼圖 VRAM 估 %.1f MB（≤ %.0f）；違規 %s（群植成本＝P12 technical debt，ART-FIRST）" % [
		"、".join(parts), total, vram, VRAM_MAX_MB, "、".join(bad) if bad else "0"])


# ─────────────────────────── gate.json ───────────────────────────

func _write_gate(part: String, keys: Array[String]) -> void:
	var sha := FileAccess.get_sha256(ENTRY)
	var g: Dictionary = {}
	if FileAccess.file_exists(GATE):
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(GATE))
		if old is Dictionary and String(old.get("entry_sha256", "")) == sha:
			g = old
	g["asset"] = "bamboo_kit"
	g["entry"] = ENTRY
	g["entry_sha256"] = sha
	g["godot"] = Engine.get_version_info()["string"]
	g["scope"] = "P9 R3：竹 Kit 獨立審圖（未植入 village_v2；竹林美術核准後才放進西林與村緣，地塊／F5 實走屆時驗）"
	var checks: Dictionary = g.get("checks", {})
	for k in keys:
		var e: Dictionary = R[k]
		checks[k] = {"result": e["result"], "detail": e["detail"], "part": part, "date": Time.get_datetime_string_from_system()}
	g["checks"] = checks
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


const GROVE_SHOTS := ["grove_out30", "grove_edge8", "grove_path_a", "grove_path_b", "grove_gap", "grove_inside_up",
	"grove_top", "grove_far60", "grove_far120"]


func _render() -> void:
	var shots := (ProjectSettings.globalize_path("res://") + "../docs/art_review/village_v2_p9_vegetation/r3/shots").simplify_path()
	var miss: Array = []
	var flat: Array = []
	var n := 0
	var lo := INF
	var names: Array = GROVE_SHOTS.duplicate()
	for tid: String in trees:
		var vs: Array = ["near", "mid", "up", "top", "lods"] if String(trees[tid]["cls"]) == "bamboo" else ["near", "top", "lods"]
		for v: String in vs:
			names.append("%s_%s" % [tid, v])
	for nm: String in names:
		var p := shots.path_join(nm + ".png")
		if not FileAccess.file_exists(p):
			miss.append(nm)
			continue
		var sd := _img_std(Image.load_from_file(p))
		lo = minf(lo, sd)
		n += 1
		if sd < 0.03:
			flat.append("%s %.3f" % [nm, sd])
	_res("player_screenshot", miss.is_empty() and flat.is_empty(), "審圖截圖 %d 張（Forward+；每稈 near 1.7 m／mid／仰望梢／35° 俯視／LOD 階梯，筍與落葉 near／top／lods，試作竹林 9 視角：林外 30 m、林緣 8 m、小徑×2、空洞、林內仰望、俯視、60／120 m）：缺 %s；空白（亮度標準差 < 0.03）%s；最低 %.3f" % [
		n, "、".join(miss.slice(0, 5)) if miss else "0", "、".join(flat) if flat else "0", lo])
	var lg := _Log.new()
	OS.add_logger(lg)
	var sc: Node3D = (load(REVIEW) as PackedScene).instantiate()
	root.add_child(sc)
	var cam := Camera3D.new()
	sc.add_child(cam)
	cam.current = true
	# 相機從試作竹林外 60 m 走進林內小徑再走出（含林內換檔）
	for i in 120:
		cam.position = Vector3(-60.0 + i * 1.0, 1.7, -70.0 + 2.5 * sin((-60.0 + i * 1.0) * 0.25) * 0.0)
		cam.look_at(cam.position + Vector3(1, 0, 0), Vector3.UP)
		await process_frame
	OS.remove_logger(lg)
	var gr := sc.get_node("Subjects/Grove")
	_res("f5_f6", lg.n == 0, "F6＝審圖場景（%d 種＋試作竹林 %d 稈）相機自林外 60 m 穿過竹林 120 幀、Logger 錯誤 %d；F5＝核准後正式擺放實走" % [
		trees.size(), int(gr.get_meta("culms", 0)), lg.n])
	sc.queue_free()
	_flush(RENDER_KEYS)
	if neg == "":
		_write_gate("render", RENDER_KEYS)
