extends "res://tools/p13/w6/w6_base.gd"
## P13 Wave 6 調査 2：layout の全道路・全巷道を step m ごと（通常 TPS）＋監査で見つけた要確認点＋参道周辺。
##   godot --path . --script res://tools/p13/w6/w6_survey2.gd -- <outdir/> <tag> [--step=45] [--id] [--only=roads|spots|sando] [--max=N]
const LAYOUT := "res://maps/village_v2/layout_v2.json"

## 監査で見つけた要確認点（名前, 立ち位置 xz, 見る方向の点 xz）
const SPOTS := [
	["hillfoot_bridge_w", Vector2(350.0, -131.0), Vector2(366.0, -131.0)],
	["hillfoot_bridge_e", Vector2(376.0, -130.0), Vector2(360.0, -131.0)],
	["rivernorth_dragon", Vector2(372.0, -198.0), Vector2(380.0, -206.0)],
	["dragonroad_e", Vector2(414.0, -203.0), Vector2(428.0, -205.0)],
	["hillapproach_s", Vector2(296.0, -150.0), Vector2(284.0, -190.0)],
	["hillapproach_n", Vector2(284.0, -190.0), Vector2(270.0, -206.0)],
	["westlane_w", Vector2(172.0, -11.0), Vector2(156.0, -8.0)],
	["riverside_e", Vector2(492.0, -96.0), Vector2(506.0, -97.0)],
	["crosssouth_e", Vector2(330.0, 44.0), Vector2(358.0, 42.0)],
	["crossmid_e", Vector2(350.0, -33.0), Vector2(372.0, -34.0)],
]
const SANDO_S := [4.0, 14.0, 26.0, 37.0, 50.0, 62.0, 78.0, 92.0]


func _road_samples(step: float) -> Array:
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var polys: Array = []
	for r: Dictionary in L["roads"]:
		polys.append([String(r["name"]), r["pts"]])
	for r: Dictionary in L["lanes"]:
		polys.append([String(r["name"]), r["pts"]])
	var res: Array = []
	for pr: Array in polys:
		var pts: Array = pr[1]
		var acc := 0.0
		var next_at := step * 0.5
		for i in range(pts.size() - 1):
			var a := Vector2(float(pts[i][0]), float(pts[i][1]))
			var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
			var ln := a.distance_to(b)
			if ln < 0.01:
				continue
			while next_at <= acc + ln:
				var t := (next_at - acc) / ln
				res.append({"seg": pr[0], "pos": a.lerp(b, t), "face": (b - a).normalized(), "s": next_at})
				next_at += step
			acc += ln
	return res


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var tag := args[1]
	var step := 45.0
	var want_id := false
	var only := "all"
	var mx := 100000
	var lifts: Array = []     # [path, dy]
	var hides: Array = []
	var disables: Array = []
	var ats: Array = []       # [name, pos, tgt]
	for a: String in args:
		if a.begins_with("--step="):
			step = float(a.trim_prefix("--step="))
		elif a == "--id":
			want_id = true
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--max="):
			mx = int(a.trim_prefix("--max="))
		elif a.begins_with("--lift="):
			for it: String in a.trim_prefix("--lift=").split(",", false):
				var kv := it.rsplit(":", true, 1)
				lifts.append([kv[0], float(kv[1])])
		elif a.begins_with("--disable="):
			disables.append_array(a.trim_prefix("--disable=").split(",", false))
		elif a.begins_with("--at="):
			# --at=name:x,z,tx,tz;name2:...
			for it: String in a.trim_prefix("--at=").split(";", false):
				var kv2 := it.split(":")
				var c := kv2[1].split(",")
				ats.append([kv2[0], Vector2(float(c[0]), float(c[1])), Vector2(float(c[2]), float(c[3]))])
		elif a.begins_with("--hide="):
			hides.append_array(a.trim_prefix("--hide=").split(",", false))
	DirAccess.make_dir_recursive_absolute(out)
	cl = SA.centerline()
	await _boot()
	# 診断専用の一時変更（場景ファイルは書かない）
	for lf: Array in lifts:
		var n3 := vil.get_node_or_null(NodePath(String(lf[0]))) as Node3D
		if n3 != null:
			n3.position.y += float(lf[1])
			print("[W6S2] lift ", lf[0], " +", lf[1])
		else:
			print("[W6S2] lift: node not found ", lf[0])
	for hp: String in hides:
		var h3 := vil.get_node_or_null(NodePath(hp)) as Node3D
		if h3 != null:
			h3.visible = false
			print("[W6S2] hide ", hp)
		else:
			print("[W6S2] hide: node not found ", hp)
	for dn: String in disables:
		var dnode := vil.get_node_or_null(NodePath(dn))
		if dnode != null:
			dnode.set("enabled", false)
			print("[W6S2] disabled ", dn)
		else:
			print("[W6S2] disable: node not found ", dn)
	if not disables.is_empty():
		await _frames(4)
	var samples: Array = []
	if only == "at":
		for at: Array in ats:
			var p0: Vector2 = at[1]
			samples.append({"seg": "at_" + String(at[0]), "pos": p0, "face": (Vector2(at[2]) - p0).normalized(), "s": 0.0})
	if only in ["all", "roads"]:
		samples.append_array(_road_samples(step))
	if only in ["all", "spots"]:
		for sp in SPOTS:
			var p: Vector2 = sp[1]
			samples.append({"seg": "spot_" + String(sp[0]), "pos": p, "face": (Vector2(sp[2]) - p).normalized(), "s": 0.0})
	if only == "sandoback":
		for s in [60.0, 80.0, 96.0]:
			var kb := clampi(int(round(s / 0.05)), 0, cl.size() - 1)
			samples.append({"seg": "sandoback", "pos": cl[kb], "face": -SA.tangent(cl, kb), "s": s})
	if only in ["all", "sando"]:
		for s in SANDO_S:
			var k := clampi(int(round(s / 0.05)), 0, cl.size() - 1)
			samples.append({"seg": "sando", "pos": cl[k], "face": SA.tangent(cl, k), "s": s})
	if samples.size() > mx:
		samples = samples.slice(0, mx)
	print("[W6S2] samples ", samples.size())
	var index: Array = []
	for i in samples.size():
		var s: Dictionary = samples[i]
		await _tpw(s["pos"], s["face"])
		var nm := "%s_%03d" % [tag, i]
		await _shot(nm, 6)
		var rec := cam_record()
		rec["i"] = i
		rec["seg"] = s["seg"]
		rec["s"] = snappedf(float(s["s"]), 0.1)
		rec["name"] = nm
		rec["face"] = [snappedf(s["face"].x, 0.001), snappedf(s["face"].y, 0.001)]
		index.append(rec)
	if want_id:
		var n := id_begin()
		print("[W6S2] ID パス：節点 ", n, " bits ", _id_bits)
		await _frames(6)
		for i in samples.size():
			var s: Dictionary = samples[i]
			await _tpw(s["pos"], s["face"])
			await _shot("%s_%03d_id" % [tag, i], 6)
		id_end()
		id_table_save(out + tag + "_idtable.json")
	var f := FileAccess.open(out + tag + "_index.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(index, "\t") + "\n")
	f.close()
	print("[W6S2] DONE")
	quit(0)
