extends SceneTree
## P10 R3b Population Pilot gate——「壊れていない」ことだけを証明する（美術判定ではない；ART は使用者）。
##   godot --headless --path . --script res://tools/verify_village_v2_population.gd                 plan gate（配役・対位・重複・婆婆／少年の歩き・構図・接地・体の衝突・往復路・歩速・封存 overlay）
##   … -- --negatives    反向 9 案（各案で狙った項目が FAIL すれば PASS）
##   … -- --build        gen/population_p10.tscn を書く（個別ノード、MultiMesh なし → headless 可）
##   … -- --attach       village_v2.tscn に Population/PopulationP10 を掛ける（末尾の新トップノード；Props の下には置かない）
##   … -- --scene        場景級（掛載・封存 NPC 場景の instance・審圖鏡位ごとの同一モデル数・runtime 4 秒：往復が path 上／Idle は動かない・SpringArm 除外）
## 真の FAIL は exit code ≠ 0。

const PL := preload("res://tools/village_v2_population_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const VIEWS := "res://tools/shot_village_v2_population_views.json"
const SEALS := {
	"godot/maps/village_v2/gen/market_p10.scn": "res://data/village_v2_p10r1_seal.json",
	"godot/maps/village_v2/gen/market_west_p10.scn": "res://data/village_v2_p10r1b_seal.json",
}

var fails := 0
var quiet := false
var results := {}


func check(label: String, ok: bool, key := "") -> void:
	if key != "":
		results[key] = ok
	if not ok:
		fails += 1
	if not quiet:
		print("[POP] %s %s" % ["PASS" if ok else "FAIL", label])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1920, 1080)  # 與正式 ART_REVIEW capture 的 viewport / aspect 一致
	var args := OS.get_cmdline_user_args()
	if "--seal" in args:
		quit(_seal())
		return
	# Approved baseline is immutable without an explicit user-approved reopen/reseal.
	# Attach writes the entire world scene; forbid it too rather than trusting editor state.
	if ("--build" in args or "--attach" in args) and FileAccess.file_exists("res://data/village_v2_p10r3b_seal.json"):
		if OS.get_environment("POP_ALLOW_USER_APPROVED_REBAKE_AND_RESEAL") != "1":
			push_error("[POP] SEALED baseline: --build/--attach denied; user-approved reopen + reseal required")
			quit(1)
			return
	if "--attach" in args:
		quit(_attach())
		return
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 3:
		await physics_frame
	if "--scene" in args:
		await _scene(v)
		print("[POP] 結果：%d 項失敗（scene）" % fails)
		quit(fails)
		return
	var P := PL.plan(v)
	if "--build" in args:
		var bad := _gate(v, P)
		if bad > 0:
			push_error("gate FAIL %d → build しない" % bad)
			quit(1)
			return
		var node := PL.build(P)
		var ps := PackedScene.new()
		ps.pack(node)
		var err := ResourceSaver.save(ps, PL.OUTPUT)
		print("[POP] build → %s（%d 人、err %d）" % [PL.OUTPUT, (P["actors"] as Array).size(), err])
		node.free()
		quit(1 if err != OK else 0)
		return
	if "--negatives" in args:
		quit(await _negatives(v))
		return
	_gate(v, P)
	print("[POP] 結果：%d 項失敗（plan、%d ms）" % [fails, P["ms"]])
	quit(fails)


func _d2(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _seg_d(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


## 立ち位置／path の 2D 点列（idle は 1 点）
func _pts(a: Dictionary) -> PackedVector2Array:
	if a["mode"] == "patrol":
		var out := PackedVector2Array()
		var pts: PackedVector2Array = a["path_xz"]
		for i in range(1, pts.size()):
			var n := int(ceil(pts[i].distance_to(pts[i - 1]) / 0.5))
			for k in n:
				out.append(pts[i - 1].lerp(pts[i], float(k) / n))
		out.append(pts[pts.size() - 1])
		return out
	var p: Vector3 = a["p"]
	return PackedVector2Array([Vector2(p.x, p.z)])


func _min_d(a: Dictionary, b: Dictionary) -> float:
	var best := INF
	for p in _pts(a):
		for q in _pts(b):
			best = minf(best, p.distance_to(q))
	return best


func _hits(v: Node3D, sp: PhysicsDirectSpaceState3D, p: Vector3, h: float, r := PL.CAP_R) -> Array:
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = h - 0.10
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis(), p + Vector3(0, cap.height * 0.5 + 0.08, 0))
	var own := v.get_node_or_null(PL.PARENT)
	var out := []
	for hh in sp.intersect_shape(q, 16):
		var c := hh.collider as Node
		var nm := String(c.name)
		if nm.begins_with("TerrainCollision"):
			continue
		if own != null and own.is_ancestor_of(c):
			continue
		out.append(String(v.get_path_to(c)).get_file() if v.is_ancestor_of(c) else nm)
	return out


func _gate(v: Node3D, P: Dictionary) -> int:
	var f0 := fails
	var A: Array = P["actors"]
	var C: Dictionary = P["C"]
	var sp := v.get_world_3d().direct_space_state
	# 1 人数・区域
	var zc := {}
	for a: Dictionary in A:
		zc[a["zone"]] = int(zc.get(a["zone"], 0)) + 1
	check("人數 %d（12–18）、區域 %s（主市集・Market West・主街の 3 區のみ、各 ≥ 3）" % [A.size(), str(zc)],
		A.size() >= 12 and A.size() <= 18 and zc.size() == 3 and zc.keys().all(func(z: String) -> bool: return z in ["market", "market_west", "main_street"] and int(zc[z]) >= 3), "count")
	# 2 anchor・モデル
	var bad_a := A.filter(func(a: Dictionary) -> bool: return a.has("error") or not ResourceLoader.exists(PL.npc_scene(a["model"])))
	check("全員：封存 NPC 場景が存在し、anchor（封存 P10 overlay の Marker）を読めた（欠落 %s）" % str(bad_a.map(func(a: Dictionary) -> String: return a["id"])), bad_a.is_empty(), "anchor")
	if not bad_a.is_empty():
		return fails - f0
	# 3 職業対位
	var bad_r := A.filter(func(a: Dictionary) -> bool: return not (a["trade"] in PL.ROLE_OK.get(a["model"], [])))
	check("職業對位：外見→商い（菜販→八百屋・魚販→魚・布料→呉服・茶屋→茶屋・木柴→雜貨／運び・藥草→乾物／薬・陶器→瀬戸物…；違反 %s）" % str(bad_r.map(func(a: Dictionary) -> String: return "%s %s→%s" % [a["id"], a["model"], a["trade"]])), bad_r.is_empty(), "role")
	# 4 同一モデルの間隔
	var near := []
	var dmin := INF
	for i in A.size():
		for j in range(i + 1, A.size()):
			if A[i]["model"] == A[j]["model"]:
				var d := _min_d(A[i], A[j])
				dmin = minf(dmin, d)
				if d < 12.0:
					near.append("%s-%s %.1f m" % [A[i]["id"], A[j]["id"], d])
	check("同一モデルは隣接しない：同モデル間の最短 %.1f m（≥ 12 m；違反 %s）" % [dmin, str(near)], near.is_empty(), "twin")
	# 5 歩き：婆婆 0、少年 ≤ 1、walker 2–4
	var walkers := A.filter(func(a: Dictionary) -> bool: return a["mode"] == "patrol")
	var wbad := walkers.filter(func(a: Dictionary) -> bool: return a["model"] in PL.NO_WALK)
	var wcount := {}
	for a: Dictionary in walkers:
		wcount[a["model"]] = int(wcount.get(a["model"], 0)) + 1
	var wmax_bad := PL.WALK_MAX.keys().filter(func(m: String) -> bool: return int(wcount.get(m, 0)) > int(PL.WALK_MAX[m]))
	check("歩く人 %d（2–4）：婆婆 2 人は Walk 0（%s）、跑腿少年 ≤ 1（%s）" % [walkers.size(), str(wbad.map(func(a: Dictionary) -> String: return a["id"])), str(wmax_bad)],
		walkers.size() >= 2 and walkers.size() <= 4 and wbad.is_empty() and wmax_bad.is_empty(), "walk_rule")
	# 6 構図：小群（2–3 人、互いに 3 m 以内）≥ 3、単独（3 m 以内に誰もいない）≥ 4、等間隔に撒かない（最近傍距離の変動係数）
	var idle := A.filter(func(a: Dictionary) -> bool: return a["mode"] == "idle")
	var nn := []
	var groups := {}
	var singles := 0
	for a: Dictionary in idle:
		var best := INF
		var mates := 0
		for b: Dictionary in idle:
			if a == b:
				continue
			var d := _d2(a["p"], b["p"])
			best = minf(best, d)
			if d <= 3.0:
				mates += 1
		nn.append(best)
		if mates == 0:
			singles += 1
		elif String(a["group"]) != "":
			groups[a["group"]] = int(groups.get(a["group"], 0)) + 1
	var g_ok := groups.keys().filter(func(g: String) -> bool: return int(groups[g]) >= 2 and int(groups[g]) <= 3)
	var mean := 0.0
	for x: float in nn:
		mean += x
	mean /= maxf(nn.size(), 1)
	var vs := 0.0
	for x: float in nn:
		vs += (x - mean) * (x - mean)
	var cv := sqrt(vs / maxf(nn.size(), 1)) / maxf(mean, 1e-4)
	check("構圖：小群（2–3 人・3 m 以内）%d 組（≥ 3：%s）、単独 %d（≥ 4）、最近傍距離の変動係數 %.2f（≥ 0.5＝等間隔に撒いていない）" % [g_ok.size(), str(g_ok), singles, cv],
		g_ok.size() >= 3 and singles >= 4 and cv >= 0.5, "compose")
	# 7 接地（Idle：足元＝見えている最上面 ±3 cm）
	var gbad := []
	var gmax := 0.0
	for a: Dictionary in idle:
		var p: Vector3 = a["p"]
		var e := absf(p.y - PL.top_h(C, Vector2(p.x, p.z)))
		gmax = maxf(gmax, e)
		if e > 0.03:
			gbad.append("%s %.2f" % [a["id"], e])
	check("接地：Idle %d 人の足元と見えている最上面の差 最大 %.3f m（≤ 0.03；違反 %s）" % [idle.size(), gmax, str(gbad)], gbad.is_empty(), "ground")
	# 8 体の衝突：capsule（r 0.22、身長）が屋台・棚・建物・柵の衝突体と重ならない、NPC 同士 ≥ 0.55 m
	var cbad := []
	for a: Dictionary in idle:
		var h := (C["RI"] as PL.RenderIndex).body_hits(a["p"], float(a["height"]), PL.CAP_R)
		h.append_array(_hits(v, sp, a["p"], float(a["height"])))
		if not h.is_empty():
			cbad.append("%s→%s" % [a["id"], str(h.slice(0, 2))])
	var pbad := []
	for i in idle.size():
		for j in range(i + 1, idle.size()):
			if _d2(idle[i]["p"], idle[j]["p"]) < 0.55:
				pbad.append("%s-%s" % [idle[i]["id"], idle[j]["id"]])
	check("體の衝突：Idle の capsule が屋台・棚・建物の衝突體に入らない（違反 %s）、NPC 間 ≥ 0.55 m（%s）" % [str(cbad), str(pbad)], cbad.is_empty() and pbad.is_empty(), "body")
	# 9 往復路：0.25 m 毎の capsule が衝突體に入らない、Idle の人から ≥ 0.6 m、高さの段差 ≤ 0.10 m／0.25 m、長さ 6–20 m
	var rbad := []
	for a: Dictionary in walkers:
		var ys: PackedFloat32Array = a["path_y"]
		var L := float(a["path_len"])
		var step := 0.0
		for j in range(1, ys.size()):
			step = maxf(step, absf(ys[j] - ys[j - 1]))
		var hit := []
		var j2 := 0
		while j2 * 0.25 <= L:
			var q := PL._along(a["path_xz"], j2 * 0.25)
			var h := _hits(v, sp, Vector3(q.x, ys[mini(j2, ys.size() - 1)], q.y), float(a["height"]))
			if not h.is_empty():
				hit.append("%.1f m %s" % [j2 * 0.25, str(h.slice(0, 1))])
			j2 += 1
		var clear := INF
		for b: Dictionary in idle:
			clear = minf(clear, _min_d(a, b))
		if not hit.is_empty() or step > 0.10 or L < 6.0 or L > 20.0 or clear < 0.6:
			rbad.append("%s 衝突 %s 段差 %.2f 長 %.1f Idle 迄 %.2f" % [a["id"], str(hit.slice(0, 2)), step, L, clear])
	check("往復路 %d 本：衝突體に入らない・Idle の人から ≥ 0.6 m・段差 ≤ 0.10 m・長さ 6–20 m（違反 %s）" % [walkers.size(), str(rbad)], rbad.is_empty(), "path")
	# 10 歩速＝clip の足の接地速度（滑り ≤ 3 %）
	var sbad := []
	var sinfo := []
	for a: Dictionary in walkers:
		var meas := float(a["walk"]["speed"])
		var r := float(a["walk_speed"]) / maxf(meas, 1e-4)
		sinfo.append("%s %.2f m/s" % [a["model"], float(a["walk_speed"])])
		if absf(r - 1.0) > 0.03 or meas < 0.6:
			sbad.append("%s 比 %.2f" % [a["id"], r])
	check("歩速＝Walk clip の足の接地速度（%s；滑り ≤ 3 %%、違反 %s）" % [", ".join(sinfo), str(sbad)], sbad.is_empty(), "speed")
	# 11 封存 overlay：読むだけ（overlay 雜湊＝封存時）
	var hbad := []
	for k: String in SEALS:
		var seal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SEALS[k]))
		var path := "res://" + k.trim_prefix("godot/")
		if FileAccess.get_sha256(path) != String(seal["frozen"].get(k, "")):
			hbad.append(k.get_file())
	check("封存 P10 overlay（MarketP10・MarketWestP10）は読むだけ：雜湊＝封存時（違い %s）" % str(hbad), hbad.is_empty(), "sealed")
	return fails - f0


func _negatives(v: Node3D) -> int:
	var cases := {
		"twin": func(c: Array) -> void: c[1]["model"] = "yaoya_m01",                                       # 八百屋の客を八百屋に＝同一モデルが隣
		"walk_rule": func(c: Array) -> void: c[10]["mode"] = "patrol"; c[10]["path"] = [[219.0, -45.0], [226.0, -45.0]],   # 婆婆を歩かせる
		"role": func(c: Array) -> void: c[7]["trade"] = "sakana",                                          # 布料老闆娘を魚屋に
		"body": func(c: Array) -> void: c[4]["off"] = [-1.2, 0.0],                                          # 陶器婆婆を棚の中へ
		"path": func(c: Array) -> void: c[11]["path"] = [[208.6, -44.6], [216.0, -48.5], [224.2, -44.6]],    # 往復路を店の中へ
		"count": func(c: Array) -> void:
			var extra := []
			for k in 10:
				var e: Dictionary = c[3].duplicate(true)
				e["id"] = "X%d" % k
				extra.append(e)
			c.append_array(extra),
		"compose": func(c: Array) -> void:                                                                   # 2 人組を全部ばらす
			for k in [1, 8, 14]:
				c[k]["off"] = [3.5, 0.0]
				c[k]["face"] = "anchor",
	}
	var post := {
		"ground": func(P: Dictionary) -> void: P["actors"][2]["p"] += Vector3(0, 0.2, 0),                  # 浮かせる
		"speed": func(P: Dictionary) -> void: P["actors"][6]["walk_speed"] *= 1.3,                         # 歩速を 1.3 倍＝足が滑る
	}
	var mism := 0
	quiet = true
	for key: String in cases.keys() + post.keys():
		var cast: Array = PL.CAST.duplicate(true)
		if cases.has(key):
			(cases[key] as Callable).call(cast)
		var P := PL.plan(v, cast)
		if post.has(key):
			(post[key] as Callable).call(P)
		fails = 0
		results.clear()
		_gate(v, P)
		var hit: bool = results.has(key) and not bool(results[key])
		print("[POP] 反向 %-10s → 狙った項目 %s（全 FAIL %d）%s" % [key, "FAIL" if hit else "PASS", fails, "" if hit else "  ← 不符預期"])
		if not hit:
			mism += 1
	quiet = false
	fails = mism
	print("[POP] 結果：%d 項失敗（negatives %d 案）" % [mism, cases.size() + post.size()])
	return mism


func _tps(v: Node3D, sp: PhysicsDirectSpaceState3D, vw: Dictionary) -> Transform3D:
	var pp := Vector2(vw["player"][0], vw["player"][1])
	var tt := Vector2(vw["target"][0], vw["target"][1])
	var gy := _ground(sp, pp)
	var f := (tt - pp).normalized()
	var b := Basis.from_euler(Vector3(float(vw["pitch"]), atan2(-f.x, -f.y), 0))
	var piv := Vector3(pp.x, gy + 1.70, pp.y)
	var dist := float(vw["dist"])
	var q := PhysicsRayQueryParameters3D.create(piv, piv + b * Vector3(0.0, 0.0, dist))
	var own := v.get_node_or_null(PL.PARENT)
	var ex: Array[RID] = []
	if own != null:
		for n in own.find_children("*", "AnimatableBody3D", true, false):
			ex.append((n as CollisionObject3D).get_rid())
	q.exclude = ex
	var hit := sp.intersect_ray(q)
	if not hit.is_empty():
		dist = maxf(0.6, piv.distance_to(hit.position) - 0.2)
	return Transform3D(b, piv + b * Vector3(0.40, 0.10, dist))


static func _ground(sp: PhysicsDirectSpaceState3D, p: Vector2) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 60.0, p.y), Vector3(p.x, -20.0, p.y))
	var ex: Array[RID] = []
	for k in 16:
		q.exclude = ex
		var hit := sp.intersect_ray(q)
		if hit.is_empty():
			break
		if String((hit.collider as Node).name).begins_with("TerrainCollision"):
			return hit.position.y
		ex.append(hit.rid)
	return 0.0


func _scene(v: Node3D) -> void:
	var txt := FileAccess.get_file_as_string(SCENE)
	var go := v.get_node_or_null(PL.PARENT + "/" + PL.NODE_NAME) as Node3D
	check("場景已掛 %s/%s（1 個、scene_file_path＝%s、visible）；Props の下ではない" % [PL.PARENT, PL.NODE_NAME, PL.OUTPUT],
		go != null and go.scene_file_path == PL.OUTPUT and go.is_visible_in_tree() and txt.count("gen/population_p10.tscn") == 1
		and v.get_node("Props").find_children(PL.NODE_NAME, "", true, false).is_empty())
	if go == null:
		return
	check("art_revision＝%s" % go.get_meta("art_revision", "?"), String(go.get_meta("art_revision", "")) == PL.ART_REVISION)
	# 封存 P10 overlay・P9 Vegetation はそのまま掛かっている
	var names: Array = []
	for c in v.get_node("Props").get_children():
		names.append(String(c.name))
	check("Props の子は不變（%s）" % " → ".join(names), names == ["MarketP10", "StreetP10", "MarketWestP10", "EnvironmentP9"])
	var bodies := go.find_children("*", "AnimatableBody3D", true, false)
	var RO := PL.roster()
	var ibad := []
	for b in bodies:
		var npc := b.get_node_or_null("NPC")
		var m := String(b.get_meta("model", ""))
		if npc == null or npc.scene_file_path != PL.npc_scene(m) or b.get_script() == null or String((b.get_script() as Script).resource_path) != PL.ACTOR \
				or npc.get("idle_clip") != (RO[m].get("idle_clip", "") if m != "chonin_m01" else "") or npc.get("walk_clip") != (RO[m].get("walk_clip", "") if m != "chonin_m01" else ""):
			ibad.append(String(b.name))
	check("NPC %d 人：封存 NPC 場景の instance（clip は Asset Library の Idle／Walk のまま、上書きなし）・行動スクリプト（違反 %s）" % [bodies.size(), str(ibad)], ibad.is_empty() and bodies.size() >= 12 and bodies.size() <= 18)
	var mbad := []
	for b in bodies:
		var npc := b.get_node("NPC")
		var original := (load(PL.npc_scene(String(b.get_meta("model")))) as PackedScene).instantiate()
		for mesh in npc.find_children("*", "MeshInstance3D", true, false):
			var m := mesh as MeshInstance3D
			var src := original.get_node_or_null(npc.get_path_to(m)) as MeshInstance3D
			var same := src != null and m.mesh == src.mesh and m.material_override == src.material_override and m.material_overlay == src.material_overlay
			if same:
				for j in m.get_surface_override_material_count():
					same = same and m.get_surface_override_material(j) == src.get_surface_override_material(j)
			if not same:
				mbad.append("%s/%s" % [b.name, m.name])
		original.free()
	check("Population instance 的 mesh／材質 override＝封存 wrapper 原值（不新增材質／貼圖覆寫；%s）" % str(mbad), mbad.is_empty())
	# 審圖鏡位ごとに見える同一モデル数 ≤ 2（視錐台・60 m 以内・頭への視線が建物で遮られない）
	var sp := v.get_world_3d().direct_space_state
	var views: Array = JSON.parse_string(FileAccess.get_file_as_string(VIEWS))
	var cam := Camera3D.new()
	cam.fov = 75.0
	root.add_child(cam)
	await process_frame
	check("審圖 viewport 1920×1080・FOV 75・projection 有效（與 runtime capture 相同）",
		root.size == Vector2i(1920, 1080) and absf(cam.get_camera_projection().determinant()) > 1e-8)
	var vbad := []
	var vinfo := []
	var ex: Array[RID] = []
	for b in bodies:
		ex.append((b as CollisionObject3D).get_rid())
	for vw: Dictionary in views:
		cam.global_transform = _tps(v, sp, vw)
		var cnt := {}
		var tot := 0
		for b in bodies:
			var head := (b as Node3D).global_position + Vector3(0, 1.4, 0)
			if not cam.is_position_in_frustum(head) or cam.global_position.distance_to(head) > 60.0:
				continue
			var q := PhysicsRayQueryParameters3D.create(cam.global_position, head)
			q.exclude = ex
			if not sp.intersect_ray(q).is_empty():
				continue
			var m := String(b.get_meta("model"))
			cnt[m] = int(cnt.get(m, 0)) + 1
			tot += 1
		var over := cnt.keys().filter(func(m: String) -> bool: return int(cnt[m]) > 2)
		vinfo.append("%s %d 人" % [vw["name"], tot])
		if not over.is_empty() or tot == 0:
			vbad.append("%s %s" % [vw["name"], str(cnt)])
	cam.queue_free()
	check("審圖鏡位：同一モデルが同じ鏡頭に 3 人以上いない、各鏡位に人が見える（%s；違反 %s）" % ["、".join(vinfo), str(vbad)], vbad.is_empty())
	# runtime 30 秒：逐名 walker 驗證移動、至少一次折返、XZ 路線及 Y 高度；Idle 不動。
	var start := {}
	var dirs := {}
	var reversed := {}
	var traveled := {}
	var prev := {}
	var max_y := {}
	var max_xz := {}
	var C := PL.context(v)
	for b in bodies:
		start[b] = (b as Node3D).global_position
		prev[b] = start[b]
		dirs[b] = int(b.get("_dir"))
		reversed[b] = false
		traveled[b] = 0.0
		max_y[b] = 0.0
		max_xz[b] = 0.0
	for i in 1800:
		await physics_frame
		if i % 30 != 0:
			continue
		for b in bodies:
			if String(b.get("mode")) != "patrol":
				continue
			var pos := (b as Node3D).global_position
			traveled[b] += (prev[b] as Vector3).distance_to(pos)
			prev[b] = pos
			reversed[b] = bool(reversed[b]) or int(b.get("_dir")) != int(dirs[b])
			var pts: PackedVector2Array = b.get("path_xz")
			var p2 := Vector2(pos.x, pos.z)
			var dd := INF
			for k in range(1, pts.size()):
				dd = minf(dd, _seg_d(p2, pts[k - 1], pts[k]))
			max_xz[b] = maxf(float(max_xz[b]), dd)
			max_y[b] = maxf(float(max_y[b]), absf(pos.y - PL.top_h(C, p2)))
	var rbad := []
	var moved := 0
	var reversed_n := 0
	var yerr := 0.0
	for b in bodies:
		var n3 := b as Node3D
		if String(b.get("mode")) == "patrol":
			var ys: PackedFloat32Array = b.get("path_y")
			var end: Vector3 = b.call("_sample", float(b.get("_len")))
			var end_err := absf(end.y - ys[ys.size() - 1])
			if float(max_xz[b]) > 0.05 or float(max_y[b]) > 0.03 or end_err > 1e-5 or not bool(reversed[b]) or float(traveled[b]) <= 1.0:
				rbad.append("%s XZ %.3f Y %.3f end %.6f reversed %s travel %.1f" % [b.name, max_xz[b], max_y[b], end_err, reversed[b], traveled[b]])
			if float(traveled[b]) > 1.0:
				moved += 1
			if bool(reversed[b]):
				reversed_n += 1
			yerr = maxf(yerr, float(max_y[b]))
		elif (start[b] as Vector3).distance_to(n3.global_position) > 0.001:
			rbad.append("%s Idle が動いた" % b.name)
	var nwalk := bodies.filter(func(b: Node) -> bool: return String(b.get("mode")) == "patrol").size()
	check("runtime 30 秒：walker %d/%d 移動、%d/%d 折返、XZ ≤ 5 cm／Y 最大 %.4f m ≤ 3 cm、末段端點正確、Idle 不動（%s）" % [moved, nwalk, reversed_n, nwalk, yerr, str(rbad)],
		rbad.is_empty() and moved == nwalk and reversed_n == nwalk)
	# SpringArm：NPC が玩家とカメラの間にいてもカメラ臂は縮まない（actor が node_added で除外を登録）
	var tgt := bodies[0] as Node3D
	var arm := SpringArm3D.new()
	arm.spring_length = 6.0
	arm.collision_mask = 1
	var piv := Node3D.new()
	root.add_child(piv)
	var p0 := tgt.global_position + Vector3(0, 1.0, 0) - Vector3(0, 0, 2.0)
	piv.global_transform = Transform3D(Basis(), p0)   # 臂は局所 +Z（世界 +Z）へ＝NPC を貫く
	piv.add_child(arm)
	for i in 4:
		await physics_frame
	var hl := arm.get_hit_length()
	var rq := PhysicsRayQueryParameters3D.create(p0, p0 + Vector3(0, 0, 6.0))
	var ctrl := sp.intersect_ray(rq)   # 對照：除外なしの射線は NPC に当たる
	rq.exclude = ex
	var want := sp.intersect_ray(rq)   # NPC を除いた時に臂が届くべき長さ
	var want_l := 6.0 if want.is_empty() else p0.distance_to(want.position)
	var ctrl_npc: bool = not ctrl.is_empty() and ctrl.collider == tgt
	check("SpringArm：NPC（%s）を貫く臂の長さ %.2f m＝NPC を除いた長さ %.2f m（對照：除外なしの射線は NPC に當たる＝%s）" % [tgt.name, hl, want_l, ctrl_npc],
		ctrl_npc and absf(hl - want_l) < 0.15)
	piv.queue_free()


func _seal_mismatch(seal: Dictionary) -> PackedStringArray:
	var repo := (ProjectSettings.globalize_path("res://") + "..").simplify_path() + "/"
	var bad := PackedStringArray()
	for group: String in ["frozen", "art_review_images", "evidence", "child_seals"]:
		var hashes: Dictionary = seal.get(group, {})
		if hashes.is_empty():
			bad.append("missing group " + group)
		for path: String in hashes:
			if not FileAccess.file_exists(repo + path) or FileAccess.get_sha256(repo + path) != String(hashes[path]):
				bad.append(path)
	return bad


func _seal_scope(tamper := false) -> bool:
	# Inspect PackedScene state without adding it to the tree: patrol _ready must not
	# replace approved initial position/facing before the baseline assertion.
	var world := (load(SCENE) as PackedScene).instantiate()
	var mount := world.get_node_or_null("Population/PopulationP10")
	var ok: bool = mount != null and mount.scene_file_path == PL.OUTPUT
	ok = ok and world.find_children("PopulationP10", "", true, false).size() == 1
	if mount != null:
		var actors := mount.find_children("*", "AnimatableBody3D", true, false)
		var baseline := (load(PL.OUTPUT) as PackedScene).instantiate()
		if tamper and not actors.is_empty():
			(actors[0] as Node3D).position.x += 0.25
		ok = ok and (mount as Node3D).transform == (baseline as Node3D).transform and (mount.get_parent() as Node3D).transform == Transform3D.IDENTITY
		ok = ok and (world as Node3D).transform == Transform3D.IDENTITY and (mount as Node3D).visible and (mount.get_parent() as Node3D).visible
		for actor in actors:
			var original := baseline.get_node_or_null(mount.get_path_to(actor))
			if original == null:
				ok = false
				continue
			ok = ok and (actor.get_parent() as Node3D).transform == (original.get_parent() as Node3D).transform and (actor.get_parent() as Node3D).visible
			for property: String in ["transform", "visible", "mode", "path_xz", "path_y", "walk_speed", "wait_min", "wait_max", "seed_i", "start_u", "collision_layer", "collision_mask"]:
				ok = ok and actor.get(property) == original.get(property)
			ok = ok and actor.get_meta_list() == original.get_meta_list()
			for key in original.get_meta_list():
				ok = ok and actor.get_meta(key, null) == original.get_meta(key)
			var npc := actor.get_node_or_null("NPC")
			var src_npc := original.get_node_or_null("NPC")
			if npc == null or src_npc == null:
				ok = false
				continue
			ok = ok and npc.scene_file_path == src_npc.scene_file_path
			for property: String in ["transform", "start_time", "speed_scale", "idle_clip", "walk_clip"]:
				ok = ok and npc.get(property) == src_npc.get(property)
		baseline.free()
		var zones := {}
		var idle := 0
		var patrol := 0
		for actor in actors:
			var zone := String(actor.get_meta("zone", ""))
			zones[zone] = int(zones.get(zone, 0)) + 1
			idle += int(String(actor.get("mode")) == "idle")
			patrol += int(String(actor.get("mode")) == "patrol")
		ok = ok and actors.size() == 16 and idle == 13 and patrol == 3
		ok = ok and zones.size() == 3 and zones.get("market", 0) == 7 and zones.get("market_west", 0) == 5 and zones.get("main_street", 0) == 4
	world.free()
	return ok


func _seal() -> int:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/village_v2_p10r3b_seal.json"))
	if not parsed is Dictionary:
		check("seal manifest exists and parses", false)
		return fails
	var seal: Dictionary = parsed
	# Diagnostic expected-fail run: tamper only the in-memory manifest, never disk.
	if "--seal-negative" in OS.get_cmdline_user_args():
		var key: String = (seal["frozen"] as Dictionary).keys()[0]
		seal["frozen"][key] = "f".repeat(64)
	check("status ART_APPROVED: user ruling 2026-10-06; not agent art approval", seal.get("status", "") == "ART_APPROVED" and seal.get("approved_by", "") == "user")
	var bad := _seal_mismatch(seal)
	var total := 0
	for group: String in ["frozen", "art_review_images", "evidence", "child_seals"]:
		total += (seal.get(group, {}) as Dictionary).size()
	check("seal %d hashes incl child seals: mismatch %d %s" % [total, bad.size(), str(bad)], bad.is_empty())
	check("baseline mount Population/PopulationP10 exact 1; 16 actors 7/5/4, 13 Idle + 3 patrol; world file NOT globally hash-locked", _seal_scope())
	check("permanent negative: in-memory mounted actor position override rejected", not _seal_scope(true))
	var snapshot = JSON.parse_string(FileAccess.get_file_as_string("res://data/village_v2_p10r3b_snapshot.json"))
	check("instance snapshot 16 identities/anchors/transforms/phases/params/endpoints bound to baked baseline", snapshot is Dictionary and (snapshot.get("actors", []) as Array).size() == 16 and snapshot.get("population_sha256", "") == FileAccess.get_sha256(PL.OUTPUT))
	var negative := seal.duplicate(true)
	var first: String = (negative["frozen"] as Dictionary).keys()[0]
	negative["frozen"][first] = "0".repeat(64)
	check("permanent negative: in-memory frozen hash tamper detected exactly once; no disk writes", _seal_mismatch(negative).size() == bad.size() + 1)
	var dep_negative := seal.duplicate(true)
	var child: String = (dep_negative["child_seals"] as Dictionary).keys()[0]
	dep_negative["child_seals"][child] = "0".repeat(64)
	check("permanent negative: in-memory child seal hash tamper detected exactly once", _seal_mismatch(dep_negative).size() == bad.size() + 1)
	print("[POP] 結果：%d 項失敗（seal）" % fails)
	return fails


func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(PL.OUTPUT):
		push_error("找不到 %s（先 --build）" % PL.OUTPUT)
		return 1
	if txt.contains("gen/population_p10.tscn"):
		push_error("已經掛過 PopulationP10")
		return 1
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	while lines.size() > 0 and lines[lines.size() - 1].strip_edges() == "":
		lines.remove_at(lines.size() - 1)
	var out := PackedStringArray(lines)
	out.append("")
	out.append("[node name=\"%s\" type=\"Node3D\" parent=\".\"]" % PL.PARENT)
	out.append("")
	out.append("[node name=\"%s\" parent=\"%s\" instance=ExtResource(\"p10r3b_population\")]" % [PL.NODE_NAME, PL.PARENT])
	out.append("")
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p10r3b_population\"]" % PL.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[POP] attach：加 %s/%s（village_v2 の末尾の新トップノード）→ %s" % [PL.PARENT, PL.NODE_NAME, SCENE])
	return 0
