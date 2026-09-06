extends SceneTree
## Recommend Asset Placer brush radius/density per nature collection.
##
## Why this exists: brush_radius/brush_density live only in the plugin's runtime
## UI state (see ui/asset_placer_options/asset_placer_options.gd) — there is no
## file to preset them in, so the user has to type them. This computes the two
## numbers per category from the plugin's OWN spawn formula plus the measured
## XZ footprint of each model, so the values are derived rather than guessed.
##
## Plugin formula (asset_preview_container.gd:30-36):
##   asset_area   = max(0.25, aabb.size.x * aabb.size.z)
##   max_assets   = (PI * r * r / asset_area) * 0.2
##   spawn_count  = round(max_assets * density^2)
## Solving for density at a target count:
##   density = sqrt(target / max_assets)
##
## Targets are per single click-stroke and chosen for hand painting: a few big
## trees, many small ground props. Radius is set from the model footprint so a
## stroke covers a believable clump rather than a parade-ground grid.
##
## Run: godot --headless --path godot --script tools/calc_brush_presets.gd

const NATURE_DIR := "res://assets/nature"

# {collection: [radius_m, target_instances_per_stroke, purpose]}
const PLAN := {
	"地被層": [2.5, 12, "蕨、蘑菇、小植株 — 填草叢之間的空隙"],
	"灌木叢": [3.5, 6, "牆角、路邊、樹下"],
	"草叢": [3.0, 10, "田埂、河岸、荒地"],
	"樹木": [12.0, 3, "村外林緣、河岸散生"],
	"枯木": [15.0, 1, "荒地點景，單株就夠"],
	"石頭": [2.0, 8, "河灘、路肩"],
	"鋪路石": [1.5, 6, "小徑、院子踏石"],
	"花瓣": [2.0, 20, "櫻花樹下散落"],
}

const COL_NAMES := {
	1: "地被層", 2: "灌木叢", 3: "草叢", 4: "樹木",
	5: "枯木", 6: "石頭", 7: "鋪路石", 8: "花瓣",
}


func _init() -> void:
	var lib_path := "user://asset_library.json"
	var f := FileAccess.open(lib_path, FileAccess.READ)
	if f == null:
		push_error("no asset library at %s — run gen_nature_asset_library.gd first" % lib_path)
		quit(1)
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data == null or not data.has("assets"):
		push_error("asset library is malformed")
		quit(1)
		return

	# Group measured footprints by collection.
	var by_col := {}
	for a in data["assets"]:
		var col := int(a["primary_collection"])
		var path: String = a["id"]
		if path.begins_with("uid://"):
			path = ResourceUID.get_id_path(ResourceUID.text_to_id(path))
		var fp := _footprint(path)
		if fp <= 0.0:
			continue
		if not by_col.has(col):
			by_col[col] = []
		by_col[col].append(fp)

	print("Asset Placer 筆刷建議值（依實測尺寸推算）")
	print("欄位: Brush Radius / Brush Density / 一筆約放幾件\n")

	var ids := COL_NAMES.keys()
	ids.sort()
	for col in ids:
		var cname: String = COL_NAMES[col]
		if not PLAN.has(cname):
			continue
		var areas: Array = by_col.get(col, [])
		if areas.is_empty():
			print("== %s ==  (無資產)" % cname)
			continue

		var total := 0.0
		for v in areas:
			total += v
		var avg_area := total / areas.size()
		var asset_area: float = max(0.25, avg_area)

		var target: int = PLAN[cname][1]
		var purpose: String = PLAN[cname][2]

		# The plugin's 0.2 factor makes strokes sparse: at the radii that feel
		# right for hand painting, density pins at 1.0 and still under-delivers.
		# So solve the other way — fix density at 0.7 (leaving headroom to dial
		# up AND down) and report the radius that actually yields the target.
		var d_ref := 0.7
		var r_needed := sqrt(float(target) * asset_area / (0.2 * PI * d_ref * d_ref))

		var radius: float = PLAN[cname][0]
		var max_assets := (PI * radius * radius / asset_area) * 0.2
		var density := sqrt(float(target) / max(max_assets, 0.001))
		density = clampf(density, 0.01, 1.0)
		var actual := int(round(max_assets * pow(density, 2.0)))

		print("== %s ==  (%d 件資產，平均佔地 %.2f m²)" % [cname, areas.size(), avg_area])
		print("   用途: %s" % purpose)
		if density >= 0.99 and actual < target:
			print("   建議: Radius %.1f   Density 0.70   →  一筆約 %d 件" % [r_needed, target])
			print("   (想要細節筆刷改 Radius %.1f + Density 1.00，一筆約 %d 件)" % [radius, actual])
		else:
			print("   建議: Radius %.1f   Density %.2f   →  一筆約 %d 件" % [radius, density, actual])
		print("")

	print("---")
	print("通用設定（不分類別）:")
	print("  Rotate on Placement = 開   Max Rotation Y = 180   (不開會全部同方向，很假)")
	print("  Random Scale        = 開   Min 0.85 / Max 1.15    (樹可放寬到 0.7~1.3)")
	print("  Align Normals       = 關   (開了斜坡上的樹會跟著歪)")
	print("  Group Automatically = 開   (刷出來的自動歸到同一個父節點)")
	quit(0)


## Ground footprint in m², from the model's combined AABB on the XZ plane.
func _footprint(path: String) -> float:
	if path.is_empty():
		return -1.0
	var packed = load(path)
	if packed == null or not (packed is PackedScene):
		return -1.0
	var inst = packed.instantiate()
	if inst == null:
		return -1.0
	var aabb := AABB()
	var first := true
	for mi in _meshes(inst):
		var m: Mesh = mi.mesh
		if m == null:
			continue
		var box: AABB = m.get_aabb()
		if first:
			aabb = box
			first = false
		else:
			aabb = aabb.merge(box)
	inst.free()
	if first:
		return -1.0
	return aabb.size.x * aabb.size.z


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
