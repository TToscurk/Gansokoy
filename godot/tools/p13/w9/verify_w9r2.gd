extends SceneTree
## P13 W9 Round 2 gate：ArchW9R2P13（建築外形サンプル 10 棟）を「保存された場景」から独立に検査する ＋ 反向案例。
##   godot --headless --path godot --script res://tools/p13/w9/verify_w9r2.gd
## 見るもの：掛載（1 回・順序）／10 棟の id・body 追従／LOD0・1 の予算／footprint への張り出し上限／戸口前の淨空／通行の頭上淨空／
##          enabled の往復（Kit の visible が完全に元へ戻る）／新規碰撞 0／Kit を『永久に消した』ものが無いこと。
const L := preload("res://tools/p13/w9/w9r2_lib.gd")

const MAX_TRI0 := 26000        # 1 棟 LOD0
const MAX_TRI0_ALL := 160000
const MAX_TRI1 := 500          # 1 棟 LOD1
const SIDE_OVER := 1.35        # 左右（妻・桁行）への張り出し上限 [m]（P4 massing の外側）
const BACK_OVER := 1.35
const FRONT_OVER := 2.6        # 前（街側）への張り出し上限 [m]：深い庇＋日除け
const HEAD_LO := 1.1           # 壁の外（z>zf+0.3）で、この帯に三角形があれば通行の頭に当たる
const HEAD_HI := 1.8
const DOOR_PAD := 0.05
const HUG := 0.7               # 壁にへばりつく帯（樽・薪・縁台など）の厚み [m]：この内側は『壁の付属物』として頭上帯の検査から外す

var passed := 0
var failed := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("[W9R2G] PASS ", msg)
	else:
		failed += 1
		print("[W9R2G] FAIL ", msg)


func _init() -> void:
	_run.call_deferred()


## メッシュの形状検査（ローカル座標）。戻り値：tri、aabb、帯違反数、戸口違反数、最悪の位置（診断用）
static func analyze(mesh: Mesh, w: float, d: float, door_cx: float, door_w: float) -> Dictionary:
	var zf := d / 2.0
	var tri := 0
	var head := 0
	var door := 0
	var worst: PackedStringArray = []
	var ab := AABB()
	var first := true
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for p in v:
			if first:
				ab = AABB(p, Vector3.ZERO)
				first = false
			else:
				ab = ab.expand(p)
		for t in idx.size() / 3:
			var a := v[idx[t * 3]]
			var b := v[idx[t * 3 + 1]]
			var c := v[idx[t * 3 + 2]]
			tri += 1
			var h_hit := false
			var d_hit := false
			for q: Vector3 in [a, b, c, (a + b + c) / 3.0]:
				# 通行の頭の高さ帯：壁にへばりつく帯（z ≤ zf+0.7）の外
				if q.z > zf + HUG and q.y > HEAD_LO and q.y < HEAD_HI:
					h_hit = true
				# 戸口の前：幅＋余白、壁から 1.6 m まで、y 0.35–1.8
				if q.z > zf + 0.25 and q.z < zf + 1.6 and q.x > door_cx - door_w / 2.0 - DOOR_PAD and q.x < door_cx + door_w / 2.0 + DOOR_PAD \
						and q.y > 0.35 and q.y < HEAD_HI:
					d_hit = true
			if h_hit:
				head += 1
				if worst.size() < 3:
					worst.append("head@(%.2f,%.2f,%.2f)" % [a.x, a.y, a.z])
			if d_hit:
				door += 1
				if worst.size() < 6:
					worst.append("door@(%.2f,%.2f,%.2f)" % [a.x, a.y, a.z])
	return {"tri": tri, "aabb": ab, "head": head, "door": door, "worst": ", ".join(worst)}


static func over_ok(ab: AABB, w: float, d: float) -> bool:
	var zf := d / 2.0
	return ab.position.x >= -w / 2.0 - SIDE_OVER and ab.end.x <= w / 2.0 + SIDE_OVER \
		and ab.position.z >= -zf - BACK_OVER and ab.end.z <= zf + FRONT_OVER


func _run() -> void:
	# ---------- 反向案例（検査関数が本当に違反を拾う）----------
	var neg := _negatives()
	# ---------- 本番 ----------
	var txt := FileAccess.get_file_as_string(L.SCENE)
	var line := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"p13w9r2_arch\")]" % L.NODE_NAME
	_ok(txt.count(line) == 1, "root 直下に %s が 1 回だけ掛載（保存された village_v2.tscn）" % L.NODE_NAME)
	var order: PackedStringArray = []
	for l: String in txt.split("\n"):
		if l.begins_with("[node name=\"") and l.contains("parent=\".\""):
			order.append(l.split("\"")[1])
	_ok(order.find(L.NODE_NAME) == order.find(L.AFTER) + 1, "%s は %s の直後（順序）" % [L.NODE_NAME, L.AFTER])
	var v := (load(L.SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(v)
	for i in 4:
		await process_frame
	var ov := v.get_node_or_null(L.NODE_NAME)
	_ok(ov != null, "実行時に root/%s がある" % L.NODE_NAME)
	if ov == null:
		print("[W9R2G] 結果：%d 通過・%d 失敗（反向案例 %d/%d）" % [passed, failed, neg[0], neg[1]])
		quit(1)
		return
	_ok(ov.get_child_count() == L.SPECS.size(), "建築 %d 棟（SPECS と一致）" % L.SPECS.size())
	var tri_all := 0
	var coll := 0
	var kit_hidden_total := 0
	for n in ov.find_children("*", "CollisionObject3D", true, false):
		coll += 1
	_ok(coll == 0, "overlay に碰撞体 0（実際 %d）" % coll)
	var before: Dictionary = {}     # body path → [visible…]
	var hid_n := {}
	for id: String in L.SPECS:
		var sp: Dictionary = L.SPECS[id]
		var n := ov.get_node_or_null(id) as Node3D
		_ok(n != null, "%s：overlay 子がある" % id)
		if n == null:
			continue
		var body := v.get_node_or_null(NodePath(sp["path"])) as Node3D
		_ok(body != null, "%s：body が実在（%s）" % [id, sp["path"]])
		if body == null:
			continue
		var same := n.global_transform.origin.distance_to(body.global_transform.origin) < 0.002 \
			and (n.global_transform.basis.get_euler() - body.global_transform.basis.get_euler()).length() < 0.001
		_ok(same, "%s：overlay の transform が body と同じ" % id)
		var kit := body.get_node("Kit")
		var dcx := float(kit.get_meta("door_cx", 0.0))
		var dw := float(kit.get_meta("door_w", 1.7))
		var shp := body.get_node_or_null("Shape") as CollisionShape3D
		var box := shp.shape as BoxShape3D if shp else null
		var w := box.size.x if box else 5.0
		var d := box.size.z if box else 10.0
		var l0 := n.get_node_or_null("L0") as MeshInstance3D
		var l1 := n.get_node_or_null("L1") as MeshInstance3D
		_ok(l0 != null and l1 != null, "%s：L0／L1 あり" % id)
		if l0 == null or l1 == null:
			continue
		_ok(l0.visibility_range_begin == 0.0 and l0.visibility_range_end == l1.visibility_range_begin \
			and l1.visibility_range_end >= 400.0, "%s：LOD 範囲が連続（L0→L1・遠距離まで）" % id)
		var a0 := analyze(l0.mesh, w, d, dcx, dw)
		var a1 := analyze(l1.mesh, w, d, dcx, dw)
		tri_all += int(a0["tri"])
		_ok(int(a0["tri"]) <= MAX_TRI0 and int(a1["tri"]) <= MAX_TRI1, "%s：三角面 L0 %d／L1 %d（上限 %d／%d）" % [id, a0["tri"], a1["tri"], MAX_TRI0, MAX_TRI1])
		_ok(over_ok(a0["aabb"], w, d), "%s：張り出しが上限内（%s）" % [id, a0["aabb"]])
		_ok(int(a0["door"]) == 0, "%s：戸口の前（幅＋余白・壁から 1.6 m）に y 0.35–1.8 の三角形 0（%d）" % [id, a0["door"]])
		_ok(int(a0["head"]) == 0, "%s：壁の外の頭の高さ帯（y %.1f–%.1f）に三角形 0（%d）%s" % [id, HEAD_LO, HEAD_HI, a0["head"], a0["worst"]])
		# Kit の visible を記録（overlay 有効時の状態）
		var states: Array = []
		for lod in 3:
			var g := kit.get_node_or_null("LOD%d" % lod)
			if g:
				for mi in g.get_children():
					if mi is MeshInstance3D:
						states.append([mi, (mi as MeshInstance3D).visible])
		before[id] = states
	_ok(tri_all <= MAX_TRI0_ALL, "10 棟 LOD0 合計 %d tri（上限 %d）" % [tri_all, MAX_TRI0_ALL])
	# enabled の往復：false → Kit の visible は全て true（元の状態）。true → 非表示が復活。
	var hidden_on := 0
	for id: String in before:
		for s: Array in before[id]:
			if not bool(s[1]):
				hidden_on += 1
	_ok(int(ov.get("r1_hidden")) == 7, "enabled=true：R1 の吊り物（簾・吊柿・杉玉）7 件がこの 10 棟でだけ隠れる（実際 %d）" % int(ov.get("r1_hidden")))
	var r1n := v.get_node("EnrichW9P13")
	var r1_off := 0
	var r1_all := 0
	for z in r1n.get_children():
		for cl in z.get_children():
			for it in cl.get_children():
				if it is Node3D:
					r1_all += 1
					if not (it as Node3D).visible:
						r1_off += 1
	_ok(r1_off == 7, "EnrichW9P13 全 %d 件のうち非表示は 7 件だけ（他の R1 内容は触れていない・実際 %d）" % [r1_all, r1_off])
	ov.set("enabled", false)
	await process_frame
	r1_off = 0
	for z in r1n.get_children():
		for cl in z.get_children():
			for it in cl.get_children():
				if it is Node3D and not (it as Node3D).visible:
					r1_off += 1
	_ok(r1_off == 0 and int(ov.get("r1_hidden")) == 0, "enabled=false で R1 の物は全て元の表示（非表示 %d）" % r1_off)
	var still_hidden := 0
	for id: String in before:
		for s: Array in before[id]:
			if is_instance_valid(s[0]) and not (s[0] as MeshInstance3D).visible:
				still_hidden += 1
	_ok(still_hidden == 0, "enabled=false で Kit は全て元の表示へ（非表示だったもの %d → 残り %d）" % [hidden_on, still_hidden])
	_ok(not (ov as Node3D).visible, "enabled=false で overlay は非表示")
	ov.set("enabled", true)
	await process_frame
	var hidden_again := 0
	for id: String in before:
		for s: Array in before[id]:
			if is_instance_valid(s[0]) and not (s[0] as MeshInstance3D).visible:
				hidden_again += 1
	_ok(hidden_again == hidden_on and hidden_on > 0, "enabled=true で同じ Kit 構件が再び隠れる（%d → %d）" % [hidden_on, hidden_again])
	# 永久に消していない：.tscn 本体に Kit 構件の visible=false が書かれていない
	var gout := []
	OS.execute("git", ["diff", "--numstat", "--", ProjectSettings.globalize_path(L.SCENE)], gout)
	var ns: PackedStringArray = String(gout[0]).strip_edges().split("\t") if gout.size() > 0 else PackedStringArray()
	_ok(ns.size() >= 2 and int(ns[1]) == 0 and int(ns[0]) <= 3, "village_v2.tscn の git diff は『追加のみ・≤3 行』（掛載の ext_resource＋node＋空行。実際 +%s −%s）" % [ns[0] if ns.size() > 0 else "?", ns[1] if ns.size() > 1 else "?"])
	# 碰撞：body の Shape が 1 つのまま
	var shape_ok := true
	for id: String in L.SPECS:
		var body := v.get_node_or_null(NodePath(L.SPECS[id]["path"])) as Node3D
		if body:
			var k := 0
			for c in body.get_children():
				if c is CollisionShape3D:
					k += 1
			if k != 1:
				shape_ok = false
	_ok(shape_ok, "10 棟とも body の碰撞は Kit 由来の 1 Shape のまま（増減なし）")
	print("[W9R2G] 結果：%d 通過・%d 失敗（反向案例 %d/%d）" % [passed, failed, neg[0], neg[1]])
	quit(0 if failed == 0 and int(neg[0]) == int(neg[1]) else 1)


## 反向案例：検査関数に『違反するメッシュ』を与えて、確かに拾うこと
func _negatives() -> Array:
	var okc := 0
	var tot := 0
	# 1 戸口の前に立つ柱
	var m1 := _tri_mesh(Vector3(-0.2, 0.0, 6.0), Vector3(0.2, 0.0, 6.0), Vector3(0.0, 2.0, 6.1))
	var r1 := analyze(m1, 5.0, 10.0, 0.0, 1.7)
	tot += 1
	okc += 1 if int(r1["door"]) > 0 else 0
	# 2 通行の頭の高さ帯にぶら下がる布（壁の外 1.4 m）
	var m2 := _tri_mesh(Vector3(2.0, 1.3, 6.4), Vector3(3.0, 1.3, 6.4), Vector3(2.5, 1.6, 6.4))
	var r2 := analyze(m2, 5.0, 10.0, 0.0, 1.7)
	tot += 1
	okc += 1 if int(r2["head"]) > 0 else 0
	# 3 張り出し過大（前へ 4 m）
	var m3 := _tri_mesh(Vector3(0, 3, 5), Vector3(1, 3, 9.2), Vector3(-1, 3, 9.2))
	tot += 1
	okc += 1 if not over_ok(analyze(m3, 5.0, 10.0, 0.0, 1.7)["aabb"], 5.0, 10.0) else 0
	# 4 左右へ過大
	var m4 := _tri_mesh(Vector3(-4.5, 3, 0), Vector3(0, 3, 0), Vector3(0, 3.5, 0))
	tot += 1
	okc += 1 if not over_ok(analyze(m4, 5.0, 10.0, 0.0, 1.7)["aabb"], 5.0, 10.0) else 0
	# 5 正常な軒（壁際 y 2.8 → 先端 2.5、頭上 ≥2.4）は誤検出しない
	var m5 := _tri_mesh(Vector3(-2, 2.8, 5.0), Vector3(2, 2.8, 5.0), Vector3(0, 2.5, 6.5))
	var r5 := analyze(m5, 5.0, 10.0, 0.0, 1.7)
	tot += 1
	okc += 1 if int(r5["head"]) == 0 and int(r5["door"]) == 0 and over_ok(r5["aabb"], 5.0, 10.0) else 0
	# 6 壁の内側（z<zf）の低い物（室内の棚）は拾わない
	var m6 := _tri_mesh(Vector3(0, 1.2, 4.0), Vector3(1, 1.2, 4.0), Vector3(0.5, 1.5, 4.0))
	var r6 := analyze(m6, 5.0, 10.0, 0.0, 1.7)
	tot += 1
	okc += 1 if int(r6["head"]) == 0 and int(r6["door"]) == 0 else 0
	print("[W9R2G] 反向案例 %d/%d（戸口・頭上・張り出し×2・正常軒・室内）" % [okc, tot])
	return [okc, tot]


static func _tri_mesh(a: Vector3, b: Vector3, c: Vector3) -> ArrayMesh:
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([a, b, c])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
