extends SceneTree
## 量候選牆／籬資產的原始尺寸與面數（只量，不改）。

const PATHS: Array = [
	"res://assets/landscape/竹垣.glb",
	"res://assets/riverbank/塊石疊砌牆一段.glb",
	"res://assets/shrine/袖石垣.glb",
	"res://assets/_lod/袖石垣.glb",
	"res://imported_models/Japanese Castle Wall/Japanese Castle Wall.glb",
]

func _init() -> void:
	for p in PATHS:
		var ps: PackedScene = load(p)
		if ps == null:
			print("ASSET %s LOAD_FAIL" % p)
			continue
		var inst: Node3D = ps.instantiate()
		var acc := AABB()
		var has := false
		var faces := 0
		var mats := 0
		var stack: Array = [[inst, Transform3D.IDENTITY]]
		while not stack.is_empty():
			var pair: Array = stack.pop_back()
			var n: Node = pair[0]
			var xf: Transform3D = pair[1]
			if n is Node3D:
				xf = xf * (n as Node3D).transform
			if n is MeshInstance3D and n.mesh != null:
				var bb: AABB = xf * n.mesh.get_aabb()
				acc = acc.merge(bb) if has else bb
				has = true
				faces += n.mesh.get_faces().size() / 3
				mats += n.mesh.get_surface_count()
			for c in n.get_children():
				stack.push_back([c, xf])
		print("ASSET %s size=(%.2f, %.2f, %.2f) min_y=%.2f faces=%d surfaces=%d" % [
			p, acc.size.x, acc.size.y, acc.size.z, acc.position.y, faces, mats])
		inst.free()
	quit(0)
