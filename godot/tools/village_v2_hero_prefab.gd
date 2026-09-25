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
##     <Rotor>（R4 水車起，asset.json rotors）：Node3D 放在 pivot，底下 LOD0–2 同距離切換；
##       RotorAnim（AnimationPlayer，autoplay「spin」）以 period_s 一圈、線性循環轉 rotation:<axis>。
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
	# 轉動部件（水車輪）：網格頂點在 Blender 端已以 pivot 為原點 → 節點放在 pivot、LOD 子節點 identity
	var ap: AnimationPlayer = null
	var alib := AnimationLibrary.new()
	var spin := Animation.new()
	for rt: Dictionary in S.get("rotors", []):
		var rn := Node3D.new()
		rn.name = String(rt["name"])
		var pv: Array = rt["pivot"]
		rn.position = Vector3(float(pv[0]), float(pv[1]), float(pv[2]))
		rn.set_meta("rotor", true)
		root.add_child(rn)
		var objs: Array = rt["lod_objects"]
		for li in objs.size():
			var on := String(objs[li])
			if not found.has(on):
				_fail("GLB 缺轉動物件 %s" % on)
				continue
			var src: Mesh = found[on][0]
			var xf: Transform3D = found[on][1]
			if not xf.is_equal_approx(Transform3D.IDENTITY):
				_fail("%s 節點 transform 不是 identity：%s" % [on, xf])
			var am := ArrayMesh.new()
			for si in src.get_surface_count():
				var mat: Material = src.surface_get_material(si)
				var mname := mat.resource_name if mat != null else ""
				if not mats.has(mname):
					_fail("%s surface %d 材質「%s」不在 asset.json materials" % [on, si, mname])
					continue
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(si))
				am.surface_set_name(am.get_surface_count() - 1, mname)
				am.surface_set_material(am.get_surface_count() - 1, load(String(mats[mname])))
			am.resource_name = "%s_%s_LOD%d" % [S["id"], rt["name"], li]
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
			rn.add_child(mi)
			_p("%s/%s ← %s：%d 三角面" % [rn.name, mi.name, on, am.get_faces().size() / 3])
		var period := float(rt["period_s"])
		spin.length = period
		spin.loop_mode = Animation.LOOP_LINEAR
		var t := spin.add_track(Animation.TYPE_VALUE)
		spin.track_set_path(t, NodePath("%s:rotation:%s" % [rn.name, String(rt["axis"])]))
		spin.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
		spin.value_track_set_update_mode(t, Animation.UPDATE_CONTINUOUS)
		spin.track_insert_key(t, 0.0, 0.0)
		spin.track_insert_key(t, period, float(rt["dir"]) * TAU)
		if ap == null:
			ap = AnimationPlayer.new()
			ap.name = "RotorAnim"
	if ap != null:
		alib.add_animation("spin", spin)
		ap.add_animation_library("", alib)
		ap.autoplay = "spin"
		root.add_child(ap)
		_p("轉動：%d 個 rotor、RotorAnim autoplay spin（%.1f s 一圈）" % [S["rotors"].size(), spin.length])
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
		if c.has("roll_deg"):
			cs.rotation.z = deg_to_rad(float(c["roll_deg"]))   # 圓柱軸改水平（水車輪、軸）
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
