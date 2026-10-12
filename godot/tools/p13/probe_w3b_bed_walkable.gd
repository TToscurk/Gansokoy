extends SceneTree
## P13 W3B 驗收後（使用者 2026-10-12「盛土 KEEP；玩家が立てる位置では視覚と碰撞の不一致が明顕でないことだけ確認」）：
## 木槽下盛土の「見えている高さ」と「歩く地面（碰撞）」の差を、玩家が実際に立てる位置（木槽碰撞箱の外）で測る。唯讀・headless 可。
##   godot --headless --path . --script res://tools/p13/probe_w3b_bed_walkable.gd
## 前提：盛土そのものには碰撞が無い（見た目だけ）。木槽の碰撞箱は半幅 (TROUGH_W + 0.05 + 2*LOW_CAM_PAD)/2、
##       玩家の膠囊は半径 0.3 m（characters/yoriichi/player_yoriichi.tscn の CapsuleShape3D_body）。
## 方法：T0 の土メッシュ（ground.gdshader 材質）へ真上から下向きにレイを撃ち（＝見える最上面）、ground_h（歩く地面）との差を槽の左右で測る。
##       焼き込み済み farmland_p8.scn（新）と W3B 前の原版バックアップ（旧）の両方を撃ち、
##       「追加分」＝新の最上面 − max(旧の最上面, 地面)＝W3B が増やした高さだけ、「旧」＝改前からある土手（木槽の両端 1.2 m の collar 堤頂など）を分けて出す。
##       木槽 3 本・槽に沿って 0.25 m ごと・左右。
const FLib := preload("res://tools/village_v2_farmland_lib.gd")
const ZLib := preload("res://tools/village_v2_farmland_zone.gd")
const SCENE := "res://maps/village_v2/gen/farmland_p8.scn"
const OLD_SCENE := "res://.godot/w3b_backup/farmland_p8_before.scn"
const CAPSULE_R := 0.3
const STEP := 0.25


func _init() -> void:
	_run.call_deferred()


func _earth_tms(path: String) -> Array:
	var ps := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var inst := ps.instantiate()
	root.add_child(inst)
	await process_frame
	var out: Array = []
	var brn := inst.get_node_or_null("ZoneWorks/ZoneIrrigation/Branches/Branch_T0")
	if brn == null:
		return out
	for mi: MeshInstance3D in brn.find_children("*", "MeshInstance3D", true, false):
		var m := mi.material_override
		if m is ShaderMaterial and String((m as ShaderMaterial).shader.resource_path).ends_with("ground.gdshader") and mi.mesh != null:
			out.append([mi.mesh.generate_triangle_mesh(), mi.global_transform])
	return out


func _top(tms: Array, p: Vector2) -> float:
	var best := NAN
	for e: Array in tms:
		var xf: Transform3D = e[1]
		var inv := xf.affine_inverse()
		var hit: Dictionary = (e[0] as TriangleMesh).intersect_ray(inv * Vector3(p.x, 3.0, p.y), inv.basis * Vector3.DOWN)
		if not hit.is_empty():
			var y: float = (xf * (hit["position"] as Vector3)).y
			best = y if is_nan(best) else maxf(best, y)
	return best


func _pct(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[clampi(int(ceil(q * s.size())) - 1, 0, s.size() - 1)])


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += float(v)
	return t / a.size()


func _max(a: Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, float(v))
	return m


func _share(a: Array, thr: float) -> float:
	var n := 0
	for v in a:
		if float(v) > thr:
			n += 1
	return 100.0 * n / maxf(a.size(), 1.0)


func _run() -> void:
	var P: Dictionary = FLib.plan()
	var tn: Array = await _earth_tms(SCENE)
	var to: Array = await _earth_tms(OLD_SCENE)
	if tn.is_empty() or to.is_empty():
		print("[BEDW] FAIL 土メッシュを取得できない（新 %d・旧 %d）" % [tn.size(), to.size()])
		quit(1)
		return
	var box_half := (FLib.TROUGH_W + 0.05 + 2.0 * FLib.LOW_CAM_PAD) * 0.5
	var ds: Array = [box_half, box_half + 0.1, box_half + 0.2, box_half + CAPSULE_R, 0.8]
	print("[BEDW] T0 土メッシュ 新 %d・旧 %d 個。木槽碰撞箱の半幅 %.3f m・膠囊半径 %.2f m → 玩家の中心は槽中心から ≥ %.3f m（d＝槽中心からの横距離）" % [tn.size(), to.size(), box_half, CAPSULE_R, box_half + CAPSULE_R])
	var add_all: Array = []
	var tot_all: Array = []
	var pre_all: Array = []
	for i in ds.size():
		add_all.append([])
		tot_all.append([])
		pre_all.append([])
	for br: Dictionary in P["zone"]["branches"]:
		if br["id"] != "T0":
			continue
		var ri := 0
		for r: Dictionary in br["runs"]:
			if r["kind"] != "open":
				ri += 1
				continue
			var line: PackedVector2Array = r["line"]
			for sp: Array in ZLib.branch_spans(r):
				if sp[0] != "trough":
					continue
				var s0: float = sp[1]
				var s1: float = sp[2]
				var add: Array = []
				for i in ds.size():
					add.append([])
				var wg_max := 0.0
				var n := 0
				var s := s0
				while s <= s1 + 1e-6:
					var at: Array = FLib.at_s(line, s)
					var c: Vector2 = at[0]
					var dir: Vector2 = at[1]
					var nrm := Vector2(-dir.y, dir.x)
					wg_max = maxf(wg_max, ZLib.branch_water(r, s) - ZLib.ground_h(c))
					for i in ds.size():
						for side in [-1.0, 1.0]:
							var p := c + nrm * float(side) * float(ds[i])
							var g := ZLib.ground_h(p)
							var yn := _top(tn, p)
							var yo := _top(to, p)
							var base := g if is_nan(yo) else maxf(g, yo)
							var a_add := 0.0 if is_nan(yn) else maxf(yn - base, 0.0)
							(add[i] as Array).append(a_add)
							(add_all[i] as Array).append(a_add)
							(tot_all[i] as Array).append(0.0 if is_nan(yn) else maxf(yn - g, 0.0))
							(pre_all[i] as Array).append(0.0 if is_nan(yo) else maxf(yo - g, 0.0))
					n += 1
					s += STEP
				print("[BEDW] T0 run%d 木槽 s %.1f–%.1f（%.1f m・%d 断面）水面−地面 最大 %.1f cm" % [ri, s0, s1, s1 - s0, n, wg_max * 100.0])
				for i in [0, 2, 3]:
					var a: Array = add[i]
					print("[BEDW]     d=%.3f m：W3B の追加分 最大 %.1f cm・平均 %.1f cm・p95 %.1f cm" % [float(ds[i]), _max(a) * 100.0, _mean(a) * 100.0, _pct(a, 0.95) * 100.0])
			ri += 1
	print("[BEDW] ── 3 本まとめ（左右 × 全断面 188 点／d）──  追加分＝W3B が増やした高さ、全体＝新の最上面−歩く地面、旧＝改前からある土手（collar 等）")
	for i in ds.size():
		var a: Array = add_all[i]
		print("[BEDW] d=%.3f m：追加分 最大 %.1f・平均 %.1f・p95 %.1f cm（> 5 cm %.1f %%・> 10 cm %.1f %%）｜全体 最大 %.1f・平均 %.1f cm｜旧 最大 %.1f・平均 %.1f cm%s" % [float(ds[i]),
				_max(a) * 100.0, _mean(a) * 100.0, _pct(a, 0.95) * 100.0, _share(a, 0.05), _share(a, 0.10),
				_max(tot_all[i]) * 100.0, _mean(tot_all[i]) * 100.0, _max(pre_all[i]) * 100.0, _mean(pre_all[i]) * 100.0,
				"  ← 膠囊の中心の限界" if i == 3 else ("  ← 碰撞箱の縁" if i == 0 else "")])
	quit(0)
