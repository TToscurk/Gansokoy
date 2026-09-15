extends SceneTree
## 地形 r2 之後，把「跟著地形走」的小物件依**地形高差**平移：
##   Δ = terrain_r2(x,z) − terrain_exit(x,z)，節點 y += Δ。
## 保留產生器原本設計的落地偏移（草 −0.02、石板頂 +0.02+dy…），不重新推算。
## 樹已由 fix_shrine_tree_ground.gd 處理（那支用 AABB 底重新落地）。
##
##   Godot --headless --path godot --script tools/fix_shrine_ground_objects.gd -- [--dry]

const SCENE := "res://maps/shrine/shrine.tscn"
const OLD_T := "res://maps/shrine/gen/terrain_exit.res"
const NEW_T := "res://maps/shrine/gen/terrain_r2.res"
const HALF := 75.0
const GROUPS := ["植被/地表植被", "鋪石/參道鋪石", "鋪石/境內鋪石", "鋪石/飛石_本殿", "鋪石/飛石_東側"]

var _old: PackedFloat32Array
var _new: PackedFloat32Array
var _res := 0
var _step := 0.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var dry := "--dry" in OS.get_cmdline_user_args()
	_old = _grid(load(OLD_T))
	_new = _grid(load(NEW_T))
	var ps := load(SCENE) as PackedScene
	var rootn := ps.instantiate() as Node3D
	root.add_child(rootn)
	await process_frame
	var moved := 0
	var total := 0
	var worst := 0.0
	var per := {}
	for gp in GROUPS:
		var g := rootn.get_node_or_null(gp)
		if g == null:
			print("[FG] 找不到 " + gp)
			continue
		# 地表植被下面還有一層樹種容器；鋪石直接是 MeshInstance3D
		var items: Array = []
		for c in g.get_children():
			if c is MeshInstance3D or c.scene_file_path != "":
				items.append(c)
			else:
				for cc in c.get_children():
					items.append(cc)
		var n := 0
		var mx := 0.0
		for it in items:
			if not (it is Node3D):
				continue
			var p: Vector3 = (it as Node3D).global_position
			if absf(p.x) > HALF or absf(p.z) > HALF:
				continue
			total += 1
			var d := _h(_new, p.x, p.z) - _h(_old, p.x, p.z)
			if absf(d) < 0.01:
				continue
			n += 1
			moved += 1
			mx = maxf(mx, absf(d))
			worst = maxf(worst, absf(d))
			if not dry:
				(it as Node3D).global_position = p + Vector3(0.0, d, 0.0)
		per[gp] = [items.size(), n, mx]
		print("[FG] %-14s %5d 件，平移 %4d 件，最大 |Δ| %.2f m" % [gp, items.size(), n, mx])
	print("[FG] 合計 %d 件、平移 %d、最大 %.2f m" % [total, moved, worst])
	if dry:
		print("[FG] DRY RUN")
		quit(0)
		return
	var out := PackedScene.new()
	_reown(rootn, rootn)
	var err := out.pack(rootn)
	if err == OK:
		err = ResourceSaver.save(out, SCENE)
	print("[FG] SAVE err=%d" % err)
	quit(0 if err == OK else 1)


func _grid(m: ArrayMesh) -> PackedFloat32Array:
	var v: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_res = int(round(sqrt(float(v.size()))))
	_step = 2.0 * HALF / float(_res - 1)
	var g := PackedFloat32Array()
	g.resize(v.size())
	for p in v:
		g[int(round((p.z + HALF) / _step)) * _res + int(round((p.x + HALF) / _step))] = p.y
	return g


func _h(g: PackedFloat32Array, x: float, z: float) -> float:
	var fx := (x + HALF) / _step
	var fz := (z + HALF) / _step
	var i := clampi(int(floor(fx)), 0, _res - 2)
	var j := clampi(int(floor(fz)), 0, _res - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	var a := g[j * _res + i]
	var b := g[j * _res + i + 1]
	var c := g[(j + 1) * _res + i]
	var d := g[(j + 1) * _res + i + 1]
	if tx + tz <= 1.0:
		return a + (b - a) * tx + (c - a) * tz
	return d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)


func _reown(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		if c.owner != null:
			c.owner = owner_node
		if c.get_child_count() > 0 and c.scene_file_path == "":
			_reown(c, owner_node)
