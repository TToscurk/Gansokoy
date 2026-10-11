extends SceneTree
## P12 Final Cleanup A3（只讀、headless）：HUX 015／016 の旧位置（封存 overlay）と新位置（現行計画の rebuild）について、
## LOD0 頂点と P11 R2D 支線（ZoneIrrigation/Branches）可見網格頂点の最短水平距離、HU の P8 禁區パッド 0.4 m との比較。
##   godot --headless --path . --script res://tools/p12/probe_hux_branch_gap.gd -- --old=<abs scn> --new=<abs scn>
const BR := "Districts/FarmlandEast/FarmlandP8/ZoneWorks/ZoneIrrigation/Branches"
const PAD := 0.4   # village_v2_human_use_lib.gd：P8 の田／畦／水路 +0.4

func _init() -> void:
	_run.call_deferred()

func _pts(n: Node, xf_root: Transform3D) -> PackedVector2Array:
	var out := PackedVector2Array()
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).contains("LOD1") or mi.mesh == null:
			continue
		var xf := xf_root * _rel(mi, n)
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var w := xf * v
				out.append(Vector2(w.x, w.z))
	return out

func _rel(n: Node3D, top: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != top:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf

func _run() -> void:
	var a := {}
	for s: String in OS.get_cmdline_user_args():
		if s.begins_with("--old="):
			a["old"] = s.trim_prefix("--old=")
		elif s.begins_with("--new="):
			a["new"] = s.trim_prefix("--new=")
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	var br := v.get_node(BR)
	var bp := _pts(br, _rel(br as Node3D, v))
	print("[HUXGAP] Branches 頂点 %d" % bp.size())
	for tag in ["old", "new"]:
		var r := (ResourceLoader.load(a[tag], "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		for nm in ["015_mk_tsumini", "016_hu_seoikago"]:
			var n := r.find_child(nm, true, false) as Node3D
			var ip := _pts(n, _rel(n, r))
			var best := INF
			for p in ip:
				for q in bp:
					var d := p.distance_squared_to(q)
					if d < best:
						best = d
			best = sqrt(best)
			print("[HUXGAP] %s %s 中心 %s：支線可見網格まで最短 %.3f m（P8 禁區パッド %.1f → %s）" % [tag, nm, _rel(n, r).origin.snappedf(0.01), best, PAD, "違反" if best < PAD else "OK"])
		r.free()
	v.free()
	quit(0)
