extends SceneTree
## V2 資產 QA（V2 全面重製計畫 §16–18、§47–48、§53 D）。
##
##   Godot --headless --path godot --script tools/qa_assets_v2.gd -- [選項] <路徑…>
##
## 路徑可以是 .glb/.gltf/.fbx/.tscn/.scn 檔或 res:// 目錄（遞迴）。不給路徑 → 內建 V2 候選清單。
## 選項：
##   --cat=auto|building|tree|rock|prop|bridge|landmark   類別（auto = 依路徑猜）
##   --csv=<檔案>    另存 CSV（預設 D:/神社/shrine/docs/art_review/asset_qa/qa_<時間>.csv）
##
## 每個資產讀：AABB（position／size／end）、尺寸（公尺）、三角面、材質數、節點數、
## 底部 Y、Mesh 數、LOD 數（importer LOD）、最遠 Mesh 離原點距離、各 Mesh 的 AABB 異常。
## 判定（§48 自動拒絕的可機器判定部分）：
##   PIVOT_CENTERED / BELOW_PIVOT / FLOATING_PIVOT
##                          底部相對原點的高度比（< -35% / < -5% / > +3% 高度）：埋半截／土塊或地基在原點下／浮空
##   BOTTOM_CONTAMINATION   尺寸合理時，底部低於類別容差（樹 -0.3 m、建築 -0.5 m…）
##   ORIGIN_OFFSET          原點 XZ 偏離底面中心 > 20% 寬
##   BASE_SLAB              （樹）最底 3% 高度帶 XZ 範圍 > 整體 30%，且 > 3 倍樹幹段（8–15%）：自帶土塊／地台
##   HIGHPOLY_NO_USABLE_LOD 超面數預算且最低一級 importer LOD 仍超預算（§48 高模無 LOD）
##   LATERAL_CONTAMINATION  有 Mesh 遠離主體（AABB 被零星幾何拉大）
##   SCALE_SUSPECT          尺寸落在類別合理範圍外（可能單位錯／Scale 未 Apply）
##   TRI_BUDGET             三角面超出類別預算（§25、§43）
##   NO_MATERIAL            有 surface 沒材質
## 判定只是初篩：通過 ≠ ASSET_APPROVED；需要 Blender 側（non-manifold、翻面、隱藏面）另查。
## 判定結果：QA_PASS／QA_WARN／QA_FAILED。QA_FAILED＝計畫 §48 的 ASSET_REJECTED，依 2026-09-23 裁示
## 改記為 QA_FAILED：只記錄、禁止搬入正式 V2，不批次修復。

const DEFAULT_OUT := "D:/神社/shrine/docs/art_review/asset_qa/"

## 類別規格：尺寸合理範圍（最大邊，公尺）、底部容差、三角面預算
const CAT := {
	"building": {"size": [3.0, 40.0], "bottom": -0.5, "tris": 150000},
	"landmark": {"size": [3.0, 60.0], "bottom": -1.0, "tris": 300000},
	"tree": {"size": [2.0, 40.0], "bottom": -0.3, "tris": 30000},
	"rock": {"size": [0.1, 15.0], "bottom": -0.5, "tris": 8000},
	"prop": {"size": [0.05, 8.0], "bottom": -0.1, "tris": 10000},
	"bridge": {"size": [2.0, 60.0], "bottom": -3.0, "tris": 60000},
}

const DEFAULT_PATHS := [
	"res://assets/machiya/",
	"res://assets/landmark/",
	"res://assets/bridges/",
	"res://maps/village/gen/鈴奈庵/鈴奈庵.glb",
	"res://maps/village/gen/霧雨店/霧雨店.glb",
	"res://maps/village/gen/鯢吞亭/鯢吞亭.glb",
	"res://maps/village/gen/寺子屋/寺子屋.glb",
	"res://maps/village/gen/稗田邸/稗田底新版.glb",
	"res://maps/village/gen/龍神像/龍神像.glb",
	"res://assets/landscape/",
]

const EXTS := ["glb", "gltf", "fbx", "tscn", "scn"]

var rows: Array = []


func _init() -> void:
	var cat_opt := "auto"
	var csv := ""
	var paths: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cat="):
			cat_opt = a.substr(6)
		elif a.begins_with("--csv="):
			csv = a.substr(6)
		elif not a.begins_with("--"):
			paths.append(a)
	if paths.is_empty():
		paths = DEFAULT_PATHS.duplicate()
	var files: Array[String] = []
	for p in paths:
		_collect(String(p), files)
	print("[QA] %d 個資產" % files.size())
	for f in files:
		_audit(f, cat_opt)
	_print_summary()
	if csv == "":
		DirAccess.make_dir_recursive_absolute(DEFAULT_OUT)
		csv = DEFAULT_OUT + "qa_%s.csv" % Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
	_write_csv(csv)
	quit()


func _collect(p: String, out: Array[String]) -> void:
	if p.ends_with("/"):
		var d := DirAccess.open(p)
		if d == null:
			print("MISS | ", p)
			return
		for f in d.get_files():
			if EXTS.has(f.get_extension().to_lower()):
				out.append(p + f)
		for sub in d.get_directories():
			if sub.begins_with("_") or sub.begins_with("."):
				continue
			_collect(p + sub + "/", out)
	elif ResourceLoader.exists(p):
		out.append(p)
	else:
		print("MISS | ", p)


func _guess_cat(path: String) -> String:
	var p := path.to_lower()
	# 目錄／「橋」優先於材質字：龍石像橋 在 bridges/ 下，不能被「石」判成岩石
	for k in [["垣", "prop"], ["bridges", "bridge"], ["橋", "bridge"],
			["landscape", "tree"], ["tree", "tree"], ["樹", "tree"], ["杉", "tree"], ["松", "tree"],
			["rock", "rock"], ["石", "rock"],
			["landmark", "landmark"], ["鳥居", "landmark"], ["龍神像", "landmark"],
			["machiya", "building"], ["gen/", "building"], ["prop", "prop"], ["market", "prop"]]:
		if p.contains(String(k[0])):
			return String(k[1])
	return "prop"


func _audit(path: String, cat_opt: String) -> void:
	var cat := _guess_cat(path) if cat_opt == "auto" else cat_opt
	var spec: Dictionary = CAT.get(cat, CAT["prop"])
	var ps := load(path) as PackedScene
	if ps == null:
		print("NOLOAD | ", path)
		rows.append({"path": path, "cat": cat, "verdict": "QA_FAILED", "flags": ["NOLOAD"]})
		return
	var root_node := ps.instantiate()
	var box := AABB()
	var first := true
	var tris := 0
	var surfaces := 0
	var mats := {}
	var no_mat := 0
	var lods := 0
	var min_lod_tris := 0
	var lod_fmt_ok := true
	var verts: PackedVector3Array = PackedVector3Array()
	var meshes: Array = []
	for n in root_node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := _xf(mi, root_node)
		var a: AABB = xf * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
		var mt := 0
		for s in mi.mesh.get_surface_count():
			surfaces += 1
			var arr := mi.mesh.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			var t := 0
			if idx != null and (idx as PackedInt32Array).size() > 0:
				t = (idx as PackedInt32Array).size() / 3
			else:
				t = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			mt += t
			var m: Material = mi.get_surface_override_material(s)
			if m == null:
				m = mi.mesh.surface_get_material(s)
			if m == null and mi.material_override == null:
				no_mat += 1
			elif m != null:
				mats[m.get_rid()] = true
			# LOD：ArrayMesh 沒有 LOD 查詢方法（ClassDB 實查），改讀 RenderingServer 的 surface 資料
			var sd: Dictionary = RenderingServer.mesh_get_surface(mi.mesh.get_rid(), s)
			var lod_arr: Array = sd.get("lods", [])
			lods = maxi(lods, lod_arr.size())
			var smallest := t
			if not lod_arr.is_empty() and int(sd.get("index_count", 0)) > 0 and sd.has("index_data"):
				var bpi := float((sd["index_data"] as PackedByteArray).size()) / float(sd["index_count"])
				for L in lod_arr:
					if L is Dictionary and (L as Dictionary).has("index_data"):
						smallest = mini(smallest, int((L["index_data"] as PackedByteArray).size() / bpi / 3.0))
					else:
						lod_fmt_ok = false
			min_lod_tris += smallest
			if cat == "tree":
				for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					verts.append(xf * v)
		if mi.material_override != null:
			mats[mi.material_override.get_rid()] = true
		tris += mt
		meshes.append({"name": String(mi.name), "aabb": a, "tris": mt})
	var nodes := _count(root_node)
	root_node.free()
	if first:
		rows.append({"path": path, "cat": cat, "verdict": "QA_FAILED", "flags": ["NO_MESH"]})
		print("NOMESH | ", path)
		return
	var flags: Array[String] = []
	var size := box.size
	var maxdim := maxf(size.x, maxf(size.y, size.z))
	var szr: Array = spec["size"]
	if maxdim < float(szr[0]) or maxdim > float(szr[1]):
		flags.append("SCALE_SUSPECT")
	var h := maxf(size.y, 0.001)
	var rel_bottom := box.position.y / h
	if rel_bottom < -0.35:
		flags.append("PIVOT_CENTERED")      # 原點在半高：擺到地面會埋一半
	elif rel_bottom < -0.05:
		flags.append("BELOW_PIVOT")         # 原點下方有幾何：地基/土塊埋地或原點錯
	elif rel_bottom > 0.03:
		flags.append("FLOATING_PIVOT")      # 底部高於原點：擺到地面會浮空
	if not flags.has("SCALE_SUSPECT") and box.position.y < float(spec["bottom"]):
		flags.append("BOTTOM_CONTAMINATION")
	var cxz := Vector2(box.get_center().x, box.get_center().z)
	if cxz.length() > 0.2 * maxf(size.x, size.z):
		flags.append("ORIGIN_OFFSET")
	# 樹木自帶土塊（§48）：最底 3% 高度帶很寬、但上方 8–15% 高度帶（樹幹段）很窄 → 底下多一塊地台。
	# 只看最底帶會誤判：針葉樹下枝本來就貼地，兩個帶都寬。
	var slab := -1.0
	var trunk := -1.0
	if cat == "tree" and verts.size() > 0:
		var whole := maxf(size.x * size.z, 1e-6)
		slab = _band_area(verts, box.position.y, box.position.y + 0.03 * h) / whole
		trunk = _band_area(verts, box.position.y + 0.08 * h, box.position.y + 0.15 * h) / whole
		if slab > 0.3 and slab > 3.0 * trunk:
			flags.append("BASE_SLAB")
	# 側向污染：有 Mesh 的中心離主體（面數最大的 Mesh）很遠且面數很少
	var main_m: Dictionary = meshes[0]
	for m in meshes:
		if int(m["tris"]) > int(main_m["tris"]):
			main_m = m
	var ma: AABB = main_m["aabb"]
	var stray: Array[String] = []
	for m in meshes:
		var a2: AABB = m["aabb"]
		var gap := _aabb_gap(ma, a2)
		if gap > 0.5 * maxf(ma.size.x, ma.size.z) and int(m["tris"]) < int(main_m["tris"]) / 10:
			stray.append("%s(%.1fm)" % [m["name"], gap])
	if not stray.is_empty():
		flags.append("LATERAL_CONTAMINATION")
	if tris > int(spec["tris"]):
		flags.append("TRI_BUDGET")
		if min_lod_tris > int(spec["tris"]):
			flags.append("HIGHPOLY_NO_USABLE_LOD")   # §48 高模無 LOD：最低一級 LOD 仍超預算
	if no_mat > 0:
		flags.append("NO_MATERIAL")
	var hard := ["BOTTOM_CONTAMINATION", "SCALE_SUSPECT", "LATERAL_CONTAMINATION", "NO_MATERIAL",
		"PIVOT_CENTERED", "BELOW_PIVOT", "FLOATING_PIVOT", "ORIGIN_OFFSET", "BASE_SLAB",
		"HIGHPOLY_NO_USABLE_LOD"]
	var verdict := "QA_PASS"
	for f in flags:
		if hard.has(f):
			verdict = "QA_FAILED"
	if verdict == "QA_PASS" and not flags.is_empty():
		verdict = "QA_WARN"
	var row := {"path": path, "cat": cat, "verdict": verdict, "flags": flags,
		"size": size, "aabb_pos": box.position, "aabb_end": box.end, "bottom": box.position.y,
		"tris": tris, "surfaces": surfaces, "materials": mats.size(), "nodes": nodes,
		"meshes": meshes.size(), "lods": lods, "min_lod_tris": min_lod_tris,
		"rel_bottom": rel_bottom, "slab": slab, "trunk": trunk, "stray": stray}
	if not lod_fmt_ok:
		print("      ⚠ LOD 資料格式與預期不符（lods 項目沒有 index_data），min_lod_tris 不可信")
	rows.append(row)
	print("QA | %-14s | %-22s | %6.2f×%6.2f×%6.2f m | 底 %6.2f (%+.0f%%) | %8d tris | LOD+%d 最低 %7d | mat %2d | node %3d | mesh %2d%s | %s" % [
		verdict, path.get_file(), size.x, size.y, size.z, box.position.y, rel_bottom * 100.0, tris,
		lods, min_lod_tris, mats.size(), nodes, meshes.size(),
		(" | 底帶 %.2f／幹帶 %.2f" % [slab, trunk]) if slab >= 0.0 else "", ",".join(flags)])
	if not stray.is_empty():
		print("      stray: ", ", ".join(stray.slice(0, 6)))


func _band_area(verts: PackedVector3Array, y0: float, y1: float) -> float:
	var bmin := Vector2(INF, INF)
	var bmax := Vector2(-INF, -INF)
	for v in verts:
		if v.y >= y0 and v.y <= y1:
			bmin = Vector2(minf(bmin.x, v.x), minf(bmin.y, v.z))
			bmax = Vector2(maxf(bmax.x, v.x), maxf(bmax.y, v.z))
	if bmin.x == INF:
		return 0.0
	return (bmax.x - bmin.x) * (bmax.y - bmin.y)


func _aabb_gap(a: AABB, b: AABB) -> float:
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy := maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	var dz := maxf(0.0, maxf(a.position.z - b.end.z, b.position.z - a.end.z))
	return Vector3(dx, dy, dz).length()


func _xf(n: Node, root_node: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root_node:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	if root_node is Node3D:
		t = (root_node as Node3D).transform * t
	return t


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


func _print_summary() -> void:
	var tally := {}
	for r in rows:
		tally[r["verdict"]] = int(tally.get(r["verdict"], 0)) + 1
	print("[QA] 結果：", tally)


func _write_csv(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[QA] 無法寫 " + path)
		return
	f.store_line("asset,category,verdict,flags,size_x,size_y,size_z,aabb_pos_y,aabb_end_y,bottom_y,bottom_rel_height,triangles,min_lod_triangles,surfaces,materials,nodes,meshes,extra_lods,base_slab_ratio,stray")
	for r in rows:
		if not r.has("size"):
			f.store_line("%s,%s,%s,%s,,,,,,,,,,,,,,,," % [r["path"], r["cat"], r["verdict"], "|".join(r["flags"])])
			continue
		var s: Vector3 = r["size"]
		f.store_line("%s,%s,%s,%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%d,%d,%d,%d,%d,%d,%.3f,%s" % [
			r["path"], r["cat"], r["verdict"], "|".join(r["flags"]), s.x, s.y, s.z,
			(r["aabb_pos"] as Vector3).y, (r["aabb_end"] as Vector3).y, r["bottom"], r["rel_bottom"],
			r["tris"], r["min_lod_tris"], r["surfaces"], r["materials"], r["nodes"], r["meshes"],
			r["lods"], r["slab"], "|".join(r["stray"])])
	f.close()
	print("[QA] CSV → ", path)
