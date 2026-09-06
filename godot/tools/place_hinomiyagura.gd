extends SceneTree
## 將火見櫓放入 slice.tscn（B3 r7）。
## 依 .claude/rules/godot.md 與 ningen-no-sato.md：量產出物不信參數——
## 縮放與落地高度一律由實測 AABB 反推（資產原點在幾何中心，非底面）。
##
## 擺位依據 tools/survey_hinomiyagura.gd 的實測勘查：
##   (235.0, -70.0) 主街正北、街廓外
##   從南端大鳥居 (235, 101) 望去：視距 167m、水平偏角 0.0°、塔頂仰角 4.6°
##   最近建築淨空 7.77m（machiya_西_00）、地面 y=0.00
## 朝向：面南（望向主街與大鳥居），資產正面為 -Z，故 yaw=180。

const SCENE: String = "res://maps/slice/slice.tscn"
const ASSET: String = "res://assets/landmark/火見櫓.glb"
const NODE_NAME: String = "火見櫓"
# r7b 修正：原 (235,-70) 踩在主街鋪面延伸帶上（路面畫到 z=-73），等于立在路中央。
# 新位偏西 11m 退到街尾路西空地：自大鳥居 (235,101) 視距 ~168m、水平偏角 ~3.8°、
# 淨空 machiya_西_00（z -60 起）北緣 ~4.5m。街仍可通行，塔在街尾側旁收景。
const POS_X: float = 224.0
const POS_Z: float = -67.0
const TARGET_H: float = 15.0
const SINK: float = 0.12          # 石礎微陷，與街廓建築的 SINK 0.15 同語彙
const YAW_DEG: float = 180.0

func _local_bbox(n: Node3D) -> AABB:
	var acc: AABB = AABB()
	var has: bool = false
	var stack: Array = [[n, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var node: Node = pair[0]
		var xf: Transform3D = pair[1]
		if node is Node3D:
			xf = xf * (node as Node3D).transform
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var a: AABB = xf * (node as MeshInstance3D).mesh.get_aabb()
			if has:
				acc = acc.merge(a)
			else:
				acc = a
				has = true
		for c in node.get_children():
			stack.push_back([c, xf])
	return acc

func _init() -> void:
	var scn: PackedScene = load(SCENE)
	if scn == null:
		push_error("slice.tscn load failed")
		quit()
		return
	var root: Node3D = scn.instantiate() as Node3D

	# 可重跑：先移除既有節點
	var old: Node = root.get_node_or_null(NODE_NAME)
	if old != null:
		root.remove_child(old)
		old.free()
		print("REPLACED existing %s" % NODE_NAME)

	var asset: PackedScene = load(ASSET)
	if asset == null:
		push_error("火見櫓.glb load failed")
		quit()
		return
	var t: Node3D = asset.instantiate() as Node3D
	t.name = NODE_NAME

	var bb: AABB = _local_bbox(t)
	var s: float = TARGET_H / maxf(bb.size.y, 0.001)
	t.scale = Vector3(s, s, s)
	t.rotation_degrees = Vector3(0.0, YAW_DEG, 0.0)

	# 落地：底面沉入 SINK。旋轉僅繞 Y，且 yaw=180 對中心位移取負，
	# 故 XZ 補正需套用旋轉後的中心偏移。
	var c: Vector3 = bb.position + bb.size * 0.5
	var yaw: float = deg_to_rad(YAW_DEG)
	var cx: float = c.x * s
	var cz: float = c.z * s
	var rx: float = cx * cos(yaw) + cz * sin(yaw)
	var rz: float = -cx * sin(yaw) + cz * cos(yaw)
	t.position = Vector3(
		POS_X - rx,
		-SINK - bb.position.y * s,
		POS_Z - rz)

	root.add_child(t)
	t.owner = root

	var packed: PackedScene = PackedScene.new()
	var perr: int = packed.pack(root)
	if perr != OK:
		push_error("pack failed %d" % perr)
		quit()
		return
	var err: int = ResourceSaver.save(packed, SCENE)
	print("PLACED %s  scale=%.4f  pos=(%.2f, %.3f, %.2f)  高=%.2fm  底=%.2f x %.2f  save=%s" % [
		NODE_NAME, s, t.position.x, t.position.y, t.position.z,
		bb.size.y * s, bb.size.x * s, bb.size.z * s,
		"OK" if err == OK else "FAIL %d" % err])
	root.free()
	quit()
