extends "res://tools/p13/w6/w6_base.gd"
## P13 W9 FIX：外形碰撞箱（Shell）の生存期間を正式な遊玩経路で検査（唯讀・場景ファイルは書かない・有視窗）。
##   godot --path godot --resolution 1280x720 --script res://tools/p13/w9/w9fix_lifecycle_real.gd -- <out.json>
## main.tscn → ReviewStart → village_v2（実際の玩家・main.gd の load_map／_on_load_requested）。
##   1. 起動後：collision_fit.json の 22 棟すべてで Shell 有効・body の元の箱が無効・同時有効 0・layer／mask＝body・形と位置＝json・
##      物理サーバ上の実照会（修正で歩けるようになった所に碰撞が無い／Shell の中に碰撞がある）
##   2. 読檔（main._on_load_requested）で修正で歩けるようになった所に玩家を置く：load_map 直後（同期・物理フレーム前）に入れ替え済み、
##      60 物理フレームで水平に押し出されない（≤ 0.10 m）
##   3. 退出と再入場（main.load_map("beast_path") → main.load_map("village_v2")）：新しい村で 1 と同じ
##   4. overlay の繰り返し有効化（enabled false → true × 3）：各段の状態と物理照会
const L := preload("res://tools/p13/w9/w9r2_lib.gd")
## [建物 id, 局部 x, 局部 z]：修正前は元の箱の中・修正後は歩ける所（開いた見世・前庭・庭）
## MXC_007 の (0.35, 3.0) は使わない：v16 で見世の床（地面から 0.37 m）に碰撞を付けた結果、そこは床と床の間の幅 0.5 m の土間
## （x 0.3..0.8）で、直径 0.6 m の玩家は立てない＝そこで存檔されることがない。代わりに表の床の上（0.0, 5.1）。
const SPOTS := [
	["B_P_MXC_007", 0.0, 5.1],
	["B_P_MXC_007", -1.7, 3.0],
	["B_P_MKT_025", -2.0, 4.2],
	["B_P_RSW_076", -2.2, -3.0],
	["B_P_RSW_014", -1.8, 2.75],
]
const PUSH_TOL := 0.10

var _cf: Dictionary
var _res := {"checks": [], "fails": 0}


func _ok(cond: bool, msg: String) -> void:
	(_res["checks"] as Array).append([cond, msg])
	if not cond:
		_res["fails"] = int(_res["fails"]) + 1
	print("[W9LIFE] %s %s" % ["PASS" if cond else "FAIL", msg])


func _state(v: Node) -> Dictionary:
	var ov := v.get_node("ArchW9R2P13")
	var r := {"bld": 0, "boxes": 0, "shell_on": 0, "body_on": 0, "body_off": 0, "conflict": 0, "layer_bad": 0, "xf_bad": 0, "missing": 0, "unreg": 0, "enabled": ov.get("enabled")}
	for id: String in _cf:
		var b := ov.get_node_or_null(id)
		var sh := b.get_node_or_null("Shell") as StaticBody3D if b else null
		if sh == null:
			r["missing"] += 1
			continue
		r["bld"] += 1
		var body := v.get_node(NodePath(String(L.SPECS[id]["path"]))) as StaticBody3D
		if sh.collision_layer != body.collision_layer or sh.collision_mask != body.collision_mask:
			r["layer_bad"] += 1
		var boxes: Array = (_cf[id] as Dictionary)["boxes"]
		var kids := sh.get_children()
		if kids.size() != boxes.size():
			r["xf_bad"] += 1
		var any_on := false
		for i in mini(kids.size(), boxes.size()):
			var cs := kids[i] as CollisionShape3D
			var bx: Dictionary = boxes[i]
			var c := Vector3((float(bx["x0"]) + float(bx["x1"])) / 2.0, (float(bx["y0"]) + float(bx["y1"])) / 2.0, (float(bx["z0"]) + float(bx["z1"])) / 2.0)
			var s := Vector3(float(bx["x1"]) - float(bx["x0"]), float(bx["y1"]) - float(bx["y0"]), float(bx["z1"]) - float(bx["z0"]))
			if cs.position.distance_to(c) > 0.005 or (cs.shape as BoxShape3D).size.distance_to(s) > 0.005 or not cs.basis.is_equal_approx(Basis.IDENTITY):
				r["xf_bad"] += 1
			if not cs.disabled:
				r["shell_on"] += 1
				any_on = true
		r["boxes"] += kids.size()
		var bon := false
		for c in body.get_children():
			if c is CollisionShape3D and not (c as CollisionShape3D).disabled:
				bon = true
		r["body_on" if bon else "body_off"] += 1
		if bon and any_on:
			r["conflict"] += 1
	for b in ov.get_children():
		if b.get_node_or_null("Shell") != null and not _cf.has(String(b.name)):
			r["unreg"] += 1
	return r


## 立てる面（建物局部 +1.6 m から下へ当てた最初の碰撞の上面：地面、または新しい床の箱〈地面から 0.37–0.41 m〉）。
## 以前は地形だけを見ていた → 床の箱を足した後は玩家を床の箱の中に置いてしまい、押し出しを誤検出した（W9 FIX 最終驗收）。
func _spot_world(v: Node, sp: Array) -> Vector3:
	var body := v.get_node(NodePath(String(L.SPECS[String(sp[0])]["path"]))) as Node3D
	var o := body.global_transform * Vector3(float(sp[1]), 1.6, float(sp[2]))
	var space := (v as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(o, o - Vector3(0, 4.0, 0), 0xFFFFFFFF)
	if player != null:
		q.exclude = [player.get_rid()]
	var h := space.intersect_ray(q)
	return Vector3(o.x, (h["position"] as Vector3).y if not h.is_empty() else o.y - 1.6, o.z)


## 物理サーバへの実照会：各 SPOT の足元 +1.0 m に建物の碰撞があるか（body／Shell／Posts のどれか）
func _phys(v: Node) -> Array:
	var space := (v as Node3D).get_world_3d().direct_space_state
	var out: Array = []
	for sp: Array in SPOTS:
		var wp := _spot_world(v, sp) + Vector3(0, 1.0, 0)
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = wp
		pq.collision_mask = 1
		var hit := ""
		for h in space.intersect_point(pq, 8):
			var co := h["collider"] as Node
			if co and (String(co.name) == String(sp[0]) or String(co.get_parent().name) == String(sp[0])):
				hit = String(co.name)
		out.append(hit)
	return out


func _check_on(v: Node, tag: String) -> void:
	var s := _state(v)
	_ok(s["bld"] == _cf.size() and s["missing"] == 0 and s["unreg"] == 0 and s["boxes"] == _count_boxes(),
		"%s：Shell %d 棟／%d 箱（json %d 棟／%d 箱）・未登録 %d・欠落 %d" % [tag, s["bld"], s["boxes"], _cf.size(), _count_boxes(), s["unreg"], s["missing"]])
	_ok(s["shell_on"] == s["boxes"] and s["body_off"] == s["bld"] and s["conflict"] == 0,
		"%s：Shell 有効 %d/%d・body の元の箱 無効 %d/%d・同時有効 %d" % [tag, s["shell_on"], s["boxes"], s["body_off"], s["bld"], s["conflict"]])
	_ok(s["layer_bad"] == 0 and s["xf_bad"] == 0, "%s：layer／mask＝body（不一致 %d）・形と位置＝json（不一致 %d）" % [tag, s["layer_bad"], s["xf_bad"]])
	var ph := _phys(v)
	var bad := 0
	for x in ph:
		if String(x) != "":
			bad += 1
	_ok(bad == 0, "%s：物理照会（修正で歩ける所 %d 点の足元 +1.0 m）に建物の碰撞なし（当たり %d：%s）" % [tag, SPOTS.size(), bad, str(ph)])


func _check_off(v: Node, tag: String) -> void:
	var s := _state(v)
	_ok(s["shell_on"] == 0 and s["body_on"] == s["bld"] and s["conflict"] == 0,
		"%s：Shell 有効 0（%d）・body の元の箱 有効 %d/%d・同時有効 %d" % [tag, s["shell_on"], s["body_on"], s["bld"], s["conflict"]])
	var ph := _phys(v)
	var hits := 0
	for x in ph:
		if String(x) != "":
			hits += 1
	_ok(hits == SPOTS.size(), "%s：物理照会で元の箱が実際に効いている（%d/%d 点で当たり：%s）" % [tag, hits, SPOTS.size(), str(ph)])


func _count_boxes() -> int:
	var n := 0
	for k in _cf:
		n += ((_cf[k] as Dictionary)["boxes"] as Array).size()
	return n


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var outp: String = args[0] if args.size() > 0 else "user://w9fix_life.json"
	_cf = (JSON.parse_string(FileAccess.get_file_as_string(L.COLFIT)) as Dictionary)["buildings"]
	await _boot()
	var vid: String = String(main.get("current_id"))
	print("[W9LIFE] boot：current_id=%s" % vid)
	# 1. 起動
	_check_on(vil, "起動")
	# 2. 読檔で開いた所に置く
	for sp: Array in SPOTS:
		vil = main.get("map_root")
		var pos := _spot_world(vil, sp) + Vector3(0, 0.05, 0)
		main.call("_on_load_requested", vid, pos, 0.0)
		# load_map が古い村を queue_free → 同じフレームでは古い村も木にある。新しい村＝map_root
		var nv: Node = main.get("map_root")
		var s0 := _state(nv)
		var sync_ok: bool = s0["shell_on"] == s0["boxes"] and s0["body_off"] == s0["bld"]
		var p0 := player.global_position
		var maxd := 0.0
		for i in 60:
			await physics_frame
			maxd = maxf(maxd, Vector2(player.global_position.x - p0.x, player.global_position.z - p0.z).length())
		_ok(sync_ok, "読檔 %s (%.2f, %.2f)：load_map 直後（物理フレーム前）に入れ替え済み（Shell 有効 %d/%d・body 無効 %d/%d）" % [sp[0], sp[1], sp[2], s0["shell_on"], s0["boxes"], s0["body_off"], s0["bld"]])
		_ok(maxd <= PUSH_TOL, "読檔 %s (%.2f, %.2f)：60 物理フレームで押し出されない（水平移動 最大 %.3f m・上限 %.2f）・接地 %s" % [sp[0], sp[1], sp[2], maxd, PUSH_TOL, player.is_on_floor()])
	vil = main.get("map_root")
	_check_on(vil, "読檔の後")
	# 3. 退出と再入場
	main.call("load_map", "beast_path", vid)
	for i in 30:
		await physics_frame
	_ok(String(main.get("current_id")) == "beast_path" and root.find_child("VillageV2", true, false) == null, "退出：beast_path へ（村は解放・current_id=%s）" % main.get("current_id"))
	main.call("load_map", vid, "beast_path")
	vil = main.get("map_root")
	var s1 := _state(vil)
	_ok(s1["shell_on"] == s1["boxes"] and s1["body_off"] == s1["bld"] and s1["conflict"] == 0, "再入場：load_map 直後（物理フレーム前）に入れ替え済み（Shell 有効 %d/%d・body 無効 %d/%d・同時有効 %d）" % [s1["shell_on"], s1["boxes"], s1["body_off"], s1["bld"], s1["conflict"]])
	for i in 30:
		await physics_frame
	_check_on(vil, "再入場の後")
	# 4. 繰り返し有効化
	var ov := vil.get_node("ArchW9R2P13")
	for k in 3:
		ov.set("enabled", false)
		for i in 3:
			await physics_frame
		_check_off(vil, "enabled=false #%d" % (k + 1))
		ov.set("enabled", true)
		for i in 3:
			await physics_frame
		_check_on(vil, "enabled=true #%d" % (k + 1))
	var f := FileAccess.open(outp, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_res, "\t"))
		f.close()
	print("[W9LIFE] 結果：%d 項・FAIL %d" % [(_res["checks"] as Array).size(), _res["fails"]])
	quit(0 if int(_res["fails"]) == 0 else 1)
