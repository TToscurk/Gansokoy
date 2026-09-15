extends SceneTree
## 人里圍牆端頭收尾：主牆（Japanese Castle Wall，4.1 m 高）四個外端接
## 袖石垣（約 2.6 m）→ 塊石疊砌牆（約 1.3 m）→ 竹垣（約 1.5 m），
## 由高到低退到田界／林緣，取代目前的直切斷面。
## 產出 res://maps/slice/gen/village_wall_ends.tscn（每件可單獨選取），
## 並印出 COLL_JSON 供 data/slice_manual_collision.json 使用。不改 slice.tscn。
##   Godot --headless --path godot --script tools/gen_village_wall_ends.gd

const OUT := "res://maps/slice/gen/village_wall_ends.tscn"
const SINK := 0.12

# 資產（實測原始尺寸：袖石垣 1.90×0.73×0.42 min_y -0.36；塊石 1.00×0.29×0.23 min_y -0.15；竹垣 0.51×0.97×0.61 min_y 0）
const SODE := "res://assets/_lod/袖石垣.glb"
const ISHI := "res://assets/riverbank/塊石疊砌牆一段.glb"
const TAKE := "res://assets/landscape/竹垣.glb"

# 主牆實測外端（probe_village_wall.gd）：
#  南牆 z 96.24..98.79，西端 x 212.29、東端 x 260.07
#  北牆 z -78.17..-75.62，西端 x 212.76、東端 x 258.02
# dir = 往外方向；limit = 最遠可延伸到的 x（避開既有樹／建物，probe_wall_corners.gd）
const ENDS: Array = [
	{"name": "南西", "x": 212.29, "z": 97.5,  "dir": -1.0, "limit": 204.0},
	{"name": "南東", "x": 260.07, "z": 97.5,  "dir":  1.0, "limit": 275.0},
	{"name": "北西", "x": 212.76, "z": -76.9, "dir": -1.0, "limit": 204.5},
	{"name": "北東", "x": 258.02, "z": -76.9, "dir":  1.0, "limit": 272.0},
]

# 每端的退階序列：[資產, 目標高度 m, 件數]
# A（預設）：袖石垣 2.6 → 塊石 1.3 → 竹垣 1.5×4
# B（--variant-b）：不用袖石垣（放大 3.5× 後石塊像巨石堆），改 塊石 2.0×2 → 塊石 1.3 → 竹垣 1.5×6
const STEPS_A: Array = [
	[SODE, 2.6, 1],
	[ISHI, 1.3, 1],
	[TAKE, 1.5, 4],
]
const STEPS_B: Array = [
	[ISHI, 2.0, 2],
	[ISHI, 1.3, 1],
	[TAKE, 1.5, 6],
]

var _verts: PackedVector3Array
var _coll: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var slice: Node3D = load("res://maps/slice/slice.tscn").instantiate()
	root.add_child(slice)
	await process_frame
	_collect_ground(slice)
	slice.queue_free()

	var out := Node3D.new()
	out.name = "圍牆端頭"
	var steps: Array = STEPS_B if "--variant-b" in OS.get_cmdline_user_args() else STEPS_A
	for e in ENDS:
		var cursor: float = e["x"]
		for st in steps:
			for k in st[2]:
				var placed: Array = _place(out, st[0], st[1], cursor, e["z"], e["dir"], e["limit"], "%s_%s_%d" % [e["name"], st[0].get_file().get_basename(), k])
				if placed.is_empty():
					break
				cursor = placed[0]
	var ps := PackedScene.new()
	ps.pack(out)
	var err := ResourceSaver.save(ps, OUT)
	print("WALL_ENDS pieces=%d err=%d -> %s" % [out.get_child_count(), err, OUT])
	print("COLL_JSON " + JSON.stringify(_coll))
	quit(0 if err == OK else 1)


func _collect_ground(slice: Node3D) -> void:
	var g: MeshInstance3D = slice.get_node("UnifiedGround")
	var a: Array = g.mesh.surface_get_arrays(0)
	var all: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var xf: Transform3D = g.global_transform
	for v in all:
		var w: Vector3 = xf * v
		if w.x > 195.0 and w.x < 280.0 and w.z > -100.0 and w.z < 112.0:
			_verts.append(w)
	print("GROUND_VERTS %d" % _verts.size())


func _ground_y(x: float, z: float) -> float:
	var best := INF
	var y := 0.0
	for v in _verts:
		var d := (v.x - x) * (v.x - x) + (v.z - z) * (v.z - z)
		if d < best:
			best = d
			y = v.y
	return y


## 回傳 [新 cursor]；放不下（超過 limit）回傳 []。
func _place(parent: Node3D, path: String, target_h: float, cursor: float, z: float, dir: float, limit: float, nm: String) -> Array:
	var ps: PackedScene = load(path)
	var inst: Node3D = ps.instantiate()
	var bb: AABB = _bbox(inst)
	# 長軸沿 x；竹垣近方形，取較長邊當長度並轉向
	var yaw := 0.0
	var len_local: float = bb.size.x
	var thick: float = bb.size.z
	if bb.size.z > bb.size.x:
		yaw = 90.0
		len_local = bb.size.z
		thick = bb.size.x
	var s: float = target_h / bb.size.y
	var length: float = len_local * s
	var x_end: float = cursor + dir * length
	if (dir < 0.0 and x_end < limit) or (dir > 0.0 and x_end > limit):
		return []
	var cx: float = cursor + dir * length * 0.5
	var gy: float = _ground_y(cx, z)
	inst.name = nm
	inst.rotation_degrees = Vector3(0.0, yaw, 0.0)
	inst.scale = Vector3(s, s, s)
	# 局部中心 → 世界：讓 bbox 中心落在 (cx, z)，底面在 gy - SINK
	var c: Vector3 = bb.position + bb.size * 0.5
	var rc: Vector3 = Vector3(c.x, 0.0, c.z).rotated(Vector3.UP, deg_to_rad(yaw)) * s
	inst.position = Vector3(cx - rc.x, gy - SINK - bb.position.y * s, z - rc.z)
	parent.add_child(inst)
	inst.owner = parent
	_coll.append({"name": "圍牆端頭_" + nm, "pos": [snappedf(cx, 0.01), snappedf(gy - SINK + target_h * 0.5, 0.01), snappedf(z, 0.01)],
		"size": [snappedf(length, 0.01), snappedf(target_h, 0.01), snappedf(maxf(thick * s, 0.6), 0.01)]})
	print("PIECE %-18s x=%.2f..%.2f z=%.2f h=%.2f thick=%.2f ground=%.2f" % [nm, minf(cursor, x_end), maxf(cursor, x_end), z, target_h, thick * s, gy])
	return [x_end]


func _bbox(n: Node3D) -> AABB:
	var acc := AABB()
	var has := false
	var stack: Array = [[n, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var node: Node = pair[0]
		var xf: Transform3D = pair[1]
		if node != n and node is Node3D:
			xf = xf * (node as Node3D).transform
		if node is MeshInstance3D and node.mesh != null:
			var bb: AABB = xf * node.mesh.get_aabb()
			acc = acc.merge(bb) if has else bb
			has = true
		for c in node.get_children():
			stack.push_back([c, xf])
	return acc
