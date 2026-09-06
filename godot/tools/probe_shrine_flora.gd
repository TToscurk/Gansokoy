extends SceneTree
## 神社植被候選資產體檢：原始 AABB、原點類型、三角面。
## 樹用高度定 scale，地被用最大水平邊（gen_trail_v2 的教訓：
## Plant_7_Big 高 0.25 m 但寬 1.9 m，用高度算會變成 11 m 寬的巨葉）。
##
##   Godot --headless --path godot --script tools/probe_shrine_flora.gd

const LS := "res://assets/landscape/"
const NAT := "res://assets/nature/"

const CANDS := [
	[LS + "大衫.glb", "Hero 杉"],
	[LS + "2大衫.glb", "Hero 杉"],
	[LS + "松樹.glb", "松"],
	[LS + "針葉樹1.glb", "針葉"],
	[LS + "針葉樹2glb.glb", "針葉"],
	[LS + "針葉林樹3.glb", "針葉"],
	[LS + "針葉林樹4.glb", "針葉"],
	[LS + "普通樹.glb", "闊葉"],
	[LS + "鎮守之杜.glb", "遠景林 mass"],
	[LS + "盆樹.glb", "低木"],
	[NAT + "Pine_1.gltf", "Quaternius 松"],
	[NAT + "Pine_3.gltf", "Quaternius 松"],
	[NAT + "CommonTree_1.gltf", "Quaternius 闊葉"],
	[NAT + "TwistedTree_1.gltf", "Quaternius 老樹"],
	[NAT + "Bush_Common.gltf", "灌木"],
	[NAT + "Fern_1.gltf", "蕨"],
	[NAT + "Grass_Common_Short.gltf", "短草"],
	[NAT + "Grass_Common_Tall.gltf", "高草"],
	[NAT + "Grass_Wispy_Short.gltf", "細草"],
	[NAT + "Clover_1.gltf", "苜蓿/苔"],
	[NAT + "Plant_1.gltf", "小植栽"],
	[NAT + "Rock_Medium_1.gltf", "苔石"],
	[NAT + "RockPath_Round_Wide.gltf", "鋪石"],
	[NAT + "RockPath_Square_Wide.gltf", "鋪石"],
	[NAT + "Flower_3_Group.gltf", "野花"],
	[NAT + "Mushroom_Common.gltf", "菇"],
]


func _init() -> void:
	print("[FLORA] %-24s %7s %7s %7s  %-14s %8s  %s"
		% ["asset", "w", "h", "d", "origin", "tris", "用途"])
	for c in CANDS:
		_one(c[0], c[1])
	quit(0)


func _one(path: String, role: String) -> void:
	var label := path.get_file().get_basename()
	if not ResourceLoader.exists(path):
		print("[FLORA] %-24s 不存在" % label)
		return
	var ps := load(path) as PackedScene
	var inst := ps.instantiate() as Node3D
	var box: Variant = null
	var tris := 0
	for m in _meshes(inst):
		var mi := m as MeshInstance3D
		var b := _rel(mi, inst) * mi.get_aabb()
		box = b if box == null else (box as AABB).merge(b)
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx.size() > 0
				else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	inst.free()
	if box == null:
		print("[FLORA] %-24s 無網格" % label)
		return
	var bb: AABB = box
	var kind := "BASE" if absf(bb.position.y) < 0.02 * maxf(bb.size.y, 0.001) \
		else "CENTRE/OFFSET(%.3f)" % bb.position.y
	print("[FLORA] %-24s %7.3f %7.3f %7.3f  %-14s %8d  %s"
		% [label, bb.size.x, bb.size.y, bb.size.z, kind, tris, role])


func _meshes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		o.append(n)
	for c in n.get_children():
		o.append_array(_meshes(c))
	return o


func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
