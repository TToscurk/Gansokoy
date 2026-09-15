extends SceneTree
## 清除正式建成區與穿村幹渠內的植被實例。
## 直接過濾 MultiMesh buffer 並回存；原始版本在 git 裡，可 checkout 還原。
## Run: godot --headless --path godot --script tools/clear_street_vegetation.gd

## r2（2026-08-30）：B3 街廓化後走廊不夠——背排與裏路地在 x 204.9..264.6，
## 灌木與蕨類長進路地裡。改成清整個街廓外接矩形。
const STREET_X_MIN: float = 202.0
const STREET_X_MAX: float = 268.0
const STREET_Z_MIN: float = -70.0
const STREET_Z_MAX: float = 110.0

# waterway_art_review 以 (287, -2.868, 10) 搬入後的石岸外緣，加 1.5m
# 維護淨空。只刪除落在此區的實例，不重抽 RNG，不位移其餘已審查樹群。
const CANAL_X_MIN: float = 273.5
const CANAL_X_MAX: float = 302.5
const CANAL_Z_MIN: float = -73.5
const CANAL_Z_MAX: float = 105.5

const TARGETS: Array = [
	"res://maps/slice/gen/veg_mm_grasstall.res",
	"res://maps/slice/gen/veg_mm_grassflower.res",
	"res://maps/slice/gen/veg_mm_shrubs.res",
	"res://maps/slice/gen/veg_mm_ferns.res",
	"res://maps/slice/gen/treemm_櫻花樹.res",
	"res://maps/slice/gen/treemm_普通樹.res",
	"res://maps/slice/gen/treemm_大衫.res",
	"res://maps/slice/gen/treemm_2大衫.res",
	"res://maps/slice/gen/treemm_針葉樹1.res",
	"res://maps/slice/gen/treemm_針葉樹2glb.res",
	"res://maps/slice/gen/treemm_針葉林樹3.res",
	"res://maps/slice/gen/treemm_針葉林樹4.res",
	"res://maps/slice/gen/treemm_盆樹.res",
]

func _init() -> void:
	if "--south-entry" in OS.get_cmdline_user_args():
		_south_entry.call_deferred()
		return
	for p in TARGETS:
		_filter(p)
	quit()

func _filter(path: String) -> void:
	var mm: MultiMesh = load(path)
	if mm == null:
		push_error("load failed: " + path)
		return
	var n: int = mm.instance_count
	var stride: int = 16 if mm.use_colors else 12
	var src: PackedFloat32Array = mm.buffer
	var keep: PackedFloat32Array = PackedFloat32Array()
	var removed: int = 0
	for i in range(n):
		var o: int = i * stride
		var px: float = src[o + 3]
		var pz: float = src[o + 11]
		# 村樹生成器本身已避開街廓；盆樹則是有意放在裏路地外緣。
		# 樹資源只套渠道禁區，既有草蕨才同時套街廓與渠道。
		var inside: bool = _inside_canal(px, pz) if path.get_file().begins_with("treemm_") \
			else _inside_clearance(px, pz)
		if inside:
			removed += 1
			continue
		for k in range(stride):
			keep.append(src[o + k])
	var out: MultiMesh = MultiMesh.new()
	out.transform_format = MultiMesh.TRANSFORM_3D
	out.use_colors = mm.use_colors
	out.mesh = mm.mesh
	out.instance_count = n - removed
	out.buffer = keep
	var err: int = ResourceSaver.save(out, path)
	print("CLEARED %s removed=%d kept=%d err=%d" % [path.get_file(), removed, n - removed, err])


func _inside_clearance(x: float, z: float) -> bool:
	var in_street: bool = x > STREET_X_MIN and x < STREET_X_MAX \
		and z > STREET_Z_MIN and z < STREET_Z_MAX
	return in_street or _inside_canal(x, z)


func _inside_canal(x: float, z: float) -> bool:
	return x > CANAL_X_MIN and x < CANAL_X_MAX \
		and z > CANAL_Z_MIN and z < CANAL_Z_MAX


## Local, repeatable maintenance of painted vegetation. Never repacks slice.
## Outputs new resources for explicit editor assignment; preserves source backups.
func _south_entry() -> void:
	var scene: Node3D = load("res://maps/slice/slice.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var names := ["草筆刷_矮草", "草筆刷_高草", "草筆刷_牆根雜草", "Shrubs", "Ferns", "GrassTall", "GrassFlower", "灌木叢/MM_Petal_52"]
	var rows: Array = []
	DirAccess.make_dir_recursive_absolute("D:/資產glb/Gansokoy/entry-backup")
	for i in names.size():
		var node := scene.get_node_or_null(NodePath(names[i])) as MultiMeshInstance3D
		if node == null or node.multimesh == null:
			continue
		var mm := node.multimesh
		var src := mm.buffer
		var stride := 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)
		assert(src.size() == mm.instance_count * stride)
		var keep := PackedFloat32Array()
		var removed := 0
		for j in mm.instance_count:
			var o := j * stride
			var p := node.global_transform * Vector3(src[o + 3], src[o + 7], src[o + 11])
			var road := p.x > 231.0 and p.x < 240.0 and p.z > 98.0 and p.z < 128.0
			var footing := p.x > 212.5 and p.x < 260.1 and p.z > 98.0 and p.z < 100.5
			if road or footing:
				removed += 1
			else:
				keep.append_array(src.slice(o, o + stride))
		if removed == 0:
			continue
		var backup := "D:/資產glb/Gansokoy/entry-backup/grass_%d.res" % i
		if not FileAccess.file_exists(backup):
			assert(ResourceSaver.save(mm, backup) == OK)
		var out := MultiMesh.new()
		out.transform_format = MultiMesh.TRANSFORM_3D
		out.use_colors = mm.use_colors
		out.use_custom_data = mm.use_custom_data
		out.mesh = mm.mesh
		out.instance_count = mm.instance_count - removed
		out.buffer = keep
		var path := "res://maps/slice/gen/entry_grass_%d.res" % i
		assert(ResourceSaver.save(out, path) == OK)
		var check: MultiMesh = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert(check.instance_count == out.instance_count and check.buffer == keep)
		rows.append({"node": names[i], "path": path, "removed": removed, "kept": out.instance_count})
	var report := FileAccess.open("D:/資產glb/Gansokoy/entry-backup/changes.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(rows, "	"))
	print("ENTRY_GRASS " + JSON.stringify(rows))
	quit()

