extends SceneTree
## 獸道傳送點座標：量主脊兩端在**實際地形網格**上的地面高度。
##
##   Godot --headless --path godot --script tools/probe_trail_portals.gd
##
## meta.json 的 portals[].y 是地面高（main.gd 自己 +1.0 當觸發區中心），
## 所以要餵地面值，不是標記節點的高度。

func _init() -> void:
	var ps := load("res://maps/trail/trail.tscn") as PackedScene
	var root := ps.instantiate() as Node3D
	var terrain := root.get_node_or_null("Terrain") as MeshInstance3D
	if terrain == null:
		print("[PORTAL] 找不到 Terrain")
		root.free(); quit(1); return
	var arr: Array = terrain.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var res := int(round(sqrt(float(vs.size()))))
	var half := 340.0
	var step := 2.0 * half / float(res - 1)

	var mk := root.get_node_or_null("標記")
	if mk != null:
		for c in mk.get_children():
			var n3 := c as Node3D
			var gy := _grid_y(vs, res, half, step, n3.position.x, n3.position.z)
			var tgt: Variant = n3.get_meta("portal") if n3.has_meta("portal") else null
			print("[PORTAL] %-16s xz=(%.2f, %.2f)  節點y=%.2f  地面y=%.2f  target=%s"
				% [c.name, n3.position.x, n3.position.z, n3.position.y, gy, tgt])
	root.free()
	quit(0)


func _grid_y(vs: PackedVector3Array, res: int, half: float, step: float, x: float, z: float) -> float:
	var fi := clampf((x + half) / step, 0.0, float(res - 1))
	var fj := clampf((z + half) / step, 0.0, float(res - 1))
	var i0 := int(floor(fi)); var j0 := int(floor(fj))
	var i1 := mini(i0 + 1, res - 1); var j1 := mini(j0 + 1, res - 1)
	var tx := fi - float(i0); var tz := fj - float(j0)
	var h00 := vs[j0 * res + i0].y
	var h10 := vs[j0 * res + i1].y
	var h01 := vs[j1 * res + i0].y
	var h11 := vs[j1 * res + i1].y
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
