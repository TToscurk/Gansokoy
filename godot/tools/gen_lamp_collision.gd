extends SceneTree
## 路燈碰撞：14 根路燈，每根一個 CylinderShape3D。
##
##   Godot --headless --path godot --script tools/gen_lamp_collision.gd
##
## 為什麼不用 trimesh 也不用凸包：
##   - trimesh：Clockwork Lantern Pole_1.glb 是 14,462 三角面，14 根就 202,468
##     面的碰撞幾何，全部只為了「玩家撞到柱子會停」這一件事。
##   - 凸包：燈罩比柱身寬（實測本地半徑 0.166 vs 0.094），凸包會把燈罩到柱腳
##     之間填成一個上寬下窄的實心錐，玩家會在離柱子半公尺外就被擋住。
##   - CylinderShape3D：0 三角面（純數學形狀），而且路燈本來就是圓柱。
##
## 半徑取本地 0.12：實測柱身分層半徑為 底座 0.166 / 最細處 0.094 / 燈頭 0.157。
## 0.12 涵蓋玩家實際會走到的下半段柱身，又不會胖到把燈罩的空間也擋掉。
##
## ⚠ 父節點「路燈街牌」是**非等比**縮放 (0.5936, 0.4731, 0.4000)，所以世界
## 半徑在 X 與 Z 方向不同（0.71 vs 0.48 m）。CylinderShape3D 只有單一半徑，
## 這裡取兩者的較大值，寧可稍胖也不要讓玩家穿進柱子裡。

const SRC_SCENE := "res://maps/slice/slice.tscn"
const OUT_PATH := "res://maps/slice/gen/lamp_collision.scn"
const LAMP_GROUP := "village_lamps"

## 柱身半徑佔 AABB 半寬的比例。
##
## 實測本地分層半徑：底座 0.166 / 最細處 0.094 / 燈頭 0.157，而本地 X 半寬是
## 0.156。取 0.77 對應世界半徑約 0.71 m，涵蓋玩家實際會走到的下半段柱身，
## 又不會胖到把燈罩外緣的空間也擋掉。
##
## 用「比例」而非絕對值，是為了讓路燈日後被改縮放時碰撞自動跟著變——
## AABB 是世界尺寸，乘比例就對了，不需要再追一次縮放鏈。
const R_RATIO := 0.77

var _root: Node3D
var _made := 0


func _init() -> void:
	var packed: PackedScene = load(SRC_SCENE)
	if packed == null:
		push_error("cannot load %s" % SRC_SCENE)
		quit(1)
		return

	var src := packed.instantiate()
	_root = Node3D.new()
	_root.name = "LampCollision"

	# 用群組找，不用名字：road_lamp.tscn 的根節點掛了 village_lamps 群組，
	# 那是這個資產的身分標記。靠「名字開頭是路燈_」會在使用者改名後靜默漏掉。
	for lamp in _lamps(src):
		_add_cylinder(lamp, src)

	src.free()

	if _made == 0:
		push_error("找不到任何路燈（群組 %s）" % LAMP_GROUP)
		quit(1)
		return

	var out := PackedScene.new()
	var err := out.pack(_root)
	if err != OK:
		push_error("pack failed: %d" % err)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT_PATH.get_base_dir())
	err = ResourceSaver.save(out, OUT_PATH)
	if err != OK:
		push_error("save failed: %d" % err)
		quit(1)
		return

	print("\n[done] %s  %d 根路燈  0 三角面（原 trimesh 需 %d 面）" % [
		OUT_PATH, _made, _made * 14462])
	quit(0)


func _add_cylinder(lamp: Node3D, scene_root: Node) -> void:
	# ⚠ 圓柱的位置必須來自**網格的世界 AABB**，不是路燈根節點的原點。
	#
	# road_lamp.tscn 的結構是
	#   路燈 (scale 10)
	#    └ 模型偏移 (position.x = 0.2392)   ← 這一層
	#       └ Clockwork Lantern Pole_1
	#          └ mesh_node                  ← 網格實際在這
	# 第一版取根節點原點，14 根圓柱全部在 X 方向偏了 1.420 m
	# （0.2392 × scale 10 × 父節點 0.5936 = 1.420），碰撞浮在路燈旁邊的空氣裡。
	# probe_lamp_offset.gd 量到的偏差每根都是同一個 1.420，就是這層偏移。
	#
	# 直接用網格 AABB 有第二個好處：半徑與高度也不必再從本地尺寸乘縮放推算，
	# AABB 本身就是世界尺寸。
	var box: Variant = null
	for mi in _meshes(lamp):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null:
			continue
		var mxf := _global_xform(mi, scene_root)
		var b := mxf * m.get_aabb()
		box = b if box == null else (box as AABB).merge(b)
	if box == null:
		print("[skip] %s 沒有網格" % lamp.name)
		return
	var wb: AABB = box

	# 半徑：柱身佔 AABB 的比例。實測本地分層半徑 底座 0.166 / 最細 0.094 /
	# 燈頭 0.157，相對於本地 X 半寬 0.156 → 柱身約佔 0.77。AABB 半寬乘這個
	# 比例，就是柱身在世界空間的半徑，且自動吃到任何縮放。
	var r: float = maxf(wb.size.x, wb.size.z) * 0.5 * R_RATIO
	var h: float = wb.size.y

	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = h

	var body := StaticBody3D.new()
	body.name = "%s_碰撞" % lamp.name
	# 只給玩家層（1）。刷筆層 32 是給地面用的——路燈不是種植面，
	# 把它加進去只會讓草和小物件卡在燈柱上。
	body.collision_layer = 1
	body.collision_mask = 0

	var col := CollisionShape3D.new()
	col.name = "形狀"
	col.shape = shape
	body.add_child(col)

	# CylinderShape3D 的原點在自己的幾何中心，所以對齊 AABB 中心即可。
	body.transform = Transform3D(Basis.IDENTITY, wb.get_center())

	_root.add_child(body)
	body.owner = _root
	col.owner = _root
	_made += 1
	print("[ok] %-10s 中心(%.2f, %.2f, %.2f)  r=%.3f h=%.2f" % [
		lamp.name, wb.get_center().x, wb.get_center().y, wb.get_center().z, r, h])


## 相對場景根的世界變換。不能用 global_transform：場景是在樹外實例化的，
## global 變換尚未解析。
func _global_xform(node: Node3D, scene_root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != scene_root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _lamps(node: Node) -> Array:
	var out: Array = []
	if node is Node3D and node.is_in_group(LAMP_GROUP):
		out.append(node)
	for c in node.get_children():
		out.append_array(_lamps(c))
	return out


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
