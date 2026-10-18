extends SceneTree
## 道路路肩（village_v2，2026-10-18 FIX_REVIEW）：把「浮在地形上 6–10 cm、沒有側面的路面板邊緣」用一條斜坡路肩接回地形。
##
## 根因（tools/diag_village_v2_road_vs_collision.gd、路緣剖面實測）：Roads/** 的 ribbon 每個斷面只有兩側邊緣兩個頂點，
##   整片比地形高 +0.06（巷）／+0.10 m，邊緣是一刀切、下面是空的 → 低機位（≈ 路面高度）看得到板下的縫、人像浮在草上。
## 為什麼不把路緣壓低（tools/diag_village_v2_road_riders.gd 依離緣距離分帶實測）：街道道具 3,700、地被 3,400 個頂點落在
##   路緣 0.1–0.4 m 內、以路面頂為地面 → 壓低路緣它們全部浮空。所以路面一個頂點都不動，改在路緣「外側」加斜坡。
##
## 做法（每條路一個 MeshInstance3D，存 gen/road_shoulder.scn，village_v2.tscn 的 Roads/RoadShoulder 引用它）：
##   1 讀執行期實際顯示的路面網格（RoadBaseP10 換過的；surface 0），頂點以 1 mm 焊接，找出只屬於一個三角形的邊界邊（兩側＋路端）。
##   2 每條邊界邊沿水平外法線外推 S（S＝(路緣離地＋埋深)/0.25，0.25–0.6 m；轉角用斜接），外緣 y＝該點地形 −0.03 m（埋進地形，不留縫）。
##      內緣頂點＝路緣頂點原座標（與路面無縫）。坡度 ≈ 14°。
##   3 不做的邊（印出原因統計）：外緣或中點落在任何路面上（交叉口，避免與別條路共面 z-fight）、參道石段挖洞段（cut_s）、
##      路緣本來就貼地（< 1.2 cm）、外側地形比路緣高、外側沒有地形（水面）、外緣上方 0.12–3 m 有碰撞體（建築、牆、道具）。
##   4 材質＝外緣那一點地形「執行期實際顯示中」的材質（同 shader、同世界座標貼圖 → 外緣與地形無縫）；頂點權重：
##      外緣＝地形該點的 COLOR／UV／UV2（重心內插），內緣＝同一組再把踩實土（COLOR.r）拉到路緣的外觀（村內道路 1.0、pilot 道路 0.5）。
## 之後 tools/village_v2_road_contact_fix.gd 把路肩一起烘進道路碰撞（可見地面＝碰撞）。
## 用法：godot --headless --path godot --script res://tools/village_v2_road_shoulder.gd -- [--dry]

const ROAD_GROUPS := ["MainStreet", "SecondaryRoads", "Alleys", "FarmPaths"]
const OUT := "res://maps/village_v2/gen/road_shoulder.scn"
const DELTA := 0.03
const SLOPE := 0.25
const S_MIN := 0.25
const S_MAX := 0.6
const FLUSH := 0.012
const TT := 1 << 22
const TR := 1 << 21
const PILOT := "ground_p10_pilot.gdshader"

var scn: Node3D
var terr_map := []   # shape idx → [MeshInstance3D, surface, world verts, idx, arrays]
var sp: PhysicsDirectSpaceState3D
var skip_rids: Array[RID] = []


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


func _terrain_hit(x: float, z: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 200, z), Vector3(x, -50, z), TT)
	return sp.intersect_ray(q)


## 地形該點的顯示屬性（重心內插）：[y, material, COLOR, UV, UV2]
func _terrain_attr(x: float, z: float) -> Array:
	var h := _terrain_hit(x, z)
	if h.is_empty():
		return []
	var e: Array = terr_map[int(h.shape)]
	var mi := e[0] as MeshInstance3D
	var si: int = e[1]
	var w: PackedVector3Array = e[2]
	var idx: PackedInt32Array = e[3]
	var arr: Array = e[4]
	var t := int(h.face_index)
	var ia := idx[t * 3]
	var ib := idx[t * 3 + 1]
	var ic := idx[t * 3 + 2]
	var bc := Geometry3D.get_triangle_barycentric_coords(h.position, w[ia], w[ib], w[ic])
	var col := Color(0, 0, 0, 0)
	if arr[Mesh.ARRAY_COLOR] != null:
		var cc: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		col = cc[ia] * bc.x + cc[ib] * bc.y + cc[ic] * bc.z
	var uv := Vector2.ZERO
	if arr[Mesh.ARRAY_TEX_UV] != null:
		var u: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		uv = u[ia] * bc.x + u[ib] * bc.y + u[ic] * bc.z
	var uv2 := Vector2.ZERO
	if arr[Mesh.ARRAY_TEX_UV2] != null:
		var u2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		uv2 = u2[ia] * bc.x + u2[ib] * bc.y + u2[ic] * bc.z
	return [h.position.y, mi.get_active_material(si), col, uv, uv2]


func _on_road(x: float, z: float, y: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, y + 3.0, z), Vector3(x, y - 3.0, z), TR)
	return not sp.intersect_ray(q).is_empty()


func _obstacle(x: float, z: float, ty: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, ty + 3.0, z), Vector3(x, ty + 0.12, z), 0xFFFFFFFF & ~(TT | TR))
	q.exclude = skip_rids
	q.collide_with_areas = false
	return not sp.intersect_ray(q).is_empty()


func _run() -> void:
	var dry := OS.get_cmdline_user_args().has("--dry")
	scn = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(scn)
	for i in 6:
		await process_frame   # RoadBaseP10／RoadEdgeBlendP13／GroundPilotP10 在 _ready 的 call_deferred 換 mesh／材質
	for n in ["Collision/TerrainCollision", "Collision/RoadCollision", "Collision/DirtRoadCollision"]:
		var b := scn.get_node_or_null(n) as CollisionObject3D
		if b:
			skip_rids.append(b.get_rid())
	var old := scn.get_node_or_null("Roads/RoadShoulder")
	if old:
		old.queue_free()   # 重建時不讓舊路肩影響判定
	# 地形：每個 (網格, surface) 一個 shape
	var tb := StaticBody3D.new()
	tb.collision_layer = TT
	tb.collision_mask = 0
	scn.add_child(tb)
	var terr: Array = []
	_meshes(scn.get_node("Terrain"), terr)
	for mi: MeshInstance3D in terr:
		if not mi.is_visible_in_tree():
			continue
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var w := PackedVector3Array()
			for v in vs:
				w.append(mi.global_transform * v)
			var idx := _idx(arr)
			var f := PackedVector3Array()
			for i in idx:
				f.append(w[i])
			var sh := ConcavePolygonShape3D.new()
			sh.backface_collision = true
			sh.set_faces(f)
			var cs := CollisionShape3D.new()
			cs.shape = sh
			tb.add_child(cs)
			terr_map.append([mi, si, w, idx, arr])
	# 路面：全部一個 body（判「落在任何路面上」）
	var roads: Array = []
	for g in ROAD_GROUPS:
		_meshes(scn.get_node("Roads/" + g), roads)
	var rb := StaticBody3D.new()
	rb.collision_layer = TR
	rb.collision_mask = 0
	scn.add_child(rb)
	for mi: MeshInstance3D in roads:
		var arr := mi.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var f := PackedVector3Array()
		for i in _idx(arr):
			f.append(mi.global_transform * vs[i])
		var sh := ConcavePolygonShape3D.new()
		sh.backface_collision = true
		sh.set_faces(f)
		var cs := CollisionShape3D.new()
		cs.shape = sh
		rb.add_child(cs)
	for i in 3:
		await physics_frame
	sp = scn.get_world_3d().direct_space_state
	var out_root := Node3D.new()
	out_root.name = "RoadShoulder"
	out_root.set_meta("note", "2026-10-18 道路路肩（tools/village_v2_road_shoulder.gd 產生，勿手改）：路緣外側斜坡接回地形；路面頂點不動")
	var tot := {}
	var area_all := 0.0
	for mi: MeshInstance3D in roads:
		var res = _road(mi, tot)
		if res == null:
			continue
		var m: ArrayMesh = res[0]
		area_all += float(res[1])
		var o := MeshInstance3D.new()
		o.name = String(mi.name)
		o.mesh = m
		o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out_root.add_child(o)
		o.owner = out_root
	print("[shoulder] 合計：路肩面積 %.1f m²；邊界邊統計 %s" % [area_all, JSON.stringify(tot)])
	if not dry:
		var ps := PackedScene.new()
		var e := ps.pack(out_root)
		print("[shoulder] pack %s；寫 %s → %s" % [error_string(e), OUT, error_string(ResourceSaver.save(ps, OUT, ResourceSaver.FLAG_COMPRESS))])
	quit(0)


func _road(mi: MeshInstance3D, tot: Dictionary):
	var arr := mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var uv2 = arr[Mesh.ARRAY_TEX_UV2]
	var idx := _idx(arr)
	var mat := mi.get_active_material(0)
	var pilot := mat is ShaderMaterial and (mat as ShaderMaterial).shader != null and (mat as ShaderMaterial).shader.resource_path.ends_with(PILOT)
	var cut_s := Vector2.ZERO
	var cut_hw := 0.0
	if mat is ShaderMaterial:
		var cs = (mat as ShaderMaterial).get_shader_parameter("cut_s")
		if cs is Vector2:
			cut_s = cs
		var ch = (mat as ShaderMaterial).get_shader_parameter("cut_hw")
		if ch is float:
			cut_hw = ch
	# 焊接
	var key_of := {}
	var wv := PackedVector3Array()
	var wuy := PackedFloat32Array()
	var wux := PackedFloat32Array()
	var whw := PackedFloat32Array()
	var remap := PackedInt32Array()
	remap.resize(vs.size())
	for i in vs.size():
		var p := mi.global_transform * vs[i]
		var k := Vector3i(roundi(p.x * 1000.0), roundi(p.y * 1000.0), roundi(p.z * 1000.0))
		if not key_of.has(k):
			key_of[k] = wv.size()
			wv.append(p)
			wuy.append(uv[i].y)
			wux.append(absf(uv[i].x))
			whw.append((uv2 as PackedVector2Array)[i].x if uv2 != null else 1.0)
		remap[i] = key_of[k]
	var edges := {}   # Vector2i(min,max) → [count, third]
	for t in idx.size() / 3:
		var tri := [remap[idx[t * 3]], remap[idx[t * 3 + 1]], remap[idx[t * 3 + 2]]]
		for j in 3:
			var a: int = tri[j]
			var b: int = tri[(j + 1) % 3]
			var c: int = tri[(j + 2) % 3]
			if a == b:
				continue
			var ek := Vector2i(mini(a, b), maxi(a, b))
			if edges.has(ek):
				edges[ek][0] += 1
			else:
				edges[ek] = [1, c, a, b]
	# 邊界邊與外法線
	var bnd := []   # [a, b, n(Vector2)]
	var vn := {}    # 頂點 → [Σn, [邊法線]]
	for ek in edges:
		var e: Array = edges[ek]
		if int(e[0]) != 1:
			continue
		var a: int = e[2]
		var b: int = e[3]
		var c: int = e[1]
		var d := Vector2(wv[b].x - wv[a].x, wv[b].z - wv[a].z)
		if d.length() < 1e-4:
			continue
		var n := Vector2(-d.y, d.x).normalized()
		if n.dot(Vector2(wv[c].x - wv[a].x, wv[c].z - wv[a].z)) > 0.0:
			n = -n
		bnd.append([a, b, n])
		for v in [a, b]:
			if not vn.has(v):
				vn[v] = [Vector2.ZERO, []]
			vn[v][0] += n
			(vn[v][1] as Array).append(n)
	# 每個邊界頂點：外緣點與屬性（或無效原因）
	var vinfo := {}
	for v in vn:
		var p: Vector3 = wv[v]
		var sum: Vector2 = vn[v][0]
		if sum.length() < 1e-4:
			vinfo[v] = "miter"
			continue
		var nv := sum.normalized()
		var cmin := 1.0
		for en: Vector2 in vn[v][1]:
			cmin = minf(cmin, nv.dot(en))
		var ta := _terrain_attr(p.x, p.z)
		if ta.is_empty():
			vinfo[v] = "no_terrain"
			continue
		var h: float = p.y - float(ta[0])
		if h < FLUSH:
			vinfo[v] = "flush"
			continue
		var s := clampf((h + DELTA) / SLOPE, S_MIN, S_MAX) / maxf(cmin, 0.5)
		var o2 := Vector2(p.x, p.z) + nv * s
		var to := _terrain_attr(o2.x, o2.y)
		if to.is_empty():
			vinfo[v] = "no_terrain"
			continue
		if float(to[0]) - DELTA > p.y - 0.01:
			vinfo[v] = "terrain_higher"
			continue
		if cut_s.y > cut_s.x and wuy[v] > cut_s.x - 0.5 and wuy[v] < cut_s.y + 0.5 and wux[v] * whw[v] < cut_hw + 0.01:
			vinfo[v] = "cut_s"
			continue
		var inner_col: Color = ta[2]
		inner_col.r = maxf(inner_col.r, 0.5 if pilot else 1.0)
		var inner_uv2: Vector2 = ta[4]
		vinfo[v] = {"o": Vector3(o2.x, float(to[0]) - DELTA, o2.y), "mat": to[1], "oc": to[2], "ouv": to[3], "ouv2": to[4], "ic": inner_col, "iuv": ta[3], "iuv2": Vector2(inner_uv2.x, 0.0), "ty": float(to[0])}
	# 每條邊界邊 → 四邊形
	var surf := {}   # material → {verts, cols, uvs, uv2s, idx, vmap}
	var area := 0.0
	var nquad := 0
	for e in bnd:
		var a: int = e[0]
		var b: int = e[1]
		var why := ""
		if not (vinfo[a] is Dictionary):
			why = String(vinfo[a])
		elif not (vinfo[b] is Dictionary):
			why = String(vinfo[b])
		else:
			var ia: Dictionary = vinfo[a]
			var ib: Dictionary = vinfo[b]
			var oa: Vector3 = ia["o"]
			var ob: Vector3 = ib["o"]
			var mid_e := (wv[a] + wv[b]) * 0.5
			var mid_o := (oa + ob) * 0.5
			var mm := (mid_e + mid_o) * 0.5
			for q: Vector3 in [oa, ob, mid_o, mm]:
				if _on_road(q.x, q.z, q.y + 0.05):
					why = "on_road"
					break
			if why == "":
				for q: Vector3 in [oa, ob, mid_o, mm, mid_e]:
					if _obstacle(q.x, q.z, float(ia["ty"])):
						why = "obstacle"
						break
		if why != "":
			tot[why] = int(tot.get(why, 0)) + 1
			continue
		tot["ok"] = int(tot.get("ok", 0)) + 1
		var ia2: Dictionary = vinfo[a]
		var ib2: Dictionary = vinfo[b]
		var mat2: Material = ia2["mat"]
		if not surf.has(mat2):
			surf[mat2] = {"v": [], "c": [], "u": [], "u2": [], "i": [], "map": {}}   # 一般 Array（Dictionary 裡的 Packed 陣列 append 會改到副本）
		var S: Dictionary = surf[mat2]
		var ids := []
		for spec in [[a, false], [b, false], [b, true], [a, true]]:
			var v: int = spec[0]
			var outer: bool = spec[1]
			var kk := Vector2i(v, 1 if outer else 0)
			if not (S["map"] as Dictionary).has(kk):
				var info: Dictionary = vinfo[v]
				S["map"][kk] = (S["v"] as Array).size()
				(S["v"] as Array).append(info["o"] if outer else wv[v])
				(S["c"] as Array).append(info["oc"] if outer else info["ic"])
				(S["u"] as Array).append(info["ouv"] if outer else info["iuv"])
				(S["u2"] as Array).append(info["ouv2"] if outer else info["iuv2"])
			ids.append(S["map"][kk])
		var V: Array = S["v"]
		for tri in [[ids[0], ids[1], ids[2]], [ids[0], ids[2], ids[3]]]:
			var n3: Vector3 = (V[tri[1]] - V[tri[0]]).cross(V[tri[2]] - V[tri[0]])
			# Godot 正面＝從正面看順時針 → (b−a)×(c−a) 朝下（與 Terrain／路面相同）。反了的話 cull_disabled 的地面 shader
			#   會把背面法線翻成朝下 → 路肩打光變黑（2026-10-18 CrossStreetMid 實測出現黑色楔形帶）。
			if n3.y > 0.0:
				tri = [tri[0], tri[2], tri[1]]
			area += n3.length() * 0.5
			(S["i"] as Array).append_array(tri)
		nquad += 1
	if nquad == 0:
		return null
	var m := ArrayMesh.new()
	for mat3 in surf:
		var S: Dictionary = surf[mat3]
		var V := PackedVector3Array(S["v"])
		var I := PackedInt32Array(S["i"])
		var N := PackedVector3Array()
		N.resize(V.size())
		for t in I.size() / 3:
			var fn := (V[I[t * 3 + 1]] - V[I[t * 3]]).cross(V[I[t * 3 + 2]] - V[I[t * 3]])
			for j in 3:
				N[I[t * 3 + j]] += fn
		for i in N.size():
			N[i] = -N[i].normalized() if N[i].length() > 1e-9 else Vector3.UP   # 繞向朝下 → 面法線取反＝朝上
		var a2 := []
		a2.resize(Mesh.ARRAY_MAX)
		a2[Mesh.ARRAY_VERTEX] = V
		a2[Mesh.ARRAY_NORMAL] = N
		a2[Mesh.ARRAY_COLOR] = PackedColorArray(S["c"])
		a2[Mesh.ARRAY_TEX_UV] = PackedVector2Array(S["u"])
		a2[Mesh.ARRAY_TEX_UV2] = PackedVector2Array(S["u2"])
		a2[Mesh.ARRAY_INDEX] = I
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
		m.surface_set_material(m.get_surface_count() - 1, mat3)
	m.resource_name = "RoadShoulder_" + String(mi.name)
	print("[shoulder] %-18s 邊界邊 %4d → 路肩四邊形 %4d、%5.1f m²、%d 個材質%s" % [mi.name, bnd.size(), nquad, area, surf.size(), "（pilot 道路）" if pilot else ""])
	return [m, area]
