extends SceneTree
## 人間之里 V2 P7 R2：5 座灰盒橋的現地實測（正式橋 Blender 建模的輸入；gate 另行獨立實測，不信本檔）。
##
##   godot --headless --path godot --script res://tools/village_v2_bridge_survey.gd
##
## 輸出 res://assets/blender/village_v2/bridge_sites.json（assets/blender 有 .gdignore，編輯器不匯入）。
## 每座橋以「正式橋局部座標」記錄（village_v2_hero_lib.gd bridge_frame：原點＝灰盒橋面頂中心、只有 yaw、
## +z＝道路方向＝end_heights[0] 那端、+x＝右手）：
##   dims（水平橋長 L、兩端高差 dh、灰盒寬 W）、兩端地面（橋端外 0.5 m）、地形格網（0.5 m）、水面格網、
##   路×水中心線交點、鄰近地塊與道路多邊形。

const HLib := preload("res://tools/village_v2_hero_lib.gd")
const PLib := preload("res://tools/village_v2_parcel_lib.gd")
const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const PARCELS := "res://maps/village_v2/gen/parcels.json"
const OUT := "res://assets/blender/village_v2/bridge_sites.json"
const WATER_NODE := {"Canal": "Canal", "River": "MainRiver", "WestStream": "WestStream"}
const WATER_LAYOUT := {"Canal": "Canal", "River": "MainRiver"}
const STEP := 0.5
const MARGIN_X := 5.0
const MARGIN_Z := 4.0

var v: Node3D
var space: PhysicsDirectSpaceState3D
var terrain_rid: RID


func _init() -> void:
	_run.call_deferred()


func _terrain(x: float, z: float) -> float:
	var ex: Array[RID] = []
	for i in 12:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -80.0, z))
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return NAN
		if hit["rid"] == terrain_rid:
			return float(hit["position"].y)
		ex.append(hit["rid"])
	return NAN


## 世界三角面（PackedVector3Array，每 3 點一面）中 xz 落點的最高 y（沒有＝NAN）
func _tri_y(fs: PackedVector3Array, x: float, z: float) -> float:
	var best := NAN
	var a := Vector3(x, 400.0, z)
	var b := Vector3(x, -80.0, z)
	for t in range(0, fs.size(), 3):
		var p0 := fs[t]
		var p1 := fs[t + 1]
		var p2 := fs[t + 2]
		if maxf(p0.x, maxf(p1.x, p2.x)) < x or minf(p0.x, minf(p1.x, p2.x)) > x \
				or maxf(p0.z, maxf(p1.z, p2.z)) < z or minf(p0.z, minf(p1.z, p2.z)) > z:
			continue
		var hit: Variant = Geometry3D.segment_intersects_triangle(a, b, p0, p1, p2)
		if hit != null:
			best = (hit as Vector3).y if is_nan(best) else maxf(best, (hit as Vector3).y)
	return best


func _world_faces(mi: MeshInstance3D, lo: Vector2, hi: Vector2) -> PackedVector3Array:
	var out := PackedVector3Array()
	var gx := mi.global_transform
	var fs := mi.mesh.get_faces()
	for t in range(0, fs.size(), 3):
		var p0 := gx * fs[t]
		var p1 := gx * fs[t + 1]
		var p2 := gx * fs[t + 2]
		if maxf(p0.x, maxf(p1.x, p2.x)) < lo.x or minf(p0.x, minf(p1.x, p2.x)) > hi.x \
				or maxf(p0.z, maxf(p1.z, p2.z)) < lo.y or minf(p0.z, minf(p1.z, p2.z)) > hi.y:
			continue
		out.append(p0)
		out.append(p1)
		out.append(p2)
	return out


func _r3(x: float) -> float:
	return snappedf(x, 0.001)


func _run() -> void:
	v = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	await physics_frame
	await physics_frame
	space = v.get_world_3d().direct_space_state
	terrain_rid = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var PJ: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PARCELS))
	var roads := PLib.network(L)
	var out: Array = []
	for b: Node3D in v.get_node("Roads/Bridges").get_children():
		var parts := String(b.name).split("_")
		var road_name := parts[2]
		var water_key := parts[3]
		var F: Transform3D = b.global_transform * HLib.bridge_frame(b)
		var Fi := F.affine_inverse()
		var D := HLib.bridge_dims(b)
		var Lb := float(D["L"])
		var Wb := float(D["W"])
		var road_hw := 0.0
		var road_pts := PackedVector2Array()
		for r in roads:
			if String(r["name"]) == road_name:
				road_hw = float(r["hw"])
				road_pts = r["pts"]
		# 世界 bbox（局部格網四角轉世界）
		var xs := []
		var zs := []
		var nx := int(ceil((Wb * 0.5 + MARGIN_X) / STEP))
		var nz := int(ceil((Lb * 0.5 + MARGIN_Z) / STEP))
		for i in range(-nx, nx + 1):
			xs.append(i * STEP)
		for j in range(-nz, nz + 1):
			zs.append(j * STEP)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for cx: float in [xs[0], xs[-1]]:
			for cz: float in [zs[0], zs[-1]]:
				var w := F * Vector3(cx, 0, cz)
				lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.z))
				hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.z))
		lo -= Vector2.ONE
		hi += Vector2.ONE
		var wfs := PackedVector3Array()
		for mi in v.find_children(String(WATER_NODE[water_key]), "MeshInstance3D", true, false):
			wfs.append_array(_world_faces(mi as MeshInstance3D, lo, hi))
		var terr: Array = []
		var wat: Array = []
		for cz: float in zs:
			var rt: Array = []
			var rw: Array = []
			for cx: float in xs:
				var w := F * Vector3(cx, 0, cz)
				var ty := _terrain(w.x, w.z)
				rt.append(null if is_nan(ty) else _r3(ty - F.origin.y))
				var wy := _tri_y(wfs, w.x, w.z)
				rw.append(null if is_nan(wy) else _r3(wy - F.origin.y))
			terr.append(rt)
			wat.append(rw)
		# 兩端外 0.5 m 的地面（x＝−q, 0, +q）
		var q := minf(road_hw - 0.3, Wb * 0.5 - 0.6)
		var ends := {}
		for sg: float in [-1.0, 1.0]:
			var row: Array = []
			for cx: float in [-q, 0.0, q]:
				var w := F * Vector3(cx, 0, sg * (Lb * 0.5 + 0.5))
				row.append(_r3(_terrain(w.x, w.z) - F.origin.y))
			ends["plus" if sg > 0 else "minus"] = row
		# 路×水中心線交點（layout）
		var cross: Array = []
		var wpts: Array = []
		if WATER_LAYOUT.has(water_key):
			wpts = L["water"][WATER_LAYOUT[water_key]]["pts"]
		else:
			for s in L["water"]["Streams"]:
				if String(s["name"]) == water_key:
					wpts = s["pts"]
		for a in road_pts.size() - 1:
			for k in wpts.size() - 1:
				var hit: Variant = Geometry2D.segment_intersects_segment(road_pts[a], road_pts[a + 1],
					Vector2(float(wpts[k][0]), float(wpts[k][1])), Vector2(float(wpts[k + 1][0]), float(wpts[k + 1][1])))
				if hit != null:
					var lp := Fi * Vector3((hit as Vector2).x, F.origin.y, (hit as Vector2).y)
					var c := [_r3(lp.x), _r3(lp.z)]
					if not cross.has(c):
						cross.append(c)
		# 鄰近地塊、道路（局部多邊形；只收與 bbox 相交者）
		var bb := Rect2(lo, hi - lo)
		var near_parcels: Array = []
		for r in PJ["parcels"]:
			var poly := TLib.pts(r["footprint"])
			var pr := Rect2(poly[0], Vector2.ZERO)
			for p in poly:
				pr = pr.expand(p)
			if not pr.intersects(bb):
				continue
			var lpoly: Array = []
			for p in poly:
				var lp := Fi * Vector3(p.x, F.origin.y, p.y)
				lpoly.append([_r3(lp.x), _r3(lp.z)])
			near_parcels.append({"id": String(r["id"]), "kind": String(r.get("kind", "")), "poly": lpoly})
		var near_roads: Array = []
		for r in roads:
			var pts: PackedVector2Array = r["pts"]
			var rr := Rect2(pts[0], Vector2.ZERO)
			for p in pts:
				rr = rr.expand(p)
			if not rr.grow(float(r["hw"])).intersects(bb):
				continue
			var lpts: Array = []
			for p in pts:
				var lp := Fi * Vector3(p.x, F.origin.y, p.y)
				lpts.append([_r3(lp.x), _r3(lp.z)])
			near_roads.append({"name": String(r["name"]), "hw": float(r["hw"]), "pts": lpts})
		var yaw := rad_to_deg(F.basis.get_euler().y)
		out.append({"name": String(b.name), "road": road_name, "road_hw": road_hw, "water": water_key,
			"water_node": WATER_NODE[water_key], "label": String(b.get_meta("label", "")),
			"origin": [_r3(F.origin.x), _r3(F.origin.y), _r3(F.origin.z)], "yaw_deg": snappedf(yaw, 0.0001),
			"L": _r3(Lb), "dh": _r3(float(D["dh"])), "W": _r3(Wb), "box_h": _r3(float(D["box_h"])),
			"meta_length_m": float(b.get_meta("length_m")), "meta_end_heights": b.get_meta("end_heights"),
			"cross_deg": float(b.get_meta("cross_deg")), "span": TLib.bridge_span(L, String(b.name)),
			"ground_end": ends, "ground_end_q": _r3(q), "crossing": cross,
			"grid": {"step": STEP, "x": xs, "z": zs, "terrain": terr, "water": wat},
			"parcels": near_parcels, "roads": near_roads})
		print("[SURVEY] %s：L %.3f、dh %.3f、W %.2f、原點 (%.2f, %.3f, %.2f)、yaw %.2f°、路 %s hw %.1f、水 %s（%d 面）、兩端地面 − %s ＋ %s、交點 %s、鄰近地塊 %d、道路 %d" % [
			b.name, Lb, float(D["dh"]), Wb, F.origin.x, F.origin.y, F.origin.z, yaw, road_name, road_hw, water_key,
			wfs.size() / 3, ends["minus"], ends["plus"], cross, near_parcels.size(), near_roads.size()])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify({"_note": "village_v2_bridge_survey.gd 產生；正式橋 Blender 建模輸入（局部座標見腳本說明）。gate 不讀本檔。",
		"bridges": out}, "", false) + "\n")
	f.close()
	print("[SURVEY] 寫入 %s（%d 座）" % [OUT, out.size()])
	quit(0)
