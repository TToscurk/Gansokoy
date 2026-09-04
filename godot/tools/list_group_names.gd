extends SceneTree
## List the real node names under the heavy groups, so LOD rules match on facts
## rather than on guessed keywords.
##
## Why: the first LOD pass reported 2691 shrubs and 2785 stones untouched. Both
## groups ARE in the scene and ARE expensive, so the rules simply did not match
## their actual node names — and one protect-list entry ("石") swallowed the
## whole 石頭 group by accident. Print the names before writing rules again.
##
## Run: godot --headless --path godot --script tools/list_group_names.gd

const SCENE := "res://maps/slice/slice.tscn"
const GROUPS := [
	"灌木叢", "石頭", "地被層", "河岸植生", "草叢",
	"MachiCanal", "B1_Street", "EastBankDressing", "VillageTrees",
]


func _init() -> void:
	var packed: PackedScene = load(SCENE)
	var root: Node = packed.instantiate()

	for g in GROUPS:
		var node := root.find_child(g, true, false)
		if node == null:
			print("\n=== %s === (找不到)" % g)
			continue

		# Sample distinct child names and their geometry cost.
		var seen := {}
		_sample(node, seen, 0)

		print("\n=== %s === (%d 個直接子節點)" % [g, node.get_child_count()])
		var keys := seen.keys()
		keys.sort_custom(func(a, b): return seen[a]["n"] > seen[b]["n"])
		var shown := 0
		for k in keys:
			if shown >= 10:
				print("  ... 還有 %d 種名稱" % (keys.size() - shown))
				break
			var e = seen[k]
			print("  %-40s x%-6d %s面 投影%s" % [
				k.substr(0, 40), e["n"], _fmt(e["tris"]),
				"開" if e["cast"] else "關"])
			shown += 1

	root.free()
	quit(0)


## Collect leaf GeometryInstance3D names, keyed by their own name with any
## trailing digits stripped, so 樹_001/樹_002 collapse into one row.
func _sample(node: Node, seen: Dictionary, depth: int) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		# Use the nearest named ancestor when the leaf is a generic mesh_node,
		# because that is the name a rule would actually have to match.
		var label := String(gi.name)
		if label.begins_with("mesh_node") or label.begins_with("Mesh_"):
			var p := gi.get_parent()
			if p != null:
				label = "%s/%s" % [String(p.name), label]
		label = _strip_index(label)
		if not seen.has(label):
			seen[label] = {"n": 0, "tris": _tris_of(gi), "cast":
				gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF}
		seen[label]["n"] += 1
	for c in node.get_children():
		_sample(c, seen, depth + 1)


func _strip_index(s: String) -> String:
	var out := s
	# Trim "_0012", " (3)" and similar instance suffixes.
	var re := RegEx.new()
	re.compile("(_\\d+|\\s*\\(\\d+\\))$")
	var m := re.search(out)
	if m:
		out = out.substr(0, m.get_start())
	return out


func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


func _tris_of(gi: GeometryInstance3D) -> int:
	var mesh: Mesh = null
	if gi is MeshInstance3D:
		mesh = (gi as MeshInstance3D).mesh
	elif gi is MultiMeshInstance3D:
		var mm := (gi as MultiMeshInstance3D).multimesh
		if mm != null:
			mesh = mm.mesh
	if mesh == null:
		return 0
	var t := 0
	for i in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(i)
		if arr.is_empty():
			continue
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx != null and idx.size() > 0:
			t += idx.size() / 3
		else:
			var v = arr[Mesh.ARRAY_VERTEX]
			if v != null:
				t += v.size() / 3
	return t
