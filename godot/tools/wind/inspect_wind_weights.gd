extends SceneTree
## 量測既有植被網格把風權重（UV2.x）烤成什麼分佈——用來校準 shader 振幅，不靠猜。
##   Godot_v4.7.2-stable_win64_console.exe --headless --path godot \
##     --script res://tools/wind/inspect_wind_weights.gd

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	for path in ["res://maps/village_v2/gen/forest_p9.scn", "res://maps/village_v2/gen/bamboo_p9.scn"]:
		var ps := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if ps == null:
			continue
		var root := ps.instantiate()
		print("\n===== ", path)
		var seen := {}
		_walk(root, func(nd: Node):
			if nd is MeshInstance3D:
				var mi := nd as MeshInstance3D
				if mi.mesh == null:
					return
				var mat: Material = mi.material_override
				if mat == null and mi.mesh.get_surface_count() > 0:
					mat = mi.mesh.surface_get_material(0)
				if not (mat is ShaderMaterial):
					return
				var s := (mat as ShaderMaterial).shader
				var sn := s.resource_path.get_file() if s else "?"
				if not (sn.contains("veg_leaf") or sn.contains("veg_bark")):
					return
				var key := "%s|%s" % [sn, String(mi.mesh.resource_path).get_file()]
				if seen.has(key):
					return
				seen[key] = true
				var arr := mi.mesh.surface_get_arrays(0)
				var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
				var ws := []
				for v in uv2:
					ws.append(v.x)
				if ws.is_empty():
					print("  ", key, " 無 UV2")
					return
				ws.sort()
				var cnt := ws.size()
				var at := func(f: float) -> float: return ws[int(clampf(f, 0.0, 1.0) * (cnt - 1))]
				print("  %-56s n=%6d  p10=%.2f p25=%.2f p50=%.2f p75=%.2f p90=%.2f p99=%.2f max=%.2f" % [
					key, cnt, at.call(0.1), at.call(0.25), at.call(0.5), at.call(0.75), at.call(0.9), at.call(0.99), ws[cnt - 1]])
		)
		root.free()
	quit(0)

func _walk(n: Node, fn: Callable) -> void:
	fn.call(n)
	for c in n.get_children():
		_walk(c, fn)
