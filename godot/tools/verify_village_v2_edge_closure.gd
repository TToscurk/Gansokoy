extends SceneTree
## P10 R5c World Boundary Closure：EdgeClosureP10 的 plan gate／build／attach／scene gate（tag EDGE）。
##   plan gate（headless 可）：Godot --headless --path . --script res://tools/verify_village_v2_edge_closure.gd
##   build（必須非 headless：MultiMesh）：Godot --path . --script res://tools/verify_village_v2_edge_closure.gd -- --build
##   attach（root、HumanUseExpansionP10 之後；文字插入 3 行）：… -- --attach
##   scene gate（非 headless：MultiMesh 回讀）：… -- --scene
## plan gate：
##   1 接縫：frame 邊上每個 2 m 頂點的 vista 高度＝P1 地形（獨立射線重量 ≤ 0.01 m），且 P1 邊緣頂點權重全部取到
##   2 frame 外：vista 頂點不得在 frame 內
##   3 視線閉合：邊緣帶（每 8 m、眼高 1.7／相機 3.0 m、朝外 ±75°、俯角 0–8°）＋村內高點 360°＋街道軸線，射線跑出格外仍在地形上方＝看到世界盡頭 → 必須 0
##   4 水系：各延續段水位依流向單調、起點在 frame 邊且與 P2 水面同高（≤ 0.06 m）、支流匯入處高於本流（≥ 0.1 m）、南の川與主河會合處水位差 ≤ 0.3 m
##   5 樹：數量 1500–3600、不在 frame 內、不在水道（半寬 + 2 m）與小徑上、離 frame ≥ 4.5 m
##   6 預算：地形三角 ≤ 140k、林冠 ≤ 90k、水面 ≤ 12k
## 永久反向（只改記憶體）：rim（山脊壓到 2 m → 3 必 FAIL）、seam（一個接縫頂點 +0.3 m → 1 必 FAIL）、
##   tree（樹放進河心 → 5 必 FAIL）、water（RiverEast 改成往外升高 → 4 必 FAIL）。結果不符 → 退出碼 > 0。
## 每項印一行 [EDGE] PASS/FAIL；結尾 quit(失敗項數)。

const EL := preload("res://tools/village_v2_edge_closure_lib.gd")
const MMG := preload("res://tools/village_v2_mm_bake_guard.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const AFTER_NODE := "[node name=\"HumanUseExpansionP10\" parent=\".\" instance=ExtResource(\"p10r4b_human_use_exp\")]"
const EXT_ID := "p10r5c_edge_closure"
const RS := preload("res://tools/village_v2_rehab_seal.gd")
const SEAL := "res://data/village_v2_p10r5c_seal.json"   # 使用者 2026-10-09 ROUND 3 FINAL：R5c Boundary Closure＝ART_APPROVED

var fails := 0
var quiet := false

func _init() -> void:
	_run.call_deferred()

func check(name: String, ok: bool) -> bool:
	if not quiet:
		print("[EDGE] %s %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		fails += 1
	return ok

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if RS.refuse_write(args, SEAL, "EDGE_ALLOW_REBAKE", "EDGE"):
		quit(1)
		return
	if "--seal" in args:
		quit(await RS.new().run(self, SEAL, "EDGE", "EdgeClosureP10", _seal_extra))
		return
	if "--attach" in args:
		quit(_attach())
		return
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 3:
		await physics_frame
	if "--scene" in args:
		_scene(v)
		quit(fails)
		return
	print("[EDGE] plan …")
	var P := EL.plan(v)
	print("[EDGE] plan %s" % JSON.stringify(P["stats"]))
	if "--build" in args:
		if not MMG.display_ok():
			check("--build 必須在有 display 的行程（MultiMesh build rule）", false)
			quit(1)
			return
		_gates(v, P)
		if fails > 0:
			print("[EDGE] plan gate 有 FAIL，不寫檔")
			quit(fails)
			return
		var node := EL.build(v, P)
		EL.own(node, node)
		var ps := PackedScene.new()
		var err := ps.pack(node)
		check("pack", err == OK)
		err = ResourceSaver.save(ps, EL.OUTPUT)
		check("save %s" % EL.OUTPUT, err == OK)
		var au := MMG.audit_saved_scene(EL.OUTPUT)
		check("MultiMesh 回讀：%s" % MMG.summary(au), MMG.ok(au))
		var st: Dictionary = P["stats"]
		st["terrain_tris"] = int((node.get_node("VistaTerrain") as MeshInstance3D).mesh.get_meta("triangles", 0))
		st["canopy_tris"] = int((node.get_node("VistaCanopy") as MeshInstance3D).mesh.get_meta("triangles", 0))
		st["water_tris"] = int((node.get_node("VistaWater") as MeshInstance3D).mesh.get_meta("triangles", 0))
		st["tree_mmi"] = int(node.get_node("VistaTrees").get_meta("multimesh_nodes", 0))
		st["output_sha256"] = FileAccess.get_sha256(EL.OUTPUT)
		var f := FileAccess.open(EL.PLAN_JSON, FileAccess.WRITE)
		f.store_string(JSON.stringify({"stats": st, "art_revision": EL.ART_REVISION, "sides": EL.SIDES, "waters": EL.WATERS, "paths": EL.PATHS}, "\t"))
		f.close()
		print("[EDGE] build %s" % JSON.stringify(st))
		node.free()
		quit(fails)
		return
	_gates(v, P)
	if "--quick" in args:
		quit(fails)
		return
	# 永久反向
	quiet = true
	var bad := 0
	var f0 := fails
	# rim
	var Pr := EL.plan(v, {"rim_N": 2.0, "rim_W": 2.0, "rim_E": 2.0, "rim_S": 2.0, "mid_N": 2.0, "mid_W": 2.0, "mid_E": 2.0, "mid_S": 2.0})
	var r_rim := _closure(v, Pr)
	quiet = false
	if not check("反向 rim：山脊壓低 → 視線閉合 FAIL（escape %d）" % r_rim, r_rim > 0):
		bad += 1
	quiet = true
	# seam
	var xs: PackedFloat32Array = P["xs"]
	var zs: PackedFloat32Array = P["zs"]
	var n := xs.size()
	var ji := zs.find(EL.FZ1)
	var ii := xs.find(300.0)
	var H: PackedFloat32Array = P["h"]
	H[ji * n + ii] += 0.3
	var s_bad := _seam(v, P)
	H[ji * n + ii] -= 0.3
	quiet = false
	if not check("反向 seam：接縫頂點 +0.3 m → 接縫 FAIL（%d）" % s_bad, s_bad > 0):
		bad += 1
	quiet = true
	# tree
	var trees: Array = P["trees"]
	trees.append({"id": "konara_a", "p": Vector2(600.0, -108.0), "y": -0.8, "yaw": 0.0, "sc": 1.0, "lean": 0.0, "lean_dir": 0.0, "layer": "vista", "preset": "mature", "d": 40.0})
	var t_bad := _trees_bad(P)
	trees.pop_back()
	quiet = false
	if not check("反向 tree：河心放樹 → 樹 FAIL（%d）" % t_bad, t_bad > 0):
		bad += 1
	quiet = true
	# water
	var w_bad := _water_bad(v, P, {"RiverEast": [-0.8, 1.0]})
	quiet = false
	if not check("反向 water：RiverEast 往外升高 → 水系 FAIL（%d）" % w_bad, w_bad > 0):
		bad += 1
	fails = f0 + bad
	print("[EDGE] 結果：%d 項失敗" % fails)
	quit(fails)

# ─────────── gates ───────────
func _gates(v: Node3D, P: Dictionary) -> void:
	var E: Dictionary = P["edges"]
	check("P1 邊緣頂點權重取到 %d 個（四邊 ≥ 1120）" % int(E["vtx_found"]), int(E["vtx_found"]) >= 1120)
	var sb := _seam(v, P)
	check("接縫：frame 邊上 vista 高度＝P1 地形（偏差 > 0.01 m 的頂點 %d）" % sb, sb == 0)
	var info: Array = P["info"]
	var xs: PackedFloat32Array = P["xs"]
	var zs: PackedFloat32Array = P["zs"]
	var n := xs.size()
	var bad_in := 0
	var nv := 0
	for j in zs.size():
		for i in n:
			if info[j * n + i] == null:
				continue
			nv += 1
			if EL.inside(Vector2(xs[i], zs[j])):
				bad_in += 1
	check("frame 外：vista 頂點 %d、在 frame 內 %d" % [nv, bad_in], bad_in == 0 and nv > 1000)
	var esc := _closure(v, P)
	check("視線閉合：看見世界盡頭的射線 %d（必須 0）" % esc, esc == 0)
	var wb := _water_bad(v, P, {})
	check("水系延續：水位／接口／匯流 不合理 %d" % wb, wb == 0)
	var tb := _trees_bad(P)
	check("樹：%d 棵、違規 %d" % [(P["trees"] as Array).size(), tb], tb == 0 and (P["trees"] as Array).size() >= 1500)
	var tris := _tri_estimate(P)
	check("預算：地形約 %d 三角（≤ 140k）" % tris, tris <= 140000)

func _tri_estimate(P: Dictionary) -> int:
	var xs: PackedFloat32Array = P["xs"]
	var zs: PackedFloat32Array = P["zs"]
	var c := 0
	for j in zs.size() - 1:
		for i in xs.size() - 1:
			if not EL.inside(Vector2((xs[i] + xs[i + 1]) * 0.5, (zs[j] + zs[j + 1]) * 0.5)):
				c += 2
	return c

func _seam(v: Node3D, P: Dictionary) -> int:
	var E: Dictionary = P["edges"]
	var hfn: Callable = E["hfn"]
	var xs: PackedFloat32Array = P["xs"]
	var zs: PackedFloat32Array = P["zs"]
	var n := xs.size()
	var H: PackedFloat32Array = P["h"]
	var bad := 0
	for j in zs.size():
		for i in n:
			var p := Vector2(xs[i], zs[j])
			var onb := (absf(p.x - EL.FX0) < 1e-3 or absf(p.x - EL.FX1) < 1e-3) and p.y >= EL.FZ0 - 1e-3 and p.y <= EL.FZ1 + 1e-3
			onb = onb or ((absf(p.y - EL.FZ0) < 1e-3 or absf(p.y - EL.FZ1) < 1e-3) and p.x >= EL.FX0 - 1e-3 and p.x <= EL.FX1 + 1e-3)
			if not onb:
				continue
			var inw := Vector2(clampf(250.0 - p.x, -1, 1), clampf(-60.0 - p.y, -1, 1)).normalized() * 0.01
			var y: float = hfn.call(p.x + inw.x, p.y + inw.y)
			if is_nan(y) or absf(y - H[j * n + i]) > 0.01:
				bad += 1
	return bad

func _closure(v: Node3D, P: Dictionary) -> int:
	var E: Dictionary = P["edges"]
	var hfn: Callable = E["hfn"]
	var esc := 0
	var rays := 0
	var samples := []
	# 邊緣帶
	for side in ["N", "S", "W", "E"]:
		var len_s := 560.0
		var s := 4.0
		while s < len_s - 2.0:
			var p: Vector2
			var outn: Vector2
			match side:
				"N":
					p = Vector2(s, EL.FZ0 + 1.5)
					outn = Vector2(0, -1)
				"S":
					p = Vector2(s, EL.FZ1 - 1.5)
					outn = Vector2(0, 1)
				"W":
					p = Vector2(EL.FX0 + 1.5, EL.FZ0 + s)
					outn = Vector2(-1, 0)
				_:
					p = Vector2(EL.FX1 - 1.5, EL.FZ0 + s)
					outn = Vector2(1, 0)
			samples.append([p, outn, 75.0, 15.0, [-8.0, -4.0, -1.5, 0.0], [1.7, 3.0]])
			s += 8.0
	# 村內高點與街道軸線（360°／指定方向）
	for hp in [[Vector2(258, -228), 5.0], [Vector2(240, -250), 3.0], [Vector2(40, -300), 2.0], [Vector2(150, -320), 2.0],
			[Vector2(20, 120), 2.0], [Vector2(530, -300), 2.0], [Vector2(289.6, -166), 2.0], [Vector2(400, -280), 2.0]]:
		samples.append([hp[0], Vector2(1, 0), 180.0, 10.0, [-6.0, -3.0, 0.0], [1.7 + float(hp[1])]])
	for ax in [[Vector2(170, 50), Vector2(1, -0.03)], [Vector2(229, 132), Vector2(-0.1, 1)], [Vector2(372, 40), Vector2(1, 0)],
			[Vector2(440, 0), Vector2(1, 0)], [Vector2(380, -36), Vector2(1, -0.05)], [Vector2(300, -130), Vector2(1, 0.1)]]:
		samples.append([ax[0], (ax[1] as Vector2).normalized(), 20.0, 5.0, [-3.0, -1.0, 0.0], [1.7, 3.0]])
	for smp in samples:
		var p: Vector2 = smp[0]
		var g: float = hfn.call(p.x, p.y)
		if is_nan(g):
			continue
		var outn: Vector2 = smp[1]
		var half: float = smp[2]
		var stp: float = smp[3]
		for eh in smp[5]:
			var eye := Vector3(p.x, g + float(eh), p.y)
			var a := -half
			while a <= half + 0.01:
				var dv := outn.rotated(deg_to_rad(a))
				for pd in smp[4]:
					var pr := deg_to_rad(float(pd))
					var dir := Vector3(dv.x * cos(pr), sin(pr), dv.y * cos(pr))
					rays += 1
					if not EL.ray_closed(P, eye, dir):
						esc += 1
				a += stp
	if not quiet:
		print("[EDGE] 視線閉合射線 %d 條、視點 %d" % [rays, samples.size()])
	return esc

func _water_bad(v: Node3D, P: Dictionary, override: Dictionary) -> int:
	var bad := 0
	var C: Dictionary = P["ctx"]
	var by := {}
	for W: Dictionary in C["waters"]:
		by[String(W["def"]["name"])] = W
	var lvl := func(name: String, s: float) -> float:
		var W: Dictionary = by[name]
		if override.has(name):
			var tot: float = (W["cum"] as PackedFloat32Array)[(W["cum"] as PackedFloat32Array).size() - 1]
			var o: Array = override[name]
			return lerpf(float(o[0]), float(o[1]), clampf(s / maxf(tot, 1.0), 0.0, 1.0))
		return EL.water_level(W, s)
	for name in by:
		var W: Dictionary = by[name]
		var cum: PackedFloat32Array = W["cum"]
		var tot := cum[cum.size() - 1]
		var flow := String(W["def"]["flow"])
		var prev := NAN
		var s := 0.0
		while s <= tot:
			var l: float = lvl.call(name, s)
			if not is_nan(prev):
				# out／path：沿線下降；in：沿線（往上游）上升
				if (flow == "in" and l < prev - 1e-4) or (flow != "in" and l > prev + 1e-4):
					bad += 1
					if not quiet:
						print("[EDGE]   %s 水位逆流 s=%.0f %.2f→%.2f" % [name, s, prev, l])
			prev = l
			s += 10.0
	# 起點＝frame 邊、與 P2 水面同高
	var p2 := {"RiverNorth": "Water/MainRiver", "RiverEast": "Water/MainRiver", "CanalSouth": "Water/Canal", "StreamSouth": "Water/Streams/WestStream"}
	for name in p2:
		var W: Dictionary = by[name]
		var p0: Vector2 = (W["pts"] as PackedVector2Array)[0]
		var onb := absf(p0.x - EL.FX0) < 1e-3 or absf(p0.x - EL.FX1) < 1e-3 or absf(p0.y - EL.FZ0) < 1e-3 or absf(p0.y - EL.FZ1) < 1e-3
		if not onb:
			bad += 1
		var mi := v.get_node_or_null(String(p2[name])) as MeshInstance3D
		if mi == null:
			bad += 1
			continue
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var sy := 0.0
		var k := 0
		for q in vs:
			var w := mi.global_transform * q
			if Vector2(w.x, w.z).distance_to(p0) < 4.0:
				sy += w.y
				k += 1
		if k == 0 or absf(sy / k - float(lvl.call(name, 0.0))) > 0.06:
			if not quiet:
				print("[EDGE]   %s 起點水位 vista %.2f vs P2 %.2f（%d 頂點）" % [name, float(lvl.call(name, 0.0)), sy / maxf(k, 1), k])
			bad += 1
	# 支流匯入：終點水位 ≥ 南の川最近點 + 0.1
	var SR: Dictionary = by["SouthRiver"]
	for name in ["CanalSouth", "StreamSouth"]:
		var W: Dictionary = by[name]
		var pts: PackedVector2Array = W["pts"]
		var cum: PackedFloat32Array = W["cum"]
		var r := EL._seg_near(SR["pts"], SR["cum"], pts[pts.size() - 1])
		if float(lvl.call(name, cum[cum.size() - 1])) < float(lvl.call("SouthRiver", r.y)) + 0.1:
			bad += 1
			if not quiet:
				print("[EDGE]   %s 匯入：終點 %.2f vs 南の川 %.2f（距 %.1f m）" % [name, float(lvl.call(name, cum[cum.size() - 1])), float(lvl.call("SouthRiver", r.y)), r.x])
	# 南の川終點與 RiverEast 會合
	var se: PackedVector2Array = SR["pts"]
	var scum: PackedFloat32Array = SR["cum"]
	var RE: Dictionary = by["RiverEast"]
	var rr := EL._seg_near(RE["pts"], RE["cum"], se[se.size() - 1])
	if rr.x > 30.0 or absf(float(lvl.call("SouthRiver", scum[scum.size() - 1])) - float(lvl.call("RiverEast", rr.y))) > 0.3:
		bad += 1
		if not quiet:
			print("[EDGE]   會合：南の川終點 %.2f vs RiverEast %.2f（距 %.1f m）" % [float(lvl.call("SouthRiver", scum[scum.size() - 1])), float(lvl.call("RiverEast", rr.y)), rr.x])
	return bad

func _trees_bad(P: Dictionary) -> int:
	var C: Dictionary = P["ctx"]
	var bad := 0
	for it: Dictionary in P["trees"]:
		var p: Vector2 = it["p"]
		if EL.inside(p):
			bad += 1
			continue
		var d := p.distance_to(EL.frame_near(p))
		if d < float(EL.TREE_D[0]) - 0.01:
			bad += 1
			continue
		for W: Dictionary in C["waters"]:
			var r := EL._seg_near(W["pts"], W["cum"], p)
			if r.x < EL.water_hw(W, r.y) + 2.0:
				bad += 1
				break
		if EL.path_w(C, p) > 0.15:
			bad += 1
	return bad

# ─────────── scene ───────────
func _scene(v: Node3D) -> void:
	var names := []
	for c in v.get_children():
		names.append(String(c.name))
	var cnt := names.count(EL.NODE_NAME)
	check("掛載：root/%s 恰 1 個（%d）" % [EL.NODE_NAME, cnt], cnt == 1)
	var ia := names.find("HumanUseExpansionP10")
	var ib := names.find(EL.NODE_NAME)
	check("掛載順：HumanUseExpansionP10（%d）之後（%d）" % [ia, ib], ia >= 0 and ib > ia)
	var node := v.get_node_or_null(EL.NODE_NAME)
	if node == null:
		return
	var cols := node.find_children("*", "CollisionObject3D", true, false)
	check("無碰撞：CollisionObject3D %d" % cols.size(), cols.is_empty())
	var b := v.get_node("Collision/Boundary")
	var walls := 0
	for cs in b.get_children():
		if cs is CollisionShape3D and not (cs as CollisionShape3D).disabled and (cs as CollisionShape3D).shape is BoxShape3D:
			walls += 1
	check("Collision/Boundary 4 牆不變（%d）" % walls, walls == 4)
	var tm := node.get_node("VistaTerrain") as MeshInstance3D
	var arr: Array = tm.mesh.surface_get_arrays(0)
	var vin := 0
	for q in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		if EL.inside(Vector2(q.x, q.z)):
			vin += 1
	check("VistaTerrain 頂點在 frame 內 %d" % vin, vin == 0)
	if MMG.display_ok():
		var au := MMG.audit_node(node)
		check("MultiMesh：%s" % MMG.summary(au), MMG.ok(au))
	else:
		print("[EDGE] INFO headless：MultiMesh 回讀不在 headless 驗（build rule），請用非 headless --scene")

# ─────────── attach ───────────
func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(EL.OUTPUT):
		push_error("找不到 %s（先 --build）" % EL.OUTPUT)
		return 1
	var line := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]" % [EL.NODE_NAME, EXT_ID]
	if txt.contains(line):
		print("[EDGE] attach：已掛（不重複、不寫場景）")
		return 0
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	if not txt.contains(AFTER_NODE):
		push_error("找不到 root/HumanUseExpansionP10")
		return 1
	var lines := txt.split(nl)
	var out := PackedStringArray(Array(lines))
	var at := out.find(AFTER_NODE)
	out.insert(at + 1, "")
	out.insert(at + 2, line)
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%s\"]" % [EL.OUTPUT, EXT_ID])
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[EDGE] attach：加 root/%s（HumanUseExpansionP10 之後）→ %s（+%d 行）" % [EL.NODE_NAME, SCENE, out.size() - lines.size()])
	return 0


## --seal 固有：EdgeClosureP10 の内容（林帯・遠景）が見えて掛かっている（使用者：林帯の数は増やさない＝seal の frozen に overlay 雜湊）
func _seal_extra(v: Node3D) -> Array:
	var n := v.get_node("EdgeClosureP10") as Node3D
	var mi := n.find_children("*", "MeshInstance3D", true, false).size()
	var mm := n.find_children("*", "MultiMeshInstance3D", true, false).size()
	return [[n.visible and mi + mm > 0, "EdgeClosureP10 visible・描画ノード MeshInstance %d／MultiMesh %d" % [mi, mm]]]
