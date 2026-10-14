extends SceneTree
## 診断：DrapeFix の原網格 vs 修正網格で、どの属性スロットが（どれだけ）違うか。
const SCENE := "res://maps/village_v2/village_v2.tscn"
const SLOTS := {"normal": Mesh.ARRAY_NORMAL, "color": Mesh.ARRAY_COLOR, "uv": Mesh.ARRAY_TEX_UV, "uv2": Mesh.ARRAY_TEX_UV2, "index": Mesh.ARRAY_INDEX, "tangent": Mesh.ARRAY_TANGENT, "custom0": Mesh.ARRAY_CUSTOM0}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 10:
		await process_frame
	var fx := v.get_node("DrapeFixP13")
	var paths: PackedStringArray = fx.get("paths")
	fx.set("enabled", false)
	await process_frame
	var origs := {}
	var fmts := {}
	for p in paths.slice(0, 6):
		var mi := v.get_node(NodePath(p)) as MeshInstance3D
		origs[p] = mi.mesh.surface_get_arrays(0)
		fmts[p] = mi.mesh.surface_get_format(0)
	fx.set("enabled", true)
	await process_frame
	for p in paths.slice(0, 6):
		var mi := v.get_node(NodePath(p)) as MeshInstance3D
		var a: Array = origs[p]
		var b: Array = mi.mesh.surface_get_arrays(0)
		var line := "%s fmt orig=%d new=%d" % [p.get_slice("/", 2) + "/" + p.get_slice("/", 3), fmts[p], mi.mesh.surface_get_format(0)]
		for nm in SLOTS.keys():
			var s: int = SLOTS[nm]
			var ea = a[s]
			var eb = b[s]
			if ea == null and eb == null:
				continue
			if (ea == null) != (eb == null):
				line += " | %s: presence differs (%s vs %s)" % [nm, str(ea != null), str(eb != null)]
				continue
			if ea == eb:
				line += " | %s: equal" % nm
			else:
				var maxd := 0.0
				var cnt := 0
				var n := mini(ea.size(), eb.size())
				for k in n:
					var d := 0.0
					match typeof(ea[k]):
						TYPE_VECTOR3:
							d = (ea[k] - eb[k]).length()
						TYPE_VECTOR2:
							d = (ea[k] - eb[k]).length()
						TYPE_COLOR:
							d = absf(ea[k].r - eb[k].r) + absf(ea[k].g - eb[k].g) + absf(ea[k].b - eb[k].b) + absf(ea[k].a - eb[k].a)
						TYPE_INT:
							d = absf(float(ea[k]) - float(eb[k]))
						_:
							d = 0.0
					if d > 1e-6:
						cnt += 1
					maxd = maxf(maxd, d)
				line += " | %s: DIFF n=%d/%d max=%.5f (size %d vs %d)" % [nm, cnt, n, maxd, ea.size(), eb.size()]
		print("[DIAGB1] ", line)
	quit(0)
