extends SceneTree
## 暫用探針（不進版控）：P7 R3 護岸面板「下沉量 vs 可見比例」曲線
## 目的：判定 rev 面板的曝光比例是否可能落在使用者要求的 40–70 % 帶內，
##      還是幾何上就是全露／全埋（決定後續修法：微調下潛 vs 必須換排列方式）。
## 用法：godot --headless --path . --script res://tools/_probe_rev_curve.gd -- --out=<path> [--ns=8]

const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"

var S: RLib.TriSampler


func _init() -> void:
	var out_path := ""
	var ns := 8
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.trim_prefix("--out=")
		elif a.begins_with("--ns="):
			ns = int(a.trim_prefix("--ns="))
	var v := (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	var Lj: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var lib := RLib.load_lib()
	var P: Dictionary = RLib.plan(v, Lj)
	var items: Array = P["items"]
	S = RLib.terrain_sampler(v)

	# 站點索引（與 gate 相同的建法）
	var st_by_key := {}
	var cnt := {}
	for st: Dictionary in P["stats"].get("stations", []):
		var w := String(st["water"])
		var side := "L" if float(st["side"]) < 0.0 else "R"
		var k := "%s|%s" % [w, side]
		var i := int(cnt.get(k, 0))
		cnt[k] = i + 1
		if not st_by_key.has(k):
			st_by_key[k] = []
		(st_by_key[k] as Array).append(st)

	# 收集全部 rev 面板 + 基準曝光
	var all: Array = []
	for it: Dictionary in items:
		if String(it["k"]) != "rev":
			continue
		var m: Mesh = lib.get(String(it["m"]))
		if m == null:
			continue
		var o := RLib._outward_of(it, st_by_key)
		if o == Vector3.ZERO:
			continue
		var e := RLib._exposure(m, it["xf"], S, o)
		all.append([e, it, m, o])
	all.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))

	# 取最低／最高各半數做代表
	var pick: Array = []
	var half := ns / 2
	for i in half:
		pick.append(all[i])
	for i in half:
		pick.append(all[all.size() - 1 - i])

	var lines: Array = []
	lines.append("=== rev 面板：下沉量(m) vs 可見比例（細分取樣，NaN 地形樣本不計入分子分母）===")
	var hdr := "sink"
	for r: Array in pick:
		hdr += "\t%s(e0=%.2f)" % [String(r[1]["tag"]), float(r[0])]
	lines.append(hdr)
	for si in range(0, 25):
		var sink := float(si) * 0.02
		var row := "%.2f" % sink
		for r: Array in pick:
			var it: Dictionary = r[1]
			var m: Mesh = r[2]
			var txf: Transform3D = (it["xf"] as Transform3D).translated(Vector3(0, -sink, 0))
			row += "\t%.3f" % _exp(m, txf, 40)
		lines.append(row)

	# 水平往河／往岸的影響（下沉固定 0）
	lines.append("")
	lines.append("=== 同一批：水平位移(m, +=往河) vs 可見比例 ===")
	var hdr2 := "h"
	for r: Array in pick:
		hdr2 += "\t%s" % String(r[1]["tag"])
	lines.append(hdr2)
	for hi in range(-8, 9):
		var h := float(hi) * 0.05
		var row2 := "%.2f" % h
		for r: Array in pick:
			var it: Dictionary = r[1]
			var m: Mesh = r[2]
			var o: Vector3 = r[3]
			var txf: Transform3D = (it["xf"] as Transform3D).translated(o * h)
			row2 += "\t%.3f" % _exp(m, txf, 40)
		lines.append(row2)

	# 尺寸統計
	var sizes := []
	for r: Array in pick:
		var m: Mesh = r[2]
		sizes.append("%s aabb=%s" % [String(r[1]["tag"]), str(m.get_aabb().size)])
	lines.append("")
	lines.append("=== 尺寸 ===")
	lines.append_array(sizes)

	var txt := "\n".join(lines)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(txt)
		f.close()
	print("[REVCURVE] → %s" % out_path)
	v.free()
	quit(0)


## 細分取樣的可見比例：每個抽樣三角形再中點細分 2 層（16 子三角形）
func _exp(m: Mesh, xf: Transform3D, ntris: int) -> float:
	var a: Array = m.surface_get_arrays(0)
	var V: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var I: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var valid := 0.0
	var ex := 0.0
	var step := maxi(1, (I.size() / 3) / ntris)
	for t in range(0, I.size(), 3 * step):
		if t + 2 >= I.size():
			break
		var p0 := xf * V[I[t]]
		var p1 := xf * V[I[t + 1]]
		var p2 := xf * V[I[t + 2]]
		for s: Array in _sub(p0, p1, p2, 2):
			var q0: Vector3 = s[0]
			var q1: Vector3 = s[1]
			var q2: Vector3 = s[2]
			var ar := (q1 - q0).cross(q2 - q0).length() * 0.5
			if ar < 1e-9:
				continue
			var c := (q0 + q1 + q2) / 3.0
			var th := S.h(c.x, c.z)
			if is_nan(th):
				continue
			valid += ar
			if c.y > th:
				ex += ar
	if valid < 1e-6:
		return -1.0
	return ex / valid


func _sub(p0: Vector3, p1: Vector3, p2: Vector3, depth: int) -> Array:
	if depth <= 0:
		return [[p0, p1, p2]]
	var m01 := (p0 + p1) * 0.5
	var m12 := (p1 + p2) * 0.5
	var m20 := (p2 + p0) * 0.5
	var out: Array = []
	out.append_array(_sub(p0, m01, m20, depth - 1))
	out.append_array(_sub(m01, p1, m12, depth - 1))
	out.append_array(_sub(m20, m12, p2, depth - 1))
	out.append_array(_sub(m01, m12, m20, depth - 1))
	return out
