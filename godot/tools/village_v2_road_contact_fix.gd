extends SceneTree
## 道路「可見地面 ↔ 碰撞」修正（village_v2，2026-10-18 FIX_REVIEW）。
##
## 實測根因（tools/diag_village_v2_road_vs_collision.gd／diag_village_v2_foot_contact.gd）：
##   Roads/** 的 ribbon 是純渲染（沒有碰撞），離地形 +0.06（巷道）／+0.10（主街・次要道路・農道 2/3/5）；
##   玩家站在 Collision/TerrainCollision（= 地形可見面，差 0.000）上 → 鞋底在可見路面下 6–10 cm（另加動畫本身 1.5 cm）。
## 為什麼不把路面往下貼地（tools/diag_village_v2_road_riders.gd 實測）：NPC（Population/*P10）、街道道具（StreetP10）、
##   參道石階、燈籠、河岸、地被地面……共約 2.6 萬個頂點以「路面頂」為地面 → 路面一降，它們全部浮起 6–10 cm。
##   路面頂才是這個村子實際的地面基準，所以讓碰撞跟上路面。
## 第一版（7a892c9）把 ribbon 全部三角形烘進碰撞，但 ground_p10_pilot.gdshader 會 discard（外緣草舌＋參道石段挖洞段）
##   → 約 615 m² 有碰撞、看不到路面，玩家浮在草上中位 0.10 m。修正：
##   ① 草舌改在路面高度畫草（tools/village_v2_ground_pilot_lib.gd），不再 discard → 那些地方路面看得到；
##   ② 參道石段挖洞段（材質 cut_s／cut_hw）仍 discard → 在 (UV.x×半寬, UV.y) 平面上把三角形精確減掉該矩形（不按像素、邊界是直線）；
##   ③ 路肩（Roads/RoadShoulder，tools/village_v2_road_shoulder.gd）一起烘進來（路緣外側斜坡＝可見地面）。
## 路緣垂直裙邊（2026-10-18 第一次實驗）已撤回：垂直面在 ground shader 下是近黑色的帶；改用斜坡路肩（地形材質、權重漸變）。
##
## 輸出 gen/road_col.res（ConcavePolygonShape3D），village_v2.tscn 的 Collision/DirtRoadCollision/Shape 引用它。
##   改了任何道路網格、路肩或道路材質的 cut_s 之後重跑本工具（先跑 village_v2_road_shoulder.gd）。
## 用法：godot --headless --path godot --script res://tools/village_v2_road_contact_fix.gd -- [--dry]

const ROAD_GROUPS := ["MainStreet", "SecondaryRoads", "Alleys", "FarmPaths"]
const COL_OUT := "res://maps/village_v2/gen/road_col.res"


func _init() -> void:
	_run.call_deferred()


func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)


static func _idx(arr: Array) -> PackedInt32Array:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx := PackedInt32Array()
	if arr[Mesh.ARRAY_INDEX] != null:
		idx = arr[Mesh.ARRAY_INDEX]
	if idx.is_empty():
		for i in vs.size():
			idx.append(i)
	return idx


static func _area2(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		s += p[i].x * p[(i + 1) % p.size()].y - p[(i + 1) % p.size()].x * p[i].y
	return s * 0.5


## 三角形（世界 a,b,c；平面座標 t＝(UV.x×半寬, UV.y)）減去矩形 rect → 剩下的世界三角形
static func _clip(a: Vector3, b: Vector3, c: Vector3, t: PackedVector2Array, rect: PackedVector2Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var den := (t[1].y - t[2].y) * (t[0].x - t[2].x) + (t[2].x - t[1].x) * (t[0].y - t[2].y)
	if absf(den) < 1e-12:
		return PackedVector3Array([a, b, c])
	var res := Geometry2D.clip_polygons(t, rect)
	for pg: PackedVector2Array in res:
		# Geometry2D 的結果一律外框逆時針（面積 > 0）、洞順時針（< 0），與輸入三角形的繞向無關（2026-10-18 實測）
		if _area2(pg) < 0.0:
			return PackedVector3Array([a, b, c])   # 帶洞的結果（矩形整個在三角形裡）——ribbon 不會發生；保守起見原樣保留
	for pg: PackedVector2Array in res:
		var ti := Geometry2D.triangulate_polygon(pg)
		for k in ti.size():
			var x := pg[ti[k]]
			var w0 := ((t[1].y - t[2].y) * (x.x - t[2].x) + (t[2].x - t[1].x) * (x.y - t[2].y)) / den
			var w1 := ((t[2].y - t[0].y) * (x.x - t[2].x) + (t[0].x - t[2].x) * (x.y - t[2].y)) / den
			out.append(a * w0 + b * w1 + c * (1.0 - w0 - w1))
	return out


func _run() -> void:
	var dry := OS.get_cmdline_user_args().has("--dry")
	var scn: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(scn)
	for i in 6:
		await process_frame   # RoadBaseP10／RoadEdgeBlendP13／ShrineApproachP10 等 overlay 在 _ready 的 call_deferred 換 mesh／材質
	var roads: Array = []
	for g in ROAD_GROUPS:
		_meshes(scn.get_node("Roads/" + g), roads)
	var faces := PackedVector3Array()
	var cut_area := 0.0
	for mi: MeshInstance3D in roads:
		var arr := mi.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var uv2 = arr[Mesh.ARRAY_TEX_UV2]
		var idx := _idx(arr)
		var mat := mi.get_active_material(0)
		var cut_s := Vector2.ZERO
		var cut_hw := 0.0
		if mat is ShaderMaterial:
			var cs = (mat as ShaderMaterial).get_shader_parameter("cut_s")
			var ch = (mat as ShaderMaterial).get_shader_parameter("cut_hw")
			if cs is Vector2 and ch is float:
				cut_s = cs
				cut_hw = ch
		var has_cut := cut_s.y > cut_s.x and cut_hw > 0.0
		var rect := PackedVector2Array([Vector2(-cut_hw, cut_s.x), Vector2(cut_hw, cut_s.x), Vector2(cut_hw, cut_s.y), Vector2(-cut_hw, cut_s.y)])
		var n0 := faces.size()
		var removed := 0.0
		for t in idx.size() / 3:
			var ia := idx[t * 3]
			var ib := idx[t * 3 + 1]
			var ic := idx[t * 3 + 2]
			var a := mi.global_transform * vs[ia]
			var b := mi.global_transform * vs[ib]
			var c := mi.global_transform * vs[ic]
			if not has_cut:
				faces.append_array(PackedVector3Array([a, b, c]))
				continue
			var hw: float = (uv2 as PackedVector2Array)[ia].x if uv2 != null else 1.0
			var tt := PackedVector2Array([Vector2(uv[ia].x * hw, uv[ia].y), Vector2(uv[ib].x * hw, uv[ib].y), Vector2(uv[ic].x * hw, uv[ic].y)])
			var kept := _clip(a, b, c, tt, rect)
			faces.append_array(kept)
			var ka := 0.0
			for k in kept.size() / 3:
				ka += (kept[k * 3 + 1] - kept[k * 3]).cross(kept[k * 3 + 2] - kept[k * 3]).length() * 0.5
			removed += (b - a).cross(c - a).length() * 0.5 - ka
		cut_area += removed
		print("[rcf] %-40s %5d 三角形%s" % [String(scn.get_path_to(mi)), (faces.size() - n0) / 3, "（參道石段挖洞段 cut_s=%s cut_hw=%.2f 扣除 %.1f m²）" % [cut_s, cut_hw, removed] if has_cut else ""])
	var sh_n := 0
	var shoulder := scn.get_node_or_null("Roads/RoadShoulder")
	if shoulder == null:
		push_error("找不到 Roads/RoadShoulder（先跑 tools/village_v2_road_shoulder.gd 並掛進 village_v2.tscn）")
	else:
		var sms: Array = []
		_meshes(shoulder, sms)
		for mi: MeshInstance3D in sms:
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				for i in _idx(arr):
					faces.append(mi.global_transform * vs[i])
					sh_n += 1
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	print("[rcf] DirtRoadCollision：%d 條路＋路肩 %d 三角形，共 %d 個三角形；參道挖洞段扣除 %.1f m²" % [roads.size(), sh_n / 3, faces.size() / 3, cut_area])
	if not dry:
		print("[rcf] 寫 %s → %s" % [COL_OUT, error_string(ResourceSaver.save(shape, COL_OUT))])
	quit(0)
