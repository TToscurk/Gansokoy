extends SceneTree
## P13 W7 診断（唯読・headless）：指定の道路 MeshInstance3D と FarmlandTerrain（visual mesh）の高さを格子上で比較する。
##   godot --headless --path . --script res://tools/p13/w7/w7_probe_ribbon_gap.gd -- <road node path> <x0> <x1> <xstep> <z0> <z1> <zstep>
## 出力：行＝z、列＝x の「ribbon_y - terrain_y」（cm）。正＝ribbon が上、負＝地形が上（ribbon を隠す）。'.' は mesh なし。
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _hit_y(tm: TriangleMesh, xf: Transform3D, x: float, z: float) -> float:
	var inv := xf.affine_inverse()
	var from := inv * Vector3(x, 100.0, z)
	var to := inv * Vector3(x, -100.0, z)
	var h := tm.intersect_ray(from, (to - from).normalized())
	if h.is_empty():
		return NAN
	return (xf * (h["position"] as Vector3)).y


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var rpath := String(a[0])
	var x0 := float(a[1])
	var x1 := float(a[2])
	var xs := float(a[3])
	var z0 := float(a[4])
	var z1 := float(a[5])
	var zs := float(a[6])
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 10:
		await process_frame
	var rd := v.get_node(rpath) as MeshInstance3D
	var tr := v.get_node("Terrain/FarmlandTerrain") as MeshInstance3D
	var main_t := v.get_node("Terrain/MainTerrain") as MeshInstance3D
	var rtm := rd.mesh.generate_triangle_mesh()
	var ttm := tr.mesh.generate_triangle_mesh()
	var mtm := main_t.mesh.generate_triangle_mesh()
	print("[W7R] road=", rpath, " mesh=", rd.mesh.resource_path.get_file(), " aabb=", rd.global_transform * rd.mesh.get_aabb())
	var hdr := "z\\x   "
	var x := x0
	while x <= x1 + 0.001:
		hdr += "%6.0f" % x
		x += xs
	print("[W7R] ", hdr)
	var z := z0
	while z <= z1 + 0.001:
		var line := "%6.1f " % z
		x = x0
		while x <= x1 + 0.001:
			var ry := _hit_y(rtm, rd.global_transform, x, z)
			var ty := _hit_y(ttm, tr.global_transform, x, z)
			if is_nan(ty):
				ty = _hit_y(mtm, main_t.global_transform, x, z)
			if is_nan(ry) or is_nan(ty):
				line += "     ."
			else:
				line += "%6d" % roundi((ry - ty) * 100.0)
			x += xs
		print("[W7R] ", line)
		z += zs
	quit(0)
