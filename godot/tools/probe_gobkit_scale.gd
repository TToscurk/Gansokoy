extends SceneTree
## gobkit 資產的實際匯入尺度：Godot 讀進來之後到底多大？
##
##   Godot --headless --path godot --script tools/probe_gobkit_scale.gd
##
## 直接解析 GLB 得到的頂點座標是 849 這種數字，但 .import 可能帶了
## root_scale，Godot 場上的實際大小要問引擎，不能從檔案推。
## 這一步不能省：整套配置的縮放係數由它決定，錯了就是 849 公尺的樹。

const DIR := "res://assets/_incoming/gobkit_nature"
const SAMPLES := ["TreeHigh001", "TreeMed001", "TreeLow001", "Bush001",
	"Grass001", "Rock001", "Mountain001", "MountainFar001", "Cliff001", "Reed001"]


func _init() -> void:
	print("[GOB] %-16s %8s %8s %8s  %s" % ["資產", "寬", "高", "深", "備註"])
	for n in SAMPLES:
		var p := "%s/%s.glb" % [DIR, n]
		if not ResourceLoader.exists(p):
			print("[GOB] %-16s 找不到" % n)
			continue
		var ps := ResourceLoader.load(p, "PackedScene") as PackedScene
		var inst := ps.instantiate()
		var box: Variant = null
		for mi in _meshes(inst):
			var m: Mesh = (mi as MeshInstance3D).mesh
			if m == null:
				continue
			var b := _xform(mi, inst) * m.get_aabb()
			box = b if box == null else (box as AABB).merge(b)
		if box == null:
			print("[GOB] %-16s 沒有網格" % n)
			inst.free()
			continue
		var bb: AABB = box
		var note := ""
		if bb.size.y > 100.0:
			note = "← 公分單位，需 ×0.01"
		elif bb.size.y < 0.5:
			note = "← 太小，可能已被縮過頭"
		print("[GOB] %-16s %8.2f %8.2f %8.2f  %s" % [
			n, bb.size.x, bb.size.y, bb.size.z, note])
		inst.free()

	# 匯入設定裡的 root_scale
	print("[GOB] --- .import 的 root_scale ---")
	var f := FileAccess.open("%s/TreeHigh001.glb.import" % DIR, FileAccess.READ)
	if f != null:
		for line in f.get_as_text().split("\n"):
			if line.contains("root_scale") or line.contains("apply_root"):
				print("[GOB]   %s" % line.strip_edges())

	print("[GOB] 參考：真實杉木 20-30 m、雜木林 8-15 m、灌木 1-2 m、草 0.3-0.6 m")
	print("[GOB] done")
	quit(0)


func _xform(node: Node3D, root_node: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root_node:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
