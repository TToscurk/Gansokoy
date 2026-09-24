extends SceneTree
## 人間之里 V2：Hero／地標資產 prefab 產生器（P5 R1 起；所有 v2 新資產共用）。
##
##   godot --headless --path godot --script res://tools/village_v2_hero_prefab.gd -- --asset=<id>
##
## 輸入：res://assets/village_v2/<id>/asset.json（Blender 腳本產生）＋ src/<id>.glb（src/ 有 .gdignore，編輯器不匯入；
##       這裡用 GLTFDocument 在建置期讀，結果不受 .import 設定影響）。
## 輸出：res://assets/village_v2/<id>/<id>.scn
##   <Id>（Node3D，meta asset_id／asset_json）
##     LOD0／LOD1／LOD2（MeshInstance3D，visibility_range 硬切＋margin 遲滯；材質＝共享材質庫／Hero atlas 的 .tres）
##     Collision（StaticBody3D）＋ asset.json 列的簡化形狀（box／cylinder／convex；禁止 trimesh）
## 只負責「組裝」；是否合格由 verify_village_v2_hero_gate.gd 驗收。

var fails := 0


func _p(s: String) -> void:
	print("[PREFAB] " + s)


func _fail(s: String) -> void:
	push_error("[PREFAB] " + s)
	fails += 1


func _init() -> void:
	var id := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--asset="):
			id = a.trim_prefix("--asset=")
	if id == "":
		_fail("缺 -- --asset=<id>")
		quit(1)
		return
	var dir := "res://assets/village_v2/%s" % id
	var spec: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "/asset.json"))
	if not spec is Dictionary:
		_fail("讀不到 %s/asset.json" % dir)
		quit(1)
		return
	var S: Dictionary = spec
	var glb := String(S["glb"])
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(glb), st)
	if err != OK:
		_fail("GLTF 讀取失敗 %s：%s" % [glb, error_string(err)])
		quit(1)
		return
	var gl_root: Node = doc.generate_scene(st)
	# 依物件名找各 LOD 的網格（執行期 GLTF 可能給 MeshInstance3D 或 ImporterMeshInstance3D）
	var found := {}
	for n in gl_root.find_children("*", "", true, false):
		var m: Mesh = null
		if n is MeshInstance3D:
			m = (n as MeshInstance3D).mesh
		elif n is ImporterMeshInstance3D:
			m = (n as ImporterMeshInstance3D).mesh.get_mesh()
		if m != null:
			found[String(n.name)] = [m, (n as Node3D).transform, n.get_class()]
	var mats: Dictionary = S["materials"]
	var ranges: Array = S["lod_ranges_m"]
	var root := Node3D.new()
	root.name = String(S["id"]).to_pascal_case()
	root.set_meta("asset_id", String(S["id"]))
	root.set_meta("asset_json", dir + "/asset.json")
	var lod_names: Array = S["lod_objects"]
	var margin := 4.0
	for li in lod_names.size():
		var on := String(lod_names[li])
		if not found.has(on):
			_fail("GLB 缺物件 %s（有：%s）" % [on, ", ".join(found.keys())])
			continue
		var src: Mesh = found[on][0]
		var xf: Transform3D = found[on][1]
		if not xf.is_equal_approx(Transform3D.IDENTITY):
			_fail("%s 節點 transform 不是 identity：%s" % [on, xf])
		var am := ArrayMesh.new()
		var tris := 0
		for si in src.get_surface_count():
			var arr := src.surface_get_arrays(si)
			var mat: Material = src.surface_get_material(si)
			var mname := mat.resource_name if mat != null else ""
			if not mats.has(mname):
				_fail("%s surface %d 材質「%s」不在 asset.json materials（%s）" % [on, si, mname, ", ".join(mats.keys())])
				continue
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			tris += (idx.size() if not idx.is_empty() else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			var surf := am.get_surface_count() - 1
			am.surface_set_name(surf, mname)
			am.surface_set_material(surf, load(String(mats[mname])))
		am.resource_name = "%s_LOD%d" % [S["id"], li]
		var mi := MeshInstance3D.new()
		mi.name = "LOD%d" % li
		mi.mesh = am
		var b := float(ranges[li])
		var e := float(ranges[li + 1])
		mi.visibility_range_begin = b
		mi.visibility_range_begin_margin = margin if b > 0.0 else 0.0
		mi.visibility_range_end = e
		mi.visibility_range_end_margin = margin if e > 0.0 else 0.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		root.add_child(mi)
		var cols: PackedColorArray = am.surface_get_arrays(0)[Mesh.ARRAY_COLOR] if am.get_surface_count() > 0 else PackedColorArray()
		_p("%s ← %s（%s）：%d 三角面、%d surface、AABB %s、顏色樣本 %s" % [mi.name, on, found[on][2], tris,
			am.get_surface_count(), am.get_aabb(), cols[0] if not cols.is_empty() else "無"])
	var body := StaticBody3D.new()
	body.name = "Collision"
	root.add_child(body)
	for c: Dictionary in S["collision"]:
		var cs := CollisionShape3D.new()
		cs.name = String(c["name"])
		var ctr: Array = c["center"]
		cs.position = Vector3(float(ctr[0]), float(ctr[1]), float(ctr[2]))
		if c.has("yaw_deg"):
			cs.rotation.y = deg_to_rad(float(c["yaw_deg"]))
		match String(c["type"]):
			"box":
				var bs := BoxShape3D.new()
				var sz: Array = c["size"]
				bs.size = Vector3(float(sz[0]), float(sz[1]), float(sz[2]))
				cs.shape = bs
			"cylinder":
				var cy := CylinderShape3D.new()
				cy.radius = float(c["radius"])
				cy.height = float(c["height"])
				cs.shape = cy
			"convex":
				# 簡化凸殼（例：入口踏石的斜坡，讓膠囊能走上去）；點＝局部座標
				var cv := ConvexPolygonShape3D.new()
				var pts := PackedVector3Array()
				for p: Array in c["points"]:
					pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
				cv.points = pts
				cs.shape = cv
			_:
				_fail("不支援的碰撞型別 %s（只允許 box／cylinder／convex）" % c["type"])
				continue
		body.add_child(cs)
	_p("碰撞 %d 個" % body.get_child_count())
	for n in root.find_children("*", "", true, false):
		n.owner = root
	var ps := PackedScene.new()
	err = ps.pack(root)
	if err != OK:
		_fail("pack 失敗 %s" % error_string(err))
	var out := String(S["scene"])
	err = ResourceSaver.save(ps, out)
	_p("存檔 %s → %s" % [out, error_string(err)])
	if err != OK:
		fails += 1
	gl_root.free()
	root.free()
	_p("結果：%d 項失敗" % fails)
	quit(fails)
