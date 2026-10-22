extends SceneTree
## 建築快速通道（Fast Lane，使用者 2026-10-18 裁定）：一支指令把一個 GLB 建築放進地圖。
## 不經 registry／asset.json／11 項 Hero gate／封存——那套保留給已存在的資產，新建築一律走這裡。
##
## 通常不直接跑這支，而是用包裝腳本（會先複製 GLB 並讓 Godot 匯入、自動產生 LOD）：
##   bash godot/tools/fastlane/place_building.sh --glb="D:/資產glb/町家/農舍.glb" --id=farmhouse_a --at=120,-40 --yaw=90 --height=7
##
## 參數（-- 之後）：
##   --id=<ascii id>        必填。資產資料夾 assets/village_v2/fastlane/<id>/，場景節點 FastLane/<id>
##   --at=x,z               世界座標（XZ）；或 --anchor=<NodePath>（取該節點的 XZ 與 yaw）
##   --yaw=deg              朝向（模型 +z 轉到這個角度；預設 0 或 anchor 的 yaw）
##   --height=m | --scale=s 等比縮放：目標總高（公尺）或倍率；都不給＝原尺寸
##   --sink=m               埋入地面（預設 0.08）
##   --collision=trimesh|convex|box  預設 trimesh（直接用網格三角形，可走上台階、進得了門）
##   --find=R               在 --at 周圍 R 公尺內找第一個三項都過的位置
##   --replace=<NodePath>   一併隱藏並停用碰撞的舊節點（灰盒／佔位）；只限 village_v2.tscn 本體裡的節點
##   --scene=res://…        目標場景（預設 res://maps/village_v2/village_v2.tscn）
##   --dry                  只量測＋截圖，不寫場景
##   --force                有穿插（FAIL）也照樣寫入
##   --remove               從場景移除 FastLane/<id>（資產檔保留）
##   --editor-ok            Godot 編輯器開著也寫（預設拒絕，避免互相覆蓋）
##   --layout=organic|structured|landmark|off  第 4 項道路排列的模式（預設 organic）
##   --setback=m [--setback-tol=m]  structured 的指定退縮（腳印到路緣）
##   --axis-target=x,z | --sando=<道路名>    landmark 的主軸參考（沒給 → UNKNOWN，不猜）
##   --front=+z|-z|+x|-x  --entrance=lx,lz   模型正面與入口（模型局部；預設 +Z 與正面中點）
##   --expect=<abs.json>    Blender 端 arch_check.py --godot-expect 的期望值（另比 Blender→GLB→匯入、正面標記）
## 產出：assets/village_v2/fastlane/<id>/<id>.tscn（可單獨開啟編輯）＋ <id>_collision.res；
##       docs/fastlane/<id>/sheet.jpg（4 張玩家視角）＋ result.json（arch：結構化結果列，欄位同 tools/blender/arch_spatial.py）。
## 檢查：接地、穿插、可達、layout（道路排列，arch_spatial_lib.gd），外加 consistency（GLB 原始資料 vs 匯入 vs 放置後的 Parent 鏈）。
## 這不是美術驗收；看圖後由使用者決定（ART_REVIEW → ART_APPROVED）。

const DEFAULT_SCENE := "res://maps/village_v2/village_v2.tscn"
const ROOT_DIR := "res://assets/village_v2/fastlane/"
const NL := "\r\n"
const EDITOR_EXE := "Godot_v4.7.2-stable_win64.exe"
const ARCH := preload("res://tools/arch_spatial_lib.gd")

var A := {}
var id := ""
var scene_path := DEFAULT_SCENE
var result := {"checks": {}}
var t0 := 0
var gltf_ref := {}            # GLB 原始資料（GLTFDocument，模型局部）
var arch_rows: Array = []     # Phase 7／Phase 5 的結構化結果列（arch_spatial 同一份欄位）
var consistency_check := {}   # 匯入一致性 → 併入每個候選位置的 checks


func _init() -> void:
	t0 = Time.get_ticks_msec()
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			A[kv[0]] = kv[1] if kv.size() > 1 else "1"
	id = String(A.get("id", ""))
	scene_path = String(A.get("scene", DEFAULT_SCENE))
	if id == "" or not id.is_valid_identifier():
		_die("需要 --id=<英數底線>（拿來當資料夾與節點名；中文名請放 --label）")
		return
	_main.call_deferred()


func _die(msg: String, code := 1) -> void:
	print("[FASTLANE] FAIL %s" % msg)
	quit(code)


func _log(msg: String) -> void:
	print("[FASTLANE] %s  (%.1fs)" % [msg, (Time.get_ticks_msec() - t0) / 1000.0])


func _main() -> void:
	var writes := not A.has("dry")
	if writes and not A.has("editor-ok") and _editor_running():
		_die("Godot 編輯器開著：先存檔關閉（或加 --editor-ok），否則場景會被互相覆蓋")
		return
	if A.has("remove"):
		var ok := _unmount()
		quit(0 if ok else 1)
		return
	var dir := ROOT_DIR + id + "/"
	var glb := dir + id + ".glb"
	if not ResourceLoader.exists(glb):
		_die("%s 不存在或還沒匯入（用 place_building.sh，它會先複製並 --import）" % glb)
		return
	# ── 1. 包裝場景：模型（縮放＋原點移到腳印中心底部）＋ 由網格產生的碰撞
	var wrapper := _build_wrapper(load(glb) as PackedScene, dir)
	if wrapper == null:
		return
	_log("包裝場景完成：%s" % (dir + id + ".tscn"))
	# ── 2. 載入目標場景、等物理就緒
	var ps := load(scene_path) as PackedScene
	if ps == null:
		_die("讀不到場景 %s" % scene_path)
		return
	var world := ps.instantiate() as Node3D
	root.add_child(world)
	for i in 4:
		await physics_frame
	_log("場景載入：%s" % scene_path)
	# 重跑同一個 id：場景裡已經掛著上一次的自己，先拿掉，否則會跟自己「穿插」
	var prev := world.get_node_or_null("FastLane/" + id)
	if prev != null:
		prev.get_parent().remove_child(prev)
		prev.free()
		await physics_frame
	var terrain := world.get_node_or_null("Collision/TerrainCollision") as CollisionObject3D
	if terrain == null:
		_die("場景沒有 Collision/TerrainCollision")
		return
	var space := world.get_world_3d().direct_space_state
	# ── 3. 位置
	var at := Vector2.ZERO
	var yaw := float(A.get("yaw", "0"))
	if A.has("anchor"):
		var an := world.get_node_or_null(String(A["anchor"])) as Node3D
		if an == null:
			_die("找不到 anchor %s" % A["anchor"])
			return
		at = Vector2(an.global_position.x, an.global_position.z)
		if not A.has("yaw"):
			yaw = rad_to_deg(an.global_rotation.y)
	elif A.has("at"):
		var p := String(A["at"]).split(",")
		at = Vector2(float(p[0]), float(p[1]))
	else:
		_die("需要 --at=x,z 或 --anchor=<NodePath>")
		return
	var replaced: Node3D = null
	if A.has("replace"):
		replaced = world.get_node_or_null(String(A["replace"])) as Node3D
		if replaced == null:
			_die("找不到 --replace 節點 %s" % A["replace"])
			return
		_retire_live(replaced)
	var inst := (load(dir + id + ".tscn") as PackedScene).instantiate() as Node3D
	world.add_child(inst)
	var fp: Rect2 = wrapper["footprint"]
	var candidates: Array = [at]
	if A.has("find"):
		candidates = _spiral(at, float(A["find"]), maxf(fp.size.x, fp.size.y) * 0.5)
	var best := {}
	for c: Vector2 in candidates:
		var r := await _evaluate(inst, c, yaw, fp, wrapper["base"], float(wrapper["sink"]), space, terrain)
		if best.is_empty() or _score(r) > _score(best):
			best = r
		if _passes(r):
			break
	if not best.has("xform"):
		_die("腳印下找不到地形（位置在地圖外？）")
		return
	inst.global_transform = best["xform"]
	await physics_frame
	result.merge(best, true)
	result["xform"] = var_to_str(best["xform"])
	arch_rows += best.get("layout_rows", [])
	result.erase("layout_rows")
	_placed_consistency(inst, wrapper["mx"])
	_log("位置 (%.2f, %.2f, %.2f) yaw %.1f°" % [best["xform"].origin.x, best["xform"].origin.y, best["xform"].origin.z, yaw])
	for k: String in result["checks"]:
		var ck: Dictionary = result["checks"][k]
		print("[FASTLANE] %s %s：%s" % [ck["result"], k, ck["detail"]])
	# ── 4. 截圖（需要畫面；headless 時跳過）
	if DisplayServer.get_name() != "headless" and not A.has("no-shots"):
		await _shots(inst, best, float(wrapper["height"]), fp)
	else:
		result["shots"] = "skipped（headless）"
	# ── 5. 寫入
	var failed := not _passes(result)
	result["written"] = false
	if writes and (not failed or A.has("force")):
		if _mount(best["xform"]):
			result["written"] = true
	elif writes:
		print("[FASTLANE] 有 FAIL，不寫入場景（看過圖仍要放就加 --force）")
	_save_result()
	_log("完成：written=%s" % result["written"])
	quit(0 if (result["written"] or not writes) else 2)


# ─────────────────────────── 包裝場景 ───────────────────────────

func _build_wrapper(src: PackedScene, dir: String) -> Dictionary:
	if src == null:
		_die("GLB 讀不成 PackedScene")
		return {}
	var model := src.instantiate() as Node3D
	var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	if meshes.is_empty():
		_die("GLB 裡沒有 MeshInstance3D")
		return {}
	_import_consistency(model, dir + id + ".glb")
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in meshes:
		var xf := _rel_xform(mi, model)
		var b := xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var s := 1.0
	if A.has("height"):
		s = float(A["height"]) / box.size.y
	elif A.has("scale"):
		s = float(A["scale"])
	var sink := float(A.get("sink", "0.08"))
	var c := box.get_center()
	# 模型局部：縮放後，腳印中心→原點、底面→ −sink
	var mx := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(-c.x * s, -box.position.y * s - sink, -c.z * s))
	var w := Node3D.new()
	w.name = id
	model.name = "Model"
	model.transform = mx
	w.add_child(model)
	model.owner = w
	var body := StaticBody3D.new()
	body.name = "Collision"
	w.add_child(body)
	body.owner = w
	var mode := String(A.get("collision", "trimesh"))
	var faces := PackedVector3Array()
	var pts := PackedVector3Array()
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		var xf := mx * _rel_xform(mi, model)
		for v in mi.mesh.get_faces():
			faces.append(xf * v)
	var full_tris := faces.size() / 3
	var max_tris := int(A.get("max-collision-tris", "20000"))
	if mode == "trimesh" and full_tris > max_tris:
		var lod_faces := _lod_faces(dir + id + ".glb", mx, float(max_tris) / full_tris)
		if lod_faces.size() > 0:
			_log("碰撞減面：%d → %d 三角形（取 Godot 自動 LOD）" % [full_tris, lod_faces.size() / 3])
			faces = lod_faces
		if faces.size() / 3 > max_tris:
			var area := 0.0
			for t in range(0, faces.size() - 2, 3):
				area += (faces[t + 1] - faces[t]).cross(faces[t + 2] - faces[t]).length() * 0.5
			var cell := clampf(sqrt(2.0 * area / max_tris), 0.05, 1.0)
			for attempt in 4:
				var cl := _cluster(faces, cell)
				if cl.size() / 3 <= max_tris or attempt == 3:
					_log("碰撞減面：頂點聚類 %.2f m 格 → %d 三角形（誤差 ≤ 格寬）" % [cell, cl.size() / 3])
					faces = cl
					break
				cell *= 1.4
	for v in faces:
		pts.append(v)
	var shape: Shape3D
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for v in faces:
		lo = lo.min(v)
		hi = hi.max(v)
	# 牆腳範圍：離底 0.3 m 內的頂點（不含屋簷）→ 接地量測與 Foot 薄箱都用它
	var blo := Vector2.INF
	var bhi := -Vector2.INF
	for v in faces:
		if v.y < lo.y + 0.3:
			blo = blo.min(Vector2(v.x, v.z))
			bhi = bhi.max(Vector2(v.x, v.z))
	if blo.x == INF:
		blo = Vector2(lo.x, lo.z)
		bhi = Vector2(hi.x, hi.z)
	match mode:
		"convex":
			var cv := ConvexPolygonShape3D.new()
			cv.points = pts
			shape = cv
		"box":
			var bx := BoxShape3D.new()
			bx.size = hi - lo
			shape = bx
		_:
			var cc := ConcavePolygonShape3D.new()
			cc.set_faces(faces)
			shape = cc
	var shape_path := dir + id + "_collision.res"
	ResourceSaver.save(shape, shape_path)
	shape = load(shape_path) as Shape3D
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	if mode == "box":
		cs.position = (lo + hi) * 0.5
	body.add_child(cs)
	cs.owner = w
	var foot := CollisionShape3D.new()
	foot.name = "Foot"
	var fb := BoxShape3D.new()
	fb.size = Vector3(bhi.x - blo.x, 0.3, bhi.y - blo.y)
	foot.shape = fb
	foot.position = Vector3((blo.x + bhi.x) * 0.5, lo.y + 0.15, (blo.y + bhi.y) * 0.5)
	foot.set_meta("foot", true)
	body.add_child(foot)
	foot.owner = w
	w.set_meta("fastlane", {"glb": dir + id + ".glb", "label": String(A.get("label", "")),
		"scale": s, "sink": sink, "collision": mode, "tris": faces.size() / 3,
		"date": Time.get_datetime_string_from_system()})
	var ps := PackedScene.new()
	var err := ps.pack(w)
	if err == OK:
		err = ResourceSaver.save(ps, dir + id + ".tscn")
	w.free()
	if err != OK:
		_die("包裝場景存檔失敗 %s" % error_string(err))
		return {}
	var size := (hi - lo)
	result["model"] = {"scale": snappedf(s, 0.0001), "size_m": [snappedf(size.x, 0.01), snappedf(size.y, 0.01), snappedf(size.z, 0.01)],
		"collision": mode, "collision_tris": faces.size() / 3}
	_log("模型 %.2f × %.2f × %.2f m（寬×高×深），縮放 %.4f，碰撞 %s %d 三角形" % [size.x, size.y, size.z, s, mode, faces.size() / 3])
	return {"footprint": Rect2(lo.x, lo.z, hi.x - lo.x, hi.z - lo.z), "height": hi.y,
		"base": Rect2(blo.x, blo.y, bhi.x - blo.x, bhi.y - blo.y), "sink": sink, "mx": mx}


# ─────────────────────────── Phase 7：匯入一致性 ───────────────────────────

## GLB 原始資料（GLTFDocument 讀檔，不經匯入器）vs Godot 匯入後的節點：尺寸、原點、旋轉、每軸縮放、負縮放。
## --expect=<json>（Blender 端 arch_check.py --godot-expect）另外比 Blender→GLB 與 Blender→匯入；有 front_node 時查正面。
## 找不到對應節點一律 FAIL，參考資料是空的 → UNKNOWN（不當 PASS）。
func _import_consistency(model: Node3D, glb: String) -> void:
	var rows: Array = []
	gltf_ref = ARCH.gltf_mesh_nodes(glb)
	var got := ARCH.scene_mesh_nodes(model)
	if gltf_ref.has("_error") or gltf_ref.is_empty():
		rows.append(ARCH.row("glb_vs_import", "IMPORT_CONSISTENCY", id, [], "UNKNOWN", "GLB mesh nodes",
			gltf_ref.get("_error", "GLB 沒有網格節點"), null, null, "gltf_document", "讀不到 GLB 原始資料，無法比對"))
		gltf_ref = {}
	else:
		rows += ARCH.compare_nodes(id, gltf_ref, got, "glb_vs_import")
	if A.has("expect"):
		var ref := ARCH.load_expect(String(A["expect"]))
		if ref.has("_error"):
			rows.append(ARCH.row("blender_expect", "IMPORT_CONSISTENCY", id, [], "UNKNOWN", "expect json", ref["_error"],
				null, null, "load_expect", "--expect 讀不到"))
		else:
			if not gltf_ref.is_empty():
				rows += ARCH.compare_nodes(id, ref, gltf_ref, "blender_vs_glb")
			rows += ARCH.compare_nodes(id, ref, got, "blender_vs_import")
			if ref.has("_front_node"):
				rows.append(ARCH.front_check(id, got, ref["_front_node"], "import"))
	arch_rows += rows
	var w := ARCH.worst(rows)
	var bad: Array = rows.filter(func(r): return r["status"] != "PASS")
	var detail := "匯入一致性 %d 項（%s）" % [rows.size(), JSON.stringify(ARCH.summarize(rows))]
	if not bad.is_empty():
		detail += "：" + "；".join(bad.slice(0, 4).map(func(r): return "%s %s" % [r["rule_id"], r["suggestion"]]))
	consistency_check = {"result": w, "detail": detail}
	_log(detail)


## 放置後：整條 Parent 鏈（FastLane/<id> → Model → GLB 節點）的世界 Transform 必須 = 放置 × 包裝 × GLB 節點；
## 包裝根局部的 AABB（只有縮放＋平移，沒有旋轉）必須 = 包裝 × GLB 的 AABB。
func _placed_consistency(inst: Node3D, mx: Transform3D) -> void:
	if gltf_ref.is_empty():
		return
	var model := inst.get_node("Model") as Node3D
	var local_ref := {}
	var world_ref := {}
	for nm: String in gltf_ref.keys():
		var r: Dictionary = gltf_ref[nm]
		var box := mx * AABB(r["lo"], (r["hi"] as Vector3) - (r["lo"] as Vector3))
		local_ref[nm] = {"lo": box.position, "hi": box.end, "xform": mx * (r["xform"] as Transform3D)}
		world_ref[nm] = {"lo": Vector3.ZERO, "hi": Vector3.ZERO, "xform": inst.global_transform * mx * (r["xform"] as Transform3D)}
	var got_local := ARCH.scene_mesh_nodes(model)
	for nm: String in got_local.keys():
		got_local[nm]["xform"] = model.transform * (got_local[nm]["xform"] as Transform3D)
		var b := model.transform * AABB(got_local[nm]["lo"], (got_local[nm]["hi"] as Vector3) - (got_local[nm]["lo"] as Vector3))
		got_local[nm]["lo"] = b.position
		got_local[nm]["hi"] = b.end
	var got_world := {}
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		got_world[String(mi.name)] = {"lo": Vector3.ZERO, "hi": Vector3.ZERO, "xform": mi.global_transform}
	var rows: Array = ARCH.compare_nodes(id, local_ref, got_local, "wrapper_local")
	rows += ARCH.compare_nodes(id, world_ref, got_world, "placed_world")
	arch_rows += rows
	var w := ARCH.worst(rows + [{"status": consistency_check.get("result", "PASS")}])
	if w != consistency_check.get("result", "PASS"):
		consistency_check["result"] = w
	consistency_check["detail"] += "；放置鏈 %d 項 %s" % [rows.size(), JSON.stringify(ARCH.summarize(rows))]
	result["checks"]["consistency"] = consistency_check


func _rel_xform(n: Node3D, anc: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != anc:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## 碰撞用減面三角形：重新以 GLTFDocument 讀原 GLB，ImporterMesh.generate_lods 後每個 surface 取
## 「三角形數 ≤ 原數 × ratio」的第一個 LOD（都不夠小就取最後一級）。回傳包裝場景座標的三角形頂點（每 3 個一組）。
func _lod_faces(glb: String, mx: Transform3D, ratio: float) -> PackedVector3Array:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(glb), st) != OK:
		return PackedVector3Array()
	var nodes: Array = st.get_nodes()
	var gm: Array = st.get_meshes()
	var out := PackedVector3Array()
	for ni in nodes.size():
		var nd: GLTFNode = nodes[ni]
		if nd.get_mesh() < 0:
			continue
		var xf := Transform3D.IDENTITY
		var k := ni
		while k >= 0:
			xf = (nodes[k] as GLTFNode).get_xform() * xf
			k = (nodes[k] as GLTFNode).get_parent()
		xf = mx * xf
		var im: ImporterMesh = (gm[nd.get_mesh()] as GLTFMesh).get_mesh()
		im.generate_lods(60.0, 25.0, [])
		for s in im.get_surface_count():
			if im.get_surface_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arr := im.get_surface_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var base_n := idx.size() if idx.size() > 0 else verts.size()
			for l in im.get_surface_lod_count(s):
				var li := im.get_surface_lod_indices(s, l)
				idx = li
				if li.size() <= base_n * ratio:
					break
			if idx.is_empty():
				for v in verts:
					out.append(xf * v)
			else:
				for i in idx:
					out.append(xf * verts[i])
	return out


## 頂點聚類減面：頂點吸到 cell 公尺的格點（格內平均），丟掉退化三角形。只拿來做碰撞。
func _cluster(faces: PackedVector3Array, cell: float) -> PackedVector3Array:
	var n := faces.size()
	var keys := PackedInt64Array()
	keys.resize(n)
	var slot := {}
	var sums := PackedVector3Array()
	var cnts := PackedInt32Array()
	var inv := 1.0 / cell
	for i in n:
		var v := faces[i]
		var k := ((floori(v.x * inv) + 1048576) << 42) | ((floori(v.y * inv) + 1048576) << 21) | (floori(v.z * inv) + 1048576)
		var s: int = slot.get(k, -1)
		if s < 0:
			s = sums.size()
			slot[k] = s
			sums.append(Vector3.ZERO)
			cnts.append(0)
		sums[s] += v
		cnts[s] += 1
		keys[i] = s
	for s in sums.size():
		sums[s] /= cnts[s]
	var out := PackedVector3Array()
	for t in range(0, n - 2, 3):
		var a := keys[t]
		var b := keys[t + 1]
		var c := keys[t + 2]
		if a == b or b == c or a == c:
			continue
		out.append(sums[a])
		out.append(sums[b])
		out.append(sums[c])
	return out


# ─────────────────────────── 量測 ───────────────────────────

## 接地規約＝場景擺放稽核（audit_village_v2_placement.gd）同一套：地形高出地板面 ≤ GRADE_TOL、可見底懸空 ≤ FLOAT_FAIL。
## 地板面 y 取兩條件的交集；腳印（牆腳範圍）內起伏 > GRADE_TOL＋FLOAT_FAIL＋sink 就放不平 → FAIL（換位置、--find，或另做基壇）。
const GRADE_TOL := 0.05
const FLOAT_FAIL := 0.15

func _evaluate(inst: Node3D, at: Vector2, yaw: float, fp: Rect2, base_r: Rect2, sink: float, space: PhysicsDirectSpaceState3D, terrain: CollisionObject3D) -> Dictionary:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw))
	var nx := clampi(ceili(base_r.size.x / 1.0) + 1, 3, 20)
	var nz := clampi(ceili(base_r.size.y / 1.0) + 1, 3, 20)
	var ys: Array[float] = []
	for i in nx:
		for j in nz:
			var lp := Vector3(lerpf(base_r.position.x + 0.1, base_r.end.x - 0.1, float(i) / (nx - 1)), 0,
				lerpf(base_r.position.y + 0.1, base_r.end.y - 0.1, float(j) / (nz - 1)))
			var wp := basis * lp + Vector3(at.x, 0, at.y)
			var y: Variant = _terrain_y(space, terrain, wp)
			if y != null:
				ys.append(y)
	if ys.is_empty():
		return {}
	ys.sort()
	var t_lo: float = ys[0]
	var t_hi: float = ys[-1]
	var relief := t_hi - t_lo
	# 地板面 y：地形頂進屋內 t_hi − y ≤ GRADE_TOL，且可見底 (y − sink) − t_lo ≤ FLOAT_FAIL
	var y_min := t_hi - GRADE_TOL
	var y_max := t_lo + sink + FLOAT_FAIL
	var y0 := minf(y_min, y_max) if y_min > y_max else y_min
	var limit := GRADE_TOL + FLOAT_FAIL + sink
	var xf := Transform3D(basis, Vector3(at.x, y0, at.y))
	inst.global_transform = xf
	await physics_frame
	await physics_frame
	var r := {"xform": xf, "at": [snappedf(at.x, 0.01), snappedf(at.y, 0.01)], "checks": {}}
	var poke := t_hi - y0
	var flt := (y0 - sink) - t_lo
	r["checks"]["ground"] = {"result": "PASS" if relief <= limit else "FAIL",
		"detail": "牆腳範圍內地形起伏 %.2f m（上限 %.2f）：地形高出地板 %.2f m、低側可見底懸空 %.2f m；%d 點" % [relief, limit, poke, maxf(flt, 0.0), ys.size()],
		"relief_m": snappedf(relief, 0.01)}
	r["checks"]["overlap"] = _overlap(inst, space, terrain)
	r["checks"]["access"] = _access(inst, fp, basis, at, space, terrain)
	if String(A.get("layout", "organic")) != "off":
		var lr := _layout_check(inst, fp, basis, at)
		r["layout_rows"] = lr
		var bad: Array = lr.filter(func(x): return x["status"] != "PASS")
		r["checks"]["layout"] = {"result": ARCH.worst(lr),
			"detail": "%s 排列 %d 項 %s%s" % [String(A.get("layout", "organic")), lr.size(), JSON.stringify(ARCH.summarize(lr)),
				("：" + "；".join(bad.slice(0, 3).map(func(x): return "%s %s" % [x["rule_id"], x["suggestion"]]))) if not bad.is_empty() else ""]}
	if not consistency_check.is_empty():
		r["checks"]["consistency"] = consistency_check.duplicate()
	return r


# ─────────────────────────── Phase 5：道路排列（第 4 項） ───────────────────────────
const LAYOUT_FILE := "res://maps/village_v2/layout_v2.json"
var _road_lines: Array = []
var _neighbour_cache: Array = []


## 正面＝模型 +Z（--front=-z|+x|-x 可改）；入口＝正面那一邊腳印的中點（--entrance=lx,lz 可改，模型局部）。
func _layout_check(inst: Node3D, fp: Rect2, basis: Basis, at: Vector2) -> Array:
	if _road_lines.is_empty():
		_road_lines = ARCH.road_lines(String(A.get("layout-file", LAYOUT_FILE)))
	var fl := {"+z": Vector3(0, 0, 1), "-z": Vector3(0, 0, -1), "+x": Vector3(1, 0, 0), "-x": Vector3(-1, 0, 0)}
	var f3: Vector3 = fl.get(String(A.get("front", "+z")), Vector3(0, 0, 1))
	var c3 := Vector3(fp.get_center().x, 0, fp.get_center().y)
	var e3 := c3 + Vector3(f3.x * fp.size.x * 0.5, 0, f3.z * fp.size.y * 0.5)
	if A.has("entrance"):
		var ep := String(A["entrance"]).split(",")
		e3 = Vector3(float(ep[0]), 0, float(ep[1]))
	var off := Vector3(at.x, 0, at.y)
	var poly := PackedVector2Array()
	for p in [fp.position, Vector2(fp.end.x, fp.position.y), fp.end, Vector2(fp.position.x, fp.end.y)]:
		var w := basis * Vector3(p.x, 0, p.y) + off
		poly.append(Vector2(w.x, w.z))
	var fw := basis * f3
	var cw := basis * c3 + off
	var ew := basis * e3 + off
	var b := {"center": Vector2(cw.x, cw.z), "front": Vector2(fw.x, fw.z), "entrance": Vector2(ew.x, ew.z), "poly": poly}
	var mode := String(A.get("layout", "organic"))
	if mode == "structured":
		b["neighbors"] = _neighbours(inst, Vector2(cw.x, cw.z), 40.0)
	var opts := {"mode": mode}
	if A.has("setback"):
		opts["setback"] = float(A["setback"])
	if A.has("setback-tol"):
		opts["setback_tol"] = float(A["setback-tol"])
	if A.has("axis-target"):
		var tp := String(A["axis-target"]).split(",")
		opts["axis_target"] = Vector2(float(tp[0]), float(tp[1]))
	if A.has("sando"):
		opts["sando"] = String(A["sando"])
	return ARCH.road_alignment(id, _road_lines, b, opts)


## 鄰棟腳印（保留 yaw）：FastLane/*、Districts/**/B_*、Landmarks/*/Hero，第一次呼叫時收集一次。
func _neighbours(inst: Node3D, c: Vector2, radius: float) -> Array:
	var world := inst.get_parent()
	if _neighbour_cache.is_empty():
		var cands: Array = []
		var fl := world.get_node_or_null("FastLane")
		if fl:
			cands += fl.get_children()
		var ds := world.get_node_or_null("Districts")
		if ds:
			cands += ds.find_children("B_*", "", true, false)
		var lm := world.get_node_or_null("Landmarks")
		if lm:
			cands += lm.find_children("Hero", "", true, false)
		for n in cands:
			if n == inst or not (n is Node3D) or (n as Node3D).has_meta("retired_by_hero") or not (n as Node3D).is_visible_in_tree():
				continue
			var poly := ARCH.footprint_xz(n as Node3D)
			if poly.size() >= 3:
				_neighbour_cache.append({"name": String(world.get_path_to(n)), "poly": poly})
	return _neighbour_cache.filter(func(x): return ARCH._centroid(x["poly"]).distance_to(c) <= radius)


## 環境查詢只認玩家撞得到的靜態物（2026-10-22）：玩家 CharacterBody3D 預設遮罩 layer 1；NPC 身體／布料代理是會動的物體。
## 阿求袖子模擬 floor_collision 的 WorldBoundaryShape3D（layer 20 無限平面）讓外圍膠囊 23/23 點、鏡位探測全部被擋（noka_b 實測）。
const PLAYER_MASK := 1


static func _is_env(o: Object) -> bool:
	return not (o is AnimatableBody3D or o is CharacterBody3D or o is RigidBody3D or o is PhysicalBone3D)


static func _blocked(space: PhysicsDirectSpaceState3D, q: PhysicsShapeQueryParameters3D) -> bool:
	q.collision_mask = PLAYER_MASK
	for h in space.intersect_shape(q, 8):
		if _is_env(h["collider"]):
			return true
	return false


static func _ray_env(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, ex: Array[RID]) -> Dictionary:
	var rq := PhysicsRayQueryParameters3D.create(a, b, PLAYER_MASK)
	for i in 8:
		rq.exclude = ex
		var hit := space.intersect_ray(rq)
		if hit.is_empty() or _is_env(hit["collider"]):
			return hit
		ex.append(hit["rid"])
	return {}


func _terrain_y(space: PhysicsDirectSpaceState3D, terrain: CollisionObject3D, wp: Vector3) -> Variant:
	var q := PhysicsRayQueryParameters3D.create(Vector3(wp.x, 400, wp.z), Vector3(wp.x, -200, wp.z))
	var ex: Array[RID] = []
	for k in 12:
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return null
		if hit["rid"] == terrain.get_rid():
			return (hit["position"] as Vector3).y
		ex.append(hit["rid"])
	return null


## 穿插：把「別人的」碰撞形狀當查詢，只對本建築求接觸深度（本建築是三角網格，不能當查詢形狀）。
func _overlap(inst: Node3D, space: PhysicsDirectSpaceState3D, terrain: CollisionObject3D) -> Dictionary:
	var me := inst.get_node("Collision") as CollisionObject3D
	var my_box := _world_aabb(inst).grow(0.1)
	var others: Array = []
	var all_rids: Array[RID] = []
	for co: CollisionObject3D in inst.get_parent().find_children("*", "CollisionObject3D", true, false):
		if co == me or co == terrain:
			continue
		all_rids.append(co.get_rid())
		if co.collision_layer & PLAYER_MASK == 0 or not _is_env(co):
			continue
		for c in co.get_children():
			if c is CollisionShape3D and not (c as CollisionShape3D).disabled and (c as CollisionShape3D).shape != null:
				var cs := c as CollisionShape3D
				if (cs.global_transform * cs.shape.get_debug_mesh().get_aabb()).intersects(my_box):
					others.append(cs)
	all_rids.append(terrain.get_rid())
	var hits := {}
	for cs: CollisionShape3D in others:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cs.shape
		q.transform = cs.global_transform
		q.exclude = all_rids
		var pts := space.collide_shape(q, 32)
		var depth := 0.0
		for i in range(0, pts.size() - 1, 2):
			depth = maxf(depth, (pts[i] as Vector3).distance_to(pts[i + 1]))
		if depth > 0.05:
			var nm := String(inst.get_parent().get_path_to(cs.get_parent()))
			hits[nm] = maxf(float(hits.get(nm, 0.0)), depth)
	var names: Array = hits.keys()
	names.sort_custom(func(a, b): return hits[a] > hits[b])
	var detail := "與既有碰撞體穿插 > 0.05 m：%d 個（候選 %d）" % [names.size(), others.size()]
	if not names.is_empty():
		detail += "：" + ", ".join(names.slice(0, 5).map(func(n): return "%s %.2f m" % [n, hits[n]]))
	return {"result": "PASS" if names.is_empty() else "FAIL", "detail": detail, "bodies": names.slice(0, 20)}


## 可達：腳印外 1.5 m 一圈，每 ~2 m 一個點，玩家膠囊（r 0.35、高 1.7）站不站得下。
func _access(inst: Node3D, fp: Rect2, basis: Basis, at: Vector2, space: PhysicsDirectSpaceState3D, terrain: CollisionObject3D) -> Dictionary:
	var g := fp.grow(1.5)
	var ring: Array[Vector3] = []
	var per := g.size.x * 2 + g.size.y * 2
	var n := clampi(int(per / 2.0), 8, 64)
	for k in n:
		var d := per * k / n
		var p: Vector2
		if d < g.size.x:
			p = Vector2(g.position.x + d, g.position.y)
		elif d < g.size.x + g.size.y:
			p = Vector2(g.end.x, g.position.y + d - g.size.x)
		elif d < g.size.x * 2 + g.size.y:
			p = Vector2(g.end.x - (d - g.size.x - g.size.y), g.end.y)
		else:
			p = Vector2(g.position.x, g.end.y - (d - g.size.x * 2 - g.size.y))
		ring.append(basis * Vector3(p.x, 0, p.y) + Vector3(at.x, 0, at.y))
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	var free := 0
	for wp in ring:
		var y: Variant = _terrain_y(space, terrain, wp)
		if y == null:
			continue
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cap
		q.transform = Transform3D(Basis.IDENTITY, Vector3(wp.x, float(y) + 0.85 + 0.12, wp.z))
		q.exclude = [terrain.get_rid()]
		if not _blocked(space, q):
			free += 1
	var frac := float(free) / maxf(1, ring.size())
	return {"result": "PASS" if frac >= 0.5 else ("REVIEW" if frac >= 0.25 else "FAIL"),
		"detail": "外圍 1.5 m 一圈 %d 點，玩家站得下 %d 點（%.0f%%）" % [ring.size(), free, frac * 100], "free_ratio": snappedf(frac, 0.01)}


func _world_aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _passes(r: Dictionary) -> bool:
	if r.is_empty():
		return false
	for k: String in r["checks"]:
		if r["checks"][k]["result"] == "FAIL":
			return false
	return true


func _score(r: Dictionary) -> float:
	if r.is_empty():
		return -1e9
	var s := 0.0
	for k: String in r["checks"]:
		s += {"PASS": 2.0, "WARN": 1.5, "REVIEW": 1.0, "UNKNOWN": 1.0, "FAIL": 0.0}[r["checks"][k]["result"]]
	return s - float(r["checks"]["ground"]["relief_m"]) * 0.1


func _spiral(c: Vector2, radius: float, step: float) -> Array:
	var out: Array = [c]
	step = maxf(step, 2.0)
	var r := step
	while r <= radius:
		var n := maxi(8, int(TAU * r / step))
		for k in n:
			out.append(c + Vector2(cos(TAU * k / n), sin(TAU * k / n)) * r)
		r += step
	return out


func _retire_live(n: Node3D) -> void:
	n.visible = false
	for c in n.find_children("*", "", true, false) + [n]:
		if c is CollisionObject3D:
			(c as CollisionObject3D).collision_layer = 0


# ─────────────────────────── 截圖 ───────────────────────────

func _shots(inst: Node3D, r: Dictionary, h: float, fp: Rect2) -> void:
	var out_dir := ProjectSettings.globalize_path("res://").path_join("../docs/fastlane/" + id).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280, 720)
	var cam := Camera3D.new()
	cam.fov = 60
	cam.far = 2000
	inst.get_parent().add_child(cam)
	cam.current = true
	var xf: Transform3D = r["xform"]
	var center := xf.origin + Vector3(0, h * 0.45, 0)
	# 讓建築剛好填滿 60° 視野的距離 ×1.15（寬與高取大者）
	var span := maxf(maxf(fp.size.x, fp.size.y), h * 1.6)
	var dist := span * 0.5 / tan(deg_to_rad(30.0)) * 1.15 + 2.0
	var sheet := Image.create(1280, 720, false, Image.FORMAT_RGB8)
	var terrain := inst.get_parent().get_node("Collision/TerrainCollision") as CollisionObject3D
	var space := inst.get_world_3d().direct_space_state
	# 10:00 白天（與 walk_village_v2_farmland.gd 的審圖鏡位同一時刻）
	var sky: Node = inst.get_parent().get_node_or_null("Lighting/天象系統")
	if sky != null:
		sky.set("一日長度分鐘", 0.0)
		sky.set("時刻", 10.0)
	var dn := root.get_node_or_null("/root/DayNight")
	if dn != null:
		dn.set("flowing", false)
		if dn.has_method("set_hour"):
			dn.call("set_hour", 10.0)
	var me := inst.get_node("Collision") as CollisionObject3D
	var probe := SphereShape3D.new()
	probe.radius = 0.4
	var used: Array = []
	for k in 4:
		var best_p := Vector3.INF
		# 每個方向：角度 ±0／20／40°、距離 0.7–1.5 倍，取第一個「相機不在東西裡、看得到建築中心與屋頂」的位置
		for da: float in [0.0, 20.0, -20.0, 40.0, -40.0]:
			for dm: float in [1.0, 0.9, 1.15, 0.8, 1.3]:
				var a := PI * 0.5 * k + deg_to_rad(da)
				var p := xf.origin + xf.basis * Vector3(sin(a), 0, cos(a)) * dist * dm
				var gy: Variant = _terrain_y(space, terrain, p)
				if gy == null:
					continue
				p.y = float(gy) + 1.7
				if float(gy) < xf.origin.y - 1.5:   # 比建築低 1.5 m 以上＝多半在水渠／河床裡
					continue
				var sq := PhysicsShapeQueryParameters3D.new()
				sq.shape = probe
				sq.transform = Transform3D(Basis.IDENTITY, p)
				sq.exclude = [terrain.get_rid()]
				if _blocked(space, sq):
					continue
				var clear := true
				for tgt in [center, xf.origin + Vector3(0, h * 0.85, 0)]:
					var hit := _ray_env(space, p, tgt, [me.get_rid()] as Array[RID])
					if not hit.is_empty() and (hit["position"] as Vector3).distance_to(tgt) > 1.0:
						clear = false
				if clear:
					best_p = p
					break
			if best_p != Vector3.INF:
				break
		if best_p == Vector3.INF:
			var a0 := PI * 0.5 * k
			best_p = xf.origin + xf.basis * Vector3(sin(a0), 0, cos(a0)) * dist
			var g0: Variant = _terrain_y(space, terrain, best_p)
			best_p.y = (float(g0) if g0 != null else xf.origin.y) + 1.7
			used.append("%s：找不到無遮擋位置，用預設" % ["front", "right", "back", "left"][k])
		cam.global_position = best_p
		cam.look_at(center, Vector3.UP)
		for f in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.resize(640, 360, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(0, 0, 640, 360), Vector2i((k % 2) * 640, (k / 2) * 360))
	cam.queue_free()
	var path := out_dir.path_join("sheet.jpg")
	sheet.save_jpg(path, 0.85)
	result["shots"] = path
	result["shot_notes"] = used
	_log("截圖 %s（front／right／back／left，10:00、玩家眼高 1.7 m、基準距離 %.1f m）%s" % [path, dist, "；" + "；".join(used) if not used.is_empty() else ""])


# ─────────────────────────── 寫入場景（文字插入，不重存整個場景） ───────────────────────────

func _scene_file() -> String:
	return ProjectSettings.globalize_path(scene_path)


func _ext_line() -> String:
	return '[ext_resource type="PackedScene" path="%s%s/%s.tscn" id="fl_%s"]' % [ROOT_DIR, id, id, id]


func _node_hdr() -> String:
	return '[node name="%s" parent="FastLane" instance=ExtResource("fl_%s")]' % [id, id]


func _read_lines() -> PackedStringArray:
	var raw := FileAccess.get_file_as_string(_scene_file())
	return raw.split(NL)


func _write_lines(lines: PackedStringArray) -> bool:
	var f := FileAccess.open(_scene_file(), FileAccess.WRITE)
	if f == null:
		_die("寫不進 %s" % _scene_file())
		return false
	f.store_string(NL.join(lines))
	f.close()
	return true


func _block_end(lines: PackedStringArray, start: int) -> int:
	for i in range(start + 1, lines.size()):
		if lines[i].begins_with("["):
			return i
	return lines.size()


func _mount(xf: Transform3D) -> bool:
	var lines := _read_lines()
	if lines.size() < 10 or not lines[0].begins_with("[gd_scene"):
		_die("%s 不是 CRLF 文字場景" % scene_path)
		return false
	if not _ext_line() in lines:
		var last_ext := -1
		for i in lines.size():
			if lines[i].begins_with("[ext_resource"):
				last_ext = i
		lines.insert(last_ext + 1, _ext_line())
	var xline := "transform = " + var_to_str(xf)
	var hdr := lines.find(_node_hdr())
	if hdr >= 0:
		var e := _block_end(lines, hdr)
		var body := PackedStringArray([_node_hdr(), xline, ""])
		for i in range(hdr, e):
			lines.remove_at(hdr)
		for i in body.size():
			lines.insert(hdr + i, body[i])
	else:
		if lines.find('[node name="FastLane" type="Node3D" parent="."]') < 0:
			while lines.size() > 0 and lines[-1] == "":
				lines.remove_at(lines.size() - 1)
			lines.append("")
			lines.append('[node name="FastLane" type="Node3D" parent="."]')
			lines.append('metadata/note = "建築快速通道（tools/fastlane/place_building.gd）放的建築；每個子節點是獨立場景，可直接選取編輯"')
			lines.append("")
		while lines.size() > 0 and lines[-1] == "":
			lines.remove_at(lines.size() - 1)
		lines.append("")
		lines.append(_node_hdr())
		lines.append(xline)
		lines.append("")
	if A.has("replace"):
		var rp := String(A["replace"])
		var nm := rp.get_file()
		var par := rp.get_base_dir()
		var want := '[node name="%s" ' % nm
		var found := -1
		for i in lines.size():
			if lines[i].begins_with(want) and ('parent="%s"' % (par if par != "" else ".")) in lines[i]:
				found = i
		if found < 0:
			print("[FASTLANE] REVIEW --replace %s 不在場景本體裡（可能在 overlay 子場景內），只在本次量測時隱藏，未寫入" % rp)
		else:
			var e := _block_end(lines, found)
			var props := {"visible": "false", "collision_layer": "0"} if "StaticBody3D" in lines[found] else {"visible": "false"}
			for k: String in props:
				var done := false
				for i in range(found + 1, e):
					if lines[i].begins_with(k + " = "):
						lines[i] = "%s = %s" % [k, props[k]]
						done = true
				if not done:
					lines.insert(found + 1, "%s = %s" % [k, props[k]])
					e += 1
			lines.insert(found + 1, 'metadata/replaced_by_fastlane = "%s"' % id)
	if not _write_lines(lines):
		return false
	# 回讀：不用快取重新載入，確認節點在、位置一致
	var back := ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var w := back.instantiate() as Node3D if back != null else null
	var n := w.get_node_or_null("FastLane/" + id) as Node3D if w != null else null
	var ok := n != null and n.transform.origin.distance_to(xf.origin) < 0.001
	print("[FASTLANE] %s 寫入 %s → FastLane/%s（回讀%s）" % ["PASS" if ok else "FAIL", scene_path, id, "一致" if ok else "不一致"])
	if w != null:
		w.free()
	return ok


func _unmount() -> bool:
	var lines := _read_lines()
	var hdr := lines.find(_node_hdr())
	if hdr < 0:
		print("[FASTLANE] FastLane/%s 不在場景裡，沒有要移除的" % id)
		return true
	var e := _block_end(lines, hdr)
	for i in range(hdr, e):
		lines.remove_at(hdr)
	var ei := lines.find(_ext_line())
	if ei >= 0:
		lines.remove_at(ei)
	for i in lines.size():
		if lines[i] == 'metadata/replaced_by_fastlane = "%s"' % id:
			print("[FASTLANE] REVIEW 第 %d 行的節點曾被 --replace 隱藏；移除後它仍是隱藏的，需要的話手動恢復" % (i + 1))
	var ok := _write_lines(lines)
	print("[FASTLANE] %s 移除 FastLane/%s（資產檔保留在 %s%s/）" % ["PASS" if ok else "FAIL", id, ROOT_DIR, id])
	return ok


func _save_result() -> void:
	var out_dir := ProjectSettings.globalize_path("res://").path_join("../docs/fastlane/" + id).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	result["id"] = id
	result["scene"] = scene_path
	result["seconds"] = snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1)
	result["arch"] = {"tool": ARCH.TOOL, "summary": ARCH.summarize(arch_rows), "results": arch_rows}
	var f := FileAccess.open(out_dir.path_join("result.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(result, " "))
	f.close()


## 編輯器開著嗎：Godot_*.exe 且命令列沒有 --script／-s／--headless（console 版跑腳本時也會生出非 console 子行程，不能只看檔名）。
func _editor_running() -> bool:
	var out: Array = []
	OS.execute("powershell", ["-NoProfile", "-Command",
		"Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'Godot*' } | ForEach-Object { $_.CommandLine }"], out)
	for line: String in String(out[0] if out.size() > 0 else "").split("\n"):
		var l := line.strip_edges()
		if l == "" or "--script" in l or " -s " in l or "--headless" in l or "godot-ai" in l.to_lower():
			continue
		if "Godot_v" in l:
			return true
	return false
