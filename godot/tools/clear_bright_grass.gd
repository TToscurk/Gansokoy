extends SceneTree
## 全圖移除「亮雜草」（GrassTall / GrassFlower）。
## 使用者 2026-08-29 指示：這兩層彩度過高、尺寸過大，與新街道質感衝突。
## 做法：把 MultiMesh 實例清空（instance_count = 0），節點結構不動。
## 還原：git checkout maps/slice/gen/veg_mm_grasstall.res veg_mm_grassflower.res
## Run: godot --headless --path godot --script tools/clear_bright_grass.gd

const TARGETS: Array = [
	"res://maps/slice/gen/veg_mm_grasstall.res",
	"res://maps/slice/gen/veg_mm_grassflower.res",
]

func _init() -> void:
	for p in TARGETS:
		var mm: MultiMesh = load(p)
		if mm == null:
			push_error("load failed: " + p)
			continue
		var before: int = mm.instance_count
		var out: MultiMesh = MultiMesh.new()
		out.transform_format = MultiMesh.TRANSFORM_3D
		out.use_colors = mm.use_colors
		out.mesh = mm.mesh
		out.instance_count = 0
		out.buffer = PackedFloat32Array()
		var err: int = ResourceSaver.save(out, p)
		print("EMPTIED %s was=%d err=%d" % [p.get_file(), before, err])
	quit()
