extends SceneTree
## 獸道用資產的實際匯入尺寸：Quaternius nature/ 與 gobkit 遠景山。
##
##   Godot --headless --path godot --script tools/probe_trail_assets.gd
##
## 產生器的每一類縮放都從這裡的數字算（目標尺寸 ÷ 實測本地高度），
## 不猜。同時記錄原點在底還是中心——Quaternius 記憶中是 BASE，要驗證。

const NATURE := "res://assets/nature/"
const GOB := "res://assets/_incoming/gobkit_nature/"

const LIST := [
	# 樹
	"CommonTree_1", "CommonTree_3", "CommonTree_5",
	"Pine_1", "Pine_3", "Pine_5",
	"DeadTree_1", "DeadTree_3", "DeadTree_5",
	"TwistedTree_1", "TwistedTree_3", "TwistedTree_5",
	# 地表
	"Fern_1", "Bush_Common", "Bush_Common_Flowers",
	"Grass_Common_Tall", "Grass_Common_Short", "Grass_Wispy_Tall", "Grass_Wispy_Short",
	"Plant_1", "Plant_3", "Clover_1",
	"Mushroom_Common", "Mushroom_Laetiporus",
	"Flower_3_Group", "Flower_4_Group",
	"Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3",
	"Pebble_1", "Pebble_5", "RockPath_1", "RockPath_5",
]
const GOB_LIST := ["Mountain001", "Mountain002", "MountainFar001", "Hill001", "Hill002", "Cliff001"]
const LP := "res://assets/lowpoly_scene/"
const LP_LIST := ["StoneLantern", "Fence_Wood", "Log_Cluster", "LogStorage", "Barrel", "CeremicPot", "Basket_S", "WoodenBox", "Table_Circular", "Chair"]


func _init() -> void:
	print("[PROBE] %-22s %8s %8s %8s  %6s %6s  origin  tris" % ["name", "w", "h", "d", "ymin", "ymax"])
	for n in LIST:
		_one(NATURE + n + ".gltf", n)
	for n in GOB_LIST:
		_one(GOB + n + ".glb", n)
	for n in LP_LIST:
		_one(LP + n + ".gltf", n)
	quit(0)


func _one(path: String, label: String) -> void:
	var ps := load(path) as PackedScene
	if ps == null:
		print("[PROBE] %-22s 載入失敗" % label)
		return
	var inst := ps.instantiate() as Node3D
	var box: Variant = null
	var tris := 0
	for m in _meshes(inst):
		var mi := m as MeshInstance3D
		var a := mi.get_aabb()
		var xf := _rel(mi, inst)
		var b := xf * a
		box = b if box == null else (box as AABB).merge(b)
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	inst.free()
	if box == null:
		print("[PROBE] %-22s 無網格" % label)
		return
	var bb := box as AABB
	var org := "BASE" if absf(bb.position.y) < bb.size.y * 0.1 else ("CENTRE" if absf(bb.position.y + bb.size.y * 0.5) < bb.size.y * 0.15 else "?")
	print("[PROBE] %-22s %8.2f %8.2f %8.2f  %6.2f %6.2f  %-6s  %d" % [
		label, bb.size.x, bb.size.y, bb.size.z, bb.position.y, bb.end.y, org, tris])


func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
