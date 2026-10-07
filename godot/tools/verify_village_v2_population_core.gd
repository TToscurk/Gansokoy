extends SceneTree
## P10 R3d Village Core Population Expansion gate（tag CORE）。R3b（封存 16 人）＋R3d 追加の合計で検査する。美術判定ではない。
##   godot --headless --path godot --script res://tools/verify_village_v2_population_core.gd                 plan gate
##   godot --headless --path godot --script res://tools/verify_village_v2_population_core.gd -- --negatives  永久反向（各案が瞄準項を FAIL）
##   godot --headless --path godot --script res://tools/verify_village_v2_population_core.gd -- --build      plan PASS 時のみ gen/population_core_p10.tscn を書く
##   godot --headless --path godot --script res://tools/verify_village_v2_population_core.gd -- --attach     village_v2.tscn の Population へ CoreP10＋ActivityCoreP10（ActivityP10 の後）
##   godot --path godot --script res://tools/verify_village_v2_population_core.gd -- --scene                 場景級（掛載順・人数・Activity 再生・道具・歩行 30 秒・審圖鏡位の同モデル）
##   -- --map  配役一覧（位置・最近傍・同モデル距離）
const PL := preload("res://tools/village_v2_population_lib.gd")
const CL := preload("res://tools/village_v2_population_core_lib.gd")
const CUE := preload("res://tools/village_v2_entrance_cue_lib.gd")
const VG := preload("res://tools/verify_village_v2_population.gd")
const VA := preload("res://tools/verify_p10_activity.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const VIEWS := "res://tools/shot_village_v2_population_core_views.json"
const R3C_SEAL := "res://data/village_v2_p10r3c_seal.json"
const R3B_SEAL := "res://data/village_v2_p10r3b_seal.json"
## 核心區の範囲（xz の箱）：農田・河岸・森林へは出ない
const ZONE_BOX := {
	"market": Rect2(229.0, -61.0, 28.0, 41.0),
	"market_west": Rect2(200.0, -57.0, 34.0, 31.0),
	"main_street": Rect2(245.0, -50.0, 32.0, 45.0),
	"izakaya": Rect2(270.0, -68.0, 18.0, 16.0),
	"terakoya": Rect2(196.0, 14.0, 18.0, 20.0),
}
const TWIN_MIN := 8.0

var fails := 0
var failed := []
var quiet := false
var helper: SceneTree


func check(label: String, ok: bool, key := "") -> void:
	if not quiet:
		print("[CORE] %s %s" % ["PASS" if ok else "FAIL", label])
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


func _hits(v: Node3D, sp: PhysicsDirectSpaceState3D, p: Vector3, h: float) -> Array:
	return helper._hits(v, sp, p, h)


## 承認済み vocabulary：R3c seal の assignments から (type, model, clip, slot, options) の組
func _vocab() -> Array:
	var seal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(R3C_SEAL))
	var out := []
	for k: String in seal["assignments"]:
		var s: Dictionary = seal["assignments"][k]
		out.append(JSON.stringify([s["type"], s["npc"], s["clip"], s["slot"], s["options"]]))
	return out


func _gate(v: Node3D, P: Dictionary, B: Array, assign: Dictionary) -> int:
	var f0 := fails
	var A: Array = P["actors"]
	var C: Dictionary = P["C"]
	var sp := v.get_world_3d().direct_space_state
	var ALL: Array = B + A
	# 1 人数・区域・密度の順
	var zc := {}
	for a: Dictionary in ALL:
		zc[a["zone"]] = int(zc.get(a["zone"], 0)) + 1
	var dens_ok := int(zc.get("market", 0)) > int(zc.get("main_street", 0)) and int(zc.get("main_street", 0)) > int(zc.get("market_west", 0)) \
		and int(zc.get("izakaya", 0)) <= 3 and int(zc.get("terakoya", 0)) <= 4
	check("人數：R3b %d＋R3d %d＝%d（30–40）、區域 %s（市集＞主街＞裏通り、居酒屋 ≤ 3・寺子屋 ≤ 4）" % [B.size(), A.size(), ALL.size(), str(zc)],
		ALL.size() >= 30 and ALL.size() <= 40 and A.size() >= 14 and dens_ok and zc.keys().all(func(z: String) -> bool: return CL.ZONE_NODE.has(z)), "count")
	# 2 核心區の範囲（農田・河岸・森林へ出ない）
	var obad := []
	for a: Dictionary in A:
		var box: Rect2 = ZONE_BOX.get(a["zone"], Rect2())
		for q in _pts(a):
			if not box.has_point(q):
				obad.append("%s(%.1f,%.1f)" % [a["id"], q.x, q.y])
				break
	check("範圍：全員が自分の核心區の箱の中（農田・河岸・森林へ出ない；違反 %s）" % str(obad), obad.is_empty(), "zone")
	# 3 anchor：存在・R3b と重複しない・互いに重複しない
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
	check("anchor：封存 overlay の Marker を読めた（欠落 %s）、R3b・互いと重複しない（重複 %s）" % [str(bad_a.map(func(a: Dictionary) -> String: return a["id"])), str(dup)],
		bad_a.is_empty() and dup.is_empty(), "anchor")
	if not bad_a.is_empty():
		return fails - f0
	# 4 職業対位・歩く人の規則
	var bad_r := A.filter(func(a: Dictionary) -> bool: return not (a["trade"] in CL.ROLE_OK.get(a["model"], [])))
	var walkers := ALL.filter(func(a: Dictionary) -> bool: return a["mode"] == "patrol")
	var wbad := walkers.filter(func(a: Dictionary) -> bool: return a["model"] in CL.NO_WALK)
	var kozo_w := walkers.filter(func(a: Dictionary) -> bool: return a["model"] == "kozo_m01").size()
	check("職業對位：外見→商い（違反 %s）" % str(bad_r.map(func(a: Dictionary) -> String: return "%s %s→%s" % [a["id"], a["model"], a["trade"]])), bad_r.is_empty(), "role")
	check("歩く人 %d（≤ 7）：婆婆は Walk 0（違反 %s）、少年 ≤ 2（%d）" % [walkers.size(), str(wbad.map(func(a: Dictionary) -> String: return a["id"])), kozo_w],
		wbad.is_empty() and kozo_w <= 2 and walkers.size() <= 7, "walk_rule")
	# 5 同一モデルは隣接しない（R3b＋R3d、≥ TWIN_MIN）
	var near := []
	var dmin := INF
	for i in ALL.size():
		for j in range(i + 1, ALL.size()):
			if ALL[i]["model"] == ALL[j]["model"] and (i >= B.size() or j >= B.size()):
				var d := _min_d(ALL[i], ALL[j])
				dmin = minf(dmin, d)
				if d < TWIN_MIN:
					near.append("%s-%s %.1f m" % [ALL[i]["id"], ALL[j]["id"], d])
	check("同一モデルは隣接しない：追加分が絡む同モデル間の最短 %.1f m（≥ %.0f m；違反 %s）" % [dmin, TWIN_MIN, str(near)], near.is_empty(), "twin")
	# 6 構図：追加分の小群（2–3 人・3 m 以内）≥ 4、全体の単独 ≥ 6、最近傍距離の変動係数 ≥ 0.5（等間隔に撒かない）
	var idle := ALL.filter(func(a: Dictionary) -> bool: return a["mode"] == "idle")
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
		elif String(a["group"]) != "" and A.has(a):
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
	check("構圖：追加分の小群 %d 組（≥ 4：%s）、全体の単独 %d（≥ 6）、最近傍距離の変動係數 %.2f（≥ 0.5）" % [g_ok.size(), str(g_ok), singles, cv],
		g_ok.size() >= 4 and singles >= 6 and cv >= 0.5, "compose")
	# 7 接地（Idle：足元＝見えている最上面 ±3 cm）
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
	check("接地：追加 Idle の足元と見えている最上面の差 最大 %.3f m（≤ 0.03；違反 %s）" % [gmax, str(gbad)], gbad.is_empty(), "ground")
	# 8 体の衝突：capsule が描画三角形・衝突体に入らない、NPC 間 ≥ 0.55 m（R3b 含む）
	var cbad := []
	for a: Dictionary in A:
		if a["mode"] != "idle":
			continue
		var h := (C["RI"] as PL.RenderIndex).body_hits(a["p"], float(a["height"]), PL.CAP_R)
		h.append_array(_hits(v, sp, a["p"], float(a["height"])))
		if not h.is_empty():
			cbad.append("%s→%s" % [a["id"], str(h.slice(0, 2))])
	var pbad := []
	for a: Dictionary in A:
		for b: Dictionary in ALL:
			if a == b or a["mode"] != "idle" or b["mode"] != "idle":
				continue
			if _d2(a["p"], b["p"]) < 0.55 and not pbad.has("%s-%s" % [b["id"], a["id"]]):
				pbad.append("%s-%s" % [a["id"], b["id"]])
	check("體の衝突：追加 Idle の capsule が屋台・棚・建物（描画三角形＋衝突體）に入らない（違反 %s）、NPC 間 ≥ 0.55 m（%s）" % [str(cbad), str(pbad)], cbad.is_empty() and pbad.is_empty(), "body")
	# 9 往復路：0.25 m 毎の capsule が衝突體に入らない・Idle から ≥ 0.6 m・段差 ≤ 0.10 m・長さ 6–20 m
	var rbad := []
	var my_walkers := A.filter(func(a: Dictionary) -> bool: return a["mode"] == "patrol")
	for a: Dictionary in my_walkers:
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
			var h := _hits(v, sp, hp, float(a["height"]))
			h.append_array((C["RI"] as PL.RenderIndex).body_hits(hp, float(a["height"]), PL.CAP_R))
			if not h.is_empty():
				hit.append("%.1f m %s" % [j2 * 0.25, str(h.slice(0, 1))])
			j2 += 1
		var clear := INF
		for b: Dictionary in idle:
			clear = minf(clear, _min_d(a, b))
		if not hit.is_empty() or step > 0.10 or L < 6.0 or L > 20.0 or clear < 0.6:
			rbad.append("%s 衝突 %s 段差 %.2f 長 %.1f Idle 迄 %.2f" % [a["id"], str(hit.slice(0, 2)), step, L, clear])
	check("往復路 %d 本：衝突體・描畫三角形に入らない・Idle から ≥ 0.6 m・段差 ≤ 0.10 m・長さ 6–20 m（違反 %s）" % [my_walkers.size(), str(rbad)], rbad.is_empty(), "path")
	# 10 歩速＝clip の足の接地速度（滑り ≤ 3 %）
	var sbad := []
	for a: Dictionary in my_walkers:
		var r := float(a["walk_speed"]) / maxf(float(a["walk"]["speed"]), 1e-4)
		if absf(r - 1.0) > 0.03 or float(a["walk"]["speed"]) < 0.6:
			sbad.append("%s 比 %.2f" % [a["id"], r])
	check("歩速＝Walk clip の足の接地速度（滑り ≤ 3 %%、違反 %s）" % str(sbad), sbad.is_empty(), "speed")
	# 11 Activity：承認済み vocabulary だけ（R3c seal の (type, model, clip, slot, options) と一致）、対象は追加分の実在する住人
	var voc := _vocab()
	var names := {}
	for a: Dictionary in A:
		names["%s/%s_%s" % [CL.ZONE_NODE[a["zone"]], a["id"], a["model"]]] = a
	var vbad := []
	var types := {}
	for path: String in assign:
		var e: Array = assign[path]
		var key := JSON.stringify([e[0], e[1], e[2], e[3], e[4] if e.size() > 4 else {}])
		if not voc.has(key) or not names.has(path) or String(names[path]["model"]) != String(e[1]):
			vbad.append(path)
		if names.has(path) and (String(e[0]) == "YouthShortStep") != (String(names[path]["mode"]) == "patrol"):
			vbad.append(path + "（walk slot と patrol が不一致）")
		types[e[0]] = int(types.get(e[0], 0)) + 1
	check("Activity：%d 件・%s がすべて R3c／R3c.1 封存 vocabulary（type・model・clip・slot・options 一致）で追加分の実在の住人（違反 %s）" % [assign.size(), str(types), str(vbad)],
		vbad.is_empty() and assign.size() >= 5, "vocab")
	# 12 封存は読むだけ：R3b の Population scene・R3c の overlay の雜湊＝封存時
	var hb := []
	var b_seal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(R3B_SEAL))
	for k: String in b_seal["frozen"]:
		if k.ends_with(".tscn") or k.ends_with("population_lib.gd") or k.ends_with("npc_population_actor.gd"):
			if FileAccess.get_sha256("res://" + k.trim_prefix("godot/")) != String(b_seal["frozen"][k]):
				hb.append(k.get_file())
	var c_seal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(R3C_SEAL))
	for k: String in ["godot/scripts/npc_activity_overlay.gd", "godot/maps/village_v2/activity_p10.tscn"]:
		if FileAccess.get_sha256("res://" + k.trim_prefix("godot/")) != String(c_seal["frozen"].get(k, "")):
			hb.append(k.get_file())
	check("封存は読むだけ：R3b population scene／generator／actor・R3c overlay の雜湊＝封存時（違い %s）" % str(hb), hb.is_empty(), "sealed")
	# 13 入口 cue（r1.1）：≤ 2 件、既存 Kit の mesh だけ、地面に立つ、道の上に立てない、建物・屋台・人・往復路に当たらない、口の通路 ≥ 8 m
	var cue: Array = P.get("cue", [])
	var qbad := []
	for c: Dictionary in cue:
		var p: Vector3 = c["p"]
		var p2 := Vector2(p.x, p.z)
		if not ResourceLoader.exists(CUE.KIT + String(c["mesh"]) + ".res"):
			qbad.append("%s mesh" % c["name"])
		if absf(p.y - PL.top_h(C, p2)) > 0.03:
			qbad.append("%s 接地 %.2f" % [c["name"], p.y - PL.top_h(C, p2)])
		if not is_nan((C["R"] as RLib.TriSampler).h(p2.x, p2.y)):
			qbad.append("%s 道の上" % c["name"])
		var h := (C["RI"] as PL.RenderIndex).body_hits(p, 3.6, 0.14)
		h.append_array(_hits(v, sp, p, 3.6))
		if not h.is_empty():
			qbad.append("%s→%s" % [c["name"], str(h.slice(0, 1))])
		for a: Dictionary in ALL:
			var dq := INF
			for q in _pts(a):
				dq = minf(dq, q.distance_to(p2))
			if dq < 0.6:
				qbad.append("%s と %s %.2f m" % [c["name"], a["id"], dq])
	var gap := INF
	if cue.size() == 2:
		gap = Vector2((cue[0]["p"] as Vector3).x, (cue[0]["p"] as Vector3).z).distance_to(Vector2((cue[1]["p"] as Vector3).x, (cue[1]["p"] as Vector3).z))
	check("入口 cue %d 件（≤ 2）：既存 Kit mesh・接地・道の上でない・建物／屋台／人／往復路に当たらない・口の通路 %.1f m（≥ 8；違反 %s）" % [cue.size(), gap, str(qbad)],
		cue.size() <= 2 and qbad.is_empty() and (cue.size() < 2 or gap >= 8.0), "cue")
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
		print("[CORE] MAP %-4s %-10s %-12s %-8s %-6s (%.1f, %.2f, %.1f) yaw %4.0f  最近 %s %.1f m  同モデル %.1f m" % [a["id"], a["zone"], a["model"], a["trade"], a["mode"],
			p.x, p.y, p.z, rad_to_deg(float(a.get("yaw", 0.0))), who, best, twin])


## 調査用：指定 id の Idle の周り（半径 1.2 m、0.15 m 格子）で体が当たらない位置を近い順に出す
func _probe(v: Node3D, P: Dictionary, ids: PackedStringArray) -> void:
	var sp := v.get_world_3d().direct_space_state
	var C: Dictionary = P["C"]
	for a: Dictionary in P["actors"]:
		if not ids.has(String(a["id"])):
			continue
		var p0: Vector3 = a["p"]
		var cands := []
		for ix in range(-8, 9):
			for iz in range(-8, 9):
				var o := Vector2(ix, iz) * 0.15
				if o.length() > 1.2:
					continue
				var p2 := Vector2(p0.x + o.x, p0.z + o.y)
				var p3 := Vector3(p2.x, PL.top_h(C, p2), p2.y)
				var h := (C["RI"] as PL.RenderIndex).body_hits(p3, float(a["height"]), PL.CAP_R)
				h.append_array(_hits(v, sp, p3, float(a["height"])))
				if h.is_empty() and absf(p3.y - p0.y) < 0.2:
					cands.append([o.length(), o])
		cands.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
		print("[CORE] PROBE %s 候補 %d：%s" % [a["id"], cands.size(), str(cands.slice(0, 6).map(func(c: Array) -> String: return "(%.2f,%.2f)" % [(c[1] as Vector2).x, (c[1] as Vector2).y]))])


func _negatives(v: Node3D, B: Array) -> int:
	var by := func(c: Array, id: String) -> Dictionary:
		for e: Dictionary in c:
			if String(e["id"]) == id:
				return e
		return {}
	var cases := {
		"twin": func(c: Array) -> void: by.call(c, "C2")["model"] = "chaya_f01"; by.call(c, "C2")["trade"] = "dango",          # 団子の客を売り子と同じ娘に
		"role": func(c: Array) -> void: by.call(c, "C8")["trade"] = "sakana",                                                 # 飯屋の婆を魚屋に
		"body": func(c: Array) -> void: by.call(c, "C3")["off"] = [-1.4, 0.0],                                                # 運び手を荷車の中へ
		"path": func(c: Array) -> void: by.call(c, "C6")["path"] = [[259.0, -19.0], [253.5, -16.0], [249.5, -21.0]],          # 往復路を家の中へ
		"zone": func(c: Array) -> void: by.call(c, "C17")["at"] = [330.0, -60.0, 0.0],                                        # 居酒屋の客を田の中へ
		"anchor": func(c: Array) -> void: by.call(c, "C7")["anchor"] = "MarketP10/vendor_yatai_cha",                           # R3b の茶屋の店員の場所を取る
		"walk_rule": func(c: Array) -> void: by.call(c, "C22")["mode"] = "patrol"; by.call(c, "C22")["path"] = [[206.0, 28.9], [212.0, 28.9]],   # 婆を歩かせる
		"count": func(c: Array) -> void:
			for k in 12:
				var e: Dictionary = by.call(c, "C12").duplicate(true)
				e["id"] = "X%d" % k
				e["anchor"] = ""
				e["at"] = [240.0 + k * 0.7, -30.0, 0.0]
				c.append(e),
		"compose": func(c: Array) -> void:                                                                                    # 二人組を全部ばらす
			for id: String in ["C2", "C5", "C13", "C18", "C21", "C24"]:
				var e: Dictionary = by.call(c, id)
				e["off"] = [3.5, 0.0]
				e["face"] = "anchor"
				if e.has("at"):
					e["at"] = [float(e["at"][0]) + 4.0, float(e["at"][1]), 0.0],
	}
	var pby := func(P: Dictionary, id: String) -> Dictionary:
		for a: Dictionary in P["actors"]:
			if String(a["id"]) == id:
				return a
		return {}
	var post := {
		"ground": func(P: Dictionary) -> void: pby.call(P, "C4")["p"] += Vector3(0, 0.2, 0),                                  # 浮かせる
		"speed": func(P: Dictionary) -> void: pby.call(P, "C6")["walk_speed"] *= 1.3,                                         # 足が滑る
	}
	var cue_cases := {
		"cue": func(P: Dictionary) -> void: P["cue"][0]["p"] = Vector3(248.0, 1.12, -20.5),   # 幟を中橫街の真ん中へ
	}
	var assign_cases := {
		"vocab": func(d: Dictionary) -> void: d["Market/C5_shufu_f01"] = ["Inspect", "shufu_f01", "browse_looking_down_a030", "idle"],   # 未承認の候補 clip
	}
	var mism := 0
	quiet = true
	for key: String in cases.keys() + post.keys() + assign_cases.keys() + cue_cases.keys():
		var cast: Array = CL.CAST.duplicate(true)
		if cases.has(key):
			(cases[key] as Callable).call(cast)
		var P := CL.plan(v, cast)
		if post.has(key):
			(post[key] as Callable).call(P)
		P["cue"] = CUE.plan(P["C"])
		if cue_cases.has(key):
			(cue_cases[key] as Callable).call(P)
		var assign: Dictionary = CL.ASSIGN.duplicate(true)
		if assign_cases.has(key):
			(assign_cases[key] as Callable).call(assign)
		fails = 0
		failed.clear()
		_gate(v, P, B, assign)
		var hit := failed.has(key)
		quiet = false
		print("[CORE] %s 反向 %s → 「%s」必須 FAIL（失敗項 %s）" % ["PASS" if hit else "FAIL", key, key, str(failed)])
		quiet = true
		if not hit:
			mism += 1
	quiet = false
	print("[CORE] 結果：%d 項失敗（negatives）" % mism)
	return mism


func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(CL.OUTPUT):
		push_error("找不到 %s（先 --build）" % CL.OUTPUT)
		return 1
	if txt.contains("gen/population_core_p10.tscn"):
		push_error("已經掛過 CoreP10")
		return 1
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var act_line := "[node name=\"ActivityP10\" parent=\"Population\""
	var i_act := txt.find(act_line)
	if i_act < 0 or txt.count(act_line) != 1:
		push_error("ActivityP10 の掛載行が 1 つではない（CoreP10 は ActivityP10 の後に掛ける）")
		return 1
	# ActivityP10 ブロックの終わり（次の [ か末尾）
	var j := txt.find(nl + "[", i_act + 1)
	var block_end := txt.length() if j < 0 else j + nl.length()
	var ins := "[node name=\"%s\" parent=\"Population\" instance=ExtResource(\"p10r3d_core\")]%s%s" % [CL.NODE_NAME, nl, nl] + \
		"[node name=\"%s\" type=\"Node3D\" parent=\"Population\"]%sscript = ExtResource(\"p10r3d_act\")%s%s" % [CL.ACT_NODE, nl, nl, nl]
	if j < 0:
		ins = nl + ins
	txt = txt.substr(0, block_end) + ins + txt.substr(block_end)
	# ext_resource は最後の ext_resource の後
	var lines := txt.split(nl)
	var last_ext := -1
	for k in lines.size():
		if lines[k].begins_with("[ext_resource"):
			last_ext = k
	lines.insert(last_ext + 1, "[ext_resource type=\"Script\" path=\"%s\" id=\"p10r3d_act\"]" % CL.ACT_SCRIPT)
	lines.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p10r3d_core\"]" % CL.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(lines))
	f.close()
	print("[CORE] attach：Population/%s＋%s（ActivityP10 の後）→ %s" % [CL.NODE_NAME, CL.ACT_NODE, SCENE])
	return 0


func _attach_cue() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(CUE.OUTPUT):
		push_error("找不到 %s（先 --build）" % CUE.OUTPUT)
		return 1
	if txt.contains("gen/entrance_cue_p10.tscn"):
		push_error("已經掛過 EntranceCueP10")
		return 1
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var key := "[node name=\"%s\" type=\"Node3D\" parent=\"Population\"]" % CL.ACT_NODE
	var i := txt.find(key)
	if i < 0 or txt.count(key) != 1:
		push_error("ActivityCoreP10 の掛載行が 1 つではない（cue は ActivityCoreP10 の後）")
		return 1
	var j := txt.find(nl + "[", i + 1)
	var block_end := txt.length() if j < 0 else j + nl.length()
	var ins := "[node name=\"%s\" parent=\"Population\" instance=ExtResource(\"p10r3d_cue\")]%s%s" % [CUE.NODE_NAME, nl, nl]
	if j < 0:
		ins = nl + ins
	txt = txt.substr(0, block_end) + ins + txt.substr(block_end)
	var lines := txt.split(nl)
	var last_ext := -1
	for k in lines.size():
		if lines[k].begins_with("[ext_resource"):
			last_ext = k
	lines.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p10r3d_cue\"]" % CUE.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(lines))
	f.close()
	print("[CORE] attach：Population/%s（ActivityCoreP10 の後）→ %s" % [CUE.NODE_NAME, SCENE])
	return 0


func _scene(v: Node3D) -> void:
	var txt := FileAccess.get_file_as_string(SCENE)
	var order := ["PopulationP10", "ActivityP10", CL.NODE_NAME, CL.ACT_NODE, CUE.NODE_NAME]
	var idx := []
	var once := true
	for nm: String in order:
		var lines := Array(txt.split("\n")).filter(func(l: String) -> bool: return l.begins_with("[node name=\"%s\"" % nm) and l.contains("parent=\"Population\""))
		once = once and lines.size() == 1
		idx.append(txt.find(String(lines[0])) if lines.size() > 0 else -1)
	var ord_ok: bool = int(idx[0]) >= 0
	for k in range(1, idx.size()):
		ord_ok = ord_ok and int(idx[k]) > int(idx[k - 1])
	var cue_n := v.get_node_or_null("Population/" + CUE.NODE_NAME)
	check("掛載：Population の PopulationP10 → ActivityP10 → %s → %s → %s（各 1 つ、この順；位置 %s）、入口 cue %d 件" % [CL.NODE_NAME, CL.ACT_NODE, CUE.NODE_NAME, str(idx),
		cue_n.get_child_count() if cue_n else -1], ord_ok and once and cue_n != null and cue_n.get_child_count() == CUE.ITEMS.size(), "mount")
	for i in 30:
		await process_frame
	var core := v.get_node_or_null("Population/" + CL.NODE_NAME)
	var base := v.get_node_or_null("Population/PopulationP10")
	var bodies := core.find_children("*", "AnimatableBody3D", true, false) if core else []
	var all_b := v.get_node("Population").find_children("*", "AnimatableBody3D", true, false)
	check("人數：CoreP10 %d（＝配役 %d）、Population 全体 %d（R3b 16＋R3d）" % [bodies.size(), CL.CAST.size(), all_b.size()],
		core != null and base != null and bodies.size() == CL.CAST.size() and all_b.size() == 16 + CL.CAST.size(), "count")
	var act := v.get_node_or_null("Population/" + CL.ACT_NODE)
	var ebad := []
	var entries: Array = act.get("entries") if act else []
	for e: Dictionary in entries:
		var ap: AnimationPlayer = e.ap
		var anim := ap.get_animation(StringName(e.slot))
		if anim != e.clip or not ap.is_playing():
			ebad.append(String(e.path) + " clip")
		if e.prop != null and not (e.prop as Node3D).visible:
			ebad.append(String(e.path) + " prop hidden")
	check("Activity：%d 件（＝割り当て %d）が承認 clip を再生、道具が見える（違反 %s）" % [entries.size(), CL.ASSIGN.size(), str(ebad)],
		act != null and entries.size() == CL.ASSIGN.size() and ebad.is_empty(), "activity")
	# 道具の位置：木箱＝両手の間、杯＝左手の近く、縁台＝腰の下
	var sp := v.get_world_3d().direct_space_state
	var pbad := []
	for k in 60:
		await physics_frame
		if k % 10 != 0:
			continue
		for e: Dictionary in entries:
			if e.prop == null:
				continue
			var sk: Skeleton3D = e.sk
			var pc: Vector3 = (e.prop as Node3D).global_transform * (e.prop as MeshInstance3D).mesh.get_aabb().get_center()
			var lh := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("LeftMiddleProximal")).origin
			var rh := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightMiddleProximal")).origin
			var hips := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips")).origin
			var d := 0.0
			match String(e.prop_kind):
				"crate": d = pc.distance_to((lh + rh) * 0.5)
				"cup": d = pc.distance_to(lh)
				"stool": d = Vector2(pc.x - hips.x, pc.z - hips.z).length()
			var lim: float = {"crate": 0.32, "cup": 0.12, "stool": 0.45}[String(e.prop_kind)]
			if d > lim:
				pbad.append("%s %s %.2f m" % [e.path, e.prop_kind, d])
	check("道具が体に付いている（木箱中心↔両手 ≤ 0.32・杯↔左手 ≤ 0.12・縁台↔腰 水平 ≤ 0.45 m；違反 %s）" % str(pbad.slice(0, 4)), pbad.is_empty(), "props")
	# 縁台・木箱が世界の衝突體と重ならない（Population と縁台自身を除く）
	var obad := []
	var ex: Array[RID] = []
	for b in all_b:
		ex.append((b as CollisionObject3D).get_rid())
	for e: Dictionary in entries:
		if e.prop == null or String(e.prop_kind) == "cup":
			continue
		if e.has("body") and e.body != null:
			ex.append((e.body as CollisionObject3D).get_rid())
		var ab: AABB = (e.prop as Node3D).global_transform * (e.prop as MeshInstance3D).mesh.get_aabb()
		var box := BoxShape3D.new()
		box.size = ab.size * 0.92
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = box
		q.transform = Transform3D(Basis(), ab.get_center())
		q.exclude = ex
		for hh in sp.intersect_shape(q, 8):
			var nm := String((hh.collider as Node).name)
			if not nm.begins_with("TerrainCollision"):
				obad.append("%s→%s" % [e.path, nm])
	check("縁台・木箱が屋台・建物の衝突體と重ならない（違反 %s）" % str(obad), obad.is_empty(), "prop_clear")
	# R3c と同じ逐フレーム検査（封存 verify_p10_activity.gd の valid()／render_prop_hits() を只讀で使う）：
	# clip 全長 30 fps で、clip・骨・道具の妥当性、足の rest 誤差 < 0.012 m、道具が描画三角形に入らない、
	# 木箱・縁台が衝突體に食い込まない、縁台の脚 4 本が人の立つ床に乗る（隙間 < 0.055 m）。
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
		var ok := inval == 0 and mg < 0.012 and rh.is_empty() and gap < 0.055 and depth < 0.02
		finfo.append("%s %d f" % [String(e.path).get_file(), n])
		if not ok:
			fbad.append("%s 無効 %d 足 %.3f 三角 %s 食込 %.3f 脚 %.3f" % [e.path, inval, mg, str(rh.keys()), depth, gap])
	va.free()
	check("逐フレーム（30 fps・clip 全長、R3c と同じ基準）：clip／道具が妥当・足の rest 誤差 < 0.012・道具が描画三角形に入らない・木箱／縁台の食い込み < 0.02・縁台の脚が床に乗る < 0.055 m（%s；違反 %s）" % [", ".join(finfo), str(fbad)], fbad.is_empty(), "frames")
	# 審圖鏡位：同一モデル ≤ 2、各鏡位に人が見える
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
			var m := String(b.get_meta("model"))
			cnt[m] = int(cnt.get(m, 0)) + 1
			tot += 1
		vinfo.append("%s %d 人" % [vw["name"], tot])
		if cnt.keys().any(func(m: String) -> bool: return int(cnt[m]) > 2) or tot == 0:
			vb.append("%s %s" % [vw["name"], str(cnt)])
	cam.queue_free()
	check("審圖鏡位 %d：同一モデルが同じ鏡頭に 3 人以上いない、各鏡位に人が見える（%s；違反 %s）" % [views.size(), "、".join(vinfo), str(vb)], vb.is_empty(), "views")
	# 歩く人 30 秒：移動・折返し・路線 XZ ≤ 0.05・高さ ≤ 0.03
	var C := PL.context(v)
	var walk := bodies.filter(func(b: Node) -> bool: return String(b.get("mode")) == "patrol")
	var st := {}
	for b in walk:
		st[b] = {"start": (b as Node3D).global_position, "dir": int(b.get("_dir")), "rev": false, "trav": 0.0, "prev": (b as Node3D).global_position, "y": 0.0, "xz": 0.0}
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
				dd = minf(dd, helper._seg_d(p2, pts[k - 1], pts[k]))
			s.xz = maxf(float(s.xz), dd)
			s.y = maxf(float(s.y), absf(pos.y - PL.top_h(C, p2)))
	var wbad := []
	for b in walk:
		var s: Dictionary = st[b]
		if float(s.trav) < 3.0 or not bool(s.rev) or float(s.xz) > 0.05 or float(s.y) > 0.03:
			wbad.append("%s 移動 %.1f 折返 %s XZ %.3f Y %.3f" % [b.name, s.trav, s.rev, s.xz, s.y])
	check("歩く人 %d：30 秒で移動・折返し・路線 XZ ≤ 0.05・高さ ≤ 0.03 m（違反 %s）" % [walk.size(), str(wbad)], wbad.is_empty() and walk.size() >= 1, "walk")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	helper = VG.new()
	if "--attach-cue" in args:
		var rc := _attach_cue()
		helper.free()
		quit(rc)
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
		print("[CORE] 結果：%d 項失敗（scene）" % fails)
		helper.free()
		quit(fails)
		return
	var old := v.get_node_or_null(CL.PARENT + "/" + CL.NODE_NAME)
	if old:
		old.get_parent().remove_child(old)
		old.free()
	root.add_child(v)
	await physics_frame
	var B: Array = PL.plan(v)["actors"]
	if "--negatives" in args:
		var r2 := _negatives(v, B)
		helper.free()
		quit(r2)
		return
	var P := CL.plan(v)
	P["cue"] = CUE.plan(P["C"])
	print("[CORE] INFO 追加 %d 人（%d ms）" % [(P["actors"] as Array).size(), P["ms"]])
	if "--map" in args:
		_map(P, B)
	for a0: String in args:
		if a0.begins_with("--scan="):
			# 調査用：x0,z0,x1,z1,step の線上で、立てるか（capsule）・高さ・道か
			var q := a0.trim_prefix("--scan=").split(",")
			var p0 := Vector2(float(q[0]), float(q[1]))
			var p1 := Vector2(float(q[2]), float(q[3]))
			var st := float(q[4])
			var n := int(p0.distance_to(p1) / st) + 1
			var sp := v.get_world_3d().direct_space_state
			var row := []
			for i in n:
				var pp := p0.lerp(p1, float(i) / maxf(n - 1, 1))
				var h := PL.top_h(P["C"], pp)
				var hit := (P["C"]["RI"] as PL.RenderIndex).body_hits(Vector3(pp.x, h, pp.y), 1.6, PL.CAP_R)
				hit.append_array(_hits(v, sp, Vector3(pp.x, h, pp.y), 1.6))
				var road := not is_nan((P["C"]["R"] as RLib.TriSampler).h(pp.x, pp.y))
				row.append("(%.1f,%.1f) h%.2f %s%s" % [pp.x, pp.y, h, "R" if road else "-", "" if hit.is_empty() else " X" + str(hit.slice(0, 1))])
			print("[CORE] SCAN ", "
[CORE] SCAN ".join(row))
			helper.free()
			quit(0)
			return
		if a0.begins_with("--probe="):
			_probe(v, P, a0.trim_prefix("--probe=").split(","))
			helper.free()
			quit(0)
			return
	_gate(v, P, B, CL.ASSIGN)
	if "--build" in args and fails == 0:
		var r := CL.build(P)
		var holder := Node3D.new()
		holder.add_child(r)
		var ps := PackedScene.new()
		var e := ps.pack(r)
		var e2 := ResourceSaver.save(ps, CL.OUTPUT) if e == OK else e
		check("save %s（%d 人）" % [CL.OUTPUT, r.get_meta("actors")], e2 == OK)
		holder.free()
		var cr := CUE.build(P["cue"])
		var h2 := Node3D.new()
		h2.add_child(cr)
		var ps2 := PackedScene.new()
		var e3 := ps2.pack(cr)
		check("save %s（cue %d 件）" % [CUE.OUTPUT, (P["cue"] as Array).size()], e3 == OK and ResourceSaver.save(ps2, CUE.OUTPUT) == OK)
		h2.free()
	print("[CORE] 結果：%d 項失敗" % fails)
	helper.free()
	quit(fails)
