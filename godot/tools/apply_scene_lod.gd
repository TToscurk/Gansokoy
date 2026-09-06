extends SceneTree
## Apply distance culling and shadow limits to maps/slice.
##
## Why this rewrite: the first version keyed rules on guessed node-name
## fragments and touched almost nothing — 2691 shrubs and 2785 stones kept
## casting shadows because their real names (Clover, Petal, Pebble_Round) were
## not in the keyword list, and a protect entry ("石") accidentally shielded the
## entire 石頭 group. list_group_names.gd produced the actual names and per-copy
## triangle counts, so this version decides from MEASURED SIZE, with names used
## only to protect things that must never be culled.
##
## Size is the honest signal: a 124-triangle pebble and a 379-triangle clover
## need identical treatment regardless of what they are called, and a rule based
## on triangle count cannot silently miss a category the way a keyword list can.
##
## Distances are set against the village's real scale — the street runs ~200 m,
## the far hills sit ~500 m out — and every value is a node property the user
## can override in the inspector.
##
## Run: godot --headless --path godot --script tools/apply_scene_lod.gd

const SCENE := "res://maps/slice/slice.tscn"

# [max_tris_per_copy, visible_end_m, cast_shadow]
# Ordered small to large; first match wins.
const TIERS := [
	# Ground clutter: pebbles, petals, clover, tiny plants. Individually
	# invisible past a few dozen metres and contributes nothing to shadows.
	{"tris": 500, "vis": 40.0, "shadow": false, "label": "細碎地被 (<500面)"},

	# Small props and grass tufts.
	{"tris": 1500, "vis": 65.0, "shadow": false, "label": "小型草木道具 (<1.5k面)"},

	# Bushes, ferns, fences, lanterns.
	{"tris": 4000, "vis": 100.0, "shadow": true, "label": "灌木與院落道具 (<4k面)"},

	# Small trees, market stalls, paddy tiles.
	{"tris": 25000, "vis": 190.0, "shadow": true, "label": "小樹與攤棚 (<25k面)"},

	# Everything larger — the commissioned architecture. Never culled: these are
	# the skyline. Their cost is the mesh density itself, which is a separate
	# (art-approval) decision.
	{"tris": 999999999, "vis": 0.0, "shadow": true, "label": "建築與大型物件"},
]

# Nodes that must keep full visibility and shadows regardless of size.
# Matched on the node's OWN name only — the previous version walked ancestors
# and let "石" shield 2785 pebbles under the 石頭 parent.
const PROTECT_EXACT := [
	"UnifiedGround", "BasinHills", "Terrain", "GroundUnderlay",
	"EastRiverWater", "EastRiverRevetment",
]

# Ancestor names whose whole subtree is protected (collision proxy, water).
const PROTECT_SUBTREE := [
	"地面碰撞_刷筆用", "CanalWater", "PaddyWater",
]


func _init() -> void:
	var packed: PackedScene = load(SCENE)
	var root: Node = packed.instantiate()

	var counts := {}
	var stats := {"vis": 0, "shadow_off": 0, "protected": 0, "no_mesh": 0}

	_walk(root, counts, stats)

	print("=== 套用可見距離與陰影裁剪 ===\n")
	print("%-30s %8s %10s %8s" % ["分級", "數量", "可見距離", "投影"])
	for t in TIERS:
		var n: int = counts.get(t["label"], 0)
		if n == 0:
			continue
		print("%-30s %8d %10s %8s" % [
			t["label"], n,
			"不限" if t["vis"] <= 0.0 else "%.0f m" % t["vis"],
			"開" if t["shadow"] else "關"])

	print("\n  設定可見距離 %d 個" % stats["vis"])
	print("  關閉投影     %d 個" % stats["shadow_off"])
	print("  保護未動     %d 個" % stats["protected"])

	var out := PackedScene.new()
	var err := out.pack(root)
	if err != OK:
		push_error("pack failed: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(out, SCENE)
	if err != OK:
		push_error("save failed: %d" % err)
		quit(1)
		return
	print("\n[done] 已寫回 %s" % SCENE)
	root.free()
	quit(0)


func _walk(node: Node, counts: Dictionary, stats: Dictionary) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		if _protected(gi):
			stats["protected"] += 1
		else:
			var tris := _tris_of(gi)
			if tris <= 0:
				stats["no_mesh"] += 1
			else:
				for t in TIERS:
					if tris <= t["tris"]:
						_apply(gi, t, stats)
						counts[t["label"]] = counts.get(t["label"], 0) + 1
						break
	for c in node.get_children():
		_walk(c, counts, stats)


func _apply(gi: GeometryInstance3D, tier: Dictionary, stats: Dictionary) -> void:
	var vis: float = tier["vis"]
	if vis > 0.0:
		gi.visibility_range_end = vis
		# Fade instead of pop; 18% of the range is enough to hide the swap.
		gi.visibility_range_end_margin = vis * 0.18
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		stats["vis"] += 1

	if not tier["shadow"]:
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			stats["shadow_off"] += 1


func _protected(gi: GeometryInstance3D) -> bool:
	var own := String(gi.name)
	for p in PROTECT_EXACT:
		if own == p:
			return true
	var n: Node = gi
	var depth := 0
	while n != null and depth < 6:
		for p in PROTECT_SUBTREE:
			if String(n.name) == p:
				return true
		n = n.get_parent()
		depth += 1
	return false


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
