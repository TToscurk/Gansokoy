extends SceneTree
## P10 R5–R6 Environmental Rehabilitation — MASTER AUDIT 量測（只讀，headless）。
##   Godot --headless --path godot --script res://tools/audit_village_v2_rehab.gd -- --out=<json> [--section=boundary,roads,sight,arch,props,env]
## 不寫任何場景／封存／overlay；只 instantiate village_v2.tscn 於記憶體中量測。
## 注意（MultiMesh Build Rule 3）：headless 讀不到 MultiMesh 實例矩陣，本工具不讀 MultiMesh 位置。

const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const FX0 := 0.0
const FX1 := 560.0
const FZ0 := -340.0
const FZ1 := 220.0
const MAX_FLOOR_DEG := 52.0

var v: Node3D
var space: PhysicsDirectSpaceState3D
var trid: RID
var L: Dictionary
var R := {}

func _init() -> void:
	_run.call_deferred()

func _p(s: String) -> void:
	print("[REHAB] " + s)

func _run() -> void:
	var out := ""
	var sections := ["boundary", "roads", "sight", "arch", "props", "env", "shrine", "vista"]
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--section="):
			sections = a.trim_prefix("--section=").split(",")
	L = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var t0 := Time.get_ticks_msec()
	v = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 3:
		await physics_frame
	space = v.get_world_3d().direct_space_state
	trid = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	R["scene"] = SCENE
	R["scene_sha256"] = FileAccess.get_sha256(SCENE)
	R["load_ms"] = Time.get_ticks_msec() - t0
	for s: String in sections:
		var ts := Time.get_ticks_msec()
		match s:
			"boundary": _boundary()
			"roads": _roads()
			"sight": _sight()
			"arch": _arch()
			"props": _props()
			"env": await _env()
			"shrine": _shrine()
			"vista": _vista()
			"water": _water()
			"props_pen": _props_pen()
			"roads_float": _roads_float()
		_p("section %s %d ms" % [s, Time.get_ticks_msec() - ts])
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(R, "\t"))
		f.close()
		_p("→ " + out)
	v.queue_free()
	await process_frame
	quit(0)

# ───────────── helpers ─────────────
func _ground(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 150.0, z), Vector3(x, -80.0, z))
	var ex: Array[RID] = []
	for k in 24:
		q.exclude = ex
		var h := space.intersect_ray(q)
		if h.is_empty():
			return NAN
		if h["rid"] == trid:
			return float(h["position"].y)
		ex.append(h["rid"])
	return NAN

func _rel(n: Node) -> String:
	return String(v.get_path_to(n))

func _top(n: Node, depth := 3) -> String:
	var parts := _rel(n).split("/")
	return "/".join(parts.slice(0, mini(depth, parts.size())))

# ───────────── BOUNDARY ─────────────
func _boundary() -> void:
	var B := {}
	# 2 m 覆蓋（front-face only）
	var tot := 0
	var miss := 0
	var x := 1.0
	while x < FX1:
		var z := FZ0 + 1.0
		while z < FZ1:
			tot += 1
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 150.0, z), Vector3(x, -80.0, z))
			q.hit_back_faces = false
			var ex: Array[RID] = []
			var h := {}
			for k in 24:
				q.exclude = ex
				h = space.intersect_ray(q)
				if h.is_empty() or h["rid"] == trid:
					break
				ex.append(h["rid"])
			if h.is_empty() or h["rid"] != trid:
				miss += 1
			z += 2.0
		x += 2.0
	B["coverage_2m"] = {"cells": tot, "no_front_face_terrain": miss}
	# 牆
	var walls := []
	for cs in v.get_node("Collision/Boundary").get_children():
		if cs is CollisionShape3D:
			var b := (cs as CollisionShape3D).shape as BoxShape3D
			var p := (cs as Node3D).global_position
			walls.append({"name": String(cs.name), "center": [p.x, p.y, p.z], "size": [b.size.x, b.size.y, b.size.z],
				"y_min": p.y - b.size.y * 0.5, "y_max": p.y + b.size.y * 0.5, "disabled": (cs as CollisionShape3D).disabled})
	B["walls"] = walls
	# 邊緣剖面：邊上 1 m、內側 15 m／40 m 高度，邊坡（內 10 m 帶）坡度
	var edges := {}
	for e in [["N", Vector2(0, -1)], ["S", Vector2(0, 1)], ["W", Vector2(-1, 0)], ["E", Vector2(1, 0)]]:
		var dir: Vector2 = e[1]
		var length := (FX1 - FX0) if dir.y != 0.0 else (FZ1 - FZ0)
		var s := 2.0
		var hs := []
		var lower_than_inside := 0
		var climbable := 0
		var n := 0
		var minh := INF
		var maxh := -INF
		var low_runs := []
		while s < length - 2.0:
			var pe: Vector2
			if dir == Vector2(0, -1):
				pe = Vector2(FX0 + s, FZ0 + 1.0)
			elif dir == Vector2(0, 1):
				pe = Vector2(FX0 + s, FZ1 - 1.0)
			elif dir == Vector2(-1, 0):
				pe = Vector2(FX0 + 1.0, FZ0 + s)
			else:
				pe = Vector2(FX1 - 1.0, FZ0 + s)
			var inw := -dir
			var h0 := _ground(pe.x, pe.y)
			var h15 := _ground(pe.x + inw.x * 15.0, pe.y + inw.y * 15.0)
			var h40 := _ground(pe.x + inw.x * 40.0, pe.y + inw.y * 40.0)
			# 內 10 m 帶最大坡度（1 m 步）
			var steep := 0.0
			var prev := h0
			for k in range(1, 11):
				var hk := _ground(pe.x + inw.x * k, pe.y + inw.y * k)
				steep = maxf(steep, rad_to_deg(atan(absf(hk - prev))))
				prev = hk
			n += 1
			minh = minf(minh, h0)
			maxh = maxf(maxh, h0)
			if h0 <= h40 + 0.5:
				lower_than_inside += 1
			if steep <= MAX_FLOOR_DEG:
				climbable += 1
			hs.append([snappedf(s, 1.0), snappedf(h0, 0.01), snappedf(h15, 0.01), snappedf(h40, 0.01), snappedf(steep, 0.1)])
			s += 8.0
		edges[e[0]] = {"samples": n, "edge_h_min": snappedf(minh, 0.01), "edge_h_max": snappedf(maxh, 0.01),
			"edge_not_higher_than_40m_inside": lower_than_inside, "edge_band_walkable_le52deg": climbable, "profile": hs}
	B["edges"] = edges
	# 畫面：越出 frame 的可見網格（AABB 超出 > 3 m）
	var beyond := {}
	var total_vis := 0
	for mi in v.find_children("*", "GeometryInstance3D", true, false):
		var gi := mi as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var bb: AABB
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
			bb = gi.global_transform * (gi as MeshInstance3D).mesh.get_aabb()
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
			bb = gi.global_transform * (gi as MultiMeshInstance3D).multimesh.get_aabb()
		else:
			continue
		total_vis += 1
		var out := bb.position.x < FX0 - 3.0 or bb.end.x > FX1 + 3.0 or bb.position.z < FZ0 - 3.0 or bb.end.z > FZ1 + 3.0
		if out:
			var k := _top(gi, 2)
			beyond[k] = int(beyond.get(k, 0)) + 1
	B["visual_beyond_frame_gt3m"] = {"geometry_instances_checked": total_vis, "by_group": beyond}
	# Terrain 網格本身的邊界
	var tb := {}
	for t in v.get_node("Terrain").get_children():
		if t is MeshInstance3D:
			var bb: AABB = t.global_transform * (t as MeshInstance3D).mesh.get_aabb()
			tb[String(t.name)] = [snappedf(bb.position.x, 0.1), snappedf(bb.position.z, 0.1), snappedf(bb.end.x, 0.1), snappedf(bb.end.z, 0.1), snappedf(bb.position.y, 0.1), snappedf(bb.end.y, 0.1)]
	B["terrain_mesh_xz_bounds"] = tb
	R["boundary"] = B
	_p("boundary coverage miss=%d/%d, walls=%d, beyond=%s" % [miss, tot, walls.size(), JSON.stringify(beyond)])

# ───────────── ROADS ─────────────
func _roads() -> void:
	var out := []
	var arrays_ok := true
	for mi in v.get_node("Roads").find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if _rel(m).begins_with("Roads/Bridges"):
			continue
		var rec := {"path": _rel(m), "class": m.get_meta("class", ""), "label": m.get_meta("label", ""), "width_m": m.get_meta("width_m", 0.0)}
		var mat := m.material_override if m.material_override else (m.mesh.surface_get_material(0) if m.mesh else null)
		rec["material"] = mat.get_class() if mat else "null"
		if mat is ShaderMaterial:
			rec["shader"] = (mat as ShaderMaterial).shader.resource_path.get_file() if (mat as ShaderMaterial).shader else ""
			rec["mode"] = (mat as ShaderMaterial).get_shader_parameter("mode")
		elif mat is StandardMaterial3D:
			rec["albedo"] = (mat as StandardMaterial3D).albedo_color.to_html(false)
		var arr: Array = m.mesh.surface_get_arrays(0) if m.mesh else []
		if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null or (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			arrays_ok = false
			rec["verts"] = 0
		else:
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			rec["verts"] = vs.size()
			var xf := m.global_transform
			var dmin := INF
			var dmax := -INF
			var dsum := 0.0
			var nd := 0
			var above15 := 0
			var below0 := 0
			var stride := maxi(1, vs.size() / 1500)
			var i := 0
			while i < vs.size():
				var w := xf * vs[i]
				var g := _ground(w.x, w.z)
				if not is_nan(g):
					var d := w.y - g
					dmin = minf(dmin, d)
					dmax = maxf(dmax, d)
					dsum += d
					nd += 1
					if d > 0.15:
						above15 += 1
					if d < 0.0:
						below0 += 1
				i += stride
			rec["ribbon_minus_terrain"] = {"n": nd, "min": snappedf(dmin, 0.001), "max": snappedf(dmax, 0.001), "mean": snappedf(dsum / maxf(nd, 1), 0.001),
				"frac_gt_0.15m": snappedf(float(above15) / maxf(nd, 1), 0.001), "frac_below_terrain": snappedf(float(below0) / maxf(nd, 1), 0.001)}
		out.append(rec)
	R["roads"] = {"mesh_arrays_readable_headless": arrays_ok, "ribbons": out}
	# 地形頂點權重（farm＝UV.y）在道路 footprint 內／路肩帶
	var tw := {}
	for tn in ["MainTerrain", "FarmlandTerrain"]:
		var tm := v.get_node_or_null("Terrain/" + tn) as MeshInstance3D
		if tm == null:
			continue
		var arr: Array = tm.mesh.surface_get_arrays(0)
		if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
			tw[tn] = "arrays unreadable"
			continue
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		tw[tn] = {"verts": vs.size(), "has_uv": not uv.is_empty()}
		if uv.is_empty():
			continue
		# 每條路：中心線 ±(hw+2) 的頂點中 farm>0.1 的比例；路面下（≤hw）與路肩（hw..hw+2）分開
		var per := {}
		for r in L["roads"]:
			var pts := PackedVector2Array()
			for p in r["pts"]:
				pts.append(Vector2(float(p[0]), float(p[1])))
			var hw := float(r["half_w"])
			var key := "%s:%s" % [r.get("label", ""), r.get("class", "")]
			var rb := Rect2(pts[0], Vector2.ZERO)
			for pp in pts:
				rb = rb.expand(pp)
			rb = rb.grow(hw + 2.5)
			var under := 0
			var under_farm := 0
			var sh := 0
			var sh_farm := 0
			for vi in range(0, vs.size()):
				var q := Vector2(vs[vi].x, vs[vi].z)
				if not rb.has_point(q):
					continue
				var d := _dist_poly(pts, q)
				if d <= hw:
					under += 1
					if uv[vi].y > 0.1:
						under_farm += 1
				elif d <= hw + 2.0:
					sh += 1
					if uv[vi].y > 0.1:
						sh_farm += 1
			if under + sh > 0:
				per[key] = {"under": under, "under_farm_gt0.1": under_farm, "shoulder2m": sh, "shoulder_farm_gt0.1": sh_farm}
		tw[tn]["roads_farm_weight"] = per
	R["roads"]["terrain_farm_weight"] = tw

func _dist_poly(pts: PackedVector2Array, q: Vector2) -> float:
	var best := INF
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * t))
	return best

# ───────────── SIGHT（進村路線 → 地標） ─────────────
const ENTRY := [[224, 172], [229, 132], [234, 104], [236, 80], [242, 40], [262, -20], [280, -80], [300, -130], [292, -160], [280, -190], [266, -208]]
const TARGETS := {
	"SOUTH_GATE_torii": [234, 100, [5.0, 9.0]],
	"TOWER_hinomi": [250, 66, [10.0, 16.0]],
	"KIRISAME": [229.7, 62, [3.5]],
	"SUZUNAAN": [247.8, -6, [3.5]],
	"GEIDONTEI": [284.6, -62, [4.0]],
	"HILL_TORII": [289.6, -166, [3.0, 5.0]],
	"HILLFOOT_TEMPLE": [228, -170, [5.0]],
	"NORTH_HILL_shrine": [258, -228, [4.0, 7.0]],
	"DRAGON": [388, -188, [8.0, 13.0]],
	"TERAKOYA": [188, 24, [6.0]],
	"HIEDA": [403, -40, [5.0]],
}

func _sight() -> void:
	var pts := PackedVector2Array()
	for p in ENTRY:
		pts.append(Vector2(float(p[0]), float(p[1])))
	var samples := []
	var acc := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var t := 0.0
		while t < seg:
			samples.append([a.lerp(b, t / seg), acc + t, i])
			t += 4.0
		acc += seg
	samples.append([pts[pts.size() - 1], acc, pts.size() - 2])
	var tgt := {}
	for k in TARGETS:
		var T: Array = TARGETS[k]
		var g := _ground(float(T[0]), float(T[1]))
		var ps := []
		for hh in T[2]:
			ps.append(Vector3(float(T[0]), g + float(hh), float(T[1])))
		tgt[k] = ps
	var res := {}
	var npc_rids: Array[RID] = []
	for b in v.get_node("Population").find_children("*", "CollisionObject3D", true, false):
		npc_rids.append((b as CollisionObject3D).get_rid())
	for k in tgt:
		res[k] = {"visible_samples": 0, "first_visible_m": -1.0, "blockers": {}, "dist_first_visible": -1.0}
	var per_sample := []
	for s in samples:
		var p2: Vector2 = s[0]
		var g := _ground(p2.x, p2.y)
		var eye := Vector3(p2.x, g + 1.7, p2.y)
		var row := {"s_m": snappedf(float(s[1]), 0.1), "at": [snappedf(p2.x, 0.1), snappedf(p2.y, 0.1)], "vis": []}
		for k in tgt:
			var seen := false
			var blk := ""
			for tp: Vector3 in tgt[k]:
				if eye.distance_to(tp) > 600.0:
					continue
				var q := PhysicsRayQueryParameters3D.create(eye, tp)
				q.exclude = npc_rids
				var h := space.intersect_ray(q)
				if h.is_empty():
					seen = true
					break
				var hp: Vector3 = h["position"]
				if hp.distance_to(tp) < 2.5:
					seen = true
					break
				var c := h["collider"] as Node
				var nm := _top(c, 4) if c else "?"
				if c and c.get_rid() == trid:
					nm = "TERRAIN"
				if blk == "":
					blk = nm
			if seen:
				res[k]["visible_samples"] += 1
				if res[k]["first_visible_m"] < 0.0:
					res[k]["first_visible_m"] = snappedf(float(s[1]), 0.1)
				row["vis"].append(k)
			elif blk != "":
				res[k]["blockers"][blk] = int(res[k]["blockers"].get(blk, 0)) + 1
		per_sample.append(row)
	for k in res:
		var bl: Dictionary = res[k]["blockers"]
		var arr := []
		for b in bl:
			arr.append([b, bl[b]])
		arr.sort_custom(func(a, b): return a[1] > b[1])
		res[k]["blockers"] = arr.slice(0, 8)
		res[k]["samples"] = samples.size()
	R["sight"] = {"route": ENTRY, "eye_h": 1.7, "sample_step_m": 4.0, "route_len_m": snappedf(acc, 0.1), "landmarks": res, "per_sample": per_sample,
		"note": "physics rays vs collision (buildings = P4 box / Hero compound / props collision); canopy foliage without collision does not block → vegetation occlusion under-estimated"}
	_p("sight samples=%d" % samples.size())

# ───────────── ARCH（P6 町家重複） ─────────────
func _arch() -> void:
	var kits := []
	for n in v.get_node("Districts").find_children("*", "", true, false):
		if n.has_meta("roof_cls") and n.has_meta("style"):
			var p := (n as Node3D).global_position if n is Node3D else Vector3.ZERO
			kits.append({"path": _rel(n), "style": String(n.get_meta("style")), "roof": String(n.get_meta("roof_cls")),
				"bays": int(n.get_meta("bays", 0)), "r3": String(n.get_meta("r3", "")), "pos": [snappedf(p.x, 0.1), snappedf(p.z, 0.1)]})
	var by_style := {}
	var by_style_roof := {}
	var by_theme := {}
	var by_full := {}
	for k: Dictionary in kits:
		by_style[k["style"]] = int(by_style.get(k["style"], 0)) + 1
		var sr := "%s|%s|%d" % [k["style"], k["roof"], k["bays"]]
		by_style_roof[sr] = int(by_style_roof.get(sr, 0)) + 1
		var th := String(k["style"]).get_slice("/", 0)
		by_theme[th] = int(by_theme.get(th, 0)) + 1
		var full := sr + "|" + String(k["r3"])
		by_full[full] = int(by_full.get(full, 0)) + 1
	var top := []
	for s in by_style_roof:
		top.append([s, by_style_roof[s]])
	top.sort_custom(func(a, b): return a[1] > b[1])
	# 鄰近同款（同 style＋roof＋bays，≤ 25 m）
	var near_dup := 0
	for i in kits.size():
		for j in range(i + 1, kits.size()):
			var a: Dictionary = kits[i]
			var b: Dictionary = kits[j]
			if a["style"] == b["style"] and a["roof"] == b["roof"] and a["bays"] == b["bays"]:
				if Vector2(a["pos"][0], a["pos"][1]).distance_to(Vector2(b["pos"][0], b["pos"][1])) <= 25.0:
					near_dup += 1
	# 材質使用（Districts 內 MeshInstance3D surface／override）
	var mats := {}
	for mi in v.get_node("Districts").find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		for si in m.mesh.get_surface_count():
			var mat: Material = m.get_active_material(si)
			if mat == null:
				continue
			var key := mat.resource_path if mat.resource_path != "" else ("%s#%d" % [mat.get_class(), mat.get_instance_id()])
			if not mats.has(key):
				var info := {"class": mat.get_class(), "uses": 0}
				if mat is StandardMaterial3D:
					var sm := mat as StandardMaterial3D
					info["albedo_color"] = sm.albedo_color.to_html(false)
					info["albedo_tex"] = sm.albedo_texture.resource_path if sm.albedo_texture else ""
					info["vertex_color_use_as_albedo"] = sm.vertex_color_use_as_albedo
					info["roughness"] = sm.roughness
					if sm.albedo_texture:
						info["tex_mean_srgb"] = _tex_mean(sm.albedo_texture)
				mats[key] = info
			mats[key]["uses"] += 1
	var mlist := []
	for k in mats:
		mlist.append([k, mats[k]])
	mlist.sort_custom(func(a, b): return a[1]["uses"] > b[1]["uses"])
	var roof_cls := {}
	for k: Dictionary in kits:
		roof_cls[k["roof"]] = int(roof_cls.get(k["roof"], 0)) + 1
	R["arch_kits"] = kits
	R["arch_roof_cls"] = roof_cls
	R["arch"] = {"kits": kits.size(), "unique_style": by_style.size(), "unique_style_roof_bays": by_style_roof.size(), "unique_full_sig": by_full.size(),
		"themes": by_theme, "top_style_roof_bays": top.slice(0, 12), "same_sig_pairs_within_25m": near_dup, "materials_top": mlist.slice(0, 25)}
	_p("arch kits=%d unique style=%d style+roof+bays=%d full=%d near_dup=%d" % [kits.size(), by_style.size(), by_style_roof.size(), by_full.size(), near_dup])

func _tex_mean(t: Texture2D) -> Array:
	var img := t.get_image()
	if img == null:
		return []
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	img.resize(64, 64, Image.INTERPOLATE_BILINEAR)
	var s := Color(0, 0, 0, 0)
	for y in 64:
		for x in 64:
			s += img.get_pixel(x, y)
	s /= 4096.0
	return [snappedf(s.r, 0.001), snappedf(s.g, 0.001), snappedf(s.b, 0.001), snappedf(0.2126 * s.r + 0.7152 * s.g + 0.0722 * s.b, 0.001)]

# ───────────── PROPS（透明／雙面／藁物） ─────────────
const STRAW_RE := "(?i)(wara|straw|hasa|inaki|komo|mushiro|tawara|zuka|warazuka|藁|稲|筵|俵|菰|hay)"

func _props() -> void:
	var re := RegEx.new()
	re.compile(STRAW_RE)
	var groups := ["Props/MarketP10", "Props/StreetP10", "Props/MarketWestP10", "Props/EnvironmentP9", "HumanUseP10", "HumanUseExpansionP10",
		"Vegetation/WatersideP9", "Vegetation/TowerYardP9", "Vegetation/SuzunaanP9", "Vegetation/GeidonteiP9", "Vegetation/KirisameP9", "Vegetation/SchoolYardP9"]
	var G := {}
	var straw := []
	for gp in groups:
		var g := v.get_node_or_null(gp)
		if g == null:
			continue
		var st := {"mesh_instances": 0, "transparent_surfaces": 0, "alpha_scissor": 0, "cull_disabled": 0, "shader_mats": 0, "mats": {}}
		for mi in g.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			st["mesh_instances"] += 1
			var nm := _rel(m)
			if re.search(nm) != null and straw.size() < 400:
				var bb: AABB = m.global_transform * m.mesh.get_aabb()
				straw.append({"path": nm, "aabb_min": [snappedf(bb.position.x, 0.01), snappedf(bb.position.y, 0.01), snappedf(bb.position.z, 0.01)],
					"aabb_size": [snappedf(bb.size.x, 0.01), snappedf(bb.size.y, 0.01), snappedf(bb.size.z, 0.01)]})
			for si in m.mesh.get_surface_count():
				var mat: Material = m.get_active_material(si)
				if mat == null:
					continue
				var key := mat.resource_path.get_file() if mat.resource_path != "" else mat.get_class()
				st["mats"][key] = int(st["mats"].get(key, 0)) + 1
				if mat is BaseMaterial3D:
					var bm := mat as BaseMaterial3D
					if bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA or bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
						st["transparent_surfaces"] += 1
					elif bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
						st["alpha_scissor"] += 1
					if bm.cull_mode == BaseMaterial3D.CULL_DISABLED:
						st["cull_disabled"] += 1
				elif mat is ShaderMaterial:
					st["shader_mats"] += 1
					var sh := (mat as ShaderMaterial).shader
					if sh:
						var code := sh.code
						if code.contains("ALPHA ") or code.contains("ALPHA="):
							st["transparent_surfaces"] += 1
						if code.contains("cull_disabled"):
							st["cull_disabled"] += 1
		G[gp] = st
	R["props"] = {"groups": G, "straw_like_nodes": straw, "straw_regex": STRAW_RE}
	_p("props groups=%d straw_like=%d" % [G.size(), straw.size()])

# ───────────── ENV（10:00 光照） ─────────────
func _env() -> void:
	for c in root.get_children():
		if c.has_method("set_hour"):
			c.call("set_hour", 10.0)
	for n in v.find_children("*", "", true, false):
		if n.has_method("set_hour"):
			n.call("set_hour", 10.0)
	for i in 10:
		await process_frame
	var E := {}
	var we := v.find_children("*", "WorldEnvironment", true, false)
	if we.size() > 0:
		var env := (we[0] as WorldEnvironment).environment
		if env:
			E["world_env_path"] = _rel(we[0])
			E["background_mode"] = env.background_mode
			E["tonemap_mode"] = env.tonemap_mode
			E["tonemap_exposure"] = env.tonemap_exposure
			E["tonemap_white"] = env.tonemap_white
			E["ambient_source"] = env.ambient_light_source
			E["ambient_color"] = env.ambient_light_color.to_html(false)
			E["ambient_energy"] = env.ambient_light_energy
			E["ambient_sky_contribution"] = env.ambient_light_sky_contribution
			E["reflected_source"] = env.reflected_light_source
			E["ssao"] = env.ssao_enabled
			E["ssil"] = env.ssil_enabled
			E["sdfgi"] = env.sdfgi_enabled
			E["glow"] = env.glow_enabled
			E["fog"] = env.fog_enabled
			E["fog_density"] = env.fog_density
			E["volumetric_fog"] = env.volumetric_fog_enabled
			E["adjustment"] = env.adjustment_enabled
			E["adj_brightness_contrast_saturation"] = [env.adjustment_brightness, env.adjustment_contrast, env.adjustment_saturation]
			if env.sky and env.sky.sky_material:
				E["sky_material"] = env.sky.sky_material.get_class() + " " + env.sky.sky_material.resource_path
	var suns := []
	for d in v.find_children("*", "DirectionalLight3D", true, false):
		var dl := d as DirectionalLight3D
		suns.append({"path": _rel(dl), "visible": dl.is_visible_in_tree(), "energy": dl.light_energy, "color": dl.light_color.to_html(false),
			"indirect": dl.light_indirect_energy, "elev_deg": snappedf(rad_to_deg(asin(clampf(dl.global_transform.basis.z.y, -1.0, 1.0))), 0.1), "shadow": dl.shadow_enabled})
	E["directional_lights"] = suns
	R["env"] = E
	_p("env " + JSON.stringify(E).left(600))


# ───────────── SHRINE（參道剖面） ─────────────
const SANDO := [[300, -130], [292, -160], [280, -190], [266, -208], [258, -222]]

func _shrine() -> void:
	var pts := PackedVector2Array()
	for p in SANDO:
		pts.append(Vector2(float(p[0]), float(p[1])))
	var prof := []
	var acc := 0.0
	var prev_y := NAN
	var prev_s := 0.0
	var hs := []
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var t := 0.0
		while t < seg:
			var q := a.lerp(b, t / seg)
			hs.append([acc + t, _ground(q.x, q.y), q])
			t += 1.0
		acc += seg
	var steep := []
	var maxdeg := 0.0
	var over8 := 0.0
	var over15 := 0.0
	var over25 := 0.0
	for i in range(0, hs.size() - 2):
		var d := rad_to_deg(atan(absf(float(hs[i + 2][1]) - float(hs[i][1])) / 2.0))
		maxdeg = maxf(maxdeg, d)
		if d > 8.0:
			over8 += 1.0
		if d > 15.0:
			over15 += 1.0
		if d > 25.0:
			over25 += 1.0
		if i % 4 == 0:
			prof.append([snappedf(float(hs[i][0]), 0.1), snappedf(float(hs[i][1]), 0.01), snappedf(d, 0.1)])
	# 參道上方 2 m 內有哪些可見節點（石段／燈籠等）
	var near := {}
	for gi in v.find_children("*", "MeshInstance3D", true, false):
		var m := gi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var c: Vector3 = m.global_transform * m.mesh.get_aabb().get_center()
		var d2 := _dist_poly(pts, Vector2(c.x, c.z))
		if d2 <= 2.5 and m.mesh.get_aabb().size.length() < 30.0:
			var k := _top(m, 3)
			near[k] = int(near.get(k, 0)) + 1
	var sando_mi := v.get_node_or_null("Roads/SecondaryRoads/HillApproach") as MeshInstance3D
	var mat_params := {}
	if sando_mi == null:
		for mi in v.get_node("Roads").find_children("*", "MeshInstance3D", true, false):
			if String(mi.get_meta("label", "")) == "參道":
				sando_mi = mi
	if sando_mi:
		var mat := sando_mi.material_override
		if mat is ShaderMaterial:
			for k in ["mode", "road_layer", "shoulder_layer", "rut_offset", "rut_strength", "wear_center", "edge_gravel"]:
				mat_params[k] = (mat as ShaderMaterial).get_shader_parameter(k)
	R["shrine"] = {"sando_len_m": snappedf(acc, 0.1), "z_start": snappedf(float(hs[0][1]), 0.01), "z_end": snappedf(float(hs[hs.size() - 1][1]), 0.01),
		"max_slope_deg_2m": snappedf(maxdeg, 0.1), "m_over_8deg": over8, "m_over_15deg": over15, "m_over_25deg": over25,
		"profile_every4m": prof, "meshes_within_2_5m_of_axis": near, "sando_node": _rel(sando_mi) if sando_mi else "", "sando_material": mat_params}
	_p("shrine len %.1f rise %.2f→%.2f max %.1f° over15 %d m" % [acc, float(hs[0][1]), float(hs[hs.size() - 1][1]), maxdeg, int(over15)])

# ───────────── VISTA（主街各段的端景） ─────────────
func _vista() -> void:
	var rows := []
	var segs := [["入口道路", [224, 172], [229, 132]], ["入口道路2", [229, 132], [234, 104]], ["主街1", [234, 104], [236, 80]], ["主街2", [236, 80], [242, 40]],
		["主街3", [242, 40], [262, -20]], ["主街4", [262, -20], [280, -80]], ["主街5", [280, -80], [300, -130]], ["參道1", [300, -130], [292, -160]],
		["中橫街E", [196, -20], [262, -20]], ["中橫街W", [380, -36], [262, -20]], ["南橫街E", [170, 50], [241, 48]], ["南橫街W", [372, 40], [241, 48]]]
	var npc_rids: Array[RID] = []
	for b in v.get_node("Population").find_children("*", "CollisionObject3D", true, false):
		npc_rids.append((b as CollisionObject3D).get_rid())
	for sg in segs:
		var a := Vector2(float(sg[1][0]), float(sg[1][1]))
		var b := Vector2(float(sg[2][0]), float(sg[2][1]))
		var dir := (b - a).normalized()
		var g := _ground(a.x, a.y)
		var eye := Vector3(a.x, g + 1.7, a.y)
		var hits := []
		for yaw_off in [-6.0, 0.0, 6.0]:
			var d2 := dir.rotated(deg_to_rad(yaw_off))
			var to := eye + Vector3(d2.x, 0.0, d2.y) * 500.0
			var q := PhysicsRayQueryParameters3D.create(eye, to)
			q.exclude = npc_rids
			var h := space.intersect_ray(q)
			if h.is_empty():
				hits.append([yaw_off, "SKY/none", -1.0])
			else:
				var c := h["collider"] as Node
				var nm := "TERRAIN" if (c and c.get_rid() == trid) else (_top(c, 4) if c else "?")
				hits.append([yaw_off, nm, snappedf(eye.distance_to(h["position"]), 0.1)])
		rows.append({"seg": sg[0], "from": [a.x, a.y], "toward": [b.x, b.y], "len_m": snappedf(a.distance_to(b), 0.1), "first_hit_at_eye_1.7": hits})
	R["vista"] = rows
	for r in rows:
		_p("vista %s len %.0f → %s" % [r["seg"], r["len_m"], str(r["first_hit_at_eye_1.7"])])


# ───────────── WATER（水位剖面、水車、出入口） ─────────────
func _water() -> void:
	var W := {}
	var bodies := {"MainRiver": L["water"]["MainRiver"]["pts"], "Canal": L["water"]["Canal"]["pts"]}
	for st in L["water"]["Streams"]:
		bodies[String(st["name"])] = st["pts"]
	var meshes := {}
	for mi in v.get_node("Water").find_children("*", "MeshInstance3D", true, false):
		meshes[String(mi.name)] = mi
	for bn in bodies:
		var pts := PackedVector2Array()
		for p in bodies[bn]:
			pts.append(Vector2(float(p[0]), float(p[1])))
		var mi: MeshInstance3D = meshes.get(bn, null)
		if mi == null:
			for k in meshes:
				if String(k).contains(bn) or bn.contains(String(k)):
					mi = meshes[k]
		if mi == null:
			W[bn] = {"mesh": "not found", "have": meshes.keys()}
			continue
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var xf := mi.global_transform
		var wv := PackedVector3Array()
		for q in vs:
			wv.append(xf * q)
		var prof := []
		var acc := 0.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var seg := a.distance_to(b)
			var t := 0.0
			while t < seg:
				var c := a.lerp(b, t / seg)
				var sy := 0.0
				var n := 0
				for w in wv:
					if Vector2(w.x, w.z).distance_squared_to(c) < 9.0:
						sy += w.y
						n += 1
				prof.append([snappedf(acc + t, 0.1), [snappedf(c.x, 0.1), snappedf(c.y, 0.1)], snappedf(sy / n, 0.01) if n > 0 else null])
				t += 20.0
			acc += seg
		var rises := 0
		var last := NAN
		for r in prof:
			if r[2] != null:
				if not is_nan(last) and float(r[2]) > last + 0.02:
					rises += 1
				last = float(r[2])
		W[bn] = {"mesh": _rel(mi), "len_m": snappedf(acc, 0.1), "stations": prof, "upstream_rises_gt2cm": rises,
			"start": bodies[bn][0], "end": bodies[bn][bodies[bn].size() - 1]}
	# 水車
	var wheels := []
	for k in ["LANDMARK_WATERWHEEL_1", "LANDMARK_WATERWHEEL_2", "LANDMARK_WATERWHEEL_3"]:
		var n := v.get_node_or_null("Landmarks/" + k) as Node3D
		if n == null:
			continue
		var h := n.get_node_or_null("Hero") as Node3D
		var names := []
		if h:
			for c in h.find_children("*", "", true, false):
				if names.size() < 40:
					names.append(String(c.name))
		wheels.append({"id": k, "pos": [snappedf(n.global_position.x, 0.01), snappedf(n.global_position.y, 0.01), snappedf(n.global_position.z, 0.01)],
			"hero_pos_y": snappedf(h.global_position.y, 0.01) if h else null, "hero_children_sample": names})
	W["waterwheels"] = wheels
	# 水上／岸邊的人為元素（P7 riverbank 名稱含 stair/moor/platform；P8 feeder）
	var rb := {}
	for c in v.get_node("Riverbank").find_children("*", "", true, false):
		var nm := String(c.name).to_lower()
		for key in ["gangi", "stair", "step", "moor", "kui", "platform", "boat", "fune", "pier"]:
			if nm.contains(key):
				rb[key] = int(rb.get(key, 0)) + 1
	W["riverbank_name_hits"] = rb
	var fl := v.find_children("*", "", true, false)
	var p8 := {}
	for c in fl:
		var nm := String(c.name)
		for key in ["Chute", "Siphon", "Culvert", "Trough", "Feeder", "Intake", "Drop", "Weir", "Outlet", "Drain"]:
			if nm.begins_with(key) or nm.contains("_" + key) or nm.contains(key + "_"):
				p8[key] = int(p8.get(key, 0)) + 1
	W["farmland_hydraulic_nodes"] = p8
	R["water"] = W
	_p("water bodies=%s wheels=%d riverbank=%s p8=%s" % [str(bodies.keys()), wheels.size(), JSON.stringify(rb), JSON.stringify(p8)])


# ───────────── PROPS_PEN（藁物の頂點 → 他の碰撞體内／地形下） ─────────────
func _props_pen() -> void:
	var re := RegEx.new()
	re.compile(STRAW_RE)
	var groups := ["Props/MarketP10", "Props/StreetP10", "Props/MarketWestP10", "HumanUseP10", "HumanUseExpansionP10", "Vegetation/WatersideP9", "Vegetation/GeidonteiP9"]
	var rows := []
	for gp in groups:
		var g := v.get_node_or_null(gp)
		if g == null:
			continue
		for mi in g.find_children("LOD0", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var item := m.get_parent()
			var nm := _rel(item)
			if re.search(nm) == null or m.mesh == null:
				continue
			var arr: Array = m.mesh.surface_get_arrays(0)
			if arr.is_empty():
				continue
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var xf := m.global_transform
			var stride := maxi(1, vs.size() / 300)
			var inside := {}
			var below := 0
			var below_max := 0.0
			var n := 0
			var i := 0
			while i < vs.size():
				var w := xf * vs[i]
				n += 1
				var pq := PhysicsPointQueryParameters3D.new()
				pq.position = w
				pq.collide_with_areas = false
				for h in space.intersect_point(pq, 4):
					var c := h["collider"] as CollisionObject3D
					if c == null or c.get_rid() == trid:
						continue
					var sid := int(h["shape"])
					var owner_id := c.shape_find_owner(sid)
					var so := c.shape_owner_get_owner(owner_id) as Node
					var key := _top(c, 4) + "::" + (String(so.name) if so else "?")
					inside[key] = int(inside.get(key, 0)) + 1
				var gy := _ground(w.x, w.z)
				if not is_nan(gy) and w.y < gy - 0.03:
					below += 1
					below_max = maxf(below_max, gy - w.y)
				i += stride
			var hits := []
			for k in inside:
				hits.append([k, inside[k]])
			hits.sort_custom(func(a, b): return a[1] > b[1])
			rows.append({"item": nm, "sampled_verts": n, "verts_inside_other_colliders": hits.slice(0, 5), "verts_below_terrain": below, "below_max_m": snappedf(below_max, 0.01)})
	R["props_pen"] = rows
	var flagged := rows.filter(func(r): return (r["verts_inside_other_colliders"] as Array).size() > 0 or int(r["verts_below_terrain"]) > 0)
	_p("props_pen items=%d flagged=%d" % [rows.size(), flagged.size()])
	for r in flagged:
		_p("  %s inside=%s below=%d (max %.2f m)" % [r["item"], str(r["verts_inside_other_colliders"]), r["verts_below_terrain"], r["below_max_m"]])


# ───────────── ROADS_FLOAT（ribbon 頂點離地 > 0.15 m 或低於地形的位置） ─────────────
func _roads_float() -> void:
	var out := {}
	for mi in v.get_node("Roads").find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if _rel(m).begins_with("Roads/Bridges") or m.mesh == null:
			continue
		var arr: Array = m.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var xf := m.global_transform
		var hi := []
		var lo := []
		for q in vs:
			var w := xf * q
			var g := _ground(w.x, w.z)
			if is_nan(g):
				continue
			var d := w.y - g
			if d > 0.15:
				hi.append([snappedf(d, 0.01), snappedf(w.x, 0.1), snappedf(w.z, 0.1)])
			elif d < 0.0:
				lo.append([snappedf(d, 0.01), snappedf(w.x, 0.1), snappedf(w.z, 0.1)])
		hi.sort_custom(func(a, b): return a[0] > b[0])
		lo.sort_custom(func(a, b): return a[0] < b[0])
		if not hi.is_empty() or not lo.is_empty():
			out[_rel(m)] = {"n_float_gt_0.15": hi.size(), "float_top": hi.slice(0, 6), "n_below": lo.size(), "below_top": lo.slice(0, 6), "verts": vs.size()}
	R["roads_float"] = out
	for k in out:
		_p("float %s: >0.15m %d top %s | below %d top %s" % [k, out[k]["n_float_gt_0.15"], str(out[k]["float_top"].slice(0, 3)), out[k]["n_below"], str(out[k]["below_top"].slice(0, 3))])
