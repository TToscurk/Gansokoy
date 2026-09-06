extends SceneTree
## Inspect whether Godot's own import-time LOD chain exists on the Meshy
## buildings, and how far it actually simplifies.
##
## Why before touching Blender: every machiya .import already has
## meshes/generate_lods=true, and project.godot has no mesh_lod_threshold
## override (so it sits at the 1.0 px default). If those chains are healthy,
## tuning one project setting is the entire fix and no asset work is needed.
## If they are degenerate, that proves offline decimation is required.
##
## Godot exposes LOD data through ArrayMesh.surface_get_lods(), which returns
## {screen_ratio: index_bytes}. Empty dict = no LOD for that surface.

const BUILDINGS := [
	"res://assets/machiya/小町家1.glb",
	"res://assets/machiya/市集商家.glb",
	"res://assets/machiya/町家.glb",
	"res://assets/machiya/長屋.glb",
	"res://assets/machiya/倉庫.glb",
	"res://assets/machiya/大町家.glb",
	"res://assets/machiya/農舍.glb",
]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("%-14s %10s %8s %10s %s" % ["模型", "LOD0面數", "LOD階數", "最簡面數", "簡化率"])
	for path in BUILDINGS:
		var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
		if packed == null:
			print("%-14s  載入失敗" % path.get_file())
			continue
		var inst := packed.instantiate()
		var meshes: Array[MeshInstance3D] = []
		_collect(inst, meshes)

		var base := 0
		var lod_steps := 0
		var coarsest := 0
		for mi in meshes:
			var am := mi.mesh as ArrayMesh
			if am == null:
				continue
			for s in am.get_surface_count():
				var idx = am.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
				var tris := 0
				if idx != null:
					tris = idx.size() / 3
				base += tris

				var lods: Dictionary = am.surface_get_lods(s)
				lod_steps = maxi(lod_steps, lods.size())
				if lods.is_empty():
					# No LOD for this surface: it renders at full density always.
					coarsest += tris
				else:
					# Coarsest entry = the largest screen_ratio key.
					var ratios := lods.keys()
					ratios.sort()
					var last = lods[ratios[ratios.size() - 1]]
					coarsest += last.size() / 4 / 3
		var pct := 100.0 * float(coarsest) / maxf(base, 1.0)
		print("%-14s %10d %8d %10d %8.1f%%" % [
			path.get_file().replace(".glb", ""), base, lod_steps, coarsest, pct])
		inst.free()

	print("done")
	quit(0)


func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
