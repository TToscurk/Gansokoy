extends SceneTree
## slice.tscn 自身解析 11 秒的成因二分法。
##
##   Godot --headless --path godot --script tools/diag_slice_bisect.gd
##
## 產生幾個「切掉某一類巨大資料」的變體到 user://，逐個計時。變體只在 user://
## 產生，res:// 底下的 slice.tscn 完全不動。
##
## 變體：
##   full       原檔複製（對照組，證明 user:// 沒有額外開銷）
##   no_mm      三個 MultiMesh 的 buffer 換成 1 個實例（切掉 ~11 MB 浮點文字）
##   no_mesh    ArrayMesh 的 vertex/index/attribute PackedByteArray 換成空
##   no_nodes   只留 [ext_resource]/[sub_resource]，砍掉所有 [node]（不可載入，
##              僅用來量純資源區的解析成本，載入失敗照樣計時）

const SRC := "res://maps/slice/slice.tscn"


func _init() -> void:
	_run.call_deferred()


func _ms(a: int, b: int) -> float:
	return float(b - a) / 1000.0


func _run() -> void:
	var f := FileAccess.open(SRC, FileAccess.READ)
	var lines := f.get_as_text().split("\n")
	f.close()
	print("[BISECT] 原檔 %d 行" % lines.size())

	_variant("full", lines, func(l: String) -> String: return l)

	_variant("no_mm", lines, func(l: String) -> String:
		if l.begins_with("buffer = PackedFloat32Array(") and l.length() > 10000:
			return "buffer = PackedFloat32Array(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0)"
		if l.begins_with("instance_count = ") and int(l.substr(17)) > 100:
			return "instance_count = 1"
		return l)

	_variant("no_mesh", lines, func(l: String) -> String:
		var s := l.strip_edges()
		for k in ['"vertex_data": PackedByteArray(', '"index_data": PackedByteArray(',
				'"attribute_data": PackedByteArray(']:
			if s.begins_with(k) and l.length() > 10000:
				return l.substr(0, l.find("(") + 1) + '""),'
		return l)

	_variant("only_res", lines, func(l: String) -> String: return l, true)

	# 只留 header + ext_resource：量「解析 87 個外部相依宣告」本身要多久。
	_section("only_ext", lines, ["[ext_resource"])
	# header + ext + sub_resource，但巨大陣列全部清空：量結構本身。
	_section("skeleton", lines, ["[ext_resource", "[sub_resource"], true)

	print("[BISECT] done")
	quit(0)


func _variant(tag: String, lines: PackedStringArray, xf: Callable, strip_nodes := false) -> void:
	var out := PackedStringArray()
	var in_node := false
	for l in lines:
		if strip_nodes:
			if l.begins_with("[node ") or l.begins_with("[connection"):
				in_node = true
			elif l.begins_with("[") and l.ends_with("]"):
				in_node = false
			if in_node:
				continue
		out.append(xf.call(l))

	var path := "user://bisect_%s.tscn" % tag
	var w := FileAccess.open(path, FileAccess.WRITE)
	w.store_string("\n".join(out))
	w.close()
	var mb := FileAccess.open(path, FileAccess.READ).get_length() / 1048576.0

	var t0 := Time.get_ticks_usec()
	var r := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var dt := _ms(t0, Time.get_ticks_usec())
	print("[BISECT] %-10s %8.2f MB  解析 %9.1f ms  %s" % [
		tag, mb, dt, "OK" if r != null else "（載入失敗，僅供計時）"])
	r = null


## 只保留 header 與指定區段類型；shrink=true 時把超長行截成空陣列。
func _section(tag: String, lines: PackedStringArray, keep: Array, shrink := false) -> void:
	var out := PackedStringArray(["[gd_scene format=3]", ""])
	var keeping := false
	for l in lines:
		if l.begins_with("["):
			keeping = false
			for k in keep:
				if l.begins_with(k):
					keeping = true
		if not keeping:
			continue
		var s := l
		if shrink and s.length() > 4000:
			var i := s.find("(")
			if i > 0:
				s = s.substr(0, i + 1) + ")"
		out.append(s)

	var path := "user://bisect_%s.tscn" % tag
	var w := FileAccess.open(path, FileAccess.WRITE)
	w.store_string("\n".join(out))
	w.close()
	var mb := FileAccess.open(path, FileAccess.READ).get_length() / 1048576.0

	var t0 := Time.get_ticks_usec()
	var r := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var dt := _ms(t0, Time.get_ticks_usec())
	print("[BISECT] %-10s %8.2f MB  解析 %9.1f ms  %s" % [
		tag, mb, dt, "OK" if r != null else "（載入失敗，僅供計時）"])
	r = null
