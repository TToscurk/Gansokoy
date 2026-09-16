extends SceneTree
## 獸道樹木接地取證 —— 用畫面判「樹是不是浮在空中」。
##   Godot --rendering-method gl_compatibility --path godot --script tools/capture_trail_trees.gd
##
## 為什麼要拍：tools/probe_trail_trees.gd 量出「12 棵浮、1044 棵埋」，與使用者
##   看到的「浮在空中」相反 —— 量測基準（mesh AABB 下緣）跟眼睛看到的不是同一件事。
##   這種歧異只有畫面能斷。
##
##  相機高度必須由 Terrain mesh 取樣 —— 第一版把相機放在 spine 的 y=0 再加高度，
##   結果整台相機埋在地形底下（拍出來下半是天空、上半是地形背面），看起來像「樹浮在
##   空中、樹根懸空」，其實是從地底往上看。那種圖不能拿來判接地。

const OUT := "D:/神社/shrine/shots2/trail_trees_20260916/"

var _root: Node3D
var _main: Node
var _dm: Node
var _verts: PackedVector3Array
var _res := 0
const HALF := 120.0


func _init() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _ground(x: float, z: float) -> float:
	var step := 2.0 * HALF / float(_res - 1)
	var fi: float = clampf((x + HALF) / step, 0.0, float(_res - 1))
	var fj: float = clampf((z + HALF) / step, 0.0, float(_res - 1))
	var i0 := int(floor(fi))
	var j0 := int(floor(fj))
	var i1: int = mini(i0 + 1, _res - 1)
	var j1: int = mini(j0 + 1, _res - 1)
	var tx := fi - float(i0)
	var tz := fj - float(j0)
	return lerpf(lerpf(_verts[j0 * _res + i0].y, _verts[j0 * _res + i1].y, tx),
		lerpf(_verts[j1 * _res + i0].y, _verts[j1 * _res + i1].y, tx), tz)


func _spine_point(t: float) -> Vector2:
	var spine: PackedVector2Array = _root.get_meta("spine")
	var f := t * float(spine.size() - 1)
	var i := int(floor(f))
	var j: int = mini(i + 1, spine.size() - 1)
	return spine[i].lerp(spine[j], f - float(i))


func _shoot(cam: Camera3D, pos: Vector3, look: Vector3, tag: String) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	await _wait(8)
	_main.get_viewport().get_texture().get_image().save_png(OUT + tag + ".png")
	print("[SHOT] %-16s cam=(%.1f, %.1f, %.1f) 地面y=%.2f" % [
		tag, pos.x, pos.y, pos.z, _ground(pos.x, pos.z)])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _wait(4)
	_dm = root.get_node("/root/DialogueManager")
	for n in _main.find_children("*", "CanvasLayer", true, false):
		var sc = n.get_script()
		if sc != null and String(sc.resource_path).ends_with("dialogue_ui.gd"):
			n.set_process_unhandled_input(false)

	_main.load_map("trail", "")
	await _wait(120)
	var w := 0
	while not _dm.call("is_active") and w < 1800:
		await _wait(10)
		w += 10
	while _dm.call("is_active"):
		_dm.call("advance", 0)
		await _wait(2)

	_root = _main.get_node_or_null("MapRoot")
	if _root == null:
		var forest := _main.find_child("森林", true, false)
		if forest != null:
			_root = forest.get_parent() as Node3D
	if _root == null or not _root.has_meta("spine"):
		push_error("找不到帶 spine meta 的場景根")
		quit(1)
		return
	var terr: MeshInstance3D = null
	for c in _root.get_children():
		if c is MeshInstance3D and String(c.name).findn("Terrain") >= 0:
			terr = c
			break
	_verts = terr.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_res = int(round(sqrt(float(_verts.size()))))
	print("[SHOT] 地形 %d×%d" % [_res, _res])

	var cam := Camera3D.new()
	_main.add_child(cam)
	cam.fov = 62.0
	cam.current = true

	# 路沿（10 m 內會被 trunk_lift 下沉最多 2.6 m）＋大空地（古樹帶）
	for t in [0.05, 0.22, 0.40, 0.62, 0.80, 0.95]:
		var p := _spine_point(t)
		var nxt := _spine_point(minf(t + 0.04, 1.0))
		var gy := _ground(p.x, p.y)
		var tag := "t%02d" % int(t * 100)
		# ① 站在路上往前看（玩家視角，眼高 1.6 m）
		await _shoot(cam, Vector3(p.x, gy + 1.6, p.y),
			Vector3(nxt.x, _ground(nxt.x, nxt.y) + 1.0, nxt.y), tag + "_along")
		# ② 站在路上往側邊看（看樹根與地面接觸處）
		var perp := Vector2(nxt.x - p.x, nxt.y - p.y).orthogonal().normalized()
		await _shoot(cam, Vector3(p.x, gy + 1.6, p.y),
			Vector3(p.x + perp.x * 16.0, gy + 2.0, p.y + perp.y * 16.0), tag + "_side")
		# ③ 斜上俯看路沿（最容易看出底座有沒有離地）
		await _shoot(cam, Vector3(p.x - perp.x * 8.0, gy + 7.0, p.y - perp.y * 8.0),
			Vector3(p.x + perp.x * 8.0, gy, p.y + perp.y * 8.0), tag + "_down")
	quit(0)