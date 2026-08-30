extends SceneTree
## 清除主街走廊內的植被實例（B1 街道用）。
## 直接過濾 MultiMesh buffer 並回存；原始版本在 git 裡，可 checkout 還原。
## Run: godot --headless --path godot --script tools/clear_street_vegetation.gd

## r2（2026-08-30）：B3 街廓化後走廊不夠——背排與裏路地在 x 204.9..264.6，
## 灌木與蕨類長進路地裡。改成清整個街廓外接矩形。
const X_MIN: float = 202.0
const X_MAX: float = 268.0
const Z_MIN: float = -70.0
const Z_MAX: float = 110.0

const TARGETS: Array = [
	"res://maps/slice/gen/veg_mm_grasstall.res",
	"res://maps/slice/gen/veg_mm_grassflower.res",
	"res://maps/slice/gen/veg_mm_shrubs.res",
	"res://maps/slice/gen/veg_mm_ferns.res",
]

func _init() -> void:
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
		var inside: bool = px > X_MIN and px < X_MAX and pz > Z_MIN and pz < Z_MAX
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
