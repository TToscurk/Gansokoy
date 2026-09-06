extends SceneTree
## 獸道／香霖堂重整前的落差盤點：這兩張圖缺了 slice 這輪建立的哪些系統？
##
##   Godot --headless --path godot --script tools/survey_map_gap.gd -- trail
##   Godot --headless --path godot --script tools/survey_map_gap.gd -- kourindou
##
## slice 這一輪建立的基礎設施（天象系統、效能裁剪、統一地面、碰撞產物、
## 夜間燈火）都是後加的，trail/kourindou 停在 8/29 那個時間點。重整的第一步
## 是知道差在哪，而不是憑印象重做。

const SYSTEMS := [
	["天象系統", "scripts/sky_system.gd", "晝夜、天空、雲、太陽"],
	["場景效能裁剪", "scripts/scene_perf_cull.gd", "距離剔除、小件關陰影"],
	["夜間燈火", "scripts/night_lights.gd", "入夜自動點燈"],
	["降水", "scripts/precipitation.gd", "雨雪"],
]


func _init() -> void:
	var map_id := "trail"
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			map_id = a

	var path := "res://maps/%s/%s.tscn" % [map_id, map_id]
	if not ResourceLoader.exists(path):
		print("[GAP] 找不到 %s" % path)
		quit(1)
		return

	var packed: PackedScene = load(path)
	var src := packed.instantiate()
	print("[GAP] ===== %s =====" % map_id)

	# ── 系統節點 ──
	print("[GAP] --- slice 已有、這張圖是否也有 ---")
	for s in SYSTEMS:
		var n := src.find_child(s[0], true, false)
		print("[GAP]   %-12s %s   %s" % [
			s[0], "✓ 有" if n != null else "✗ 缺", s[2]])

	# ── 環境 ──
	var we := _find(src, "WorldEnvironment")
	if we == null:
		print("[GAP]   %-12s ✗ 缺   完全沒有 WorldEnvironment" % "環境")
	else:
		var env: Environment = (we as WorldEnvironment).environment
		print("[GAP]   %-12s ✓ 有   節點名「%s」bg=%d sky=%s" % [
			"環境", we.name, env.background_mode,
			"有" if env.sky != null else "無"])

	# ── 幾何規模 ──
	var mi := 0
	var mm := 0
	var tris := 0
	var lights := 0
	var bodies := 0
	for n in _all(src):
		if n is MeshInstance3D:
			mi += 1
			tris += _tris((n as MeshInstance3D).mesh)
		elif n is MultiMeshInstance3D:
			mm += 1
			var m := (n as MultiMeshInstance3D).multimesh
			if m != null:
				tris += _tris(m.mesh) * m.instance_count
		elif n is Light3D:
			lights += 1
		elif n is CollisionObject3D:
			bodies += 1
	print("[GAP] --- 規模 ---")
	print("[GAP]   節點 %d｜MeshInstance %d｜MultiMesh %d｜燈 %d｜碰撞體 %d" % [
		_all(src).size(), mi, mm, lights, bodies])
	print("[GAP]   三角面約 %s" % _fmt(tris))

	# ── 頂層結構 ──
	print("[GAP] --- 頂層節點 ---")
	for c in src.get_children():
		print("[GAP]   %-26s %-22s 子樹 %d" % [
			c.name, c.get_class(), _all(c).size()])

	src.free()
	print("[GAP] done")
	quit(0)


func _tris(m: Mesh) -> int:
	if m == null:
		return 0
	var t := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			t += (idx as PackedInt32Array).size() / 3
		else:
			t += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _fmt(v: int) -> String:
	var s := str(v)
	var out := ""
	var k := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		k += 1
		if k % 3 == 0 and i > 0:
			out = "," + out
	return out
