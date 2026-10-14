extends SceneTree
## P13 W8 TASK A：LOD 可視遲滯の探針（非 headless・場景は書かない）。
##   godot --path . --resolution 320x180 --script res://tools/p13/w8/w8_lod_sweep.gd -- <out.json> [--guard=on|off] [--quick]
## 原理：目標（南大門 Hero・町家 Kit 2 棟）の LOD0／1／2 部品を専用 layer に載せ、camera の cull_mask でその 1 級だけ描かせ、
##   RenderingServer.viewport_get_render_info(OBJECTS_IN_FRAME)＝その級で実際に可視の『表面数』を読む。
## 1 サンプル＝『状態を作る → 測る位置へ移動 → 全層で 1 幀 settle（実ゲームと同じ：全層描画）→ 3 つの cull_mask で数える』。
##   （可視範囲の状態ビットは layer 判定と視錐判定を通った instance だけ更新される → settle は必ず全層・目標を視錐内に）
## 状態の作り方（scenario）：
##   near／mid／far＝その距離に 3 幀置いてから瞬間移動（テレポート）／cold＝可視範囲を 1 度クリアして作り直す（＝初回ロード直後の状態）／
##   turn_fast＝目標に背を向けて 5 m/幀 で歩き離れ、距離 d で 1 幀で振り向く／turn_slow＝同じく、振り向きを 10°/幀（回転トリガーに掛からない）
## 判定（表面数 c_k／全 n_k）：ok＝ちょうど 1 級が全部／gap＝何も見えない／double＝2 級が 50 % 以上同時／partial＝部品ごとの中心距離差による遷移帯。
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYERS := [1 << 19, 1 << 18, 1 << 17]
const TARGETS := [
	{"name": "gate", "path": "Landmarks/LANDMARK_SOUTH_GATE/Hero", "e": [60.0, 160.0]},
	{"name": "SGT_002", "path": "Districts/SouthGate/Buildings/B_P_SGT_002/Kit", "e": [40.0, 110.0]},
	{"name": "MKT_032", "path": "Districts/Market/Buildings/B_P_MKT_032/Kit", "e": [40.0, 110.0]},
]

var v: Node3D
var cam: Camera3D
var vp: RID
var guard: Node = null


func _init() -> void:
	_run.call_deferred()


func _tick() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


func _count() -> int:
	return int(RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME))


func _face(c: Vector3, d: float, toward: bool) -> void:
	cam.global_position = c + Vector3(d, 1.7, 0.0)
	if toward:
		cam.look_at(c + Vector3(0, 2.5, 0))
	else:
		cam.look_at(c + Vector3(d * 2.0, 1.7, 0.0))


func _all() -> void:
	cam.cull_mask = LAYERS[0] | LAYERS[1] | LAYERS[2]


func _measure() -> Array:
	var res := []
	for k in 3:
		cam.cull_mask = LAYERS[k]
		await _tick()
		res.append(_count())
	return res


func _classify(c: Array, n: Array) -> String:
	var fr := []
	for k in 3:
		fr.append(float(c[k]) / float(maxi(1, n[k])))
	var full := 0
	var any := 0
	var half := 0
	for k in 3:
		if fr[k] >= 0.999:
			full += 1
		if fr[k] > 0.0:
			any += 1
		if fr[k] >= 0.5:
			half += 1
	if any == 0:
		return "gap"
	if full == 1 and any == 1:
		return "ok"
	if half >= 2:
		return "double"
	return "partial"


func _runs(ds: Array, cls: Array, want: String) -> Array:
	var out := []
	var s := -1.0
	var last := -1.0
	for i in ds.size():
		if cls[i] == want:
			if s < 0.0:
				s = float(ds[i])
			last = float(ds[i])
		elif s >= 0.0:
			out.append([s, last])
			s = -1.0
	if s >= 0.0:
		out.append([s, last])
	return out


func _reset_state(gis: Array) -> void:
	## 初回ロード直後の状態を再現：可視範囲を 1 度クリア → 設定し直し＝instance の可視状態が 0 の新規登録になる
	for g: GeometryInstance3D in gis:
		var fm := int(g.visibility_range_fade_mode) as RenderingServer.VisibilityRangeFadeMode
		RenderingServer.instance_geometry_set_visibility_range(g.get_instance(), 0.0, 0.0, 0.0, 0.0, RenderingServer.VISIBILITY_RANGE_FADE_DISABLED)
		RenderingServer.instance_geometry_set_visibility_range(g.get_instance(), g.visibility_range_begin, g.visibility_range_end, g.visibility_range_begin_margin, g.visibility_range_end_margin, fm)


func _sample(c: Vector3, d: float, scen: String, gis: Array, n: Array) -> String:
	_all()
	match scen:
		"near", "mid", "far":
			var o: float = {"near": 14.0, "mid": 75.0, "far": 400.0}[scen]
			_face(c, o, true)
			for i in 3:
				await _tick()
			_face(c, d, true)
		"cold":
			_face(c, 300.0, true)
			await _tick()
			_reset_state(gis)
			_face(c, d, true)
		"turn_fast", "turn_slow":
			_face(c, 14.0, true)
			for i in 3:
				await _tick()
			var x := 14.0
			_face(c, x, false)
			await _tick()
			while x < d - 0.01:
				x = minf(x + 5.0, d)
				_face(c, x, false)
				await _tick()
			if scen == "turn_fast":
				_face(c, d, true)
			else:
				# 10°/幀 で振り向く（180°→0°）。回転トリガー（幀間 35° 以上）に掛からない
				var away := (c + Vector3(d * 2.0, 1.7, 0.0)) - cam.global_position
				var toward := (c + Vector3(0, 2.5, 0)) - cam.global_position
				var ang := away.angle_to(toward)
				var steps := int(ceil(ang / deg_to_rad(10.0)))
				var ax := away.cross(toward).normalized()
				if ax.length() < 0.5:
					ax = Vector3.UP
				for i in range(1, steps):
					var dir := away.rotated(ax, ang * float(i) / float(steps))
					cam.look_at(cam.global_position + dir)
					await _tick()
				_face(c, d, true)
	await _tick()   # settle：全層・目標を視錐内に（実ゲームの 1 幀目）
	var cc := await _measure()
	return _classify(cc, n) + "|" + str(cc)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0])
	var guard_mode := "on"
	var step := 1.0
	for a: String in args:
		if a.begins_with("--guard="):
			guard_mode = a.trim_prefix("--guard=")
		elif a == "--quick":
			step = 2.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	vp = root.get_viewport_rid()
	v = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	cam = Camera3D.new()
	cam.fov = 110.0
	cam.far = 3000.0
	root.add_child(cam)
	cam.current = true
	guard = v.get_node_or_null("LodGuardP13")
	if guard != null:
		guard.set("enabled", guard_mode != "off")
		if "--interval0" in args:
			guard.set("minimum_interval", 0.0)   # 探針は 10 ms/幀 で回る → 実時間の間引きを外して『論理』だけ検証する
	print("[W8S] guard node: ", ("あり enabled=" + str(guard.get("enabled"))) if guard != null else "なし（現行の素の挙動）")
	for i in 12:
		await _tick()
	if guard != null:
		print("[W8S] 起動後 primes=", guard.get("primes"), " tracked=", guard.get("tracked"), " scan_ms=%.1f" % (float(guard.get("scan_usec")) / 1000.0), " prime_ms=%.2f restore_ms=%.2f" % [float(guard.get("last_prime_usec")) / 1000.0, float(guard.get("last_restore_usec")) / 1000.0])
	var report := {"guard": guard_mode, "guard_node": guard != null, "targets": {}}
	for T: Dictionary in TARGETS:
		var node := v.get_node(String(T["path"]))
		var saved_layers: Array = []
		var parts := [[], [], []]
		var all_gis: Array = []
		for k in 3:
			var lod := node.get_node("LOD%d" % k)
			var arr: Array = []
			if lod is GeometryInstance3D:
				arr.append(lod)
			for g in lod.find_children("*", "GeometryInstance3D", true, false):
				arr.append(g)
			for g in arr:
				saved_layers.append([g, (g as VisualInstance3D).layers])
				(g as VisualInstance3D).layers = LAYERS[k]
				all_gis.append(g)
			parts[k] = arr
		var n := [0, 0, 0]
		for k in 3:
			for g in parts[k]:
				if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
					n[k] += (g as MeshInstance3D).mesh.get_surface_count()
		var c: Vector3 = (node as Node3D).global_position
		var e: Array = T["e"]
		print("[W8S] ", T["name"], " 部品 ", [parts[0].size(), parts[1].size(), parts[2].size()], " 表面 = ", n, "  境界 ", e)
		var tr := {"n": n, "e": e, "scen": {}}
		# (1) 全距離スイープ：near／mid／far／cold の 4 起点（テレポート）。範囲は境界の少し手前〜奥
		var ds: Array = []
		var d: float = float(e[0]) - 12.0
		while d <= float(e[1]) + 12.0:
			ds.append(d)
			d += step
		for scen in ["near", "mid", "far", "cold"]:
			var cls: Array = []
			var raw: Array = []
			for dd: float in ds:
				var r := await _sample(c, dd, scen, all_gis, n)
				cls.append(r.split("|")[0])
				raw.append(r.split("|")[1])
			var gaps := _runs(ds, cls, "gap")
			var dbl := _runs(ds, cls, "double")
			print("[W8S]   %-9s ok %3d／%d  gap %s  double %s  partial %d" % [scen, cls.count("ok"), cls.size(), str(gaps), str(dbl), cls.count("partial")])
			(tr["scen"] as Dictionary)[scen] = {"d": ds, "cls": cls, "gap_runs": gaps, "double_runs": dbl, "partial": cls.count("partial"), "ok": cls.count("ok")}
		# (2) 振り向き：境界 ±6 m だけ。歩き離れてから振り向く
		var bds: Array = []
		for b: float in e:
			for off in [-6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0]:
				bds.append(b + off)
		for scen in ["turn_fast", "turn_slow"]:
			var cls2: Array = []
			for dd: float in bds:
				var r2 := await _sample(c, dd, scen, all_gis, n)
				cls2.append(r2.split("|")[0])
			var gaps2 := _runs(bds, cls2, "gap")
			var dbl2 := _runs(bds, cls2, "double")
			print("[W8S]   %-9s ok %3d／%d  gap %s  double %s  partial %d" % [scen, cls2.count("ok"), cls2.size(), str(gaps2), str(dbl2), cls2.count("partial")])
			(tr["scen"] as Dictionary)[scen] = {"d": bds, "cls": cls2, "gap_runs": gaps2, "double_runs": dbl2, "partial": cls2.count("partial"), "ok": cls2.count("ok")}
		for sl: Array in saved_layers:
			(sl[0] as VisualInstance3D).layers = int(sl[1])
		(report["targets"] as Dictionary)[String(T["name"])] = tr
	if guard != null:
		report["guard_primes"] = guard.get("primes")
		report["guard_tracked"] = guard.get("tracked")
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t") + "\n")
	f.close()
	print("[W8S] DONE -> ", out_path)
	quit(0)
