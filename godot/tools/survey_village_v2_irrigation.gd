extends SceneTree
## P10 R5b.1 IRRIGATION DESIGN REVIEW 用の計測（只讀、headless）。
##   godot --headless --path godot --script res://tools/survey_village_v2_irrigation.gd -- --out=<json>
## 測るもの：
##   1 水面：Water 下の MeshInstance（主河・水渠・細渠・跌水）の頂点から、中心線に沿った水面高さ（layout の pts に最近い頂点の y）
##   2 田面：P8 FarmlandP8 の田（Irrigation／FieldDetails）の水面・内渠・水路鎖の現状（WaterSupply の子ノード・可視・碰撞）
##   3 地形：農田〜水渠〜主河の地形高さ格子（4 m）と、候補ルート沿いの地形断面（1 m）
##   4 現状の P8 取水鎖：CHUTE／DROP_BOX／UPPER／SIPHON／TROUGH の水位（lib 定数）と、WaterLifeP10 が runtime で止めている部材
const FL := preload("res://tools/village_v2_farmland_lib.gd")
const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"

var V: Node3D
var sp: PhysicsDirectSpaceState3D
var terr: CollisionObject3D


func _init() -> void:
	_run.call_deferred()


func _ground(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 120, z), Vector3(x, -40, z))
	var ex: Array[RID] = []
	for t in 16:
		q.exclude = ex
		var h := sp.intersect_ray(q)
		if h.is_empty():
			return NAN
		if h["collider"] == terr:
			return float(h["position"].y)
		ex.append(h["rid"])
	return NAN


func _water_profile(mi: MeshInstance3D, pts: Array, step := 5.0) -> Array:
	var vs: PackedVector3Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var xf := mi.global_transform
	var wv := PackedVector3Array()
	for v in vs:
		wv.append(xf * v)
	var out := []
	var s := 0.0
	for i in pts.size() - 1:
		var a := Vector2(pts[i][0], pts[i][1])
		var b := Vector2(pts[i + 1][0], pts[i + 1][1])
		var n := maxi(1, int(a.distance_to(b) / step))
		for k in n:
			var p := a.lerp(b, float(k) / n)
			var best := INF
			var by := NAN
			for w in wv:
				var d := Vector2(w.x, w.z).distance_squared_to(p)
				if d < best:
					best = d
					by = w.y
			out.append({"s": snappedf(s + a.distance_to(p), 0.1), "x": snappedf(p.x, 0.1), "z": snappedf(p.y, 0.1), "water_y": snappedf(by, 0.01), "near_m": snappedf(sqrt(best), 0.1), "ground_y": snappedf(_ground(p.x, p.y), 0.01)})
		s += a.distance_to(b)
	return out


func _run() -> void:
	var out_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.trim_prefix("--out=")
	V = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(V)
	for i in 4:
		await process_frame
	await physics_frame
	await physics_frame
	sp = V.get_world_3d().direct_space_state
	terr = V.get_node("Collision/TerrainCollision") as CollisionObject3D
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var W: Dictionary = L["water"]
	var R := {"water": {}, "nodes": {}}
	# 1 水面
	var wm := {}
	for mi in V.get_node("Water").find_children("*", "MeshInstance3D", true, false):
		wm[String(mi.name)] = mi
		R["nodes"][String(V.get_path_to(mi))] = (mi as MeshInstance3D).get_aabb().size
	print("[IRR] Water meshes：", wm.keys())
	for key in ["MainRiver", "Canal"]:
		var mi: MeshInstance3D = null
		for nm in wm:
			if String(nm).to_lower().contains(key.to_lower()):
				mi = wm[nm]
				break
		if mi == null:
			print("[IRR] %s の水面 mesh が見つからない" % key)
			continue
		R["water"][key] = _water_profile(mi, W[key]["pts"])
		var pr: Array = R["water"][key]
		print("[IRR] %s 水面：上流 %.2f（s 0）→ 下流 %.2f（s %.0f）、標本 %d" % [key, float(pr[0]["water_y"]), float(pr[pr.size() - 1]["water_y"]), float(pr[pr.size() - 1]["s"]), pr.size()])
	# 2 P8 取水鎖と田
	var farm := V.find_child("FarmlandP8", true, false)
	R["farm_node"] = String(V.get_path_to(farm)) if farm else ""
	var ws := []
	if farm:
		var sup := farm.find_child("WaterSupply", true, false)
		for n in farm.find_children("WaterSupply", "", true, false):
			for c in n.get_children():
				var vis: bool = (c as Node3D).visible if c is Node3D else true
				var dis: bool = (c as CollisionShape3D).disabled if c is CollisionShape3D else false
				ws.append({"path": String(V.get_path_to(c)), "class": c.get_class(), "visible": vis, "disabled": dis})
	R["water_supply_children"] = ws
	R["p8_chain"] = {"CHUTE": FL.CHUTE.map(func(v): return [v.x, v.y, v.z]), "DROP_BOX": [FL.DROP_BOX.x, FL.DROP_BOX.y], "UPPER": FL.UPPER.map(func(v): return [v.x, v.y]),
		"UPPER_LIFT": FL.UPPER_LIFT, "SIPHON": FL.SIPHON.map(func(v): return [v.x, v.y]), "SIPHON_WATER": FL.SIPHON_WATER, "TROUGH": FL.TROUGH.map(func(v): return [v.x, v.y]),
		"TROUGH_BOT": FL.TROUGH_BOT, "CH_WATER_S": FL.CH_WATER_S, "CH_WATER_N": FL.CH_WATER_N}
	# 3 地形格子（農田〜水渠〜主河）
	var grid := []
	for zi in range(-200, 152, 4):
		var row := []
		for xi in range(300, 560, 4):
			row.append(snappedf(_ground(xi, zi), 0.01))
		grid.append(row)
	R["terrain_grid"] = {"x0": 300, "z0": -200, "step": 4, "rows": grid}
	# 田面（farm_level）
	var fl := []
	for p in [Vector2(390, 15), Vector2(390, 35), Vector2(390, 52), Vector2(415, 15), Vector2(415, 30), Vector2(415, 48)]:
		fl.append({"x": p.x, "z": p.y, "farm_level": snappedf(TLib.farm_level(L, p), 0.01), "ground": snappedf(_ground(p.x, p.y), 0.01)})
	R["farm_levels"] = fl
	print("[IRR] 田面：", JSON.stringify(fl))
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(R, " "))
		f.close()
	quit(0)
