extends SceneTree
## Build an Asset Placer library from assets/nature/, grouped into paint-ready
## collections.
##
## Why this exists: the user cannot drive the editor UI, so registering 68 GLTFs
## and tagging them by hand is not a viable ask. This writes the plugin's own
## user://asset_library.json directly, in the schema of
## addons/asset_placer/data/asset_library_parser.gd (version 3).
##
## Classification is MEASURED, not guessed from filenames: every mesh is loaded
## and its AABB height read, because the same folder mixes 14 m trees with 0.3 m
## clover and the brush radius / density that suit one are useless for the other.
## Height buckets decide the collection; the filename only breaks ties for
## non-plant props (rocks, path stones, petals).
##
## Individual nodes, not MultiMesh: Asset Placer instances real scene nodes, so
## every plant stays selectable and movable — the reviewability the project
## requires.
##
## Output: user://asset_library.json  (backed up first if one already exists)
## Run: godot --headless --path godot --script tools/gen_nature_asset_library.gd

const NATURE_DIR := "res://assets/nature"
const OUT := "user://asset_library.json"

# Collection ids are stable so re-running does not reshuffle the user's palette.
const COL_GROUND := 1   # 地被：蕨、四葉草、蘑菇、小花
const COL_SHRUB := 2    # 灌木：Bush、Plant
const COL_GRASS := 3    # 草叢：Grass_*
const COL_TREE := 4     # 樹木：Tree、Pine
const COL_DEADTREE := 5 # 枯木
const COL_ROCK := 6     # 石頭：Rock、Pebble
const COL_PATH := 7     # 鋪路石：RockPath
const COL_PETAL := 8    # 花瓣散件

const COLLECTIONS := [
	{"id": COL_GROUND, "name": "地被層", "color": "7ec850ff"},
	{"id": COL_SHRUB, "name": "灌木叢", "color": "3f8f3fff"},
	{"id": COL_GRASS, "name": "草叢", "color": "9fd35fff"},
	{"id": COL_TREE, "name": "樹木", "color": "1f6b2eff"},
	{"id": COL_DEADTREE, "name": "枯木", "color": "8a7a5aff"},
	{"id": COL_ROCK, "name": "石頭", "color": "9a9a9aff"},
	{"id": COL_PATH, "name": "鋪路石", "color": "b8ac96ff"},
	{"id": COL_PETAL, "name": "花瓣", "color": "e8a0c0ff"},
]

# Collections kept OUT of the library entirely. Asset Placer's random-asset mode
# draws from everything registered, so stone props kept turning up in strokes
# meant for trees and flowers. Excluding them here is the only reliable filter —
# the plugin has no per-stroke collection lock. Re-enable by emptying this list.
const EXCLUDE_COLLECTIONS := [
	COL_ROCK,
	COL_PATH,
]


func _init() -> void:
	var files := _list_models(NATURE_DIR)
	files.sort()
	if files.is_empty():
		push_error("no models under %s" % NATURE_DIR)
		quit(1)
		return

	var assets: Array = []
	var buckets := {}
	var skipped := {}
	var failed: Array = []

	for path in files:
		var stem: String = path.get_file().get_basename()
		var h := _mesh_height(path)
		if h < 0.0:
			failed.append(stem)
			continue

		var col := _classify(stem, h)
		if col in EXCLUDE_COLLECTIONS:
			if not skipped.has(col):
				skipped[col] = []
			skipped[col].append(stem)
			continue

		var uid_int := ResourceLoader.get_resource_uid(path)
		# Asset Placer stores a uid:// string when one exists and falls back to a
		# res:// path otherwise (see AssetResource.get_path); mirror that exactly.
		var res_id: String = path
		if uid_int != ResourceUID.INVALID_ID:
			res_id = ResourceUID.id_to_text(uid_int)

		assets.append({
			"name": path.get_file(),
			"id": res_id,
			"tags": [col],
			# MUST equal the registered folder's path exactly: Synchronize's
			# _is_asset_valid() drops any asset that no folder claims (see
			# AssetFolder.has_asset), so an empty folder_path silently wipes the
			# whole library on the next editor start.
			"folder_path": NATURE_DIR,
			"primary_collection": col,
			"date_added": float(Time.get_unix_time_from_system()),
		})

		if not buckets.has(col):
			buckets[col] = []
		buckets[col].append("%s(%.2fm)" % [stem, h])

	var collections: Array = []
	for c in COLLECTIONS:
		if c["id"] in EXCLUDE_COLLECTIONS:
			continue
		collections.append({"name": c["name"], "color": c["color"], "id": c["id"]})

	# Backup before overwrite: the palette is the user's, not ours to clobber.
	if FileAccess.file_exists(OUT):
		var old := FileAccess.open(OUT, FileAccess.READ)
		if old != null:
			var txt := old.get_as_text()
			old.close()
			if not txt.strip_edges().is_empty():
				var bak := "%s.bak" % OUT
				var bf := FileAccess.open(bak, FileAccess.WRITE)
				bf.store_string(txt)
				bf.close()
				print("[backup] 舊資產庫已備份到 %s" % bak)

	var lib := {
		"assets": assets,
		# Registering the source folder is mandatory, not cosmetic: without it
		# every asset fails Synchronize._is_asset_valid() and the library is
		# emptied the next time the editor loads.
		#
		# The rules are load-bearing too. AssetFolder.name_passes_filters()
		# returns true when a folder has NO rules, so a rule-less folder makes
		# "Sync Assets" re-add every file — including the stone props we just
		# excluded. Each kept species gets its own include-pattern rule, so sync
		# can only ever re-add those.
		"folders": _build_folders(),
		"collections": collections,
		"version": 3,
	}
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % OUT)
		quit(1)
		return
	f.store_string(JSON.stringify(lib))
	f.close()

	for c in COLLECTIONS:
		var items: Array = buckets.get(c["id"], [])
		print("\n== %s == (%d 件)" % [c["name"], items.size()])
		if items.is_empty():
			print("  (無)")
		else:
			print("  " + ", ".join(items))

	if not skipped.is_empty():
		print("\n=== 已排除（不進資產庫）===")
		var names := {}
		for c in COLLECTIONS:
			names[c["id"]] = c["name"]
		for cid in skipped:
			print("  %s (%d 件): %s" % [
				names.get(cid, "?"), skipped[cid].size(), ", ".join(skipped[cid])])

	if not failed.is_empty():
		print("\n[警告] 無法量測，已略過: " + ", ".join(failed))

	print("\n[done] %s  共 %d 件資產 / %d 個分類" % [
		ProjectSettings.globalize_path(OUT), assets.size(), COLLECTIONS.size()])
	quit(0)


## Folder registration for the plugin's sync pass. One folder entry per kept
## name pattern: AssetFolder.has_asset() requires SOME folder to claim each
## asset, and name_passes_filters() lets a rule-less folder claim everything —
## which would let "Sync Assets" pull the excluded stone props back in.
func _build_folders() -> Array:
	var patterns := _kept_patterns()
	var out: Array = []
	for pat in patterns:
		out.append({
			"path": NATURE_DIR,
			"include_subfolders": false,
			"rules": [{"type": "filter_by_name", "pattern": pat}],
		})
	return out


## Filename fragments for the collections we keep. Derived from the actual
## Quaternius naming in assets/nature/, not invented: Bush_*, Clover_*, Fern_*,
## Flower_*, Plant_*, Grass_*, CommonTree_*, Pine_*, TwistedTree_*, DeadTree_*,
## Mushroom_*, Petal_*. Rock/Pebble/RockPath are deliberately absent.
func _kept_patterns() -> Array:
	return [
		"Bush", "Clover", "Fern", "Flower", "Plant", "Grass",
		"CommonTree", "Pine", "TwistedTree", "DeadTree",
		"Mushroom", "Petal",
	]


func _list_models(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not d.current_is_dir():
			var ext := name.get_extension().to_lower()
			if ext in ["gltf", "glb", "obj", "fbx"]:
				out.append("%s/%s" % [dir_path, name])
		name = d.get_next()
	d.list_dir_end()
	return out


## Real world height in metres, from the instantiated scene's combined AABB.
## Filenames lie (Grass_Common_Tall is 0.9 m, TwistedTree_3 is 16 m); only the
## geometry settles which brush a model belongs to.
func _mesh_height(path: String) -> float:
	var packed = load(path)
	if packed == null or not (packed is PackedScene):
		return -1.0
	var inst = packed.instantiate()
	if inst == null:
		return -1.0
	var aabb := AABB()
	var first := true
	for mi in _all_mesh_instances(inst):
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
	return aabb.size.y


func _all_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_mesh_instances(c))
	return out


func _classify(stem: String, height: float) -> int:
	var s := stem.to_lower()

	# Non-plant props are decided by name: a path stone and a pebble sit at the
	# same height but serve completely different painting jobs.
	if s.begins_with("rockpath"):
		return COL_PATH
	if s.begins_with("pebble") or s.begins_with("rock"):
		return COL_ROCK
	if s.begins_with("petal"):
		return COL_PETAL
	if s.begins_with("deadtree"):
		return COL_DEADTREE
	if s.begins_with("grass_"):
		return COL_GRASS

	# Everything else is bucketed by measured height, so a "Plant_1_Big" that is
	# actually shrub-sized lands with the shrubs rather than with the seedlings.
	if height >= 4.0:
		return COL_TREE
	if height >= 1.0:
		return COL_SHRUB
	return COL_GROUND
