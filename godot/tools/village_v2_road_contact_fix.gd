extends SceneTree
## 道路「可見面 ↔ 碰撞」修正（village_v2，2026-10-18 FIX_REVIEW）。
##
## 實測根因（tools/diag_village_v2_road_vs_collision.gd／diag_village_v2_foot_contact.gd）：
##   Roads/** 的 ribbon 是純渲染（沒有碰撞），離地形 +0.06（巷道）／+0.10（主街・次要道路・農道 2/3/5）；
##   玩家站在 Collision/TerrainCollision（= 地形可見面，差 0.000）上 → 鞋底在可見路面下 6–10 cm（另加動畫本身 1.5 cm）。
## 為什麼不把路面往下貼地（tools/diag_village_v2_road_riders.gd 實測）：NPC（Population/*P10）、街道道具（StreetP10）、
##   參道石階、燈籠、河岸、地被地面……共約 2.6 萬個頂點以「路面頂」為地面 → 路面一降，它們全部浮起 6–10 cm。
##   路面頂才是這個村子實際的地面基準，所以讓碰撞跟上路面。
## 路緣裙邊（垂直補面）試過後撤回：玩家可到的機位（低角 0.30 m／TPS 2.3 m）原本就看不到路面下的縫（路緣有 shader 羽化），
##   補上的垂直面反而是近黑色的帶（2026-10-18 同機位開／關對照，實驗已撤回）。
##
## 本工具只做一件事：把「實際顯示中的」路面網格（RoadBaseP10 替換後；surface 0＝ribbon）三角形原樣烘成一個
##   ConcavePolygonShape3D → gen/road_col.res。village_v2.tscn 的 Collision/RoadCollision/Shape 引用它。可見路面 = 碰撞面。
##   改了任何道路網格（或 RoadBaseP10 的 road_meshes）之後重跑本工具。
## 用法：godot --headless --path godot --script res://tools/village_v2_road_contact_fix.gd -- [--dry]

const ROAD_GROUPS := ["MainStreet", "SecondaryRoads", "Alleys", "FarmPaths"]
const COL_OUT := "res://maps/village_v2/gen/road_col.res"


func _init() -> void:
	_run.call_deferred()


func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)


func _run() -> void:
	var dry := OS.get_cmdline_user_args().has("--dry")
	var scn: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(scn)
	for i in 4:
		await process_frame   # RoadBaseP10 等 overlay 在 _ready 的 call_deferred 換 mesh
	var roads: Array = []
	for g in ROAD_GROUPS:
		_meshes(scn.get_node("Roads/" + g), roads)
	var faces := PackedVector3Array()
	for mi: MeshInstance3D in roads:
		var arr := mi.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		var n0 := faces.size()
		if idx != null and (idx as PackedInt32Array).size() > 0:
			for i: int in idx:
				faces.append(mi.global_transform * vs[i])
		else:
			for v in vs:
				faces.append(mi.global_transform * v)
		print("[rcf] %-40s %5d 三角形" % [String(scn.get_path_to(mi)), (faces.size() - n0) / 3])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	print("[rcf] RoadCollision：%d 條路、%d 個三角形" % [roads.size(), faces.size() / 3])
	if not dry:
		print("[rcf] 寫 %s → %s" % [COL_OUT, error_string(ResourceSaver.save(shape, COL_OUT))])
	quit(0)
