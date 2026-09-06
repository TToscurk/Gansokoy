@tool
class_name 場景效能裁剪
extends Node
## Applies distance culling and shadow limits at load time, by walking the live
## tree — not by baking properties into the .tscn.
##
## Why runtime instead of a one-off script: PackedScene.pack() only serialises
## property overrides on nodes it OWNS. Almost every expensive object here lives
## INSIDE an instanced sub-scene (B1_Street, MachiCanal, 灌木叢, 石頭 …), so a
## script that edits those nodes and re-packs silently drops the work — measured
## 6330 shadow flags written, 15 survived the save. Making the same edits at
## runtime sidesteps the ownership rule entirely and keeps slice.tscn clean.
##
## It also means the settings are one node the user can disable to A/B the
## difference, rather than thousands of scattered property overrides they would
## have to undo by hand.
##
## Rules key on MEASURED triangle count, not node names: a keyword list already
## failed once here by missing Clover/Petal/Pebble_Round, and size is the signal
## that actually predicts cost.

## 關閉後場景回到未裁剪狀態（重載場景生效），用來 A/B 比較。
@export var 啟用: bool = true

## 編輯器中也套用。關掉可以在編輯器看完整場景，遊戲執行時仍會裁剪。
@export var 編輯器中套用: bool = true

## 全域距離倍率。1.0 = 下表原值；調高看得遠但較耗效能。
@export_range(0.4, 3.0, 0.05) var 距離倍率: float = 1.0

@export_group("分級距離（公尺）")
## <500 面：碎石、花瓣、四葉草等
@export var 細碎地被: float = 40.0
## <1500 面：小草叢、小道具
@export var 小型草木: float = 65.0
## <4000 面：灌木、圍籬、石燈籠
@export var 灌木道具: float = 100.0
## <25000 面：小樹、攤棚、水田
@export var 小樹攤棚: float = 190.0
## MultiMesh 樹林／灌木群的可見距離（公尺，絕對值，不吃距離倍率）。
## 0 = 不裁。群組以整體 AABB 判距離，超出即整組淡出。
@export var 遠樹距離: float = 380.0

@export_group("建築減面")
## 把 assets/_lod/ 裡的減面建築（22%，gltfpack 保留 UV 接縫）在載入時換上。
## 關掉即回到原始 Meshy 高模。原始 GLB 未被修改。
@export var 使用減面建築: bool = true
## 減面版本所在資料夾。檔名需與原始 GLB 相同。
@export_dir var 減面資料夾: String = "res://assets/_lod"

@export_group("陰影")
## 低於這個面數的物件不投影。陰影 pass 會依 cascade 重繪幾何，
## 小物件的陰影在遠處只是雜訊。
@export var 不投影面數上限: int = 1500
## 定向光陰影距離（公尺）。原本 260 對這個村落規模偏遠。
## 天象系統存在時由它接手（它每幀重設太陽），這裡只調非天象的定向光。
@export_range(40.0, 400.0, 5.0) var 陰影距離: float = 150.0
## MultiMesh 樹林投影。bench_slice 2026-09-03：五組 VillageTrees（每組 ~1000
## 棵 × 12k 面）進四級 cascade 是街道視角 3800 萬面中的 2000 萬——關陰影
## 街道 18→76 fps。樹影本身是美術，所以留開關；預設關，要樹影時打開。
@export var 樹林投影: bool = false
## 樹林投影關閉時，總面數（單體 × 實例數）達到這個值的 MultiMesh 不投影。
## 一組 VillageTrees 的單一樹種 MM 約 100–200 萬面；草筆刷 MM 約 40 萬
## （4 面 × 10 萬株）本來就不投影。
@export var 樹林投影面數上限: int = 200000

var _applied := false
var _triangle_cache: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint() and not 編輯器中套用:
		return
	# Defer so the whole tree (including instanced sub-scenes) exists.
	_run.call_deferred()


func _run() -> void:
	if not 啟用 or _applied:
		return
	_applied = true

	var root := get_tree().current_scene
	if root == null and Engine.is_editor_hint():
		root = get_tree().get_edited_scene_root()
	if root == null:
		root = get_parent()
	if root == null:
		return

	var stats := {"vis": 0, "shadow": 0, "protected": 0, "lod": 0, "lod_tris_saved": 0}
	# Swap meshes BEFORE the cull walk so the cull thresholds and shadow rules
	# see the triangle count that will actually be rendered.
	if 使用減面建築:
		_swap_lod_meshes(root, stats)
	_walk(root, stats)
	_tune_lights(root)

	# ProtonScatter (RiverVegetation etc.) builds its MultiMeshes in a thread
	# and adds them AFTER this deferred pass, so the walk above never sees
	# them — audit_shadow_casters 2026-09-03 found 26.8M shadow-casting tris
	# under RiverVegetation, all photoscan bushes, dwarfing everything else.
	# Hook every scatter's build_completed and re-walk just that subtree.
	for sc in _find_scatters(root):
		if sc.has_signal("build_completed") and not sc.build_completed.is_connected(_on_scatter_built):
			sc.build_completed.connect(_on_scatter_built.bind(sc))
		# It may have finished before we connected: cover that too.
		var out: Node = sc.get_node_or_null("ScatterOutput")
		if out != null and out.get_child_count() > 0:
			_on_scatter_built(sc)
	print("[效能裁剪] 可見距離 %d 個，關閉投影 %d 個，保護 %d 個，減面建築 %d 個（省 %d 萬面）" % [
		stats["vis"], stats["shadow"], stats["protected"],
		stats["lod"], stats["lod_tris_saved"] / 10000])


## Replace each heavy building's mesh with its decimated twin from 減面資料夾.
##
## Runtime swap, not a scene edit: the buildings live inside instanced
## sub-scenes (b1_street.tscn, assets/landmark/*), where PackedScene.pack()
## silently drops per-node overrides -- measured earlier in this project.
## Matching is by source GLB basename pulled from mesh.resource_path
## ("res://assets/machiya/小町家1.glb::ArrayMesh_xxx"), because the LOD tree is
## flat while sources are scattered across assets/ and assets/landmark/.
## Dictionary mapping base -> {
##   "by_name": Dictionary[String, Dictionary], # node_name -> { "mesh": Mesh, "xform": Transform3D }
##   "default": Dictionary,                     # { "mesh": Mesh, "xform": Transform3D }
##   "multi": bool                              # true if LOD scene has multiple MeshInstance3Ds
## }
var _lod_cache: Dictionary = {}

func _get_lod_entry(base: String, node_name: String) -> Dictionary:
	if not _lod_cache.has(base):
		_load_lod(base)
	var data: Dictionary = _lod_cache.get(base, {})
	if data.is_empty():
		return {}
	var by_name: Dictionary = data.get("by_name", {})
	if by_name.has(node_name):
		return by_name[node_name]
	if not data.get("multi", false):
		return data.get("default", {})
	# Multi-mesh scene with no exact node name match: do NOT fall back to default
	# to avoid replacing accessories (lanterns/signs) with the main building.
	return {}

func _load_lod(base: String) -> void:
	var path := 減面資料夾.path_join(base)
	if not ResourceLoader.exists(path):
		_lod_cache[base] = {}
		return
	# CACHE_MODE_IGNORE: do not pin the LOD PackedScene (and its embedded
	# 4K textures) in the resource cache. We keep only the mesh; once its
	# materials are swapped for the originals in _swap_lod_meshes the
	# duplicate textures have no owner left and are freed.
	var ps := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if ps == null:
		_lod_cache[base] = {}
		return
	var inst := ps.instantiate()
	var all_mi := _all_mesh_instances(inst)
	var entry := {
		"by_name": {},
		"default": {},
		"multi": all_mi.size() > 1,
	}
	var best_surfaces := -1
	for f in all_mi:
		if f.mesh != null:
			var item := { "mesh": f.mesh, "xform": f.transform }
			entry["by_name"][f.name] = item
			if f.mesh.get_surface_count() > best_surfaces:
				best_surfaces = f.mesh.get_surface_count()
				entry["default"] = item
	inst.free()
	_lod_cache[base] = entry


func _swap_lod_meshes(root: Node, stats: Dictionary) -> void:
	for mi in _all_mesh_instances(root):
		var m := mi.mesh
		if m == null:
			continue
		var rp := m.resource_path
		if rp == "" or not rp.contains(".glb"):
			continue
		var base := rp.get_slice("::", 0).get_file()
		var item := _get_lod_entry(base, mi.name)
		if item.is_empty():
			continue
		var lod: Mesh = item.get("mesh")
		if lod == null or lod == m:
			continue
		var before := _tris_of(mi)
		# Re-point the decimated mesh's surfaces at the ORIGINAL materials.
		# gltfpack re-embeds every texture, so assets/_lod/大町家.glb ships
		# its own 4K albedo/normal/ORM; loading it alongside the source GLB
		# doubled the resident texture set (+580 MB static, probe_memory_lod
		# 2026-09-03). The originals are already in memory for this very mesh
		# and the UVs are preserved (-si without -tc), so sharing is exact.
		if not lod.has_meta(&"perf_cull_mats_shared"):
			var n := mini(lod.get_surface_count(), m.get_surface_count())
			for s in n:
				var src := m.surface_get_material(s)
				if src != null:
					lod.surface_set_material(s, src)
			lod.set_meta(&"perf_cull_mats_shared", true)
		mi.mesh = lod
		# Clear any stale material override if mesh identity changed, so night_lights
		# can bind to the correct mesh material.
		if mi.get_surface_override_material(0) != null and mi.has_meta(&"perf_cull_orig_xform"):
			mi.set_surface_override_material(0, null)
		# gltfpack bakes the source GLB's mesh-node transform into vertex data
		# ONLY IF run without -kn. With -kn (now used), node transforms are preserved.
		# If the node previously had its transform canceled by an older version of this script,
		# restore it. If lod_xform == IDENTITY while mi.transform != IDENTITY, cancel it.
		var lod_xform: Transform3D = item.get("xform", Transform3D.IDENTITY)
		if mi.has_meta(&"perf_cull_orig_xform"):
			if lod_xform != Transform3D.IDENTITY:
				mi.transform = mi.get_meta(&"perf_cull_orig_xform")
				mi.remove_meta(&"perf_cull_orig_xform")
		elif mi.transform != Transform3D.IDENTITY and lod_xform == Transform3D.IDENTITY:
			mi.set_meta(&"perf_cull_orig_xform", mi.transform)
			mi.transform = Transform3D.IDENTITY
		var after := _tris_of(mi)
		stats["lod"] += 1
		stats["lod_tris_saved"] += before - after


func _lod_mesh_for(base: String) -> Mesh:
	var item := _get_lod_entry(base, "")
	return item.get("mesh", null)



func _all_mesh_instances(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_mesh_instances(c))
	return out


const PROTECT_EXACT := [
	"UnifiedGround", "BasinHills", "Terrain", "GroundUnderlay",
	"EastRiverWater", "EastRiverRevetment",
]
const PROTECT_SUBTREE := ["地面碰撞_刷筆用"]


func _walk(node: Node, stats: Dictionary) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		if _protected(gi):
			stats["protected"] += 1
		else:
			_apply(gi, stats)
	for c in node.get_children():
		_walk(c, stats)


func _apply(gi: GeometryInstance3D, stats: Dictionary) -> void:
	var tris := _tris_of(gi)
	if tris <= 0:
		return

	# A MultiMesh is culled as one large object. Its origin/AABB represents the
	# whole painted field, not each tuft, so a 40 m visibility limit can make an
	# entire 100k-instance grass field disappear at once. Keep MultiMeshes visible;
	# they are already the batched path. Shadow removal is still safe.
	var can_distance_cull := not gi is MultiMeshInstance3D
	var vis := 0.0
	if can_distance_cull:
		if tris < 500:
			vis = 細碎地被
		elif tris < 1500:
			vis = 小型草木
		elif tris < 4000:
			vis = 灌木道具
		elif tris < 25000:
			vis = 小樹攤棚
	elif tris >= 5000 and 遠樹距離 > 0.0:
		# Tree / photoscan-bush MultiMeshes (per-mesh ≥ 5k tris) are NOT the
		# grass-field case: each group is ~30 trees over ~100 m, so a distance
		# cutoff on the group is acceptable at forest distances. From the main
		# street, VillageTrees5 (483 m away) alone contributes 2.2M visible
		# triangles (audit_frustum_view 2026-09-03). Fade so it doesn't pop.
		vis = 遠樹距離 / maxf(距離倍率, 0.01)   # keep 遠樹距離 absolute
	# Larger than that: architecture, never culled.

	if vis > 0.0:
		var d := vis * 距離倍率
		gi.visibility_range_end = d
		if gi is MultiMeshInstance3D:
			gi.visibility_range_end_margin = 40.0
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			stats["vis"] += 1
			return
		# Do not use FADE_SELF here. It turns thousands of opaque clutter meshes
		# into dither-faded draws near their range boundary and measured slower than
		# a direct cutoff. These are sub-metre objects; the hard cutoff is not
		# perceptible at 40–190 m.
		gi.visibility_range_end_margin = 0.0
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		stats["vis"] += 1

	if tris < 不投影面數上限:
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			stats["shadow"] += 1
	elif gi is MultiMeshInstance3D and not 樹林投影:
		# A tree MultiMesh is one object with ~1M+ triangles: every cascade
		# redraws every tree in the group. Per-tuft grass is already below the
		# tri floor; this catches the forests. _tris_of is per-mesh, so scale
		# by the instance count to get what the shadow pass really draws.
		var mm := (gi as MultiMeshInstance3D).multimesh
		var total := tris * (mm.instance_count if mm != null else 1)
		if total >= 樹林投影面數上限 and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			stats["shadow"] += 1


## Directional shadow distance is a single global knob and one of the cheapest
## wins available: halving it roughly halves the geometry each cascade must
## redraw. 260 m was covering ground the player never scrutinises.
func _tune_lights(root: Node) -> void:
	for l in _find_lights(root):
		if l is DirectionalLight3D:
			var d := l as DirectionalLight3D
			d.directional_shadow_max_distance = 陰影距離
			# Pull the splits in so near-camera detail keeps its resolution
			# instead of spending cascades on distant hills.
			d.directional_shadow_split_1 = 0.08
			d.directional_shadow_split_2 = 0.22
			d.directional_shadow_split_3 = 0.52
			d.directional_shadow_blend_splits = true
		elif l is OmniLight3D or l is SpotLight3D:
			# Point-light shadows are expensive and these are small practicals;
			# their job is the glow, not the shadow.
			l.shadow_enabled = false


func _find_lights(node: Node) -> Array:
	var out: Array = []
	if node is Light3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_lights(c))
	return out


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
	if _triangle_cache.has(mesh):
		return _triangle_cache[mesh]
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
	_triangle_cache[mesh] = t
	return t


## Re-apply the shadow/visibility rules to a ProtonScatter's freshly built
## output. Scatter items ship with override_cast_shadow=ON, and a 156k-tri
## photoscan bush × hundreds of instances is the single biggest shadow cost
## in the scene. The per-instance MultiMeshes are treated exactly like any
## other MultiMesh in _apply (total tris = per-mesh × instances).
func _on_scatter_built(sc: Node) -> void:
	if not 啟用:
		return
	var out: Node = sc.get_node_or_null("ScatterOutput")
	if out == null:
		return
	var stats := {"vis": 0, "shadow": 0, "protected": 0, "lod": 0, "lod_tris_saved": 0}
	_walk(out, stats)
	if stats["shadow"] > 0 or stats["vis"] > 0:
		print("[效能裁剪] scatter %s：可見距離 %d 個，關閉投影 %d 個" % [sc.name, stats["vis"], stats["shadow"]])


func _find_scatters(n: Node) -> Array:
	var out := []
	if n.get_script() != null and String(n.get_script().resource_path).ends_with("proton_scatter/src/scatter.gd"):
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_scatters(c))
	return out
