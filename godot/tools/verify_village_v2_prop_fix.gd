extends SceneTree
## P10 R4c Prop Fix Pilot gate（回歸 tag R4C）。使用者 2026-10-09 D9：st_hasa LIMITED REPAIR（竹竿×稲束穿插）；封存只在 ART_APPROVED 後重封。
##   轉檔（headless）：Godot --headless --path . --script res://tools/verify_village_v2_prop_fix.gd -- --convert  → maps/village_v2/gen/r4c/*.res
##     （先 blender -b --factory-startup --python godot/assets/blender/village_v2/build_hasa_v2.py，再 godot --headless --import 匯入 glb）
##   plan＋反向（headless）：… （無參數）
##   build：… -- --build        attach：… -- --attach（ShrineApproachP10 之後）        scene（非 headless）：… -- --scene
## plan（讀 src/hasa_v2_spec.json＝Blender 端每個基本體的參數）：
##   1 竿×半束 淨距 ≥ 0.010 m（0 穿插）；束頭（跨竿の結び）坐在竿上：淨距 −0.001～0.010（接觸、不穿）
##   2 稲束×稲束（不同束）淨距 ≥ 0.005 m（上段穗端不碰下段束頭）
##   3 脚×稲束 淨距 ≥ 0.010 m
##   4 網格＝規格：轉出的 mesh AABB 與 Blender manifest dims 差 ≤ 0.01 m；外形與 st_hasa 相同尺度（AABB 差 ≤ 0.12 m）→ 原擺放直接換
const SCENE := "res://maps/village_v2/village_v2.tscn"
const KIT := "res://assets/village_v2/r4c_kit"
const GLB := KIT + "/src/r4c_kit.glb"
const SPEC := KIT + "/src/hasa_v2_spec.json"
const MANIFEST := KIT + "/src/modules_blender.json"
const MESH_DIR := "res://maps/village_v2/gen/r4c"   # 轉出的 mesh 放 village_v2 允許前綴下（P5 asset reset 白名單）
const OLD := {"res://assets/village_v2/street_kit/mesh/st_hasa.res": MESH_DIR + "/st_hasa_v2.res", "res://assets/village_v2/street_kit/mesh/st_hasa_l1.res": MESH_DIR + "/st_hasa_v2_l1.res"}
const MATS := {"V2_Wood": "res://assets/village_v2/_matlib/V2_Wood.tres", "ST_Street": "res://assets/village_v2/street_kit/ST_Street.tres"}
const NODE_NAME := "PropFixP10"
const OUTPUT := "res://maps/village_v2/gen/prop_fix_p10.scn"
const SCRIPT := "res://maps/village_v2/scripts_p10/prop_fix.gd"
const EXT_ID := "p10r4c_prop_fix"
const AFTER_NODE := "[node name=\"ShrineApproachP10\" parent=\".\" instance=ExtResource(\"p10r6b_shrine_approach\")]"
const ART_REVISION := "P10 R4c prop fix pilot r1b（A2 籠の接地修正：地面＝TerrainCollision；r1 は籠自身の碰撞に當たり 1.0 m 沈んでいた）：st_hasa → st_hasa_v2（稲束跨竿、非貫通、束列避脚）＋A2 背負い籠を千歯扱きの視線外へ 1.0 m（ART_REVIEW）"
## A2（R4 Pilot A 脫穀作業床）：背負い籠が TPS 視線（農道側）で千歯扱きの前を塞ぐ → 籠だけ東へ 1.0 m（件數・他の件は不動）
const A2_BASKET := "HumanUseP10/PilotA/A2_dakkoku/006_hu_seoikago"
const A2_SENBA := "HumanUseP10/PilotA/A2_dakkoku/005_hu_senba"
const A2_SHIFT := Vector2(1.0, 0.0)
const A2_VIEW := Vector2(346.0, 1.0)   # MASTER AUDIT r4c_dakkoku_A2 機位（農道側）
const RS := preload("res://tools/village_v2_rehab_seal.gd")
const SEAL := "res://data/village_v2_p10r4c_seal.json"   # 使用者 2026-10-09 ROUND 3 FINAL：R4c Straw Geometry Pilot＝ART_APPROVED
var fails := 0
var quiet := false


func _ok(c: bool, msg: String) -> bool:
	if not quiet:
		print("[R4C] ", "PASS " if c else "FAIL ", msg)
	if not c:
		fails += 1
	return c


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if RS.refuse_write(args, SEAL, "R4C_ALLOW_REBAKE", "R4C"):
		quit(1)
		return
	if "--seal" in args:
		quit(await RS.new().run(self, SEAL, "R4C", NODE_NAME, _seal_extra))
		return
	if "--attach" in args:
		quit(_attach())
		return
	if "--convert" in args:
		_convert()
		quit(fails)
		return
	if "--scene" in args:
		var v: Node3D = (load(SCENE) as PackedScene).instantiate()
		root.add_child(v)
		await process_frame
		await _scene(v)
		print("[R4C] 結果：%d 項失敗" % fails)
		quit(fails)
		return
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	var m0: Dictionary = spec["modules"]["st_hasa_v2"]
	_gates(m0, float(spec["clear"]))
	_mesh_gate()
	await _a2_gate(A2_SHIFT)
	if not "--build" in args:
		quiet = true
		var f0 := fails
		await _a2_gate(Vector2.ZERO)
		var tripped := fails > f0
		fails = f0
		quiet = false
		print("[R4C]   N4 籠不動（仍擋千歯扱き）：%s" % ("PASS（gate 正確失敗）" if tripped else "FAIL（gate 沒抓到）"))
		if not tripped:
			fails += 1
		quiet = true
		var f1 := fails
		await _a2_gate(A2_SHIFT, -1.0)
		var tripped5 := fails > f1
		fails = f1
		quiet = false
		print("[R4C]   N5 籠が地面に 1.0 m 沈む（r1 の不具合）：%s" % ("PASS（gate 正確失敗）" if tripped5 else "FAIL（gate 沒抓到）"))
		if not tripped5:
			fails += 1
	if "--build" in args:
		_build()
	else:
		_negatives(m0, float(spec["clear"]))
	print("[R4C] 結果：%d 項失敗" % fails)
	quit(fails)


static func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## 線段 p0p1 與 q0q1 最近點參數（s,t）
static func _closest(p0: Vector3, p1: Vector3, q0: Vector3, q1: Vector3) -> Vector2:
	var d1 := p1 - p0
	var d2 := q1 - q0
	var r := p0 - q0
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-9 and e <= 1e-9:
		return Vector2.ZERO
	if a <= 1e-9:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-9:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var den := a * e - b * b
			s = clampf((b * f - c * e) / den, 0.0, 1.0) if den > 1e-9 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return Vector2(s, t)


## 兩個（截錐）圓柱的表面淨距（沿最近點；半徑線性內插；保守）
static func _gap(a0: Vector3, a1: Vector3, ra0: float, ra1: float, b0: Vector3, b1: Vector3, rb0: float, rb1: float) -> float:
	var st := _closest(a0, a1, b0, b1)
	var pa := a0.lerp(a1, st.x)
	var pb := b0.lerp(b1, st.y)
	return pa.distance_to(pb) - lerpf(ra0, ra1, st.x) - lerpf(rb0, rb1, st.y)


func _parts(m: Dictionary) -> Array:
	# [kind, sheaf_id, a, b, r0, r1]
	var out := []
	for p: Dictionary in m["poles"]:
		out.append(["pole", -1, _v(p["a"]), _v(p["b"]), float(p["r"]), float(p["r"]) * 0.9])
	for l: Dictionary in m["legs"]:
		out.append(["leg", -1, _v(l["a"]), _v(l["b"]), float(l["w"]) * 0.7071, float(l["w"]) * 0.7071])
	var i := 0
	for s: Dictionary in m["sheaves"]:
		var t: Dictionary = s["tie"]
		out.append(["tie", i, _v(t["a"]), _v(t["b"]), float(t["r"]), float(t["r"])])
		for h: Dictionary in s["halves"]:
			out.append(["half", i, _v(h["a"]), _v(h["b"]), float(h["r0"]), float(h["r1"])])
		i += 1
	return out


func _gates(m: Dictionary, clear: float) -> void:
	var P := _parts(m)
	var pole_min := INF
	var tie_min := INF
	var sheaf_min := INF
	var leg_min := INF
	for i in P.size():
		for j in range(i + 1, P.size()):
			var a: Array = P[i]
			var b: Array = P[j]
			var ka := String(a[0])
			var kb := String(b[0])
			var straw_a := ka == "tie" or ka == "half"
			var straw_b := kb == "tie" or kb == "half"
			if not straw_a and not straw_b:
				continue   # 竿×脚＝結構接合（設計），不量
			var g := _gap(a[2], a[3], a[4], a[5], b[2], b[3], b[4], b[5])
			if (ka == "pole" and kb == "tie") or (kb == "pole" and ka == "tie"):
				tie_min = minf(tie_min, g)
			elif (ka == "pole" and straw_b) or (kb == "pole" and straw_a):
				pole_min = minf(pole_min, g)
			elif straw_a and straw_b:
				if int(a[1]) != int(b[1]):
					sheaf_min = minf(sheaf_min, g)
			elif (ka == "leg" and straw_b) or (kb == "leg" and straw_a):
				leg_min = minf(leg_min, g)
	_ok(pole_min >= clear - 0.002, "竿×半束 最小淨距 %.3f m（≥ %.3f，0 穿插）" % [pole_min, clear - 0.002])
	_ok(tie_min >= -0.001 and tie_min <= 0.01, "束頭（結び）坐在竿上：竿×束頭 %.3f m（−0.001～0.010＝接觸、不穿）" % tie_min)
	_ok(sheaf_min >= 0.005, "稲束×稲束（不同束）最小淨距 %.3f m（≥ 0.005）" % sheaf_min)
	_ok(leg_min >= 0.010, "脚×稲束 最小淨距 %.3f m（≥ 0.010）" % leg_min)


func _mesh_gate() -> void:
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var old_man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/village_v2/street_kit/src/modules_blender.json"))
	var bad := []
	for nm in ["st_hasa_v2", "st_hasa_v2_l1"]:
		var path := MESH_DIR + "/%s.res" % nm
		var m := load(path) as ArrayMesh if FileAccess.file_exists(path) else null
		if m == null:
			bad.append("%s 不存在（先 --convert）" % nm)
			continue
		var ab := m.get_aabb()
		var d: Array = man["modules"][nm]["dims"]
		var e := maxf(ab.position.distance_to(Vector3(d[0], d[1], d[2])), ab.end.distance_to(Vector3(d[3], d[4], d[5])))
		var od: Array = old_man["modules"][nm.replace("_v2", "")]["dims"]
		var e2 := maxf(ab.position.distance_to(Vector3(od[0], od[1], od[2])), ab.end.distance_to(Vector3(od[3], od[4], od[5])))
		for si in m.get_surface_count():
			var mt := m.surface_get_material(si)
			if mt == null or not (mt.resource_path in MATS.values()):
				bad.append("%s 面 %d 材質 %s" % [nm, si, mt.resource_path if mt else "null"])
		if e > 0.01:
			bad.append("%s AABB≠manifest（%.3f）" % [nm, e])
		if e2 > 0.12:
			bad.append("%s 外形與 st_hasa 差 %.3f m" % [nm, e2])
	_ok(bad.is_empty(), "網格＝規格（AABB＝manifest、材質＝V2_Wood／ST_Street、外形與 st_hasa 同尺度）%s" % ("" if bad.is_empty() else " ✗ " + str(bad)))


func _negatives(m: Dictionary, clear: float) -> void:
	print("[R4C] 永久反向（每案必須讓 gate 失敗）")
	var cases := []
	# N1 舊 st_hasa 的稲束（頂端 z ±0.03、r 0.06→0.085、長 0.48）＝竿穿稲束
	var m1 := m.duplicate(true)
	for s: Dictionary in m1["sheaves"]:
		for h: Dictionary in s["halves"]:
			var a: Array = h["a"]
			var sgn := signf(float(a[2]))
			h["a"] = [a[0], float(a[1]) - 0.01, sgn * 0.03]
			h["r0"] = 0.06
			h["r1"] = 0.085
	cases.append(["N1 舊 st_hasa 稲束（竿穿稲束）", m1])
	# N2 上段束長 0.60（穗端碰下段）
	var m2 := m.duplicate(true)
	for s: Dictionary in m2["sheaves"]:
		for h: Dictionary in s["halves"]:
			if float(h["a"][1]) > 1.5:
				h["b"] = [h["b"][0], float(h["a"][1]) - 0.60, h["b"][2]]
	cases.append(["N2 上段束長 0.60（穗端壓下段束頭）", m2])
	# N3 一束掛在脚上（x＝0）
	var m3 := m.duplicate(true)
	var s0: Dictionary = (m3["sheaves"] as Array)[0]
	var dx := 0.0 - float(s0["tie"]["a"][0])
	for key in ["a", "b"]:
		s0["tie"][key] = [float(s0["tie"][key][0]) + dx, s0["tie"][key][1], s0["tie"][key][2]]
	for h: Dictionary in s0["halves"]:
		for key in ["a", "b"]:
			h[key] = [float(h[key][0]) + dx, h[key][1], h[key][2]]
	cases.append(["N3 稲束掛在 X 脚上", m3])
	var neg_fail := 0
	for c in cases:
		var f0 := fails
		quiet = true
		_gates(c[1], clear)
		quiet = false
		var tripped := fails > f0
		fails = f0
		print("[R4C]   %s：%s" % [c[0], "PASS（gate 正確失敗）" if tripped else "FAIL（gate 沒抓到）"])
		if not tripped:
			neg_fail += 1
	_ok(neg_fail == 0, "反向 %d/%d" % [cases.size() - neg_fail, cases.size()])


func _convert() -> void:
	var ps := load(GLB) as PackedScene
	if not _ok(ps != null, "載入 %s（需先 godot --headless --import）" % GLB):
		return
	var s := ps.instantiate()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MESH_DIR))
	for nm in ["st_hasa_v2", "st_hasa_v2_l1"]:
		var mi := s.find_child(nm, true, false) as MeshInstance3D
		if mi == null:
			for c in s.find_children("*", "MeshInstance3D", true, false):
				if String(c.name).begins_with(nm) and (nm.ends_with("_l1") == String(c.name).contains("_l1")):
					mi = c
		if not _ok(mi != null and mi.mesh != null, "glb 內找到 %s" % nm):
			continue
		var src := mi.mesh
		var am := ArrayMesh.new()
		for si in src.get_surface_count():
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(si))
			var sm := src.surface_get_material(si)
			var key := String(sm.resource_name) if sm else ""
			var mp := ""
			for k in MATS:
				if key.begins_with(k):
					mp = MATS[k]
			_ok(mp != "", "%s 面 %d 材質名 %s → %s" % [nm, si, key, mp])
			if mp != "":
				am.surface_set_material(si, load(mp))
		am.resource_name = "r4c_" + nm
		_ok(ResourceSaver.save(am, MESH_DIR + "/%s.res" % nm) == OK, "存 %s/%s.res（AABB %s）" % [MESH_DIR, nm, am.get_aabb()])
	s.free()


var a2_moves := {}


## A2：籠の新位置（地面＝射線）＋視線（農道機位→千歯）が籠に遮られないこと＋籠が他の碰撞体に入らないこと
func _a2_gate(shift: Vector2, sink := 0.0) -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	await process_frame
	var pf := v.get_node_or_null(NODE_NAME)
	if pf:
		pf.set("enabled", false)   # 讀 R4 封存的原位置（overlay 已掛時先還原）
	await physics_frame
	await physics_frame
	var b := v.get_node_or_null(A2_BASKET) as Node3D
	var sn := v.get_node_or_null(A2_SENBA) as Node3D
	if not _ok(b != null and sn != null, "A2 籠／千歯扱き節點存在"):
		v.free()
		return
	var np := Vector2(b.global_position.x, b.global_position.z) + shift
	var sp := v.get_world_3d().direct_space_state
	var ex: Array[RID] = []
	for co in b.find_children("*", "CollisionObject3D", true, false):
		ex.append((co as CollisionObject3D).get_rid())
	if b is CollisionObject3D:
		ex.append((b as CollisionObject3D).get_rid())
	# 地面＝P1 TerrainCollision だけ（籠自身や周りの道具の碰撞に当たると、その高さぶん沈む／浮く——r1 で 1.0 m 沈んだ原因）
	var g_old := _ground_at(sp, Vector2(b.global_position.x, b.global_position.z), ex)
	var gy := _ground_at(sp, np, ex)
	var off0 := b.global_position.y - g_old          # 封存の原位置：地面からの高さ（≈ 0 のはず）
	var y := gy + off0 + sink if not is_nan(gy) else NAN
	# 視線：農道機位（眼高 1.6）→ 千歯扱き中心（0.6）；籠（半徑 0.35）中心到線段距離
	var s2 := Vector2(sn.global_position.x, sn.global_position.z)
	var ab := s2 - A2_VIEW
	var t := clampf((np - A2_VIEW).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var dlos := np.distance_to(A2_VIEW + ab * t)
	var t0 := clampf((Vector2(b.global_position.x, b.global_position.z) - A2_VIEW).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var dlos0 := Vector2(b.global_position.x, b.global_position.z).distance_to(A2_VIEW + ab * t0)
	# 碰撞：籠 0.7 × 0.6 × 0.7 盒（地面上 0.05 起）
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.7, 0.6, 0.7)
	var qs := PhysicsShapeQueryParameters3D.new()
	qs.shape = bs
	qs.transform = Transform3D(Basis(), Vector3(np.x, y + 0.35, np.y))
	qs.exclude = ex
	var hits := []
	for r in sp.intersect_shape(qs, 8):
		var nm := String(v.get_path_to(r["collider"])) if V_is(v, r["collider"]) else str(r["collider"])
		if not nm.contains("TerrainCollision"):
			hits.append(nm)
	var grounded := not is_nan(y) and absf(off0) <= 0.15 and absf(y - gy) <= 0.15
	_ok(grounded and dlos >= 0.45 and hits.is_empty(), "A2 背負い籠 東へ %.1f m：視線（農道→千歯）距籠 %.2f m（原 %.2f）≥ 0.45、接地 新 %+.3f m（原 %+.3f；|·| ≤ 0.15、地面＝TerrainCollision）、碰撞 %s" % [shift.length(), dlos, dlos0, y - gy, off0, str(hits) if not hits.is_empty() else "0"])
	if not quiet:
		a2_moves = {A2_BASKET: Vector3(np.x, y, np.y)}
	v.free()


static func V_is(v: Node, o) -> bool:
	return o is Node and v.is_ancestor_of(o)


func _ground_at(sp: PhysicsDirectSpaceState3D, p: Vector2, ex: Array[RID]) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 20.0, p.y), Vector3(p.x, -10.0, p.y))
	var ex2: Array[RID] = ex.duplicate()
	for t in 24:
		q.exclude = ex2
		var h := sp.intersect_ray(q)
		if h.is_empty():
			return NAN
		if String((h["collider"] as Node).name).begins_with("TerrainCollision"):
			return float(h["position"].y)
		ex2.append(h["rid"])
	return NAN


func _build() -> void:
	if fails > 0:
		_ok(false, "plan gate 未過，不 build")
		return
	var n := Node3D.new()
	n.name = NODE_NAME
	n.set_script(load(SCRIPT))
	var sw := {}
	for k in OLD:
		sw[k] = load(OLD[k])
	n.set("swaps", sw)
	n.set("moves", a2_moves)
	n.set_meta("art_revision", ART_REVISION)
	n.set_meta("phase", "P10 R4c pilot")
	var ps := PackedScene.new()
	_ok(ps.pack(n) == OK, "pack")
	_ok(ResourceSaver.save(ps, OUTPUT) == OK, "save %s" % OUTPUT)
	n.free()
	print("[R4C] build {\"output_sha256\":\"%s\"}" % FileAccess.get_sha256(OUTPUT))


func _scene(v: Node3D) -> void:
	var nodes := v.find_children(NODE_NAME, "", false, false)
	_ok(nodes.size() == 1, "root/%s 掛載 1 個（實得 %d）" % [NODE_NAME, nodes.size()])
	if nodes.is_empty():
		return
	var n := nodes[0] as Node3D
	var sa := v.get_node_or_null("ShrineApproachP10")
	_ok(sa != null and sa.get_index() == n.get_index() - 1, "順序：ShrineApproachP10 之後（index %d）" % n.get_index())
	for i in 4:
		await process_frame
	var left := 0
	var newc := 0
	var owners := {}
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		if OLD.has(m.resource_path):
			left += 1
		if m.resource_path in OLD.values():
			newc += 1
			var p := String(v.get_path_to(mi))
			owners[p.split("/")[0] + "/" + (p.split("/")[1] if p.split("/").size() > 1 else "")] = true
	_ok(left == 0 and newc == int(n.get("swapped")) and newc > 0, "st_hasa → v2：換 %d 個 MeshInstance（殘留舊 mesh %d）、所在 %s" % [newc, left, str(owners.keys())])
	_ok(int(n.get("moved")) == 1, "A2 背負い籠 移位 %d 件（只動這一件）" % int(n.get("moved")))
	var bk := v.get_node_or_null(A2_BASKET) as Node3D
	var exb: Array[RID] = []
	if bk:
		for co in bk.find_children("*", "CollisionObject3D", true, false):
			exb.append((co as CollisionObject3D).get_rid())
	var gyb := _ground_at(v.get_world_3d().direct_space_state, Vector2(bk.global_position.x, bk.global_position.z), exb) if bk else NAN
	_ok(bk != null and not is_nan(gyb) and absf(bk.global_position.y - gyb) <= 0.15, "A2 背負い籠（移位後）接地：底 %+.3f m（地面＝TerrainCollision、|·| ≤ 0.15）" % ((bk.global_position.y - gyb) if bk and not is_nan(gyb) else NAN))
	n.set("enabled", false)
	var back := 0
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m and OLD.has(m.resource_path):
			back += 1
	_ok(back == newc, "enabled=false → 還原 %d 個" % back)
	_ok(int(n.get("moved")) == 0, "enabled=false → A2 籠回原位")
	n.set("enabled", true)


func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(OUTPUT):
		push_error("找不到 %s（先 --build）" % OUTPUT)
		return 1
	var line := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]" % [NODE_NAME, EXT_ID]
	if txt.contains(line):
		print("[R4C] attach：已掛（不重複、不寫場景）")
		return 0
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	var out := PackedStringArray(Array(lines))
	var at := out.find(AFTER_NODE)
	if at < 0:
		push_error("找不到 root/ShrineApproachP10")
		return 1
	if at + 1 < out.size() and out[at + 1].strip_edges() != "":
		push_error("ShrineApproachP10 節點後面不是空行，拒絕文字插入")
		return 1
	out.insert(at + 1, "")
	out.insert(at + 2, line)
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%s\"]" % [OUTPUT, EXT_ID])
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[R4C] attach：加 root/%s（ShrineApproachP10 之後）→ %s（+%d 行）" % [NODE_NAME, SCENE, out.size() - lines.size()])
	return 0


## --seal 固有：st_hasa → st_hasa_v2 の差し替え 18（StreetP10・HumanUseP10/PilotA・HumanUseExpansionP10/ZoneA）、A2 背負い籠の移位 1 件だけ、
## 籠の接地（地面＝TerrainCollision）。R4 snapshot（limited reseal 後）の A2＝この移位後の位置。
func _seal_extra(v: Node3D) -> Array:
	var n := v.get_node(NODE_NAME)
	var left := 0
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m and OLD.has(m.resource_path):
			left += 1
	var b := v.get_node(A2_BASKET) as Node3D
	var snap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/village_v2_p10r4_snapshot.json"))
	var want := Vector3.ZERO
	for it: Dictionary in snap["items"]:
		if "HumanUseP10/" + String(it["node"]) == A2_BASKET:
			want = Vector3(it["position"][0], it["position"][1], it["position"][2])
	return [[int(n.get("swapped")) == 18 and left == 0, "st_hasa → st_hasa_v2：%d 個（舊 mesh 殘り %d）" % [int(n.get("swapped")), left]],
		[int(n.get("moved")) == 1, "A2 背負い籠の移位 %d 件だけ" % int(n.get("moved"))],
		[b.global_position.distance_to(want) <= 0.01, "A2 籠の位置＝R4 snapshot（limited reseal 後）%s（差 %.3f m）" % [str(want), b.global_position.distance_to(want)]]]
