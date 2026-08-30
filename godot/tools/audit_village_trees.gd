extends SceneTree
## 量產出物：載入 gen/village_trees.tscn，回報每個樹種的實例數、佈點範圍與
## 高度，並檢查是否有樹落在街廓或借景走廊內。

const BLOCK := Rect2(200.0, -72.0, 70.0, 184.0)
const SIGHT := Rect2(213.0, 94.0, 44.0, 172.0)

func _init() -> void:
	var scn: PackedScene = load("res://maps/slice/gen/village_trees.tscn")
	var root: Node3D = scn.instantiate() as Node3D
	var total: int = 0
	var in_block: int = 0
	var in_sight: int = 0
	for c in root.get_children():
		if not (c is MultiMeshInstance3D):
			continue
		var mmi: MultiMeshInstance3D = c
		var mm: MultiMesh = mmi.multimesh
		if mm == null:
			print("MISSING multimesh on %s" % c.name)
			continue
		var n: int = mm.instance_count
		total += n
		var h: float = 0.0
		if mm.mesh != null:
			h = mm.mesh.get_aabb().size.y
		var x0: float = 1e9; var x1: float = -1e9
		var z0: float = 1e9; var z1: float = -1e9
		var zero: int = 0
		# headless 的 dummy renderer 讓 get_instance_transform() 一律回原點——
		# 讀 buffer 才是實況（stride 12，origin 在 offset 3/7/11）。
		var buf: PackedFloat32Array = mm.buffer
		var stride: int = 16 if mm.use_colors else 12
		for i in range(n):
			var b0: int = i * stride
			var o := Vector3(buf[b0 + 3], buf[b0 + 7], buf[b0 + 11])
			if o.length() < 0.01:
				zero += 1
			x0 = minf(x0, o.x); x1 = maxf(x1, o.x)
			z0 = minf(z0, o.z); z1 = maxf(z1, o.z)
			# 盆樹是刻意種在裏路地外緣的，本來就在街廓矩形內——不計入
			if BLOCK.has_point(Vector2(o.x, o.z)) and not String(c.name).ends_with("盆樹"):
				in_block += 1
			if SIGHT.has_point(Vector2(o.x, o.z)):
				in_sight += 1
		print("%-18s n=%-3d h=%5.1fm  x %6.1f..%6.1f  z %7.1f..%7.1f  原點重疊=%d" % [
			c.name, n, h, x0, x1, z0, z1, zero])
	print("TOTAL %d" % total)
	print("IN_BLOCK %d   IN_SIGHT_CORRIDOR %d   (兩者都必須是 0；盆樹不計)" % [in_block, in_sight])
	root.free()
	quit()
