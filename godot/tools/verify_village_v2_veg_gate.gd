extends SceneTree
## 人間之里 V2 P9 R1：植被庫（veg_kit）Asset Gate（11 項，與 Hero／町家／河岸 Kit Gate 同名同義）。
##   headless 1–9：godot --headless --path . --script res://tools/verify_village_v2_veg_gate.gd [-- --neg=<案例>]
##   render 10–11：godot --path . --resolution 1600x900 --script res://tools/verify_village_v2_veg_gate.gd -- --render
## entry＝assets/village_v2/veg_kit/veg_kit_manifest.json（mesh／材質／shader／貼圖／樹 prefab 全部 sha256）；
## gate.json 記 entry 雜湊，任何一檔改動 → gate 失效。R1 不植入 village_v2：地塊（2）與 F5（11 的實走）在 P9 R2
## 林帶植入時才有對象，本 gate 在 R1 驗「審圖場景」的對應項並明寫範圍。
## 視覺（樹形、種別辨識、LOD 換檔觀感）不在 gate 範圍：只到 ART_REVIEW，ART_APPROVED 只有使用者能給。
##   1 尺寸     每棵 LOD0 AABB 高＝Blender 設計高（±2 %）、冠幅（±5 %）；樹高在類別合理範圍
##   2 地塊     R1：審圖場景 Live 列樹與樹的 LOD0 外框（XZ，內縮 15 %）不互穿；R2 植入時改驗地塊／道路／建築
##   3 接地     pivot＝根部：樹幹基部（碰撞圓柱底＝樹幹中心線）離原點 ≤ 0.15 m；接地交線中心 ≤ 0.15＋0.6×dbh；
##              最低頂點 −0.8～+0.05（根只淺埋、不浮）；**無自帶土台**：貼地 ≤ 0.15 m 朝上水平面（n.y > 0.95）
##              ≤ 0.6 m²＋樹幹基部斷面積（板根的水平分量與樹幹同量級；土台是樹幹斷面的數倍）
##   4 材質     只用 veg_kit/mat/VK_*.tres（ShaderMaterial、veg shader）；無 material_override；貼圖 ≤ 2K、VRAM 壓縮
##   5 幾何     無退化／NaN；有法線、UV、UV2（風權重∈[0,1]）、頂點色；風遮罩分層：樹幹平均 < 葉卡平均
##   6 Pivot    prefab 根與 LOD 節點 transform＝identity（縮放 1）
##   7 碰撞     普通樹＝1 根樹幹圓柱（Hero ≤ 7）；地被 0；禁止 trimesh；膠囊（r 0.3、h 1.7）在樹幹中心會撞、
##              在碰撞半徑＋0.4 m 外不撞（碰撞貼樹幹、不包樹冠）；碰撞半徑 0.3–0.75×dbh
##   8 LOD      級數（樹 4／地被與倒木 3）、換檔距離遞增且 lod_band 首尾相接；LOD1 30–45 %、LOD2 8–20 %（≥ 6 面）；
##              LOD1/2 高度與 LOD0 差 ≤ 8 %（地被 < 2.5 m：≤ 0.15 m）；LOD0 < 500 面的小件：遞減、LOD1 < 60 %、LOD2 ≤ 25 %
##   9 效能     LOD0 ≤ 類別上限（一般林 6000／庭園地標 12000／Hero 15000／幼樹 3500／枯木 2500／地被 1000）；
##              每級 surface ≤ 2；Kit 貼圖 VRAM 合計報告（≤ 64 MB）
##  10 截圖     審圖截圖齊全（每棵 near／mid／top／lods／sweep，群組 far50／far100）且非空白（亮度標準差 > 0.03）
##  11 F6      審圖場景 120 幀、Logger 錯誤 0（F5 實走＝R2 植入後）
## 反向案例（--neg，不寫 gate.json，預期對應項 FAIL）：slab（LOD0 加 3×3 m 土台）、lod（刪 LOD2）、collision（加 trimesh）、
##   material（override）、perf（LOD0 面數放大到上限＋1）、scale（根縮 1.1）
## P9 R1 ART_APPROVED（2026-10-01）封存後的回歸入口（皆唯讀、不寫 gate.json）：
##   -- --regress    重驗 1–9 項＋gate.json 11 項 PASS 且 entry 雜湊一致
##   -- --negatives  6 個永久反向案例一次跑完，每個都必須讓「它瞄準的那一項」FAIL（任一沒 FAIL → exit 1）
##   -- --seal       data/village_v2_p9r1_seal.json：樹庫／生成器／LOD 指標／7 張核准總表／證據 sha256 一致＋記憶體竄改反向
const VegLib := preload("res://tools/village_v2_veg_lib.gd")
const DIR := "res://assets/village_v2/veg_kit"
const ENTRY := DIR + "/veg_kit_manifest.json"
const GATE := DIR + "/gate.json"
const REVIEW := DIR + "/review/veg_review.tscn"
const HEADLESS_KEYS: Array[String] = ["size", "parcel_fit", "grounding", "materials", "geometry", "pivot_scale",
	"collision", "lod", "perf"]
const RENDER_KEYS: Array[String] = ["player_screenshot", "f5_f6"]
const CAP := {"forest": 6000, "garden": 12000, "hero": 15000, "young": 3500, "dead": 2500, "under": 1000}
const H_RANGE := {"forest": [8.0, 32.0], "garden": [3.0, 18.0], "hero": [14.0, 34.0], "young": [2.5, 9.0],
	"dead": [0.5, 14.0], "under": [0.3, 2.5]}
const SLAB_AREA := 0.6
const TEX_MAX := 2048
const VRAM_MAX_MB := 64.0

var R := {}
var fails := 0
var neg := ""
var man: Dictionary
var trees: Dictionary
var errors_seen := 0
var regress := false
const SEAL := "res://data/village_v2_p9r1_seal.json"
## 反向案例 → 必須 FAIL 的 gate 項
const NEG_EXPECT := {"slab": "grounding", "lod": "lod", "collision": "collision", "material": "materials",
	"perf": "perf", "scale": "size"}


class _Log extends Logger:
	var n := 0
	func _log_error(_f: String, _file: String, _l: int, _c: String, _r: String, _e: bool, _t: int, _b: Array[ScriptBacktrace]) -> void:
		n += 1
	func _log_message(_m: String, _e: bool) -> void:
		pass


func _init() -> void:
	_run.call_deferred()


func _p(s: String) -> void:
	print("[VEG] " + s)


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
		print("[VEG] %s veg_kit %s：%s" % [e["result"], k, "；".join(e["detail"])])
		if e["result"] != "PASS":
			fails += 1


func _run() -> void:
	var render := false
	var negall := false
	for a: String in OS.get_cmdline_user_args():
		if a == "--render":
			render = true
		elif a == "--regress":
			regress = true
		elif a == "--negatives":
			negall = true
		elif a == "--seal":
			_seal()
			return
		elif a.begins_with("--neg="):
			neg = a.trim_prefix("--neg=")
	if not FileAccess.file_exists(ENTRY):
		_p("FAIL 缺 %s（先跑 village_v2_machiya_kit_prefab.gd -- --kit=veg_kit）" % ENTRY)
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
	var t: Node3D = (load(VegLib.TREE_DIR + "/%s.tscn" % tid) as PackedScene).instantiate()
	if neg == "" or tid != _neg_target():
		return t
	var l0 := t.get_node("LOD0") as MeshInstance3D
	match neg:
		"slab":
			# 3×3 m 土台頂面（離地 0.05、朝上），併進樹皮 surface（同一 draw call，模擬 Tripo 樹自帶土台）
			var am := ArrayMesh.new()
			var src := l0.mesh as ArrayMesh
			for s in src.get_surface_count():
				var a := src.surface_get_arrays(s)
				if s == 0:
					var V: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
					var I: PackedInt32Array = a[Mesh.ARRAY_INDEX]
					var n0 := V.size()
					for c in [Vector3(-1.5, 0.05, -1.5), Vector3(1.5, 0.05, -1.5), Vector3(1.5, 0.05, 1.5), Vector3(-1.5, 0.05, 1.5)]:
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
			var cap := int(CAP[String(trees[tid]["cls"])])
			while _mesh_tris(am2) <= cap:
				am2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
			l0.mesh = am2
		"scale":
			t.scale = Vector3.ONE * 1.1
	return t


func _neg_target() -> String:
	return "konara_a"


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


## 6 個永久反向案例：各自只改記憶體裡的 konara_a，預期它瞄準的那一項 FAIL；fails 只計「沒抓到」的案例
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


# ─────────────────────────── 封存（--seal） ───────────────────────────

func _seal_mismatch(seal: Dictionary) -> PackedStringArray:
	var repo := (ProjectSettings.globalize_path("res://") + "..").simplify_path() + "/"
	var docs := repo + "docs/art_review/village_v2_p9_vegetation/"
	var bad := PackedStringArray()
	for grp: String in ["frozen", "art_review_images", "evidence"]:
		var d: Dictionary = seal[grp]
		for k: String in d:
			var path: String = (repo + k) if grp == "frozen" else (docs + k)
			if not FileAccess.file_exists(path):
				bad.append("%s 不存在" % k)
			elif FileAccess.get_sha256(path) != String(d[k]):
				bad.append("%s 雜湊變了" % k)
	return bad


func _seal() -> void:
	var seal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SEAL))
	var bad := _seal_mismatch(seal)
	var n: int = seal["frozen"].size() + seal["art_review_images"].size() + seal["evidence"].size()
	_p("%s P9 R1 封存 %d 檔雜湊一致（凍結 %d、核准總表 %d、證據 %d；不符 %d：%s）" % ["PASS" if bad.is_empty() else "FAIL",
		n, seal["frozen"].size(), seal["art_review_images"].size(), seal["evidence"].size(), bad.size(),
		", ".join(bad.slice(0, 4))])
	var neg_seal := seal.duplicate(true)
	var k0: String = neg_seal["frozen"].keys()[0]
	neg_seal["frozen"][k0] = "0".repeat(64)
	var nb := _seal_mismatch(neg_seal)
	var ok_neg := nb.size() == bad.size() + 1
	_p("%s 反向：竄改 %s 期望雜湊 → 偵測到 1 筆不符（實際 %d）" % ["PASS" if ok_neg else "FAIL", k0, nb.size() - bad.size()])
	var f := (0 if bad.is_empty() else 1) + (0 if ok_neg else 1)
	_p("結果：%d 項失敗（seal）" % f)
	quit(f)


func _c_size(loaded: Dictionary) -> void:
	var worst_h := 0.0
	var worst_w := 0.0
	var wid := ""
	var bad: Array = []
	for tid: String in loaded:
		var info: Dictionary = trees[tid]
		var t: Node3D = loaded[tid]
		var a := t.transform * _maabb(t.get_node("LOD0") as MeshInstance3D)
		var H := float(info["height"])
		var eh := absf(a.end.y - H) / maxf(H, 0.01)
		var W := float(info["crown_w"])
		var ew := absf(maxf(a.size.x, a.size.z) - W) / maxf(W, 0.01)
		if eh > worst_h:
			worst_h = eh
			wid = tid
		worst_w = maxf(worst_w, ew)
		var rg: Array = H_RANGE[String(info["cls"])]
		if eh > 0.02 or ew > 0.05 or H < float(rg[0]) or H > float(rg[1]):
			bad.append("%s（高 %.2f／設計 %.2f、冠幅差 %.0f %%、類別 %s %.1f–%.1f）" % [tid, a.end.y, H, ew * 100,
				info["cls"], rg[0], rg[1]])
	_res("size", bad.is_empty(), "%d 棵：LOD0 高 vs 設計最大差 %.1f %%（%s）、冠幅最大差 %.1f %%；違規 %s" % [loaded.size(),
		worst_h * 100, wid, worst_w * 100, "、".join(bad) if bad else "0"])


func _c_parcel() -> void:
	var rs: Node3D = (load(REVIEW) as PackedScene).instantiate()
	var rects: Array = []
	for gn in rs.get_node("Subjects/Live").get_children():
		for t: Node3D in gn.get_children():
			var a := t.transform * _maabb(t.get_node("LOD0") as MeshInstance3D)
			var sh := a.size * 0.15
			rects.append([String(t.name), Rect2(Vector2(a.position.x + sh.x * 0.5, a.position.z + sh.z * 0.5) + Vector2((gn as Node3D).position.x, (gn as Node3D).position.z),
				Vector2(a.size.x - sh.x, a.size.z - sh.z))])
	var hits: Array = []
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i][1] as Rect2).intersects(rects[j][1] as Rect2):
				hits.append("%s×%s" % [rects[i][0], rects[j][0]])
	rs.free()
	_res("parcel_fit", hits.is_empty(), "R1 不植入 village_v2（規格：先獨立審圖場景）；審圖場景 %d 棵 LOD0 外框（XZ 內縮 15 %%）互穿 %s；地塊／道路／建築於 P9 R2 植入時驗" % [
		rects.size(), "、".join(hits) if hits else "0"])


func _c_ground(loaded: Dictionary) -> void:
	var bad: Array = []
	var worst_slab := 0.0
	var wslab := ""
	var worst_off := 0.0
	for tid: String in loaded:
		var t: Node3D = loaded[tid]
		var info: Dictionary = trees[tid]
		var l0 := t.get_node("LOD0") as MeshInstance3D
		var m := l0.mesh
		var miny := INF
		var slab := 0.0
		var base_pts := Vector3.ZERO
		var nb := 0
		var root_check := String(info["cls"]) != "under" and tid != "log_a"
		var is_log := tid == "log_a"
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var mat := m.surface_get_material(s)
			var bark := mat != null and mat.resource_path.contains("VK_Bark")
			for v in V:
				miny = minf(miny, v.y)
				# 地面交線（−0.05～0.25 m 的樹皮頂點）範圍中心：根部接地中心
				if root_check and bark and v.y > -0.05 and v.y < 0.25:
					base_pts += v
					nb += 1
			var k := 0
			while k + 2 < I.size():
				var a := V[I[k]]
				var b := V[I[k + 1]]
				var c := V[I[k + 2]]
				var cr := (b - a).cross(c - a)
				var area := cr.length() * 0.5
				# 土台＝貼地（≤ 0.15 m）朝上的近水平面（n.y > 0.95）；倒木底面（朝下）、板根斜面不計
				if area > 1e-6 and maxf(a.y, maxf(b.y, c.y)) < 0.15 and cr.normalized().y > 0.95:
					slab += area
				k += 3
		if slab > worst_slab:
			worst_slab = slab
			wslab = tid
		var off := 0.0
		if nb > 0:
			var bc := base_pts / nb
			off = Vector2(bc.x, bc.z).length()
			worst_off = maxf(worst_off, off)
		# pivot＝樹幹基部：碰撞圓柱底（由樹幹中心線產生）離原點 ≤ 0.15 m；接地交線中心（含不對稱板根）≤ 0.15＋0.6×dbh
		var col: Array = info.get("collision", [])
		var pv_off := 0.0
		if not col.is_empty():
			var ca: Array = col[0]["a"]
			pv_off = Vector2(float(ca[0]), float(ca[2])).length()
		if is_log:
			pv_off = 0.0
		var t_ok := not root_check or (nb > 0 and off <= 0.15 + float(info["dbh_m"]) * 0.6 and pv_off <= 0.15)
		# 上限＝0.6 m²＋樹幹基部斷面積（巨木板根的水平分量與樹幹同量級；土台是樹幹斷面的數倍）
		var slab_cap := SLAB_AREA + PI * pow(float(info["dbh_m"]) * 0.5, 2.0)
		if is_log:
			# 倒木半埋：與地面交線處的切面算「接地」，上限＝長 × 直徑 × 0.5（不是土台）
			slab_cap = maxf(slab_cap, float(info["crown_w"]) * float(info["dbh_m"]) * 0.5)
		if slab > slab_cap or miny < -0.8 or miny > 0.05 or not t_ok:
			bad.append("%s（土台面 %.2f m²、最低 %.2f、接地中心偏 %.2f、樹幹基部偏 %.2f）" % [tid, slab, miny, off, pv_off])
	_res("grounding", bad.is_empty(), "pivot＝根部：樹幹基部（碰撞圓柱底）離原點 ≤ 0.15 m、接地交線中心最大偏 %.2f m（≤ 0.15＋0.6×dbh，板根不對稱）；無自帶土台：貼地 ≤ 0.15 m 朝上水平面最大 %.2f m²（%s；上限 %.1f＋樹幹斷面積）；最低頂點 −0.8～+0.05；違規 %s" % [
		worst_off, worst_slab, wslab, SLAB_AREA, "、".join(bad) if bad else "0"])


func _c_materials(loaded: Dictionary) -> void:
	var allowed := {}
	for k: String in VegLib.material_paths():
		allowed[String(VegLib.material_paths()[k])] = true
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
	_res("materials", bad.is_empty() and tex_bad.is_empty(), "只用 veg_kit/mat 的 ShaderMaterial（%d 種實際使用）、無 override：違規 %s；貼圖 ≤ %d、VRAM 壓縮：違規 %s" % [
		used.size(), "、".join(bad.slice(0, 4)) if bad else "0", TEX_MAX, "、".join(tex_bad) if tex_bad else "0"])


func _c_geometry(loaded: Dictionary) -> void:
	var bad: Array = []
	var wt := 0.0
	var nt := 0
	var wl := 0.0
	var nl := 0
	for tid: String in loaded:
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
					bad.append("%s/%s surf%d 缺 %s" % [tid, mi.name, s, ",".join(["N" if N == null else "", "UV" if U == null else "",
						"UV2" if U2 == null else "", "COLOR" if C == null else ""])])
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
				var leaf := (m.surface_get_material(s) as Resource).resource_path.contains("VK_Leaf") if m.surface_get_material(s) else false
				for q in (U2 as PackedVector2Array):
					if q.x < -0.001 or q.x > 1.001:
						w_bad += 1
					if mi.name == "LOD0":
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
	_res("geometry", bad.is_empty() and aw_t < aw_l, "全部 LOD 有法線／UV／UV2（風）／頂點色、無退化／NaN：違規 %s；風遮罩分層 LOD0 平均：樹皮 %.2f < 葉卡 %.2f" % [
		"、".join(bad.slice(0, 4)) if bad else "0", aw_t, aw_l])


func _c_pivot(loaded: Dictionary) -> void:
	var bad: Array = []
	for tid: String in loaded:
		var t: Node3D = loaded[tid]
		if not t.transform.basis.is_equal_approx(Basis.IDENTITY):
			bad.append("%s 根 basis≠identity" % tid)
		for mi in _lods(t):
			if not mi.transform.is_equal_approx(Transform3D.IDENTITY):
				bad.append("%s/%s" % [tid, mi.name])
	_res("pivot_scale", bad.is_empty(), "%d 棵 prefab 根 basis／LOD 節點 transform＝identity（縮放 1；擺放時才給旋轉縮放）：違規 %s" % [
		loaded.size(), "、".join(bad) if bad else "0"])


func _c_collision(world: Node3D) -> void:
	var bad: Array = []
	var n_cyl := 0
	var probes := 0
	# 每棵單獨放在遠處（間隔 200 m），膠囊探針
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
		var cls := String(info["cls"])
		if cls == "under":
			if not shapes.is_empty():
				bad.append("%s 地被有碰撞" % tid)
			continue
		var maxn := 7 if cls == "hero" else 1
		if shapes.is_empty() or shapes.size() > maxn:
			bad.append("%s 碰撞數 %d（應 1–%d）" % [tid, shapes.size(), maxn])
			continue
		var trunk_r := 0.0
		for cs: CollisionShape3D in shapes:
			if cs.shape is ConcavePolygonShape3D or not (cs.shape is CylinderShape3D or cs.shape is CapsuleShape3D or cs.shape is BoxShape3D):
				bad.append("%s %s 形狀 %s" % [tid, cs.name, cs.shape.get_class()])
			elif cs.shape is CylinderShape3D:
				n_cyl += 1
		var c0 := shapes[0] as CollisionShape3D
		if c0.shape is CylinderShape3D:
			trunk_r = (c0.shape as CylinderShape3D).radius
		var dbh := float(info["dbh_m"])
		if trunk_r < dbh * 0.3 or trunk_r > maxf(dbh * 0.75, 0.12):
			bad.append("%s 樹幹碰撞半徑 %.2f vs dbh %.2f" % [tid, trunk_r, dbh])
		# 膠囊：樹幹中心（離地 0.9）要撞；碰撞半徑＋0.4 外（四方位）不撞
		var base := t.to_global(c0.position)
		# 膠囊（h 1.7）中心離地 1.15 → 底 0.3；倒木（橫躺）改用碰撞中心高度＋0.55（膠囊下半身擦過樹幹）
		var upright := absf(c0.global_transform.basis.y.normalized().y) > 0.7
		base.y = t.global_position.y + (1.15 if upright else c0.position.y + 0.55)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cap
		q.transform = Transform3D(Basis.IDENTITY, Vector3(base.x, base.y, base.z))
		var hit := space.intersect_shape(q, 1).size() > 0
		var miss_ok := true
		# 外圈探針只取垂直於圓柱軸的水平方向（直立樹幹＝四方位；倒木＝只取兩側）
		var axis := (c0.global_transform.basis.y).normalized()
		for a in 8:
			var dir := Vector3.RIGHT.rotated(Vector3.UP, a * PI * 0.25)
			dir = dir - axis * dir.dot(axis)
			if dir.length() < 0.9:
				continue
			dir = dir.normalized()
			q.transform = Transform3D(Basis.IDENTITY, Vector3(base.x, base.y, base.z) + dir * (trunk_r + 0.3 + 0.4))
			if space.intersect_shape(q, 1).size() > 0:
				miss_ok = false
		probes += 5
		if not hit or not miss_ok:
			bad.append("%s 膠囊探針（中心撞 %s、外圈不撞 %s）" % [tid, hit, miss_ok])
	_res("collision", bad.is_empty(), "普通樹 1 根樹幹圓柱、Hero ≤ 7、地被 0、無 trimesh；樹幹圓柱共 %d；膠囊探針 %d 次（中心撞、半徑＋0.4 m 外不撞）；違規 %s" % [
		n_cyl, probes, "、".join(bad) if bad else "0"])


func _c_lod(loaded: Dictionary) -> void:
	var bad: Array = []
	var r1s: Array = []
	var r2s: Array = []
	for tid: String in loaded:
		var info: Dictionary = trees[tid]
		var t: Node3D = loaded[tid]
		var ls := _lods(t)
		var want := (info["lods"] as Array).size() if tid == "log_a" else (3 if String(info["cls"]) == "under" else 4)
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
		# LOD0 < 500 面的小件（倒木、地被）：比例只要求遞減且 LOD2 ≤ 25 %（再砍就失去輪廓，省的面數可忽略）
		var small := int(tr[0]) < 500
		var r_ok := (r1 >= 0.3 and r1 <= 0.45 and r2 >= 0.08 and r2 <= 0.2) if not small else (r1 < 0.6 and r2 <= 0.25 and r2 < r1)
		if not r_ok or int(tr[2]) < 6:
			bad.append("%s 面數 %s（LOD1 %.0f %%、LOD2 %.0f %%）" % [tid, tr, r1 * 100, r2 * 100])
		# 高度差：樹 ≤ 8 %；地被（< 2.5 m）≤ 0.15 m（1 m 草叢的 8 % 只有 8 cm，卡片抖動就超過）
		var h0 := _maabb(ls[0]).end.y
		for k in [1, 2]:
			var hk := _maabb(ls[k]).end.y
			var tol := 0.15 if h0 < 2.5 else h0 * 0.08
			if absf(hk - h0) > tol:
				bad.append("%s LOD%d 高 %.2f vs %.2f" % [tid, k, hk, h0])
		# 換檔帶首尾相接
		for k in range(ls.size() - 1):
			var a: Vector4 = ls[k].get_instance_shader_parameter("lod_band")
			var b: Vector4 = ls[k + 1].get_instance_shader_parameter("lod_band")
			if absf(a.y - b.x) > 0.01 or absf(a.w - b.z) > 0.01 or a.y <= 0.0:
				bad.append("%s LOD%d→%d 換檔帶不接（%.1f／%.1f）" % [tid, k, k + 1, a.y, b.x])
			if ls[k].visibility_range_end < a.y + a.w * 0.5 or ls[k + 1].visibility_range_begin > b.x - b.z * 0.5:
				bad.append("%s LOD%d 粗剔除切到交叉帶" % [tid, k])
	r1s.sort()
	r2s.sort()
	_res("lod", bad.is_empty(), "%d 棵：級數（樹 4／地被 3）、LOD1 %.0f–%.0f %%、LOD2 %.0f–%.0f %%（規格 ≈ 40 %%／10–20 %%）、高度差 ≤ 8 %%、抖動換檔帶首尾相接：違規 %s" % [
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
				# BC/ETC 壓縮 RGBA ≈ 1 byte/px（BC7／BC3）、RGB ≈ 0.5；mipmaps ×1.33
				vram += tx.get_width() * tx.get_height() * 1.0 * 1.33 / 1048576.0
	var parts: Array = []
	for k: String in by:
		parts.append("%s 最大 %d／%d" % [k, by[k], CAP[k]])
	_res("perf", bad.is_empty() and vram <= VRAM_MAX_MB, "LOD0 類別上限：%s；每級 surface ≤ 2；全庫 LOD0 合計 %d（每種一棵）；Kit 貼圖 VRAM 估 %.1f MB（≤ %.0f）；違規 %s" % [
		"、".join(parts), total, vram, VRAM_MAX_MB, "、".join(bad) if bad else "0"])


# ─────────────────────────── gate.json ───────────────────────────

func _write_gate(part: String, keys: Array[String]) -> void:
	var sha := FileAccess.get_sha256(ENTRY)
	var g: Dictionary = {}
	if FileAccess.file_exists(GATE):
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(GATE))
		if old is Dictionary and String(old.get("entry_sha256", "")) == sha:
			g = old
	g["asset"] = "veg_kit"
	g["entry"] = ENTRY
	g["entry_sha256"] = sha
	g["godot"] = Engine.get_version_info()["string"]
	g["scope"] = "P9 R1：植被庫獨立審圖（未植入 village_v2；地塊／F5 實走於 R2）"
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


## 截圖輪次（新→舊）：重做輪只重拍重做的樹；未改的樹幾何逐位元不變（build_veg_kit.py --hash 比對），沿用前一輪截圖
const SHOT_ROUNDS := ["r1c", "r1b", "r1"]


func _shot(name: String) -> String:
	var base := (ProjectSettings.globalize_path("res://") + "../docs/art_review/village_v2_p9_vegetation").simplify_path()
	for r: String in SHOT_ROUNDS:
		var p := base.path_join(r).path_join("shots").path_join(name)
		if FileAccess.file_exists(p):
			return p
	return base.path_join(SHOT_ROUNDS[0]).path_join("shots").path_join(name)


func _render() -> void:
	var miss: Array = []
	var flat: Array = []
	var n := 0
	var lo := INF
	var groups := {}
	for tid: String in trees:
		groups[String(trees[tid]["group"])] = true
		for v in ["near", "mid", "top", "lods", "sweep"]:
			var p := _shot("%s_%s.png" % [tid, v])
			if not FileAccess.file_exists(p):
				miss.append(p.get_file())
				continue
			var img := Image.load_from_file(p)
			var sd := _img_std(img)
			lo = minf(lo, sd)
			n += 1
			if sd < 0.03:
				flat.append("%s %.3f" % [p.get_file(), sd])
	for g: String in groups:
		for v in ["far50", "far100"]:
			var p := _shot("group_%s_%s.png" % [g, v])
			if not FileAccess.file_exists(p):
				miss.append(p.get_file())
				continue
			var sd := _img_std(Image.load_from_file(p))
			lo = minf(lo, sd)
			n += 1
			if sd < 0.03:
				flat.append("%s %.3f" % [p.get_file(), sd])
	_res("player_screenshot", miss.is_empty() and flat.is_empty(), "審圖截圖 %d 張（每棵 near 1.7 m／mid 10–20 m／top 35°／LOD 階梯／換檔掃描，群組 50 m／100 m 剪影）：缺 %s；空白（亮度標準差 < 0.03）%s；最低 %.3f；村內玩家視角＝P9 R2" % [
		n, "、".join(miss.slice(0, 5)) if miss else "0", "、".join(flat) if flat else "0", lo])
	# F6：審圖場景 120 幀，Logger 錯誤 0
	var lg := _Log.new()
	OS.add_logger(lg)
	var sc: Node3D = (load(REVIEW) as PackedScene).instantiate()
	root.add_child(sc)
	var cam := Camera3D.new()
	sc.add_child(cam)
	cam.current = true
	cam.position = Vector3(0, 1.7, 30)
	for i in 120:
		cam.position.z = 30.0 - i * 2.0
		await process_frame
	OS.remove_logger(lg)
	_res("f5_f6", lg.n == 0, "F6＝審圖場景（%d 棵 × 自動 LOD＋LOD 階梯）相機穿越 120 幀、Logger 錯誤 %d；F5＝P9 R2 植入 village_v2 後實走" % [
		trees.size(), lg.n])
	sc.queue_free()
	_flush(RENDER_KEYS)
	if neg == "":
		_write_gate("render", RENDER_KEYS)
