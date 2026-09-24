extends SceneTree
## 人間之里 V2：主街視線回歸（P1 起每次改產生器都要跑）。
##   Godot --headless --path godot --script res://tools/verify_village_v2_sightlines.gd
## 視點：MainStreet 中線每 4 m，眼高 1.7 m（人眼）與 2.3 m（審圖鏡頭）。
## 目標：(a) 同一條中線上前後 12–150 m 的點（同眼高）＝街道走廊視線；
##       (b) 視覺終點：山頂社殿頂、南大鳥居笠木（主街 62 站）；
##       (c) 龍神像「漸進式揭露」：終點接近區 REVEAL_ZONE 每 4 m 一站。
## 擋物：Landmarks／QuestAnchors／Portals 底下所有「有體積」的三角面網格
##       （AABB 高 > 0.3 m；平貼地面的 footprint 與線框不算）；(c) 另外加上 Districts/*/Buildings 全部建築。
## 門檻＝P1 ART_APPROVED（2026-09-24）時的實測：走廊 0、社殿 0、南大鳥居 0。
## 龍神像（使用者裁示 2026-09-24，P4 r1 後）：主街→龍神像的設計意圖保留，但改成漸進式揭露、不要求主街全程可見。
##   P4 放進 187 棟町家後主街 62 站只剩 1 站看得到——彎曲町家街本來就會擋遠景，舊 gate（只算地標、主街 62 站）
##   跟真實街廓不相容。主街 62 站改為 INFO 報數據；硬 gate 改到終點接近區，且把所有建築算進去。
## 每項印一行 [SL] PASS/FAIL（INFO 不計失敗）；結尾 quit(失敗項數)。

const SCN := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
## 每個眼高允許被擋的站數上限：{眼高: {目標: 上限}}
## 龍神像只報 INFO（不在表內＝不判失敗）
const LIMITS := {
	1.7: {"山頂社殿": 0, "南大鳥居": 0},
	2.3: {"山頂社殿": 0, "南大鳥居": 0},
}
## 龍神像漸進式揭露：[道路, 起點錨, 終點錨, 硬 gate?]。錨＝某條路的起點／終點（"Road:start"／"Road:end"），"" ＝整條路頭／尾。
##   (1) 揭露段 INFO：主街北端轉進山腳街 → 河北小徑路口。北側是 P3 核准的正式町家列（MXC_018–022，已多為平屋），
##       龍神像在東北、會被這排擋住一部分——這段本來就是「轉角後逐漸露出」，只報看得到幾站。
##   (2) 終點接近區（硬 gate，上限 0 站）：離開町家街廓以後——山腳街河北小徑路口以東、河北小徑、龍神橋路。
const REVEAL_ZONE := [
	["HillFootStreet", "MainStreet:end", "RiverNorthPath:start", false],
	["HillFootStreet", "RiverNorthPath:start", "", true],
	["RiverNorthPath", "", "", true],
	["DragonBridgeRoad", "", "", true],
]
const REVEAL_LIMIT := 0

var occ: Array = []   # [id, group, AABB, PackedVector3Array faces(world)]
var occ_all: Array = []   # occ＋Districts/*/Buildings（P4 起）
var fails := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v: Node3D = (load(SCN) as PackedScene).instantiate()
	root.add_child(v)
	await physics_frame
	await physics_frame
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	for grp in ["Landmarks", "QuestAnchors", "Portals"]:
		for n in v.get_node(grp).get_children():
			var faces := PackedVector3Array()
			var box := AABB()
			var first := true
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				var m: Mesh = (mi as MeshInstance3D).mesh
				if m == null or not (mi as MeshInstance3D).visible:
					continue
				var ab: AABB = (mi as MeshInstance3D).global_transform * m.get_aabb()
				if ab.size.y <= 0.3:
					continue
				# Mesh.get_faces() 只收三角面 surface：線框（PRIMITIVE_LINES）回傳空陣列
				var mf := m.get_faces()
				if mf.is_empty():
					continue
				var xf: Transform3D = (mi as MeshInstance3D).global_transform
				for p in mf:
					faces.append(xf * p)
				box = ab if first else box.merge(ab)
				first = false
			if not faces.is_empty():
				occ.append([String(n.name), grp, box, faces])
	occ_all = occ.duplicate()
	for d in v.get_node("Districts").get_children():
		var bg := d.get_node_or_null("Buildings")
		if bg == null:
			continue
		for n in bg.get_children():
			var e := _collect(n)
			if not e.is_empty():
				occ_all.append([String(n.name), "Buildings", e[0], e[1]])
	print("[SL] 有體積的 placeholder：%d 個；加上建築共 %d 個" % [occ.size(), occ_all.size()])
	var ms := PackedVector2Array()
	for r in L["roads"]:
		if r["name"] == "MainStreet":
			for p in r["pts"]:
				ms.append(Vector2(float(p[0]), float(p[1])))
	var space := root.get_world_3d().direct_space_state
	var st: Array = []   # [Vector2, ground]
	var cum := 0.0
	var k := 0
	var s := 0.0
	while k < ms.size() - 1:
		var seg := ms[k].distance_to(ms[k + 1])
		while s <= cum + seg:
			var p := ms[k].lerp(ms[k + 1], (s - cum) / seg)
			st.append([p, _ground(space, p)])
			s += 4.0
		cum += seg
		k += 1
	_check(st.size() > 50, "主街測站 %d 個（每 4 m，全長 %.0f m）" % [st.size(), cum])
	var targets := [
		["山頂社殿", _top(v, "Landmarks/LANDMARK_NORTH_HILL")],
		["龍神像", _top(v, "Landmarks/LANDMARK_DRAGON")],
		["南大鳥居", _top(v, "Landmarks/LANDMARK_SOUTH_GATE")],
	]
	var net := {}
	for r in L["roads"]:
		net[String(r["name"])] = r["pts"]
	for eye in LIMITS.keys():
		var total := 0
		var blocked := {}
		var blocked_rays := 0
		for i in st.size():
			var a: Vector2 = st[i][0]
			var from := Vector3(a.x, float(st[i][1]) + eye, a.y)
			for j in st.size():
				var d := a.distance_to(st[j][0])
				if j == i or d < 12.0 or d > 150.0:
					continue
				var b: Vector2 = st[j][0]
				total += 1
				var hit := _hits(from, Vector3(b.x, float(st[j][1]) + eye, b.y))
				if not hit.is_empty():
					blocked_rays += 1
					for h in hit:
						blocked[h] = int(blocked.get(h, 0)) + 1
		_check(total > 0 and blocked_rays == 0, "眼高 %.1f m 走廊視線 %d 條，被擋 %d 條（上限 0）：%s" % [eye, total, blocked_rays, _fmt(blocked)])
		for tgt in targets:
			if tgt[1] == Vector3.ZERO:
				_check(false, "找不到視覺終點 %s" % tgt[0])
				continue
			var tb := {}
			var tn := 0
			for i in st.size():
				var a: Vector2 = st[i][0]
				var hit := _hits(Vector3(a.x, float(st[i][1]) + eye, a.y), tgt[1], tgt[0])
				if not hit.is_empty():
					tn += 1
					for h in hit:
						tb[h] = int(tb.get(h, 0)) + 1
			# 全建築（INFO）
			var an := 0
			var ab := {}
			for i in st.size():
				var a: Vector2 = st[i][0]
				var hit := _hits(Vector3(a.x, float(st[i][1]) + eye, a.y), tgt[1], tgt[0], occ_all)
				if not hit.is_empty():
					an += 1
					for h in hit:
						ab[h] = int(ab.get(h, 0)) + 1
			if LIMITS[eye].has(tgt[0]):
				var lim := int(LIMITS[eye][tgt[0]])
				_check(tn <= lim, "眼高 %.1f m 望%s：%d 站中 %d 站被擋（上限 %d）：%s" % [eye, tgt[0], st.size(), tn, lim, _fmt(tb)])
			else:
				print("[SL] INFO 眼高 %.1f m 主街望%s（漸進式揭露，不判失敗）：%d 站中 地標擋 %d 站、全建築擋 %d 站（看得到 %d 站）" % [
					eye, tgt[0], st.size(), tn, an, st.size() - an])
			if tgt[0] != "龍神像":
				print("[SL] INFO 眼高 %.1f m 主街望%s 全建築擋 %d 站（看得到 %d 站）：%s" % [eye, tgt[0], an, st.size() - an, _fmt_top(ab, 4)])
		_reveal(space, net, ms, targets[1][1], eye)
	print("[SL] 結果：%d 項失敗" % fails)
	quit(fails)


func _check(ok: bool, msg: String) -> void:
	print("[SL] %s %s" % ["PASS" if ok else "FAIL", msg])
	if not ok:
		fails += 1


func _ground(space: PhysicsDirectSpaceState3D, p: Vector2) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 200.0, p.y), Vector3(p.x, -50.0, p.y))
	var r := space.intersect_ray(q)
	return float(r["position"].y) if not r.is_empty() else 0.0


func _top(v: Node3D, path: String) -> Vector3:
	var n := v.get_node_or_null(path)
	if n == null:
		return Vector3.ZERO
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var ab: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).mesh.get_aabb()
		box = ab if first else box.merge(ab)
		first = false
	return Vector3(box.get_center().x, box.end.y - 0.3, box.get_center().z)


## 龍神像終點接近區：全建築、上限 REVEAL_LIMIT 站
func _reveal(space: PhysicsDirectSpaceState3D, net: Dictionary, ms: PackedVector2Array, dragon: Vector3, eye: float) -> void:
	var n := 0
	var bad := 0
	var who := {}
	var desc: Array = []
	for z in REVEAL_ZONE:
		if not net.has(z[0]):
			_check(false, "接近區道路 %s 不存在" % z[0])
			continue
		var pts := PackedVector2Array()
		for p in net[z[0]]:
			pts.append(Vector2(float(p[0]), float(p[1])))
		var total := 0.0
		for k in pts.size() - 1:
			total += pts[k].distance_to(pts[k + 1])
		var s0 := 0.0 if z[1] == "" else _arc_of(pts, _anchor(net, String(z[1])))
		var s1 := total if z[2] == "" else _arc_of(pts, _anchor(net, String(z[2])))
		var cum := 0.0
		var s := s0
		var zn := 0
		var zb := 0
		var zw := {}
		for k in pts.size() - 1:
			var seg := pts[k].distance_to(pts[k + 1])
			while s <= cum + seg and s <= s1 + 0.001:
				var p := pts[k].lerp(pts[k + 1], (s - cum) / seg)
				var hit := _hits(Vector3(p.x, _ground(space, p) + eye, p.y), dragon, "龍神像", occ_all)
				zn += 1
				if not hit.is_empty():
					zb += 1
					for h in hit:
						zw[h] = int(zw.get(h, 0)) + 1
				s += 4.0
			cum += seg
		if z[3]:
			n += zn
			bad += zb
			for h in zw:
				who[h] = int(who.get(h, 0)) + int(zw[h])
			desc.append("%s %.0f–%.0f m %d 站" % [z[0], s0, s1, zn])
		else:
			print("[SL] INFO 眼高 %.1f m 龍神像揭露段 %s %.0f–%.0f m（全建築，不判失敗）：%d 站中 看得到 %d 站：%s" % [
				eye, z[0], s0, s1, zn, zn - zb, _fmt(zw)])
	_check(n > 20 and bad <= REVEAL_LIMIT, "眼高 %.1f m 龍神像終點接近區（%s，全建築）：%d 站中 %d 站被擋（上限 %d）：%s" % [
		eye, "、".join(desc), n, bad, REVEAL_LIMIT, _fmt(who)])


## "Road:start"／"Road:end" → 該路第一／最後一點
func _anchor(net: Dictionary, a: String) -> Vector2:
	var parts := a.split(":")
	var arr: Array = net[parts[0]]
	var p: Array = arr[0] if parts[1] == "start" else arr[arr.size() - 1]
	return Vector2(float(p[0]), float(p[1]))


## 點 q 投影到折線 pts 的弧長
func _arc_of(pts: PackedVector2Array, q: Vector2) -> float:
	var best := INF
	var arc := 0.0
	var cum := 0.0
	for k in pts.size() - 1:
		var c := Geometry2D.get_closest_point_to_segment(q, pts[k], pts[k + 1])
		if c.distance_to(q) < best:
			best = c.distance_to(q)
			arc = cum + pts[k].distance_to(c)
		cum += pts[k].distance_to(pts[k + 1])
	return arc


## 節點底下可見三角面 → [AABB, faces]；沒有體積回傳 []
func _collect(n: Node) -> Array:
	var faces := PackedVector3Array()
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null or not (mi as MeshInstance3D).visible:
			continue
		var ab: AABB = (mi as MeshInstance3D).global_transform * m.get_aabb()
		if ab.size.y <= 0.3:
			continue
		var mf := m.get_faces()
		if mf.is_empty():
			continue
		var xf: Transform3D = (mi as MeshInstance3D).global_transform
		for p in mf:
			faces.append(xf * p)
		box = ab if first else box.merge(ab)
		first = false
	return [] if faces.is_empty() else [box, faces]


## 回傳擋住線段的 placeholder id（排除目標自己）；list 預設 occ（只算地標等）
func _hits(from: Vector3, to: Vector3, self_name := "", list: Array = []) -> Array:
	var out: Array = []
	for o in (occ if list.is_empty() else list):
		if self_name != "" and ((self_name == "山頂社殿" and o[0] == "LANDMARK_NORTH_HILL")
				or (self_name == "龍神像" and o[0] == "LANDMARK_DRAGON")
				or (self_name == "南大鳥居" and o[0] == "LANDMARK_SOUTH_GATE")):
			continue
		var box: AABB = o[2]
		if not box.grow(0.05).intersects_segment(from, to):
			continue
		var f: PackedVector3Array = o[3]
		for t in range(0, f.size(), 3):
			if Geometry3D.segment_intersects_triangle(from, to, f[t], f[t + 1], f[t + 2]) != null:
				out.append(o[0])
				break
	return out


func _fmt_top(d: Dictionary, k: int) -> String:
	var keys := d.keys()
	keys.sort_custom(func(a, b): return int(d[a]) > int(d[b]))
	var parts: Array = []
	for key in keys.slice(0, k):
		parts.append("%s×%d" % [key, d[key]])
	return "無" if parts.is_empty() else "、".join(parts)


func _fmt(d: Dictionary) -> String:
	if d.is_empty():
		return "無"
	var keys := d.keys()
	keys.sort_custom(func(a, b): return int(d[a]) > int(d[b]))
	var parts: Array = []
	for key in keys:
		parts.append("%s×%d" % [key, d[key]])
	return "、".join(parts)
