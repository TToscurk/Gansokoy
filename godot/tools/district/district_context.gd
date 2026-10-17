extends SceneTree
## 街區管線 step 1：Godot が唯讀で参考資料を書き出す（village_v2.tscn は読むだけ、書かない）。
##   godot --headless --path godot --script res://tools/district/district_context.gd -- --district=B8 [--out=<dir>] [--assets=all|used|none] [--no-glb] [--hstep=0.5] [--rstep=1.0]
## 出力（既定 <repo>/work/district/<ID>/，work/ は .gitignore）：
##   context.json  建物 footprint・戸口・道路・NPC 動線・keep_clear・腕の検査線・高さ表（見えている最上面）・水面表・置けない理由の表（ground／soft）・seed items
##   context.glb   街區 rect＋15 m の可視 MeshInstance（LOD0 のみ・大きな地形面と MultiMesh は除く；地面は高さ表から Blender 側で張る）
##   assets.glb／assets.json  置ける資産の LOD0（節点名＝資産 id、原点＝足元）と寸法
## MultiMesh は headless で行列が 0 になるので context.glb に入れない（植被層は高さ表と理由表で代用）。
const DL := preload("res://tools/district/district_lib.gd")
const W9 := preload("res://tools/p13/w9/w9_lib.gd")
const P3 := preload("res://tools/p13/w9/w9p3_lib.gd")
const SL := preload("res://tools/village_v2_street_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")

const GLB_MARGIN := 15.0
const GLB_MAX_SPAN := 120.0


func _init() -> void:
	_run.call_deferred()


func _arg(args: PackedStringArray, k: String, dflt: String) -> String:
	for s in args:
		if s.begins_with(k + "="):
			return s.trim_prefix(k + "=")
	return dflt


func _v2(v: Vector2) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001)]


func _poly(p: PackedVector2Array) -> Array:
	var out: Array = []
	for q in p:
		out.append(_v2(q))
	return out


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var d := _arg(args, "--district", "")
	if not DL.DISTRICTS.has(d):
		printerr("[DCTX] --district=%s は DISTRICTS に無い（%s）" % [d, ", ".join(PackedStringArray(DL.DISTRICTS.keys()))])
		quit(1)
		return
	var D: Dictionary = DL.DISTRICTS[d]
	var R: Rect2 = D["rect"]
	var out := _arg(args, "--out", DL.work_dir(d))
	var assets_mode := _arg(args, "--assets", "all")
	var hstep := float(_arg(args, "--hstep", "0.5"))
	var rstep := float(_arg(args, "--rstep", "1.0"))
	DirAccess.make_dir_recursive_absolute(out)
	var t0 := Time.get_ticks_msec()
	var v: Node3D = (load(DL.SCENE) as PackedScene).instantiate()
	# 自分の overlay（掛載済みなら）は参考から外す
	var own := v.get_node_or_null(DL.node_name(d))
	if own:
		v.remove_child(own)
		own.free()
	root.add_child(v)
	for i in 3:
		await physics_frame
	var n_supp := DL.prepare_scene(v, d)
	if n_supp > 0:
		print("[DCTX] 街區表 suppress：既存 %d 組を記憶内で取り除いて判定（場景ファイルは書かない）" % n_supp)
	P3.register_dims()
	var C := W9.context(v, PackedVector2Array())
	var n_surf := DL.attach_surface(C, v, d)
	if n_surf > 0:
		print("[%s] 街區表 surface：%d 三角形を W9.top_h に併入（掛載済みの境內地面）" % ["DCTX", n_surf])
	var CL := DL.local_context(C, R)
	print("[DCTX] context %d ms（建物 %d → 街區近傍 %d・樹幹 %d → %d）" % [Time.get_ticks_msec() - t0, (C["bld"] as Array).size(), (CL["bld"] as Array).size(), (C["trunks"] as Array).size(), (CL["trunks"] as Array).size()])
	# ── 建物
	var blds: Array = []
	var near := R.grow(10.0)
	for b: Dictionary in C["bld"]:
		if SL.obb_d(b, R.get_center()) > R.size.length() * 0.5 + 10.0:
			continue
		var o: Vector2 = b["o"]
		var ax: Vector2 = b["ax"]
		var az: Vector2 = b["az"]
		var hw := float(b["w"]) * 0.5
		var hd := float(b["d"]) * 0.5
		var fp := PackedVector2Array([o - ax * hw - az * hd, o + ax * hw - az * hd, o + ax * hw + az * hd, o - ax * hw + az * hd])
		var hit := near.has_point(o)
		for q in fp:
			hit = hit or near.has_point(q)
		if not hit:
			continue
		blds.append({"name": b["name"], "o": _v2(o), "ax": _v2(ax), "az": _v2(az), "w": b["w"], "d": b["d"], "type": b["type"], "road": b["road"],
			"base_y": snappedf(float((C["bld_y"] as Dictionary).get(String(b["name"]), 0.0)), 0.001), "footprint": _poly(fp), "door": _poly(SL.door_poly(b))})
	# ── 道路・NPC
	var roads: Array = []
	for rn: String in C["roads"]:
		var r: Dictionary = C["roads"][rn]
		var pts: PackedVector2Array = r["pts"]
		var keep := false
		for q in pts:
			keep = keep or R.grow(20.0).has_point(q)
		if keep:
			roads.append({"name": rn, "class": r["class"], "half_w": r["hw"], "pts": _poly(pts)})
	var paths: Array = []
	for pts: PackedVector2Array in CL["npc_paths"]:
		paths.append(_poly(pts))
	var npcs: Array = []
	for q: Vector2 in CL["npc"]:
		npcs.append(_v2(q))
	var trunks: Array = []
	for q: Vector2 in CL["trunks"]:
		if R.grow(5.0).has_point(q):
			trunks.append(_v2(q))
	# ── 高さ表（見えている最上面）・水面
	var t1 := Time.get_ticks_msec()
	var HR := R.grow(4.0)
	var hnx := int(ceil(HR.size.x / hstep)) + 1
	var hnz := int(ceil(HR.size.y / hstep)) + 1
	var hs := PackedFloat32Array()
	var ws: Array = []
	var WS: RLib.TriSampler = C["WS"]
	for j in hnz:
		for i in hnx:
			var p := HR.position + Vector2(i * hstep, j * hstep)
			var h := DL.top_h(C, p)
			hs.append(snappedf(h, 0.001) if not is_nan(h) else -9999.0)
			var wh := WS.h(p.x, p.y)
			if not is_nan(wh) and (is_nan(h) or wh > h - 0.02):
				ws.append([i, j, snappedf(wh, 0.001)])
	# ── 置けない理由（W9.why の probe 0.6 m 角・ground と soft の 2 モード）
	var rnx := int(ceil(R.size.x / rstep)) + 1
	var rnz := int(ceil(R.size.y / rstep)) + 1
	var legend: Array = ["ok"]
	var rg := PackedInt32Array()
	var rsft := PackedInt32Array()
	var counts := {}
	for j in rnz:
		for i in rnx:
			var p := R.position + Vector2(i * rstep, j * rstep)
			for pass_i in 2:
				var meta := {"mode": "ground"} if pass_i == 0 else {"mode": "soft", "soft": true}
				var it := W9.item(CL, "_probe", p, Vector2(0.0, 1.0), meta)
				var k := DL.reason_key(W9.why(CL, it, [], "ground" if pass_i == 0 else "soft"))
				var ix := legend.find(k)
				if ix < 0:
					legend.append(k)
					ix = legend.size() - 1
				if pass_i == 0:
					rg.append(ix)
					counts[k] = int(counts.get(k, 0)) + 1
				else:
					rsft.append(ix)
	print("[DCTX] 高さ表 %d×%d（%.2f m）・理由表 %d×%d（%.2f m）%d ms・ground 理由：%s" % [hnx, hnz, hstep, rnx, rnz, rstep, Time.get_ticks_msec() - t1, JSON.stringify(counts)])
	# ── seed（同区の先行 overlay → manifest と同じ形の items）
	var seed: Array = []
	var seed_src := ""
	var man := DL.load_manifest(DL.manifest_path(d))
	if man.is_empty() and String(D.get("seed_manifest", "")) != "":
		# 既存 district manifest の rect 内を再利用（vid は振り直し、元の vid は src に残す）
		var sm := DL.load_manifest(String(D["seed_manifest"]))
		seed_src = "%s（rect 内）" % D["seed_manifest"]
		for e: Dictionary in sm.get("items", []):
			if not DL.in_rect(e, R):
				continue
			var e2: Dictionary = e.duplicate(true)
			e2["src"] = String(e["vid"])
			e2["vid"] = "%s_%04d" % [d, seed.size() + 1]
			seed.append(e2)
	elif man.is_empty() and ResourceLoader.exists(String(D.get("seed_scene", ""))):
		var sn := (ResourceLoader.load(String(D["seed_scene"]), "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as Node3D
		var zn := sn.get_node_or_null(String(D["seed_zone"]))
		if zn != null:
			seed_src = "%s:%s" % [D["seed_scene"], D["seed_zone"]]
			var n_i := 0
			for cl in zn.get_children():
				for n in cl.get_children():
					if not (n is Node3D and n.has_meta("w9_id")):
						continue
					var gt := RLib.rel_xf(n, sn)
					var bz := gt.basis.z
					var it := {"id": String(n.get_meta("w9_id")), "p": Vector2(gt.origin.x, gt.origin.z), "y": gt.origin.y, "yaw": atan2(bz.x, bz.z),
						"sx": gt.basis.x.length(), "sy": gt.basis.y.length(), "sz": gt.basis.z.length(), "cluster": String(cl.name),
						"mode": String(n.get_meta("w9_mode", "ground")), "b": String(n.get_meta("w9_b", "")), "who": String(n.get_meta("w9_who", "")),
						"why": String(n.get_meta("w9_why", "")), "kind": String(n.get_meta("w9_kind", "reuse")), "feature": String(n.get_meta("w9_feature", ""))}
					for f in String(n.get_meta("w9_flags", "")).split(",", false):
						it[f] = true
					n_i += 1
					seed.append(DL.entry_from_item(it, "%s_%04d" % [d, n_i]))
		sn.free()
	print("[DCTX] seed：%s（%d 件）%s" % [seed_src if seed_src != "" else "なし", seed.size(), "・既存 manifest があるので seed は出さない" if not man.is_empty() else ""])
	# ── 座標換算の検査用：既存建物（ref_buildings）の可視 LOD0 の頂点 world AABB と変換（context.glb では REF_<名>__<k>）
	var refs: Array = []
	var ref_names := {}
	for bn: String in D.get("ref_buildings", []):
		var bnode := v.find_child(bn, true, false) as Node3D
		if bnode == null:
			refs.append({"name": bn, "missing": true})
			continue
		var ab := AABB()
		var nm := 0
		var first_xf := Transform3D()
		for mi in bnode.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null or not m.is_visible_in_tree() or m.visibility_range_begin > 0.001:
				continue
			var a := DL.tight_aabb(m.mesh, m.global_transform)
			ab = a if nm == 0 else ab.merge(a)
			if nm == 0:
				first_xf = m.global_transform
			ref_names[m] = "REF_%s__%d" % [bn, nm]
			nm += 1
		var bz := first_xf.basis.z
		refs.append({"name": bn, "n_meshes": nm, "aabb_v": DL.aabb_arr(ab), "mesh0_origin": [snappedf(first_xf.origin.x, 0.0001), snappedf(first_xf.origin.y, 0.0001), snappedf(first_xf.origin.z, 0.0001)],
			"mesh0_yaw": snappedf(atan2(bz.x, bz.z), 0.000001), "mesh0_scale": [snappedf(first_xf.basis.x.length(), 0.0001), snappedf(first_xf.basis.y.length(), 0.0001), snappedf(first_xf.basis.z.length(), 0.0001)]})
	print("[DCTX] ref_buildings %d 棟（可視 LOD0 %d 面）" % [refs.size(), ref_names.size()])
	# ── 資産表
	var ids := DL.asset_ids()
	var used := {}
	for e: Dictionary in seed:
		used[String(e["asset"])] = true
	for e: Dictionary in man.get("items", []):
		used[String(e["asset"])] = true
	var assets := {}
	for id in ids:
		var a := DL.mesh_aabb(id)
		var kind := "tree" if P3.TREES.has(id) else ("bamboo" if P3.BAMBOO.has(id) else ("veg" if W9.is_veg(id) else ("shrub" if P3.SHRUB2.has(id) else "kit")))
		assets[id] = {"lod0": DL.lod0_path(id), "aabb": DL.aabb_arr(a), "foot": W9.dims(id), "kind": kind, "kit": W9.kit_of(id),
			"collide": DL.collides(id, {}), "trunk_r": float((P3.TREES[id] as Array)[1]) if P3.TREES.has(id) else 0.0}
	_write_json(out.path_join("assets.json"), {"format": "gansokoy.district_assets.v1", "space": DL.SPACE, "assets": assets})
	# ── context.json
	var ctx := {"format": "gansokoy.district_context.v1", "space": DL.SPACE, "district": d, "name": D["name"],
		"generated_at": Time.get_datetime_string_from_system(false, true), "scene": DL.SCENE, "scene_sha256": DL.file_sha256(DL.SCENE),
		"layout_sha256": DL.file_sha256("res://maps/village_v2/layout_v2.json"),
		"rect": [R.position.x, R.position.y, R.size.x, R.size.y], "manifest": ProjectSettings.globalize_path(DL.manifest_path(d)),
		"supersedes": D.get("supersedes", []), "keep_clear": _kc(D), "keep_r": DL.KEEP_R, "arm_lanes": _lanes(D),
		"buildings": blds, "roads": roads, "npc_paths": paths, "npc_points": npcs, "trunks": trunks,
		"heights": {"origin": [HR.position.x, HR.position.y], "step": hstep, "nx": hnx, "nz": hnz, "nan": -9999.0, "h": Array(hs)},
		"water": {"cells": ws},
		"reasons": {"origin": [R.position.x, R.position.y], "step": rstep, "nx": rnx, "nz": rnz, "legend": legend, "ground": Array(rg), "soft": Array(rsft),
			"probe": "W9.why（0.6 m 角・meadow 検査なし＝verify_w9p8 と同じ）"},
		"seed_source": seed_src, "seed_items": seed, "ref_objects": refs, "tolerances": {"y_snap": DL.Y_SNAP_TOL, "aabb": DL.AABB_TOL, "ref_aabb": DL.REF_AABB_TOL}}
	_write_json(out.path_join("context.json"), ctx)
	# ── GLB
	if not ("--no-glb" in args):
		_export_context_glb(v, R, out.path_join("context.glb"), ref_names)
	if assets_mode != "none":
		var list := PackedStringArray()
		for id in ids:
			if assets_mode == "all" or used.has(id):
				list.append(id)
		_export_assets_glb(list, out.path_join("assets.glb"))
	print("[DCTX] 完了 %d ms → %s" % [Time.get_ticks_msec() - t0, out])
	quit(0)


func _kc(D: Dictionary) -> Dictionary:
	var o := {}
	for k: String in D.get("keep_clear", {}):
		o[k] = _v2(D["keep_clear"][k])
	return o


func _lanes(D: Dictionary) -> Dictionary:
	var o := {}
	for k: String in D.get("arm_lanes", {}):
		var a: Array = []
		for q: Vector2 in D["arm_lanes"][k]:
			a.append(_v2(q))
		o[k] = a
	return o


func _write_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "", false))
	f.close()
	print("[DCTX] → %s（%d KB）" % [path, int(FileAccess.get_file_as_bytes(path).size() / 1024)])


func _export_context_glb(v: Node3D, R: Rect2, path: String, ref_names: Dictionary = {}) -> void:
	var t0 := Time.get_ticks_msec()
	var holder := Node3D.new()
	holder.name = "Context"
	var g := R.grow(GLB_MARGIN)
	var n := 0
	var skipped_big := 0
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree() or m.visibility_range_begin > 0.001:
			continue
		var a := m.global_transform * m.get_aabb()
		if not g.intersects(Rect2(a.position.x, a.position.z, a.size.x, a.size.z)):
			continue
		if a.size.x > GLB_MAX_SPAN or a.size.z > GLB_MAX_SPAN:
			skipped_big += 1
			continue
		var c := MeshInstance3D.new()
		c.name = String(ref_names[m]) if ref_names.has(m) else ("%s__%s" % [m.get_parent().name, m.name]).validate_node_name()
		c.mesh = m.mesh
		c.material_override = m.material_override
		for s in m.mesh.get_surface_count():
			c.set_surface_override_material(s, m.get_surface_override_material(s))
		c.transform = m.global_transform
		holder.add_child(c)
		n += 1
	root.add_child(holder)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(holder, st)
	if err == OK:
		err = doc.write_to_filesystem(st, path)
	print("[DCTX] context.glb：MeshInstance %d（大きな面 %d を除外）%s %d ms" % [n, skipped_big, "OK" if err == OK else "FAIL %d" % err, Time.get_ticks_msec() - t0])
	holder.queue_free()


func _export_assets_glb(ids: PackedStringArray, path: String) -> void:
	var t0 := Time.get_ticks_msec()
	var holder := Node3D.new()
	holder.name = "DistrictAssets"
	var x := 0
	for id in ids:
		var m := load(DL.lod0_path(id)) as Mesh
		if m == null:
			continue
		var c := MeshInstance3D.new()
		c.name = id
		c.mesh = m
		holder.add_child(c)
		x += 1
	root.add_child(holder)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(holder, st)
	if err == OK:
		err = doc.write_to_filesystem(st, path)
	print("[DCTX] assets.glb：資産 %d 件 %s %d ms" % [x, "OK" if err == OK else "FAIL %d" % err, Time.get_ticks_msec() - t0])
	holder.queue_free()
