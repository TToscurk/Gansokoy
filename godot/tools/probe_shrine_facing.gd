extends SceneTree
## 判斷委製建築的正面朝向：切低處薄片（階梯／緣側會往正面突出），
## 比較薄片重心相對整體幾何中心的 z 偏移。
##
##   Godot --headless --path godot --script tools/probe_shrine_facing.gd

const TARGETS := [
	"res://assets/shrine/拜殿.glb",
	"res://assets/shrine/社務所.glb",
	"res://assets/shrine/手水舍.glb",
	"res://assets/shrine/博麗鳥居.glb",
]


func _init() -> void:
	for p in TARGETS:
		_one(p)
	quit(0)


func _one(path: String) -> void:
	var ps := load(path) as PackedScene
	var inst := ps.instantiate() as Node3D
	var pts := PackedVector3Array()
	var box: Variant = null
	for m in _meshes(inst):
		var mi := m as MeshInstance3D
		var xf := _rel(mi, inst)
		var b := xf * mi.get_aabb()
		box = b if box == null else (box as AABB).merge(b)
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				pts.append(xf * v)
	var bb := box as AABB
	inst.free()
	var ctr_z := bb.position.z + bb.size.z * 0.5
	# 低處薄片：底部 0–12% 高
	var cut := bb.position.y + bb.size.y * 0.12
	var lo_z := 0.0
	var lo_n := 0
	var hi_z := 0.0
	var hi_n := 0
	# 上半（屋頂）薄片：頂部 70–100%
	var top := bb.position.y + bb.size.y * 0.70
	for p in pts:
		if p.y <= cut:
			lo_z += p.z
			lo_n += 1
		elif p.y >= top:
			hi_z += p.z
			hi_n += 1
	var lo := (lo_z / maxf(lo_n, 1)) - ctr_z
	var hi := (hi_z / maxf(hi_n, 1)) - ctr_z
	print("[FACE] %-8s  z 中心 %.3f  底部薄片重心偏移 %+.4f  頂部薄片偏移 %+.4f  (%d/%d 點)"
		% [path.get_file().get_basename(), ctr_z, lo, hi, lo_n, hi_n])


func _meshes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		o.append(n)
	for c in n.get_children():
		o.append_array(_meshes(c))
	return o


func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
