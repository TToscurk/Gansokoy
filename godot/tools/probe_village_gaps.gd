extends SceneTree
## 人間之里街廓內空地探勘：把所有建物/道路/設施的 XZ 佔地投影成格點，
## 找出街廓範圍內連續的空地，列出可種樹的候選區塊。
##   --headless --path godot --script tools/probe_village_gaps.gd

const CELL := 2.0
const X0 := 190.0
const X1 := 285.0
const Z0 := -95.0
const Z1 := 135.0
## 這些節點只是地面/水面/植被，不算障礙
const SKIP := ["Terrain", "UnifiedGround", "GroundUnderlay", "BasinHills",
	"EastRiverWater", "EastRiverRevetment", "Shrubs", "Ferns", "GrassTall",
	"GrassFlower", "RiverVegetation", "VillageTrees", "VillageTrees2", "Vista"]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var scn = load("res://maps/slice/slice.tscn").instantiate()
	root.add_child(scn)
	await process_frame
	await process_frame

	var nx := int((X1 - X0) / CELL)
	var nz := int((Z1 - Z0) / CELL)
	var occ: Array = []
	for i in nx * nz:
		occ.append(false)

	var blockers := 0
	for top in scn.get_children():
		if String(top.name) in SKIP:
			continue
		for mi in _meshes(top):
			var b: AABB = mi.global_transform * mi.mesh.get_aabb()
			# 只有高過地面 0.8 m 的東西才算障礙（石板路、田埂不算）
			if b.size.y < 0.8:
				continue
			blockers += 1
			var gx0 := int(floor((b.position.x - X0) / CELL))
			var gx1 := int(floor((b.position.x + b.size.x - X0) / CELL))
			var gz0 := int(floor((b.position.z - Z0) / CELL))
			var gz1 := int(floor((b.position.z + b.size.z - Z0) / CELL))
			for gx in range(maxi(gx0, 0), mini(gx1 + 1, nx)):
				for gz in range(maxi(gz0, 0), mini(gz1 + 1, nz)):
					occ[gz * nx + gx] = true
	print("blockers=%d  grid %dx%d cell %.1f m" % [blockers, nx, nz, CELL])

	# 對每個空格算「離最近障礙的距離」，找出夠大的空地
	var out := PackedStringArray()
	var big: Array = []
	for gz in nz:
		var line := ""
		for gx in nx:
			if occ[gz * nx + gx]:
				line += "#"
			else:
				var r := _clearance(occ, nx, nz, gx, gz, 5)
				if r >= 4:
					line += "O"
					big.append([X0 + gx * CELL + CELL * 0.5, Z0 + gz * CELL + CELL * 0.5, r])
				elif r >= 3:
					line += "o"
				elif r >= 2:
					line += "."
				else:
					line += " "
		out.append("z%+7.1f %s" % [Z0 + gz * CELL, line])
	print("x 由 %.0f 至 %.0f，每格 %.1f m" % [X0, X1, CELL])
	for l in out:
		print(l)
	print("大空地格數(淨空>=8m) = %d" % big.size())
	quit()


## 以 (gx,gz) 為中心，最大能放下的正方形半徑（格）
func _clearance(occ: Array, nx: int, nz: int, gx: int, gz: int, cap: int) -> int:
	for r in range(1, cap + 1):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var x := gx + dx
				var z := gz + dz
				if x < 0 or z < 0 or x >= nx or z >= nz:
					return r - 1
				if occ[z * nx + x]:
					return r - 1
	return cap


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
