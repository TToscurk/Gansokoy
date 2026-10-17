extends "res://tools/p13/w6/w6_base.gd"
## [scratch：丘腳社寺 E2 層隔離 A/B] 唯讀・場景檔不寫（只改記憶體內 visible）。
##   godot --path godot --script <this> -- <outdir/> LAYERS <views.json> --only=v3_front_courtyard,d_ortho_top
## 對指定鏡位，依序隱藏：（無）／GroundcoverP9／MeadowP9／EnvironmentP9／三者全隱＋ShrineGroveP9＋ForestP9 → 剩下的就是地形本身（含 Roads／Yards）。
const SETS := [
	["base", []],
	["no_gc", ["Vegetation/GroundcoverP9"]],
	["no_meadow", ["Vegetation/MeadowP9"]],
	["no_env", ["Props/EnvironmentP9"]],
	["no_gc_meadow", ["Vegetation/GroundcoverP9", "Vegetation/MeadowP9"]],
	["terrain_only", ["Vegetation/GroundcoverP9", "Vegetation/MeadowP9", "Props/EnvironmentP9", "Vegetation/ShrineGroveP9", "Vegetation/ForestP9"]],
]


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var tag := args[1]
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	var only := PackedStringArray()
	for a in args:
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(out)
	await _boot()
	var dn := root.get_node_or_null("/root/DayNight")
	if dn:
		dn.flowing = false
		dn.set_hour(10.0)
	await _frames(20)
	var all_views: Array = (spec["views"] as Array).duplicate()
	var o: Dictionary = spec["ortho"]
	all_views.append({"name": o["name"], "ortho": true})
	for v: Dictionary in all_views:
		if not only.is_empty() and not (String(v["name"]) in only):
			continue
		if v.get("ortho", false):
			await _tpw(Vector2(228.0, -158.0), Vector2(0, -1))
		else:
			var pl: Array = v["player"]
			if pl[0] != null:
				await _tpw(Vector2(float(pl[0]), float(pl[1])), Vector2(float(pl[2]), float(pl[3])))
			else:
				await _tpw(Vector2(float(v["pos"][0]), float(v["pos"][2])), Vector2(float(pl[2]), float(pl[3])))
		var fc := Camera3D.new()
		root.add_child(fc)
		if v.get("ortho", false):
			fc.projection = Camera3D.PROJECTION_ORTHOGONAL
			fc.size = float(o["size"])
			fc.near = 0.5
			fc.far = 200.0
			var c: Array = o["center"]
			fc.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(c[0], float(o["height"]), c[1]))
		else:
			fc.fov = float(v["fov"])
			var p: Array = v["pos"]
			var lk: Array = v["look"]
			fc.global_transform = Transform3D(Basis(), Vector3(p[0], p[1], p[2])).looking_at(Vector3(lk[0], lk[1], lk[2]), Vector3.UP)
		fc.make_current()
		for s: Array in SETS:
			var hidden: Array = []
			for pth: String in s[1]:
				var n := vil.get_node_or_null(pth) as Node3D
				if n != null and n.visible:
					n.visible = false
					hidden.append(n)
			await _shot("%s_%s_%s" % [tag, v["name"], s[0]], 16)
			for n: Node3D in hidden:
				n.visible = true
			await _frames(2)
		fc.queue_free()
		await _frames(2)
	print("[LAYERS] done")
	quit(0)
