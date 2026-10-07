@tool
extends RefCounted
## P10 R3b Population Pilot：小規模の実景人口テスト（主市集 MarketP10・Market West 裏通り・主街の市の口の一区間、計 16 人）。
## 完全な人口システムではない：固定 anchor の Idle、A↔B の短い往復（Walk）だけ。crowd AI・navigation・schedule・避讓・日夜なし。
## 見た目＝封存 NPC Asset Library（characters/npc/<id>/<id>.tscn を instance するだけ、封存ファイルは一切変更しない）。
## 動作＝各 NPC の封存済み Idle／Walk clip だけ（新しい動作は追加しない）。
## 出力 gen/population_p10.tscn（個別ノード、MultiMesh なし）→ village_v2 の新トップノード Population/PopulationP10。
##   Props の下に置かない：封存 MeadowP9／EnvironmentP9 の規劃は Props の全メッシュ・Marker を occupancy として読むため、
##   NPC を Props に入れると封存層の再計算結果が変わる。
## 立ち位置は封存 P10 overlay（MarketP10／MarketWestP10／StreetP10）の NPC activity anchors を読む（anchor は変更しない）。

const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const ML := preload("res://tools/village_v2_groundcover_macro.gd")

const OUTPUT := "res://maps/village_v2/gen/population_p10.tscn"
const NODE_NAME := "PopulationP10"
const PARENT := "Population"
const ACTOR := "res://scripts/npc_population_actor.gd"
const ROSTER := "res://characters/npc/npc_roster.json"
const ART_REVISION := "P10 R3b Population Pilot r1 ART_REVIEW"
const OVERLAYS := ["Props/MarketP10", "Props/MarketWestP10", "Props/StreetP10"]
const CAP_R := 0.22

## 職業→その外見で許される「商い」（使用者の対位表）。gate は cast の trade がこの表に入っているかを見る。
const ROLE_OK := {
	"yaoya_m01": ["yasai", "tenbin"],
	"sakanaya_m01": ["sakana", "passer"],
	"nunoya_f01": ["gofuku"],
	"chaya_f01": ["chaya"],
	"takigi_m01": ["zakka", "porter", "takigi"],
	"shufu_f01": ["customer"],
	"yakusou_f01": ["kanbutsu", "kusuri", "customer"],
	"setomono_f01": ["seto", "zakka"],
	"kozo_m01": ["errand"],
	"chonin_m01": ["customer", "clerk", "porter", "passer"],
}
## 歩かせない（Walk が若い／歩幅が大きい → Idle 優先）：婆婆 2 人は walker 0、少年は walker ≤ 1
const NO_WALK := ["yakusou_f01", "setomono_f01"]
const WALK_MAX := {"kozo_m01": 1}

## 配役 16（zone, model, trade, 立ち位置＝anchor「overlay/anchor 名」＋局所ずらし、向き＝anchor／相手／ベクトル、mode）
## 小群：八百屋と客（市集）、呉服屋と客（裏通り）、振り売りと客（主街）＝2 人組 3。他は単独の店主・停留者・行き交う人。
const CAST := [
	# ── 主市集（MarketP10）7
	{"id": "M1", "zone": "market", "model": "yaoya_m01", "trade": "yasai", "anchor": "MarketP10/vendor_yatai_yasai", "off": [0.75, 0.0], "face": "anchor", "group": "g_yasai"},
	{"id": "M2", "zone": "market", "model": "shufu_f01", "trade": "customer", "anchor": "MarketP10/customer_yatai_yasai_b", "face": "anchor", "group": "g_yasai"},
	{"id": "M3", "zone": "market", "model": "chonin_m01", "trade": "clerk", "anchor": "MarketP10/vendor_yatai_cha", "off": [0.75, 0.0], "face": "anchor"},
	{"id": "M4", "zone": "market", "model": "sakanaya_m01", "trade": "sakana", "anchor": "MarketP10/vendor_yatai_sakana", "off": [0.0, -0.75], "face": "anchor"},
	{"id": "M5", "zone": "market", "model": "setomono_f01", "trade": "seto", "anchor": "MarketP10/vendor_tana_seto", "off": [0.0, -0.75], "face": "anchor"},
	{"id": "M6", "zone": "market", "model": "takigi_m01", "trade": "zakka", "anchor": "MarketP10/vendor_tana_zakka", "off": [0.0, -0.75], "face": "anchor"},
	{"id": "M7", "zone": "market", "model": "kozo_m01", "trade": "errand", "mode": "patrol",
		"path": [[243.0, -27.5], [243.0, -36.0], [243.0, -45.5]], "wait": [1.5, 3.5]},
	# ── Market West 裏通り（MarketWestP10）5
	{"id": "W1", "zone": "market_west", "model": "nunoya_f01", "trade": "gofuku", "anchor": "MarketWestP10/mw_n2_vendor", "face": "partner:W2", "group": "g_gofuku"},
	{"id": "W2", "zone": "market_west", "model": "shufu_f01", "trade": "customer", "anchor": "MarketWestP10/mw_n2_customer", "off": [-0.9, -0.1], "face": "partner:W1", "group": "g_gofuku"},
	{"id": "W3", "zone": "market_west", "model": "chaya_f01", "trade": "chaya", "anchor": "MarketWestP10/mw_n6_vendor", "face": "anchor"},
	{"id": "W4", "zone": "market_west", "model": "yakusou_f01", "trade": "kanbutsu", "anchor": "MarketWestP10/mw_n4_vendor", "face": "anchor"},
	{"id": "W5", "zone": "market_west", "model": "chonin_m01", "trade": "passer", "mode": "patrol",
		"path": [[208.6, -44.6], [216.0, -44.6], [224.2, -44.6]], "wait": [2.0, 5.0]},
	# ── 主街（StreetP10、中橫街との角＝市の口〜MKT_025）4
	{"id": "S1", "zone": "main_street", "model": "chonin_m01", "trade": "porter", "anchor": "StreetP10/st_porter_ichi", "face": "anchor"},
	{"id": "S2", "zone": "main_street", "model": "yaoya_m01", "trade": "tenbin", "anchor": "StreetP10/st_vendor_MKT_025", "off": [0.0, 0.25], "face": "partner:S3", "group": "g_tenbin"},
	{"id": "S3", "zone": "main_street", "model": "yakusou_f01", "trade": "customer", "anchor": "StreetP10/st_customer_MKT_025", "face": "partner:S2", "group": "g_tenbin"},
	{"id": "S4", "zone": "main_street", "model": "sakanaya_m01", "trade": "passer", "mode": "patrol",
		"path": [[264.2, -28.5], [266.0, -35.5], [267.6, -42.8]], "wait": [2.5, 5.0]},
]


static func roster() -> Dictionary:
	var ro: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROSTER))
	var out := {"chonin_m01": {"id": "chonin_m01", "height": 1.68, "walk_clip": "", "idle_clip": ""}}
	for n: Dictionary in ro["npcs"]:
		out[n["id"]] = n
	return out


static func npc_scene(model: String) -> String:
	return "res://characters/npc/%s/%s.tscn" % [model, model]


## 見えている最上面：地形・路面・P4 院子地面・Market West の通りの床（＋店先帯）
static func context(v: Node3D) -> Dictionary:
	var F := RLib.TriSampler.new()
	var mw := v.get_node_or_null("Props/MarketWestP10")
	if mw != null:
		for grp in ["Floor", "Frontage"]:
			var g := mw.get_node_or_null(grp)
			if g == null:
				continue
			for mi in g.find_children("*", "MeshInstance3D", true, false):
				var m := (mi as MeshInstance3D).mesh
				if m != null and (mi as MeshInstance3D).visibility_range_begin <= 0.001:
					F.add(m.get_faces(), RLib.rel_xf(mi, v))
	var anchors := {}
	for ov: String in OVERLAYS:
		var g := v.get_node_or_null(ov)
		if g == null:
			continue
		for mk in g.find_children("*", "Marker3D", true, false):
			var n3 := mk as Node3D
			var xf := RLib.rel_xf(n3, v)
			anchors[ov.get_file() + "/" + String(mk.name)] = {"p": xf.origin, "yaw": xf.basis.get_euler().y,
				"act": String(mk.get_meta("activity", "")), "ref": String(mk.get_meta("ref", ""))}
	return {"S": RLib.terrain_sampler(v), "R": RLib.road_sampler(v), "Y": ML.yard_sampler(v), "F": F, "RI": RenderIndex.new(v), "anchors": anchors}


static func top_h(C: Dictionary, p: Vector2) -> float:
	var h := (C["S"] as RLib.TriSampler).h(p.x, p.y)
	for k: String in ["R", "Y", "F"]:
		var hv := (C[k] as RLib.TriSampler).h(p.x, p.y)
		if not is_nan(hv):
			h = maxf(h, hv)
	var RI: RenderIndex = C.get("RI")
	if RI != null:
		var fy := RI.floor_y(p, h + 0.35)   # 店先帯・踏み段など、地表より少し高い見えている床
		if not is_nan(fy):
			h = maxf(h, fy)
	return h


## 見えている描画メッシュ（LOD0／近距離、植生・地形・水・人口を除く）の索引：足元の床の高さと体の貫通を描画三角形で測る。
## 衝突體は屋台全体の箱など粗いので、売り手が屋台の内側に立つ anchor を誤って「衝突」にしてしまう → 体の判定は描画三角形。
class RenderIndex:
	var items: Array = []      # [aabb, faces(world), path]
	var _faces := {}

	func _init(v: Node3D) -> void:
		for top in ["Props", "Districts", "Landmarks", "Roads", "Riverbank"]:
			var g := v.get_node_or_null(top)
			if g == null:
				continue
			for mi in g.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				var path := String(v.get_path_to(m))
				if m.mesh == null or m.visibility_range_begin > 0.001 or not m.is_visible_in_tree() or path.contains("ParcelLines") or String(m.name) in ["Wire", "Footprint"]:
					continue
				var xf := RLib.rel_xf(m, v)
				items.append([xf * m.get_aabb(), m, xf, path])

	func faces(it: Array) -> PackedVector3Array:
		var key: String = it[3]
		if not _faces.has(key):
			var raw := (it[1] as MeshInstance3D).mesh.get_faces()
			var xf: Transform3D = it[2]
			var out := PackedVector3Array()
			out.resize(raw.size())
			for i in raw.size():
				out[i] = xf * raw[i]
			_faces[key] = out
		return _faces[key]

	## p の真下、ymax 以下で最も高い上向き三角形（normal.y > 0.6）
	func floor_y(p: Vector2, ymax: float) -> float:
		var best := NAN
		for it: Array in items:
			var a: AABB = it[0]
			if p.x < a.position.x or p.x > a.end.x or p.y < a.position.z or p.y > a.end.z or a.position.y > ymax:
				continue
			var f := faces(it)
			for t in range(0, f.size(), 3):
				var n := (f[t + 1] - f[t]).cross(f[t + 2] - f[t])
				if n.length_squared() < 1e-12 or absf(n.normalized().y) < 0.6:
					continue
				var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(p.x, ymax, p.y), Vector3.DOWN, f[t], f[t + 1], f[t + 2])
				if hit != null and (hit as Vector3).y <= ymax and (is_nan(best) or (hit as Vector3).y > best):
					best = (hit as Vector3).y
		return best

	## 立った体（足元 p から高さ h、半径 r の capsule、足首 0.12 m より上）に入る描画三角形の持ち主
	func body_hits(p: Vector3, h: float, r: float) -> Array:
		var a0 := p + Vector3(0, 0.12 + r, 0)
		var a1 := p + Vector3(0, h - r, 0)
		var box := AABB(Vector3(p.x - r, p.y + 0.12, p.z - r), Vector3(2 * r, h - 0.12, 2 * r))
		var out := []
		for it: Array in items:
			if not (it[0] as AABB).intersects(box):
				continue
			var f := faces(it)
			for t in range(0, f.size(), 3):
				var tb := AABB(f[t], Vector3.ZERO).expand(f[t + 1]).expand(f[t + 2])
				if not tb.intersects(box):
					continue
				if _seg_tri_d(a0, a1, f[t], f[t + 1], f[t + 2]) < r:
					out.append(String(it[3]).get_file())
					break
		return out

	static func _seg_tri_d(s0: Vector3, s1: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
		if Geometry3D.segment_intersects_triangle(s0, s1, a, b, c) != null:
			return 0.0
		var best := INF
		for q in [s0, s1]:
			best = minf(best, (q as Vector3).distance_to(_closest_on_tri(q, a, b, c)))
		for e in [[a, b], [b, c], [c, a]]:
			var r := Geometry3D.get_closest_points_between_segments(s0, s1, e[0], e[1])
			best = minf(best, (r[0] as Vector3).distance_to(r[1]))
		# 線分の途中が三角形の面に最も近い場合：等間隔の点で補う
		for k in range(1, 8):
			var q := s0.lerp(s1, k / 8.0)
			best = minf(best, q.distance_to(_closest_on_tri(q, a, b, c)))
		return best

	static func _closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
		var ab := b - a
		var ac := c - a
		var ap := p - a
		var d1 := ab.dot(ap)
		var d2 := ac.dot(ap)
		if d1 <= 0.0 and d2 <= 0.0:
			return a
		var bp := p - b
		var d3 := ab.dot(bp)
		var d4 := ac.dot(bp)
		if d3 >= 0.0 and d4 <= d3:
			return b
		var vc := d1 * d4 - d3 * d2
		if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
			return a + ab * (d1 / (d1 - d3))
		var cp := p - c
		var d5 := ab.dot(cp)
		var d6 := ac.dot(cp)
		if d6 >= 0.0 and d5 <= d6:
			return c
		var vb := d5 * d2 - d1 * d6
		if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
			return a + ac * (d2 / (d2 - d6))
		var va := d3 * d6 - d5 * d4
		if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
			return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
		var den := 1.0 / (va + vb + vc)
		return a + ab * (vb * den) + ac * (vc * den)


## Walk clip の足の接地速度（m/s）：in-place clip で接地中の足が後ろへ動く速さ＝この clip を滑らずに歩かせる移動速度。
static func walk_speed(v: Node3D, model: String) -> Dictionary:
	var npc: Node3D = (load(npc_scene(model)) as PackedScene).instantiate()
	npc.set("frozen", true)
	npc.set("animation", &"walk")
	npc.set("start_time", 0.0)
	v.add_child(npc)
	var ap := npc.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var sk := npc.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var L := ap.current_animation_length
	var meds := []
	for bn in ["LeftFoot", "RightFoot"]:
		var bi := sk.find_bone(bn)
		var ys := []
		var zs := []
		var N := 120
		for k in N:
			ap.seek(L * k / N, true)
			var p := sk.global_transform * sk.get_bone_global_pose(bi).origin
			ys.append(p.y)
			zs.append(p.z)
		var ymin: float = ys.min()
		var sp := []
		for k in N:
			var k2 := (k + 1) % N
			if ys[k] < ymin + 0.02 and ys[k2] < ymin + 0.02:
				sp.append(-(zs[k2] - zs[k]) / (L / N))
		sp.sort()
		meds.append(float(sp[sp.size() / 2]) if sp.size() > 0 else 0.0)
	var clip := String(npc.get("walk_clip"))
	v.remove_child(npc)
	npc.free()
	return {"speed": 0.5 * (float(meds[0]) + float(meds[1])), "left": meds[0], "right": meds[1], "clip_len": L, "clip": clip}


static func yaw_to(d: Vector2) -> float:
	return atan2(d.x, d.y)


static func plan(v: Node3D, cast: Array = CAST) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var C := context(v)
	var RO := roster()
	var speeds := {}
	var actors: Array = []
	var byid := {}
	var k := 0
	for e: Dictionary in cast:
		var a := {"id": e["id"], "zone": e["zone"], "model": e["model"], "trade": e["trade"], "mode": e.get("mode", "idle"),
			"group": e.get("group", ""), "anchor": e.get("anchor", ""), "seed": 7919 * (k + 3)}
		var rng := RandomNumberGenerator.new()
		rng.seed = a["seed"]
		a["height"] = float(RO.get(e["model"], {}).get("height", 1.68))
		a["idle_t"] = snappedf(rng.randf_range(0.0, 6.0), 0.01)     # Idle の位相（並んだ同 clip が同期しない）
		a["speed_scale"] = snappedf(rng.randf_range(0.93, 1.07), 0.01) if a["mode"] == "idle" else 1.0
		if a["mode"] == "patrol":
			if not speeds.has(e["model"]):
				speeds[e["model"]] = walk_speed(v, e["model"])
			a["walk"] = speeds[e["model"]]
			a["walk_speed"] = snappedf(float(speeds[e["model"]]["speed"]), 0.001)
			var pts := PackedVector2Array()
			for q: Array in e["path"]:
				pts.append(Vector2(float(q[0]), float(q[1])))
			# 0.25 m 毎に見えている最上面の高さを焼く
			var L := 0.0
			for i in range(1, pts.size()):
				L += pts[i].distance_to(pts[i - 1])
			var ys := PackedFloat32Array()
			var n := int(ceil(L / 0.25)) + 1
			for j in n:
				ys.append(top_h(C, _along(pts, minf(j * 0.25, L))))
			a["path_xz"] = pts
			a["path_y"] = ys
			a["path_len"] = L
			a["wait"] = e.get("wait", [2.0, 5.0])
			a["start_u"] = snappedf(rng.randf_range(0.15, 0.85), 0.01)
			a["p"] = Vector3(pts[0].x, ys[0], pts[0].y)
			a["yaw"] = yaw_to(pts[1] - pts[0])
		else:
			var an: Dictionary = C["anchors"].get(e["anchor"], {})
			if an.is_empty():
				a["error"] = "anchor %s が無い" % e["anchor"]
				actors.append(a)
				k += 1
				continue
			var p3: Vector3 = an["p"]
			var off: Array = e.get("off", [0.0, 0.0])
			var p2 := Vector2(p3.x + float(off[0]), p3.z + float(off[1]))
			a["p"] = Vector3(p2.x, top_h(C, p2), p2.y)
			a["yaw"] = float(an["yaw"])
			a["anchor_act"] = an["act"]
		a["face"] = e.get("face", "anchor")
		actors.append(a)
		byid[a["id"]] = a
		k += 1
	# 話し相手の方を向く
	for a: Dictionary in actors:
		var f := String(a.get("face", ""))
		if f.begins_with("partner:") and byid.has(f.trim_prefix("partner:")):
			var b: Dictionary = byid[f.trim_prefix("partner:")]
			var d := Vector2((b["p"] as Vector3).x - (a["p"] as Vector3).x, (b["p"] as Vector3).z - (a["p"] as Vector3).z)
			a["yaw"] = yaw_to(d)
	return {"actors": actors, "C": C, "speeds": speeds, "ms": Time.get_ticks_msec() - t0}


static func _along(pts: PackedVector2Array, u: float) -> Vector2:
	var acc := 0.0
	for i in range(1, pts.size()):
		var s := pts[i].distance_to(pts[i - 1])
		if acc + s >= u or i == pts.size() - 1:
			return pts[i - 1].lerp(pts[i], clampf((u - acc) / maxf(s, 1e-4), 0.0, 1.0))
		acc += s
	return pts[pts.size() - 1]


## 個別ノードの場景：Population/PopulationP10/<zone>/<id>_<model>（AnimatableBody3D＋capsule＋NPC instance）
static func build(P: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	var zones := {}
	var script := load(ACTOR) as Script
	for a: Dictionary in P["actors"]:
		if a.has("error"):
			continue
		var z := String(a["zone"])
		if not zones.has(z):
			var zn := Node3D.new()
			zn.name = {"market": "Market", "market_west": "MarketWest", "main_street": "MainStreet"}[z]
			root.add_child(zn)
			zn.owner = root
			zones[z] = zn
		var body := AnimatableBody3D.new()
		body.name = "%s_%s" % [a["id"], a["model"]]
		body.set_script(script)
		body.sync_to_physics = false
		body.transform = Transform3D(Basis(Vector3.UP, float(a["yaw"])), a["p"])
		body.set("mode", a["mode"])
		body.set("seed_i", int(a["seed"]))
		if a["mode"] == "patrol":
			body.set("path_xz", a["path_xz"])
			body.set("path_y", a["path_y"])
			body.set("walk_speed", float(a["walk_speed"]))
			body.set("wait_min", float(a["wait"][0]))
			body.set("wait_max", float(a["wait"][1]))
			body.set("start_u", float(a["start_u"]))
		body.set_meta("model", a["model"])
		body.set_meta("trade", a["trade"])
		body.set_meta("zone", a["zone"])
		body.set_meta("group", a["group"])
		body.set_meta("anchor", a["anchor"])
		(zones[z] as Node).add_child(body)
		body.owner = root
		var cs := CollisionShape3D.new()
		cs.name = "Body"
		var cap := CapsuleShape3D.new()
		cap.radius = CAP_R
		cap.height = float(a["height"]) - 0.06
		cs.shape = cap
		cs.position = Vector3(0, cap.height * 0.5 + 0.04, 0)
		body.add_child(cs)
		cs.owner = root
		var npc: Node3D = (load(npc_scene(a["model"])) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		npc.name = "NPC"
		npc.set("animation", &"idle" if a["mode"] == "idle" or float(a.get("start_u", -1.0)) < 0.0 else &"walk")
		npc.set("start_time", float(a["idle_t"]))
		npc.set("speed_scale", float(a["speed_scale"]))
		body.add_child(npc)
		npc.owner = root
	root.set_meta("art_revision", ART_REVISION)
	root.set_meta("actors", (P["actors"] as Array).size())
	return root
