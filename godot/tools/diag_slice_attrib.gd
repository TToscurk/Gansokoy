extends SceneTree
## slice 載入成本歸因：把「自己的文字解析」和「相依資源」分開量。
##
##   Godot --headless --path godot --script tools/diag_slice_attrib.gd
##
## 方法：先把所有 ext_resource 載進快取（暖機），再用 CACHE_MODE_IGNORE
## （非 DEEP）重載目標本身 —— 這樣量到的就只有「這個 .tscn 自己的文字解析
## ＋ sub_resource 建構」，相依的部分走快取不重複計。

const TARGETS := [
	"res://maps/slice/slice.tscn",
	"res://maps/slice/gen/ground_collision.tscn",
	"res://maps/slice/prototypes/waterway_art_review.tscn",
	"res://maps/slice/gen/building_collision.tscn",
	"res://maps/slice/gen/b1_street.tscn",
]


func _init() -> void:
	_run.call_deferred()


func _ms(a: int, b: int) -> float:
	return float(b - a) / 1000.0


func _run() -> void:
	print("[ATTR] 目標                                   自身解析 ms   相依 ms   總冷載 ms")
	for p in TARGETS:
		if not ResourceLoader.exists(p):
			continue

		# 1) 全冷：自己 + 相依
		var t0 := Time.get_ticks_usec()
		var _cold := ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var t_cold := _ms(t0, Time.get_ticks_usec())
		_cold = null

		# 2) 相依已在快取中，只重解析自己
		t0 = Time.get_ticks_usec()
		var _self := ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE)
		var t_self := _ms(t0, Time.get_ticks_usec())
		_self = null

		print("[ATTR] %-40s %10.1f %10.1f %11.1f" % [
			p.get_file(), t_self, t_cold - t_self, t_cold])

	_grass_cost()
	print("[ATTR] done")
	quit(0)


## 草的 MultiMesh buffer 是 slice.tscn 裡最大的一塊文字（單行 10.4 MB）。
## 直接量：建一份同樣大小的 PackedFloat32Array，存成文字 vs 二進位再讀回。
func _grass_cost() -> void:
	var counts := [106658, 3937, 2746]
	var floats := 0
	for c in counts:
		floats += c * 12
	print("[ATTR] --- 草 MultiMesh：%d 個實例 = %d 個 float ---" % [
		counts[0] + counts[1] + counts[2], floats])

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = counts[0]
	var buf := PackedFloat32Array()
	buf.resize(counts[0] * 12)
	for i in buf.size():
		buf[i] = randf() * 400.0 - 200.0
	mm.buffer = buf

	var txt := "user://grass_probe.tres"
	var bin := "user://grass_probe.res"
	ResourceSaver.save(mm, txt)
	ResourceSaver.save(mm, bin)

	var t0 := Time.get_ticks_usec()
	var a := ResourceLoader.load(txt, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var t_txt := _ms(t0, Time.get_ticks_usec())
	a = null
	t0 = Time.get_ticks_usec()
	var b := ResourceLoader.load(bin, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var t_bin := _ms(t0, Time.get_ticks_usec())
	b = null

	print("[ATTR]   單獨的 106658 實例 MultiMesh：文字 %.1f ms（%.2f MB） / 二進位 %.1f ms（%.2f MB）" % [
		t_txt, FileAccess.open(txt, FileAccess.READ).get_length() / 1048576.0,
		t_bin, FileAccess.open(bin, FileAccess.READ).get_length() / 1048576.0])
