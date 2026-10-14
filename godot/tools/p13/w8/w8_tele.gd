extends "res://tools/p13/w6/w6_base.gd"
## P13 Wave 8 TASK A：正常ゲーム流程（main.tscn → ReviewStart → village_v2、実際の玩家と SpringArm TPS）での LOD 可視の再現と修正後検証。
##   [W8_LOD_GUARD_OFF=1] godot --path . --script res://tools/p13/w8/w8_tele.gd -- <outdir/> <tag>
##   W8_LOD_GUARD_OFF を立てると LodGuardP13 は起動直後から止まる（Before 用。--disable は boot 後なので既に初期化済みで基線にならない）
## 各シナリオ：玩家を『状態を作る位置』へテレポート → 目標位置へテレポート → 通常の TPS 画面を撮る →
##   **同じ相機位置のまま**南大門 Hero の LOD0／1／2 を専用 layer に載せ、相機の cull_mask でその級だけ描かせて可視表面数を読む（状態は動かさない）。
## 場景ファイルは書かない。
const GATE_PATH := "Landmarks/LANDMARK_SOUTH_GATE/Hero"
const LAYERS := [1 << 19, 1 << 18, 1 << 17]
## 目標：南大門を北に見る。相機〜門 AABB 中心 ≈ 55–61 m（W7 で消えた 61.7 m の帯）。face は北（-z）
## W7 で南大門が消えた序列の終点 f001（玩家 226.4, 152.7 → 相機〜門 61.7 m）
const TARGETS := [[226.4, 152.7]]
## 状態を作る位置：near＝門の足元（LOD0 帯）／far＝遠い（LOD2 帯）／mid＝LOD1 帯
const ORIGINS := {"near": [234.0, 118.0], "far": [258.0, -146.0], "mid": [222.9, 197.5]}   # 村内の点だけ（村外へ落ちると換圖が走る）

var _gate: Node = null


func _gate_parts() -> Array:
	var res := [[], [], []]
	for k in 3:
		var l := _gate.get_node("LOD%d" % k)
		if l is GeometryInstance3D:
			res[k].append(l)
		for g in l.find_children("*", "GeometryInstance3D", true, false):
			res[k].append(g)
	return res


func _surfaces(arr: Array) -> int:
	var n := 0
	for g in arr:
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			n += (g as MeshInstance3D).mesh.get_surface_count()
	return n


## 診断：南大門 Hero の可視範囲をクリア→設定し直し＝インスタンスの可視状態を 0 にする（初回ロード直後の状態）
func _reset_gate_state() -> void:
	var parts := _gate_parts()
	for k in 3:
		for g: GeometryInstance3D in parts[k]:
			var fm := int(g.visibility_range_fade_mode) as RenderingServer.VisibilityRangeFadeMode
			RenderingServer.instance_geometry_set_visibility_range(g.get_instance(), 0.0, 0.0, 0.0, 0.0, RenderingServer.VISIBILITY_RANGE_FADE_DISABLED)
			RenderingServer.instance_geometry_set_visibility_range(g.get_instance(), g.visibility_range_begin, g.visibility_range_end, g.visibility_range_begin_margin, g.visibility_range_end_margin, fm)


func _count() -> int:
	return int(RenderingServer.viewport_get_render_info(root.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME))


## 現在の相機位置で、門の LOD0／1／2 のうち実際に可視の表面数を読む（位置・向きは動かさない）
func _probe_gate() -> Dictionary:
	var cam := root.get_viewport().get_camera_3d()
	var parts := _gate_parts()
	var saved: Array = []
	var n := [_surfaces(parts[0]), _surfaces(parts[1]), _surfaces(parts[2])]
	for k in 3:
		for g in parts[k]:
			saved.append([g, (g as VisualInstance3D).layers])
			(g as VisualInstance3D).layers = LAYERS[k]
	var old_mask := cam.cull_mask
	var cnt := []
	for k in 3:
		cam.cull_mask = LAYERS[k]
		await _frames(2)
		cnt.append(_count())
	cam.cull_mask = old_mask
	for sl: Array in saved:
		(sl[0] as VisualInstance3D).layers = int(sl[1])
	await _frames(2)
	var vis := 0
	var which := -1
	for k in 3:
		if cnt[k] > 0:
			vis += 1
			which = k
	var verdict := "GAP" if vis == 0 else ("ok L%d" % which if vis == 1 and cnt[which] == n[which] else "MIX")
	var gc: Vector3 = (parts[0][0] as GeometryInstance3D).global_transform * (parts[0][0] as GeometryInstance3D).get_aabb().get_center()
	return {"counts": cnt, "n": n, "verdict": verdict, "cam_dist": snappedf(cam.global_position.distance_to(gc), 0.1)}


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var tag := args[1]
	var disables: Array = []
	for a: String in args:
		if a.begins_with("--disable="):
			disables.append_array(a.trim_prefix("--disable=").split(",", false))
	DirAccess.make_dir_recursive_absolute(out)
	await _boot()
	for dn: String in disables:
		var dnode := vil.get_node_or_null(NodePath(dn))
		if dnode != null:
			dnode.set("enabled", false)
			print("[W8T] disabled ", dn)
	_gate = vil.get_node(GATE_PATH)
	var guard := vil.get_node_or_null("LodGuardP13")
	print("[W8T] guard=", ("enabled=" + str(guard.get("enabled")) + " primes=" + str(guard.get("primes")) + " tracked=" + str(guard.get("tracked"))) if guard != null else "なし")
	await _frames(10)
	var rows: Array = []
	var north := Vector2(0, -1)
	# シナリオ 0：起動直後（ReviewStart の出発点）から直接テレポート＝初回ロード直後の状態
	var scen: Array = []
	scen.append(["boot", "", TARGETS[0]])        # 起動直後の出発点（ReviewStart）から直接
	for oname in ["mid", "far", "near", "cold"]:  # mid＝W7 の f000／far＝村の北端（門は背後＝視錐外）／near＝門の足元／cold＝可視状態を 1 度クリアしてから
		scen.append([oname, oname, TARGETS[0]])
	for s: Array in scen:
		print("[W8T] -- シナリオ ", s[0], " → ", s[2])
		if String(s[1]) != "":
			var oname2 := "mid" if String(s[1]) == "cold" else String(s[1])
			var o: Array = ORIGINS[oname2]
			await _tpw(Vector2(o[0], o[1]), north)
			if String(s[1]) == "cold":
				_reset_gate_state()   # 初回ロード直後と同じ『可視状態 0』にしてから目標へ
		var tg: Array = s[2]
		await _tpw(Vector2(tg[0], tg[1]), north)
		print("[W8T]    テレポート完了")
		var pr := await _probe_gate()
		print("[W8T]    プローブ完了")
		var nm := "%s_%s_f001" % [tag, s[0]]
		var cr := ""
		if String(s[0]) in ["boot", "mid", "cold"]:
			await _shot(nm, 4)
			cr = nm
		var row := {"origin": s[0], "target": tg, "verdict": pr["verdict"], "counts": pr["counts"], "n": pr["n"], "cam_dist": pr["cam_dist"], "shot": cr}
		rows.append(row)
		print("[W8T] ", s[0], " → z=", tg[1], "  cam→門 ", pr["cam_dist"], " m  可視表面 ", pr["counts"], " / ", pr["n"], "  ", pr["verdict"])
	var gap_n := 0
	for r: Dictionary in rows:
		if String(r["verdict"]) == "GAP":
			gap_n += 1
	print("[W8T] 総括 ", rows.size(), " 回のテレポート中 GAP ", gap_n, " 回")
	var f := FileAccess.open(out + tag + "_rows.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"guard": guard != null and bool(guard.get("enabled")), "rows": rows, "gap": gap_n}, "\t") + "\n")
	f.close()
	quit(0)
