extends SceneTree
## P10 R3e Outer Village Population Pilot gate（tag OUTER）。核心（R3b 16＋R3d 23、封存）＋外圍追加で検査。美術判定ではない。
##   godot --headless --path godot --script res://tools/verify_village_v2_population_outer.gd                 plan gate
##   godot --headless --path godot --script res://tools/verify_village_v2_population_outer.gd -- --negatives  永久反向
##   godot --headless --path godot --script res://tools/verify_village_v2_population_outer.gd -- --build      plan PASS 時のみ gen/population_outer_p10.tscn
##   godot --headless --path godot --script res://tools/verify_village_v2_population_outer.gd -- --attach     Population へ OuterP10＋ActivityOuterP10（EntranceCueP10 の後）
##   godot --path godot --script res://tools/verify_village_v2_population_outer.gd -- --scene                 場景級（掛載・人数・Activity 逐フレーム・審圖鏡位・歩く人・密度勾配）
##   -- --map／--probe=ID,...／--scan=x0,z0,x1,z1,step  調査用
##   -- --snapshot=<json>  封存用 snapshot（外圍 12 の id／model／zone／trade／位置／朝向／mode／patrol／activity、密度環、区域框）
##   -- --seal  封存（data/village_v2_p10r3e_seal.json：雜湊＋掛載順＋場景の住人＝snapshot＋区域框・密度環・森林／山腳 0 人＋竄改反向；R3e ART_APPROVED 2026-10-07）
##   封存中 --build／--attach は拒否（OUTER_ALLOW_REBAKE=1＝使用者が承認した collision／animation bug 修正のときだけ、その後 seal を更新）
const PL := preload("res://tools/village_v2_population_lib.gd")
const CL := preload("res://tools/village_v2_population_core_lib.gd")
const OL := preload("res://tools/village_v2_population_outer_lib.gd")
const VG := preload("res://tools/verify_village_v2_population.gd")
const VA := preload("res://tools/verify_p10_activity.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const VIEWS := "res://tools/shot_village_v2_population_outer_views.json"
const R3C_SEAL := "res://data/village_v2_p10r3c_seal.json"
const R3D_SEAL := "res://data/village_v2_p10r3d_seal.json"
## 市場の核心（主市集の中心）からの距離で密度を見る
const CENTER := Vector2(245.0, -40.0)
const RINGS := [0.0, 40.0, 90.0, 150.0, 260.0]
## 外圍の区域（xz の箱）：森林・山腳・偏僻路段の箱は無い＝そこへ置けば FAIL
const ZONE_BOX := {
	"farm": Rect2(300.0, -115.0, 40.0, 150.0),
	"waterwheel": Rect2(320.0, -60.0, 20.0, 20.0),
	"canal": Rect2(305.0, -40.0, 35.0, 90.0),
	"alley": Rect2(255.0, -95.0, 35.0, 25.0),
	"shrine": Rect2(280.0, -175.0, 20.0, 35.0),
}
const ZONE_RANGE := {"farm": [3, 5], "waterwheel": [1, 2], "canal": [1, 3], "alley": [2, 3], "shrine": [1, 2]}
const TWIN_MIN := 8.0
const SEAL := "res://data/village_v2_p10r3e_seal.json"
const SNAPSHOT := "res://data/village_v2_p10r3e_snapshot.json"
const CORE_SNAPSHOT := "res://data/village_v2_p10r3d_snapshot.json"

var fails := 0
var failed := []
var quiet := false
var helper: SceneTree


func check(label: String, ok: bool, key := "") -> void:
	if not quiet:
		print("[OUTER] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
		failed.append(key if key != "" else label)


func _initialize() -> void:
	_run.call_deferred()


func _d2(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _pts(a: Dictionary) -> PackedVector2Array:
	if a["mode"] == "patrol":
		var out := PackedVector2Array()
		var pts: PackedVector2Array = a["path_xz"]
		for i in range(1, pts.size()):
			var n := int(ceil(pts[i - 1].distance_to(pts[i]) / 0.5))
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


func _vocab() -> Array:
	var seal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(R3C_SEAL))
	var out := []
	for k: String in seal["assignments"]:
		var s: Dictionary = seal["assignments"][k]
		out.append(JSON.stringify([s["type"], s["npc"], s["clip"], s["slot"], s["options"]]))
	return out


## 環（市場の核心からの距離）ごとの人口密度（人／1000 m²）
static func ring_density(pts: Array) -> Array:
	var cnt := []
	cnt.resize(RINGS.size() - 1)
	cnt.fill(0)
	for p: Vector2 in pts:
		var d := p.distance_to(CENTER)
		for i in range(RINGS.size() - 1):
			if d >= float(RINGS[i]) and d < float(RINGS[i + 1]):
				cnt[i] += 1
	var out := []
	for i in range(RINGS.size() - 1):
		var area := PI * (pow(float(RINGS[i + 1]), 2) - pow(float(RINGS[i]), 2))
		out.append([int(cnt[i]), snappedf(1000.0 * cnt[i] / area, 0.001)])
	return out


func _gate(v: Node3D, P: Dictionary, B: Array, assign: Dictionary) -> int:
	var f0 := fails
	var A: Array = P["actors"]
	var C: Dictionary = P["C"]
	var sp := v.get_world_3d().direct_space_state
	var ALL: Array = B + A
	# 1 人数・区域
	var zc := {}
	for a: Dictionary in A:
		zc[a["zone"]] = int(zc.get(a["zone"], 0)) + 1
	var zbad := ZONE_RANGE.keys().filter(func(z: String) -> bool: return int(zc.get(z, 0)) < int(ZONE_RANGE[z][0]) or int(zc.get(z, 0)) > int(ZONE_RANGE[z][1]))
	check("人數：外圍 %d（10–16）、核心 %d＋外圍＝%d；區域 %s（農田 3–5・水車 1–2・水渠／橋 1–3・後巷 2–3・神社外 1–2；違反 %s）" % [A.size(), B.size(), ALL.size(), str(zc), str(zbad)],
		A.size() >= 10 and A.size() <= 16 and zbad.is_empty() and zc.keys().all(func(z: String) -> bool: return ZONE_RANGE.has(z)), "count")
	# 2 範囲（森林・山腳・偏僻路段へ置かない）
	var obad := []
	for a: Dictionary in A:
		var box: Rect2 = ZONE_BOX.get(a["zone"], Rect2())
		for q in _pts(a):
			if not box.has_point(q):
				obad.append("%s(%.1f,%.1f)" % [a["id"], q.x, q.y])
				break
	check("範圍：全員が自分の外圍区域の箱の中（森林・山腳・偏僻路段には置かない；違反 %s）" % str(obad), obad.is_empty(), "zone")
	# 3 密度勾配：市場の核心から離れるほど薄い（環ごとの密度が単調に下がる）
	var pts := []
	for a: Dictionary in ALL:
		var q := _pts(a)
		pts.append(q[q.size() / 2])
	var rd := ring_density(pts)
	var mono := true
	for i in range(1, rd.size()):
		mono = mono and (float(rd[i][1]) < float(rd[i - 1][1]))
	check("密度勾配：市場の核心 (245,−40) からの環 0–40／40–90／90–150／150–260 m の人／1000 m² ＝ %s（単調に下がる；核心の外 3 環に計 ≥ 10 人、一番外の環は無人でもよい）" % str(rd.map(func(r: Array) -> String: return "%d 人 %.3f" % [r[0], r[1]])),
		mono and int(rd[1][0]) + int(rd[2][0]) + int(rd[3][0]) >= 10, "gradient")
	# 4 外圍は群れない：外圍の人の 6 m 以内にいる他人 ≤ 1（二人組まで）
	var lbad := []
	for a: Dictionary in A:
		var n := 0
		for b: Dictionary in ALL:
			if a != b and _min_d(a, b) < 6.0:
				n += 1
		if n > 1:
			lbad.append("%s %d 人" % [a["id"], n])
	check("外圍は群れない：外圍の各人の 6 m 以内の他人 ≤ 1（違反 %s）" % str(lbad), lbad.is_empty(), "sparse")
	# 5 anchor
	var bad_a := A.filter(func(a: Dictionary) -> bool: return a.has("error") or not ResourceLoader.exists(PL.npc_scene(a["model"])))
	var used := {}
	for b: Dictionary in B:
		if String(b["anchor"]) != "":
			used[b["anchor"]] = b["id"]
	var dup := []
	for a: Dictionary in A:
		var an := String(a["anchor"])
		if an == "":
			continue
		if used.has(an):
			dup.append("%s=%s" % [a["id"], used[an]])
		used[an] = a["id"]
	check("anchor：封存 overlay の Marker を読めた（欠落 %s）、核心・互いと重複しない（重複 %s）" % [str(bad_a.map(func(a: Dictionary) -> String: return a["id"])), str(dup)],
		bad_a.is_empty() and dup.is_empty(), "anchor")
	if not bad_a.is_empty():
		return fails - f0
	# 6 職業・歩く人
	var bad_r := A.filter(func(a: Dictionary) -> bool: return not (a["trade"] in OL.ROLE_OK.get(a["model"], [])))
	check("職業對位（違反 %s）" % str(bad_r.map(func(a: Dictionary) -> String: return "%s %s→%s" % [a["id"], a["model"], a["trade"]])), bad_r.is_empty(), "role")
	var walkers := A.filter(func(a: Dictionary) -> bool: return a["mode"] == "patrol")
	var wbad := walkers.filter(func(a: Dictionary) -> bool: return a["model"] in OL.NO_WALK)
	check("歩く人 %d（≤ 3）：婆婆は Walk 0（違反 %s）" % [walkers.size(), str(wbad.map(func(a: Dictionary) -> String: return a["id"]))], wbad.is_empty() and walkers.size() <= 3, "walk_rule")
	# 7 同一モデルの間隔（外圍が絡む組）
	var near := []
	var dmin := INF
	for i in ALL.size():
		for j in range(i + 1, ALL.size()):
			if ALL[i]["model"] == ALL[j]["model"] and (i >= B.size() or j >= B.size()):
				var d := _min_d(ALL[i], ALL[j])
				dmin = minf(dmin, d)
				if d < TWIN_MIN:
					near.append("%s-%s %.1f m" % [ALL[i]["id"], ALL[j]["id"], d])
	check("同一モデルは隣接しない：外圍が絡む同モデル間の最短 %.1f m（≥ %.0f；違反 %s）" % [dmin, TWIN_MIN, str(near)], near.is_empty(), "twin")
	# 8 接地
	var gbad := []
	var gmax := 0.0
	for a: Dictionary in A:
		if a["mode"] != "idle":
			continue
		var p: Vector3 = a["p"]
		var e := absf(p.y - PL.top_h(C, Vector2(p.x, p.z)))
		gmax = maxf(gmax, e)
		if e > 0.03:
			gbad.append("%s %.2f" % [a["id"], e])
	check("接地：外圍 Idle の足元と見えている最上面の差 最大 %.3f m（≤ 0.03；違反 %s）" % [gmax, str(gbad)], gbad.is_empty(), "ground")
	# 9 体の衝突・水に入らない
	var cbad := []
	for a: Dictionary in A:
		if a["mode"] != "idle":
			continue
		var h := (C["RI"] as PL.RenderIndex).body_hits(a["p"], float(a["height"]), PL.CAP_R)
		h.append_array(helper._hits(v, sp, a["p"], float(a["height"])))
		if not h.is_empty():
			cbad.append("%s→%s" % [a["id"], str(h.slice(0, 2))])
	check("體の衝突：外圍 Idle の capsule が建物・稲架・橋・柵（描画三角形＋衝突體）に入らない（違反 %s）" % str(cbad), cbad.is_empty(), "body")
	# 10 往復路
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
			var hp := Vector3(q.x, ys[mini(j2, ys.size() - 1)], q.y)
			var h: Array = helper._hits(v, sp, hp, float(a["height"]))
			h.append_array((C["RI"] as PL.RenderIndex).body_hits(hp, float(a["height"]), PL.CAP_R))
			if not h.is_empty():
				hit.append("%.1f m %s" % [j2 * 0.25, str(h.slice(0, 1))])
			j2 += 1
		if not hit.is_empty() or step > 0.10 or L < 6.0 or L > 20.0:
			rbad.append("%s 衝突 %s 段差 %.2f 長 %.1f" % [a["id"], str(hit.slice(0, 2)), step, L])
	check("往復路 %d 本：衝突體・描畫三角形に入らない・段差 ≤ 0.10 m・長さ 6–20 m（違反 %s）" % [walkers.size(), str(rbad)], rbad.is_empty(), "path")
	var sbad := []
	for a: Dictionary in walkers:
		var r := float(a["walk_speed"]) / maxf(float(a["walk"]["speed"]), 1e-4)
		if absf(r - 1.0) > 0.03:
			sbad.append("%s 比 %.2f" % [a["id"], r])
	check("歩速＝Walk clip の足の接地速度（滑り ≤ 3 %%、違反 %s）" % str(sbad), sbad.is_empty(), "speed")
	# 11 Activity：封存 vocabulary だけ
	var voc := _vocab()
	var names := {}
	for a: Dictionary in A:
		names["%s/%s_%s" % [OL.ZONE_NODE[a["zone"]], a["id"], a["model"]]] = a
	var vbad := []
	var types := {}
	for path: String in assign:
		var e: Array = assign[path]
		var key := JSON.stringify([e[0], e[1], e[2], e[3], e[4] if e.size() > 4 else {}])
		if not voc.has(key) or not names.has(path) or String(names[path]["model"]) != String(e[1]) or String(names[path]["mode"]) == "patrol":
			vbad.append(path)
		types[e[0]] = int(types.get(e[0], 0)) + 1
	check("Activity：%d 件・%s が R3c／R3c.1 封存 vocabulary と一致・外圍の実在の Idle の住人（違反 %s）" % [assign.size(), str(types), str(vbad)], vbad.is_empty(), "vocab")
	# 12 封存は読むだけ（R3b・R3c・R3d）
	var hb := []
	var d_seal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(R3D_SEAL))
	var repo := (ProjectSettings.globalize_path("res://") + "..").simplify_path() + "/"
	for k: String in d_seal["frozen"]:
		if FileAccess.get_sha256(repo + k) != String(d_seal["frozen"][k]):
			hb.append(k.get_file())
	for k: String in d_seal["child_seals"]:
		if FileAccess.get_sha256(repo + k) != String(d_seal["child_seals"][k]):
			hb.append(k.get_file())
	check("封存は読むだけ：R3d の凍結 %d 件と子封存（R3b・R3c・NPCLIB）の雜湊＝封存時（違い %s）" % [(d_seal["frozen"] as Dictionary).size(), str(hb)], hb.is_empty(), "sealed")
	return fails - f0


func _map(P: Dictionary, B: Array) -> void:
	var ALL: Array = B + P["actors"]
	for a: Dictionary in P["actors"]:
		var best := INF
		var who := ""
		var twin := INF
		for b: Dictionary in ALL:
			if a == b:
				continue
			var d := _min_d(a, b)
			if d < best:
				best = d
				who = b["id"]
			if b["model"] == a["model"]:
				twin = minf(twin, d)
		var p: Vector3 = a.get("p", Vector3.ZERO)
		print("[OUTER] MAP %-4s %-10s %-12s %-9s %-6s (%.1f, %.2f, %.1f) yaw %4.0f 核心から %.0f m 最近 %s %.1f m 同モデル %.1f m" % [a["id"], a["zone"], a["model"], a["trade"], a["mode"],
			p.x, p.y, p.z, rad_to_deg(float(a.get("yaw", 0.0))), Vector2(p.x, p.z).distance_to(CENTER), who, best, twin])


func _probe(v: Node3D, P: Dictionary, ids: PackedStringArray) -> void:
	var sp := v.get_world_3d().direct_space_state
	var C: Dictionary = P["C"]
	for a: Dictionary in P["actors"]:
		if not ids.has(String(a["id"])):
			continue
		var p0: Vector3 = a["p"]
		var cands := []
		for ix in range(-10, 11):
			for iz in range(-10, 11):
				var o := Vector2(ix, iz) * 0.2
				if o.length() > 2.0:
					continue
				var p2 := Vector2(p0.x + o.x, p0.z + o.y)
				var p3 := Vector3(p2.x, PL.top_h(C, p2), p2.y)
				var h := (C["RI"] as PL.RenderIndex).body_hits(p3, float(a["height"]), PL.CAP_R)
				h.append_array(helper._hits(v, sp, p3, float(a["height"])))
				if h.is_empty():
					cands.append([o.length(), o, p3.y])
		cands.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
		print("[OUTER] PROBE %s at (%.1f,%.2f,%.1f) 候補 %d：%s" % [a["id"], p0.x, p0.y, p0.z, cands.size(), str(cands.slice(0, 6).map(func(c: Array) -> String: return "(%.1f,%.1f h%.2f)" % [(c[1] as Vector2).x, (c[1] as Vector2).y, c[2]]))])


func _negatives(v: Node3D, B: Array) -> int:
	var by := func(c: Array, id: String) -> Dictionary:
		for e: Dictionary in c:
			if String(e["id"]) == id:
				return e
		return {}
	var cases := {
		"count": func(c: Array) -> void:                                                     # 外圍に核心並みの人数（＋10）
			for k in 10:
				var e: Dictionary = by.call(c, "O1").duplicate(true)
				e["id"] = "X%d" % k
				e["anchor"] = ""
				e["at"] = [318.0 + (k % 5) * 1.5, -20.0 - (k / 5) * 1.5, 0.0]
				c.append(e),
		"zone": func(c: Array) -> void: by.call(c, "O12")["at"] = [258.0, -200.0, 0.0],        # 神社の婆を山腳の森へ
		"gradient": func(c: Array) -> void:                                                  # 外圍の全員を一番外の環へ集める
			for e: Dictionary in c:
				if e.has("anchor") and String(e["anchor"]) != "":
					e["anchor"] = ""
				e.erase("path")
				e["mode"] = "idle"
				e["at"] = [300.0 + c.find(e) * 0.0, -160.0 - c.find(e) * 0.9, 0.0],
		"sparse": func(c: Array) -> void: by.call(c, "O11")["anchor"] = ""; by.call(c, "O11")["at"] = [269.0, -90.0, 0.0],   # 井戸端に三人目
		"role": func(c: Array) -> void: by.call(c, "O1")["trade"] = "pilgrim",
		"walk_rule": func(c: Array) -> void: by.call(c, "O12")["mode"] = "patrol"; by.call(c, "O12")["path"] = [[292.0, -152.0], [292.0, -160.0]],
		"twin": func(c: Array) -> void: by.call(c, "O6")["model"] = "sakanaya_m01"; by.call(c, "O6")["trade"] = "fisher",
		"body": func(c: Array) -> void: by.call(c, "O11")["off"] = [1.5, 0.0],
		"anchor": func(c: Array) -> void: by.call(c, "O9")["anchor"] = "StreetP10/st_vendor_MKT_024",
		"path": func(c: Array) -> void: by.call(c, "O3")["path"] = [[306.0, 17.0], [309.0, 21.0], [312.0, 25.5]],   # 畦の往復を稲架の中へ
	}
	var post := {
		"ground": func(P: Dictionary) -> void:
			for a: Dictionary in P["actors"]:
				if String(a["id"]) == "O4":
					a["p"] += Vector3(0, 0.2, 0),
		"speed": func(P: Dictionary) -> void:
			for a: Dictionary in P["actors"]:
				if String(a["id"]) == "O3":
					a["walk_speed"] *= 1.3,
	}
	var assign_cases := {
		"vocab": func(d: Dictionary) -> void: d["Farm/O1_takigi_m01"] = ["Carry", "takigi_m01", "box_idle_a030", "idle"],   # 承認されていない組（takigi の Carry は R3c で淘汰）
	}
	var mism := 0
	quiet = true
	for key: String in cases.keys() + post.keys() + assign_cases.keys():
		var cast: Array = OL.CAST.duplicate(true)
		if cases.has(key):
			(cases[key] as Callable).call(cast)
		var P := OL.plan(v, cast)
		if post.has(key):
			(post[key] as Callable).call(P)
		var assign: Dictionary = OL.ASSIGN.duplicate(true)
		if assign_cases.has(key):
			(assign_cases[key] as Callable).call(assign)
		fails = 0
		failed.clear()
		_gate(v, P, B, assign)
		var hit := failed.has(key)
		quiet = false
		print("[OUTER] %s 反向 %s → 「%s」必須 FAIL（失敗項 %s）" % ["PASS" if hit else "FAIL", key, key, str(failed)])
		quiet = true
		if not hit:
			mism += 1
	quiet = false
	print("[OUTER] 結果：%d 項失敗（negatives）" % mism)
	return mism


## 往復路は全長の中点、Idle は立ち位置（密度環の代表点；snapshot と seal で同じ規則）
static func _poly_mid(pts: PackedVector2Array) -> Vector2:
	var L := 0.0
	for i in range(1, pts.size()):
		L += pts[i].distance_to(pts[i - 1])
	return PL._along(pts, L * 0.5)


static func _rec_point(r: Dictionary) -> Vector2:
	if r.has("patrol"):
		var pts := PackedVector2Array()
		for q: Array in r["patrol"]["path"]:
			pts.append(Vector2(float(q[0]), float(q[1])))
		return _poly_mid(pts)
	var pos: Array = r["position"]
	return Vector2(float(pos[0]), float(pos[2]))


func _actor_rec(a: Dictionary) -> Dictionary:
	var p: Vector3 = a["p"]
	var r := {"id": a["id"], "model": a["model"], "zone": a["zone"], "trade": a["trade"], "group": a["group"], "anchor": a["anchor"], "mode": a["mode"],
		"position": [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)], "yaw_deg": snappedf(rad_to_deg(float(a["yaw"])), 0.01),
		"anim_start_time": snappedf(fmod(float(a["idle_t"]) + 2.7, 6.0), 0.001), "speed_scale": a["speed_scale"], "seed_i": int(a["seed"]) + 7}
	if a["mode"] == "patrol":
		var pts: PackedVector2Array = a["path_xz"]
		r["patrol"] = {"endpoints": [[pts[0].x, pts[0].y], [pts[pts.size() - 1].x, pts[pts.size() - 1].y]], "path": Array(pts).map(func(q: Vector2) -> Array: return [q.x, q.y]),
			"length_m": snappedf(float(a["path_len"]), 0.01), "walk_speed": a["walk_speed"], "wait": a["wait"], "start_u": a["start_u"]}
	var key := "%s/%s_%s" % [OL.ZONE_NODE.get(a["zone"], ""), a["id"], a["model"]]
	if OL.ASSIGN.has(key):
		var e: Array = OL.ASSIGN[key]
		r["activity"] = {"type": e[0], "clip": e[2], "slot": e[3], "options": e[4] if e.size() > 4 else {}}
	r["distance_from_core_m"] = snappedf(_rec_point(r).distance_to(CENTER), 0.1)
	return r


func _snapshot(P: Dictionary, path: String) -> void:
	var zc := {}
	for a: Dictionary in P["actors"]:
		zc[a["zone"]] = int(zc.get(a["zone"], 0)) + 1
	var recs: Array = (P["actors"] as Array).map(func(a: Dictionary) -> Dictionary: return _actor_rec(a))
	var core: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CORE_SNAPSHOT))
	var pts := []
	for r: Dictionary in (core["r3b_baseline"] as Array) + (core["r3d_added"] as Array) + recs:
		pts.append(_rec_point(r))
	var boxes := {}
	for z: String in ZONE_BOX:
		var rb: Rect2 = ZONE_BOX[z]
		boxes[z] = [rb.position.x, rb.position.y, rb.size.x, rb.size.y]
	var out := {"schema": 1, "scope": "P10 R3e 外圍人口 12（核心 39＝R3d 封存 snapshot を密度計算に参照）",
		"outer_total": recs.size(), "core_total": int(core["total"]), "total": int(core["total"]) + recs.size(), "zone_counts": zc, "outer": recs,
		"density_bands": {"center_xz": [CENTER.x, CENTER.y], "rings_m": RINGS, "measured_people_per_1000m2": ring_density(pts),
			"rule": "核心 (245,−40) からの環ごとの人／1000 m² が外へ単調に下がる；150–260 m（森林・山腳）は 0 人"},
		"zone_boxes": boxes, "zone_ranges": ZONE_RANGE,
		"forbidden": "森林・山腳・偏僻路段には区域框が無い＝置けない（範圍 gate／seal）；150–260 m の環は 0 人"}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " ", false) + "\n")
	f.close()
	print("[OUTER] snapshot → %s（外圍 %d、合計 %d、密度 %s）" % [path, recs.size(), out["total"], str(out["density_bands"]["measured_people_per_1000m2"])])


func _sealed() -> bool:
	if not FileAccess.file_exists(SEAL):
		return false
	var j = JSON.parse_string(FileAccess.get_file_as_string(SEAL))
	return j is Dictionary and String(j.get("status", "")) == "ART_APPROVED"


func _seal_mismatch(seal: Dictionary) -> Array:
	var repo := (ProjectSettings.globalize_path("res://") + "..").simplify_path() + "/"
	var bad := []
	for grp: String in ["frozen", "evidence", "art_review_images", "child_seals"]:
		var d: Dictionary = seal.get(grp, {})
		for k: String in d:
			if not FileAccess.file_exists(repo + k) or FileAccess.get_sha256(repo + k) != String(d[k]):
				bad.append(k)
	return bad


## 場景の外圍住人が snapshot と一致（Idle：位置 1 cm・朝向 0.5°；全員：mode・model；patrol：端点 1 cm）
func _live_mismatch(v: Node3D, snap: Dictionary) -> Array:
	var bad := []
	var outer := v.get_node_or_null("Population/" + OL.NODE_NAME)
	if outer == null:
		return ["OuterP10 が無い"]
	var bodies := {}
	for b in outer.find_children("*", "AnimatableBody3D", true, false):
		bodies[String(b.name).split("_")[0]] = b
	if bodies.size() != (snap["outer"] as Array).size():
		bad.append("人数 %d≠%d" % [bodies.size(), (snap["outer"] as Array).size()])
	for r: Dictionary in snap["outer"]:
		var b: Node3D = bodies.get(String(r["id"]))
		if b == null:
			bad.append(String(r["id"]) + " 無い")
			continue
		var pos: Array = r["position"]
		var idle_off: bool = String(r["mode"]) == "idle" and (b.global_position.distance_to(Vector3(pos[0], pos[1], pos[2])) > 0.01 \
			or absf(angle_difference(b.global_rotation.y, deg_to_rad(float(r["yaw_deg"])))) > deg_to_rad(0.5))
		if idle_off or String(b.get("mode")) != String(r["mode"]) or String(b.get_meta("model")) != String(r["model"]):
			bad.append(String(r["id"]))
		if r.has("patrol"):
			var pts: PackedVector2Array = b.get("path_xz")
			var ep: Array = r["patrol"]["endpoints"]
			if pts.size() < 2 or pts[0].distance_to(Vector2(ep[0][0], ep[0][1])) > 0.01 or pts[pts.size() - 1].distance_to(Vector2(ep[1][0], ep[1][1])) > 0.01:
				bad.append(String(r["id"]) + " patrol")
	return bad


## 規則：外圍の全員が区域框の中（森林・山腳・偏僻路段に框は無い）、密度環が外へ単調に下がる、150–260 m は 0 人、環の人数＝snapshot
func _rule_mismatch(snap: Dictionary) -> Array:
	var bad := []
	var core: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CORE_SNAPSHOT))
	var pts := []
	for r: Dictionary in (core["r3b_baseline"] as Array) + (core["r3d_added"] as Array):
		pts.append(_rec_point(r))
	for r: Dictionary in snap["outer"]:
		var q := _rec_point(r)
		pts.append(q)
		var box: Array = (snap["zone_boxes"] as Dictionary).get(String(r["zone"]), [])
		if box.size() != 4 or not Rect2(float(box[0]), float(box[1]), float(box[2]), float(box[3])).has_point(q):
			bad.append("%s 区域框の外 (%.1f,%.1f)" % [r["id"], q.x, q.y])
	var rd := ring_density(pts)
	for i in range(1, rd.size()):
		if float(rd[i][1]) >= float(rd[i - 1][1]):
			bad.append("密度が下がらない 環 %d" % i)
	if int(rd[rd.size() - 1][0]) != 0:
		bad.append("150–260 m（森林・山腳）に %d 人" % int(rd[rd.size() - 1][0]))
	var meas: Array = snap["density_bands"]["measured_people_per_1000m2"]
	for i in rd.size():
		if int(rd[i][0]) != int(meas[i][0]):
			bad.append("環 %d の人数 %d≠snapshot %d" % [i, int(rd[i][0]), int(meas[i][0])])
	return bad


func _seal(v: Node3D) -> int:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SEAL))
	if not parsed is Dictionary:
		check("seal manifest が読める", false)
		return 2
	var seal: Dictionary = parsed
	check("status ART_APPROVED（使用者 2026-10-07；agent は美術を承認しない）", String(seal.get("status", "")) == "ART_APPROVED" and String(seal.get("approved_by", "")) == "user")
	var bad := _seal_mismatch(seal)
	var n := 0
	for grp: String in ["frozen", "evidence", "art_review_images", "child_seals"]:
		n += (seal.get(grp, {}) as Dictionary).size()
	check("封存 %d 檔雜湊一致（凍結・證據・審圖・子封存 R3d／R3c／R3b／NPCLIB；不符 %d：%s）" % [n, bad.size(), str(bad.slice(0, 4))], bad.is_empty())
	var txt := FileAccess.get_file_as_string(SCENE)
	var order := ["PopulationP10", "ActivityP10", CL.NODE_NAME, CL.ACT_NODE, "EntranceCueP10", OL.NODE_NAME, OL.ACT_NODE]
	var last := -1
	var ok_m := true
	for nm: String in order:
		var lines := Array(txt.split("\n")).filter(func(l: String) -> bool: return l.begins_with("[node name=\"%s\"" % nm) and l.contains("parent=\"Population\""))
		ok_m = ok_m and lines.size() == 1
		var at := txt.find(String(lines[0])) if lines.size() == 1 else -1
		ok_m = ok_m and at > last
		last = at
	check("掛載：Population の %s（各 1 つ、この順）" % " → ".join(order), ok_m)
	var snap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT))
	var zc: Dictionary = snap["zone_counts"]
	var zr_ok := true
	for z: String in ZONE_RANGE:
		zr_ok = zr_ok and int(zc.get(z, 0)) >= int(ZONE_RANGE[z][0]) and int(zc.get(z, 0)) <= int(ZONE_RANGE[z][1])
	check("snapshot：外圍 %d（12）・核心 %d（39）・合計 %d（51）、區域 %s が範圍内" % [int(snap["outer_total"]), int(snap["core_total"]), int(snap["total"]), str(zc)],
		int(snap["outer_total"]) == 12 and int(snap["core_total"]) == 39 and int(snap["total"]) == 51 and zr_ok)
	var lb := _live_mismatch(v, snap)
	check("場景の外圍住人 12 が snapshot と一致（Idle 位置 ≤ 1 cm・朝向 ≤ 0.5°・mode・model・patrol 端点；不符 %s）" % str(lb), lb.is_empty())
	var rb := _rule_mismatch(snap)
	check("規則：区域框の中（森林・山腳・偏僻路段に框なし）・密度環が外へ単調に下がる・150–260 m は 0 人・環の人数＝snapshot（違反 %s）" % str(rb), rb.is_empty())
	var tam := seal.duplicate(true)
	var k0: String = (tam["frozen"] as Dictionary).keys()[0]
	tam["frozen"][k0] = "0".repeat(64)
	check("反向：凍結雜湊を記憶體内で竄改 → 1 件だけ検出（%d）" % (_seal_mismatch(tam).size() - bad.size()), _seal_mismatch(tam).size() == bad.size() + 1)
	var s2: Dictionary = snap.duplicate(true)
	for r: Dictionary in s2["outer"]:
		if String(r["id"]) == "O1":
			r["position"][0] = float(r["position"][0]) + 0.25
	check("反向：snapshot の Idle 住人を 0.25 m ずらす → 不一致を検出", not _live_mismatch(v, s2).is_empty())
	var s3: Dictionary = snap.duplicate(true)
	for r: Dictionary in s3["outer"]:
		if String(r["id"]) == "O12":
			r["position"] = [258.0, 30.0, -200.0]
	check("反向：神社の婆を山腳の森 (258,−200) へ → 区域框・150–260 m 0 人の規則が FAIL", not _rule_mismatch(s3).is_empty())
	print("[OUTER] 結果：%d 項失敗（seal）" % fails)
	return 0 if fails == 0 else 2


func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(OL.OUTPUT):
		push_error("找不到 %s（先 --build）" % OL.OUTPUT)
		return 1
	if txt.contains("gen/population_outer_p10.tscn"):
		push_error("已經掛過 OuterP10")
		return 1
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var key := "[node name=\"EntranceCueP10\" parent=\"Population\""
	var i := txt.find(key)
	if i < 0 or txt.count(key) != 1:
		push_error("EntranceCueP10 の掛載行が 1 つではない")
		return 1
	var j := txt.find(nl + "[", i + 1)
	var block_end := txt.length() if j < 0 else j + nl.length()
	var ins := "[node name=\"%s\" parent=\"Population\" instance=ExtResource(\"p10r3e_outer\")]%s%s" % [OL.NODE_NAME, nl, nl] + \
		"[node name=\"%s\" type=\"Node3D\" parent=\"Population\"]%sscript = ExtResource(\"p10r3e_act\")%s" % [OL.ACT_NODE, nl, nl]
	if j < 0:
		ins = nl + ins
	else:
		ins += nl
	txt = txt.substr(0, block_end) + ins + txt.substr(block_end)
	var lines := txt.split(nl)
	var last_ext := -1
	for k in lines.size():
		if lines[k].begins_with("[ext_resource"):
			last_ext = k
	lines.insert(last_ext + 1, "[ext_resource type=\"Script\" path=\"%s\" id=\"p10r3e_act\"]" % OL.ACT_SCRIPT)
	lines.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p10r3e_outer\"]" % OL.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(lines))
	f.close()
	print("[OUTER] attach：Population/%s＋%s（EntranceCueP10 の後）→ %s" % [OL.NODE_NAME, OL.ACT_NODE, SCENE])
	return 0


func _scene(v: Node3D) -> void:
	var txt := FileAccess.get_file_as_string(SCENE)
	var order := ["PopulationP10", "ActivityP10", CL.NODE_NAME, CL.ACT_NODE, "EntranceCueP10", OL.NODE_NAME, OL.ACT_NODE]
	var last := -1
	var ok_m := true
	for nm: String in order:
		var lines := Array(txt.split("\n")).filter(func(l: String) -> bool: return l.begins_with("[node name=\"%s\"" % nm) and l.contains("parent=\"Population\""))
		ok_m = ok_m and lines.size() == 1
		var at := txt.find(String(lines[0])) if lines.size() == 1 else -1
		ok_m = ok_m and at > last
		last = at
	check("掛載：Population の %s（各 1 つ、この順）" % " → ".join(order), ok_m, "mount")
	for i in 30:
		await process_frame
	var outer := v.get_node_or_null("Population/" + OL.NODE_NAME)
	var bodies := outer.find_children("*", "AnimatableBody3D", true, false) if outer else []
	var all_b := v.get_node("Population").find_children("*", "AnimatableBody3D", true, false)
	check("人數：OuterP10 %d（＝配役 %d）、Population 全体 %d（核心 39＋外圍）" % [bodies.size(), OL.CAST.size(), all_b.size()],
		bodies.size() == OL.CAST.size() and all_b.size() == 39 + OL.CAST.size(), "count")
	var act := v.get_node_or_null("Population/" + OL.ACT_NODE)
	var entries: Array = act.get("entries") if act else []
	var ebad := []
	for e: Dictionary in entries:
		var ap: AnimationPlayer = e.ap
		if ap.get_animation(StringName(e.slot)) != e.clip or not ap.is_playing():
			ebad.append(String(e.path))
	check("Activity：%d 件（＝割り當て %d）が承認 clip を再生（違反 %s）" % [entries.size(), OL.ASSIGN.size(), str(ebad)], act != null and entries.size() == OL.ASSIGN.size() and ebad.is_empty(), "activity")
	var sp := v.get_world_3d().direct_space_state
	var ex: Array[RID] = []
	for b in all_b:
		ex.append((b as CollisionObject3D).get_rid())
	for e: Dictionary in entries:
		if e.has("body") and e.body != null:
			ex.append((e.body as CollisionObject3D).get_rid())
	# R3c と同じ逐フレーム検査
	var va: SceneTree = VA.new()
	var ri := PL.RenderIndex.new(v)
	var fbad := []
	var finfo := []
	for e: Dictionary in entries:
		var ap: AnimationPlayer = e.ap
		ap.play(StringName(e.slot))
		ap.speed_scale = 0.0
		var rest := {}
		for bn in ["LeftFoot", "RightFoot", "LeftToes", "RightToes"]:
			rest[bn] = (e.sk as Skeleton3D).get_bone_global_rest((e.sk as Skeleton3D).find_bone(bn)).origin.y
		var n := ceili((e.clip as Animation).length * 30.0)
		var inval := 0
		var mg := 0.0
		var depth := 0.0
		var gap := 0.0
		var rh := {}
		for fr in n:
			ap.seek(fr / 30.0, true)
			await process_frame
			act.call("update_props")
			if not va.valid(e):
				inval += 1
			var lo := INF
			for bn in rest:
				lo = minf(lo, (e.sk as Skeleton3D).get_bone_global_pose((e.sk as Skeleton3D).find_bone(bn)).origin.y - float(rest[bn]))
			mg = maxf(mg, absf(lo))
			if e.prop != null:
				for path in va.render_prop_hits(ri, e.prop):
					rh[path] = true
			if String(e.prop_kind) in ["crate", "stool"]:
				var bounds: AABB = (e.prop as MeshInstance3D).mesh.get_aabb()
				var shape := BoxShape3D.new()
				shape.size = bounds.size * (e.prop as Node3D).global_basis.get_scale()
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = shape
				q.transform = Transform3D((e.prop as Node3D).global_basis.orthonormalized(), (e.prop as Node3D).global_transform * bounds.get_center())
				q.exclude = ex
				q.collision_mask = 1
				var cts := sp.collide_shape(q, 32)
				for j in range(0, cts.size(), 2):
					depth = maxf(depth, (cts[j] as Vector3).distance_to(cts[j + 1]))
			if String(e.prop_kind) == "stool" and fr == 0:
				var legs: Array = (e.body as Node).get_children()
				for li in range(1, 5):
					var lp: Vector3 = (legs[li] as Node3D).global_position
					var pos := Vector3(lp.x, (e.body as Node3D).global_position.y, lp.z)
					var hit := sp.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.2, pos - Vector3.UP * 0.3, 1, ex))
					var fy := -INF if hit.is_empty() else float(hit.position.y)
					var ry := ri.floor_y(Vector2(pos.x, pos.z), pos.y + 0.2)
					if not is_nan(ry):
						fy = maxf(fy, ry)
					gap = maxf(gap, 99.0 if fy == -INF else absf(pos.y - fy))
		ap.speed_scale = 1.0
		finfo.append("%s %d f" % [String(e.path).get_file(), n])
		if not (inval == 0 and mg < 0.012 and rh.is_empty() and gap < 0.055 and depth < 0.02):
			fbad.append("%s 無効 %d 足 %.3f 三角 %s 食込 %.3f 脚 %.3f" % [e.path, inval, mg, str(rh.keys()), depth, gap])
	va.free()
	check("逐フレーム（30 fps・clip 全長、R3c と同じ基準；%s；違反 %s）" % [", ".join(finfo), str(fbad)], fbad.is_empty(), "frames")
	# 審圖鏡位：同一モデル ≤ 2、密度勾配（核心の鏡位ほど人が多い）
	var views: Array = JSON.parse_string(FileAccess.get_file_as_string(VIEWS))
	var cam := Camera3D.new()
	cam.fov = 75.0
	root.add_child(cam)
	await process_frame
	var vb := []
	var vinfo := []
	for vw: Dictionary in views:
		cam.global_transform = helper._tps(v, sp, vw)
		var cnt := {}
		var tot := 0
		for b in all_b:
			var head := (b as Node3D).global_position + Vector3(0, 1.4, 0)
			if not cam.is_position_in_frustum(head) or cam.global_position.distance_to(head) > 60.0:
				continue
			var q := PhysicsRayQueryParameters3D.create(cam.global_position, head)
			q.exclude = ex
			if not sp.intersect_ray(q).is_empty():
				continue
			cnt[String(b.get_meta("model"))] = int(cnt.get(String(b.get_meta("model")), 0)) + 1
			tot += 1
		vinfo.append("%s %d 人" % [vw["name"], tot])
		if cnt.keys().any(func(m: String) -> bool: return int(cnt[m]) > 2):
			vb.append("%s %s" % [vw["name"], str(cnt)])
	cam.queue_free()
	check("審圖鏡位 %d：同一モデルが同じ鏡頭に 3 人以上いない（%s；違反 %s）" % [views.size(), "、".join(vinfo), str(vb)], vb.is_empty(), "views")
	# 歩く人 30 秒
	var C := PL.context(v)
	var walk := bodies.filter(func(b: Node) -> bool: return String(b.get("mode")) == "patrol")
	var st := {}
	for b in walk:
		st[b] = {"dir": int(b.get("_dir")), "rev": false, "trav": 0.0, "prev": (b as Node3D).global_position, "y": 0.0, "xz": 0.0}
	for i in 1800:
		await physics_frame
		if i % 30 != 0:
			continue
		for b in walk:
			var s: Dictionary = st[b]
			var pos := (b as Node3D).global_position
			s.trav += (s.prev as Vector3).distance_to(pos)
			s.prev = pos
			s.rev = bool(s.rev) or int(b.get("_dir")) != int(s.dir)
			var pts: PackedVector2Array = b.get("path_xz")
			var p2 := Vector2(pos.x, pos.z)
			var dd := INF
			for k in range(1, pts.size()):
				dd = minf(dd, float(helper._seg_d(p2, pts[k - 1], pts[k])))
			s.xz = maxf(float(s.xz), dd)
			s.y = maxf(float(s.y), absf(pos.y - PL.top_h(C, p2)))
	var wbad := []
	for b in walk:
		var s: Dictionary = st[b]
		if float(s.trav) < 3.0 or not bool(s.rev) or float(s.xz) > 0.05 or float(s.y) > 0.03:
			wbad.append("%s 移動 %.1f 折返 %s XZ %.3f Y %.3f" % [b.name, s.trav, s.rev, s.xz, s.y])
	check("歩く人 %d：30 秒で移動・折返し・路線 XZ ≤ 0.05・高さ ≤ 0.03 m（違反 %s）" % [walk.size(), str(wbad)], wbad.is_empty(), "walk")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	helper = VG.new()
	if "--seal" in args:
		var v0: Node3D = (load(SCENE) as PackedScene).instantiate()
		root.add_child(v0)
		await physics_frame
		var rs := _seal(v0)
		helper.free()
		quit(rs)
		return
	if (("--build" in args) or ("--attach" in args)) and _sealed() and OS.get_environment("OUTER_ALLOW_REBAKE") != "1":
		push_error("P10 R3e は ART_APPROVED・封存中：--build／--attach は拒否（collision／animation bug を使用者が承認したら OUTER_ALLOW_REBAKE=1、その後 seal を更新）")
		helper.free()
		quit(1)
		return
	if "--attach" in args:
		var r := _attach()
		helper.free()
		quit(r)
		return
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	if "--scene" in args:
		root.size = Vector2i(1920, 1080)
		root.add_child(v)
		await _scene(v)
		print("[OUTER] 結果：%d 項失敗（scene）" % fails)
		helper.free()
		quit(fails)
		return
	var old := v.get_node_or_null(OL.PARENT + "/" + OL.NODE_NAME)
	if old:
		old.get_parent().remove_child(old)
		old.free()
	root.add_child(v)
	await physics_frame
	var B: Array = PL.plan(v)["actors"] + CL.plan(v)["actors"]
	if "--negatives" in args:
		var r2 := _negatives(v, B)
		helper.free()
		quit(r2)
		return
	var P := OL.plan(v)
	print("[OUTER] INFO 外圍 %d 人（%d ms）" % [(P["actors"] as Array).size(), P["ms"]])
	if "--map" in args:
		_map(P, B)
	for a1: String in args:
		if a1.begins_with("--snapshot="):
			_snapshot(P, a1.trim_prefix("--snapshot="))
	for a0: String in args:
		if a0.begins_with("--probe="):
			_probe(v, P, a0.trim_prefix("--probe=").split(","))
			helper.free()
			quit(0)
			return
		if a0.begins_with("--scan="):
			var q := a0.trim_prefix("--scan=").split(",")
			var p0 := Vector2(float(q[0]), float(q[1]))
			var p1 := Vector2(float(q[2]), float(q[3]))
			var stp := float(q[4])
			var n := int(p0.distance_to(p1) / stp) + 1
			var sp := v.get_world_3d().direct_space_state
			for i in n:
				var pp := p0.lerp(p1, float(i) / maxf(n - 1, 1))
				var h := PL.top_h(P["C"], pp)
				var hit := (P["C"]["RI"] as PL.RenderIndex).body_hits(Vector3(pp.x, h, pp.y), 1.6, PL.CAP_R)
				hit.append_array(helper._hits(v, sp, Vector3(pp.x, h, pp.y), 1.6))
				var road := not is_nan((P["C"]["R"] as RLib.TriSampler).h(pp.x, pp.y))
				print("[OUTER] SCAN (%.1f,%.1f) h%.2f %s%s" % [pp.x, pp.y, h, "R" if road else "-", "" if hit.is_empty() else " X" + str(hit.slice(0, 1))])
			helper.free()
			quit(0)
			return
	_gate(v, P, B, OL.ASSIGN)
	if "--build" in args and fails == 0:
		var r := OL.build(P)
		var holder := Node3D.new()
		holder.add_child(r)
		var ps := PackedScene.new()
		var e := ps.pack(r)
		var e2 := ResourceSaver.save(ps, OL.OUTPUT) if e == OK else e
		check("save %s（%d 人）" % [OL.OUTPUT, r.get_meta("actors")], e2 == OK)
		holder.free()
	print("[OUTER] 結果：%d 項失敗" % fails)
	helper.free()
	quit(fails)
