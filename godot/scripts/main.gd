extends Node3D
## 世界載入器 —— Godot 版的 GameCore 雛形。
##
## 讀 data/mapRegistry.json（連通圖，單一事實來源，跟 web 版同一份資料）、
## 載 blockout/<id>.glb（three.js 烤出來的佈局底稿）、
## 用 data/<id>.meta.json 生成碰撞與傳送點。
##
## 座標系：three / glTF / Godot 都是右手系 y-up，座標原樣通用。

const START_MAP := "shrine"
## 傳送落地後的冷卻，免得一落地就被同一個傳送區抓回去
const PORTAL_COOLDOWN := 2.0
## 只有 XZ 跨度超過這個值的 mesh 才做 trimesh 碰撞（地形、大結構）。
## 小物件的碰撞交給 meta 裡的遊戲碰撞箱 —— 那份是 web 版調過手感的。
const TRIMESH_MIN_SPAN := 15.0

var registry: Dictionary = {}
var current_id := ""
var map_root: Node3D = null
var portal_cooldown := 0.0

@onready var player: CharacterBody3D = $Player
@onready var map_label: Label = $UI/MapLabel

func _ready() -> void:
	registry = _load_json("res://data/mapRegistry.json")
	# godot -- --map=trail 直接跳到指定圖（測試 / 開發用）
	var start := START_MAP
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			start = a.substr(6)
		elif a.begins_with("--shot="):      # 跑 N 幀後存截圖然後退出（CI / 無頭檢視用）
			_shot_path = a.substr(7)
		elif a.begins_with("--shot-cam="):  # x,y,z,lx,ly,lz 自由鏡位（拍照模式）
			_shot_cam = a.substr(11)
	load_map(start, "")
	if _shot_cam != "":
		var v := _shot_cam.split_floats(",")
		var cam := Camera3D.new()
		cam.position = Vector3(v[0], v[1], v[2])
		add_child(cam)
		cam.look_at(Vector3(v[3], v[4], v[5]))
		cam.current = true

var _shot_path := ""
var _shot_cam := ""
var _shot_frames := 0
var _default_env: Environment = null

func _shot_tick() -> void:
	_shot_frames += 1
	if _shot_frames == 45:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		print("screenshot -> ", _shot_path)
		get_tree().quit()

func _process(delta: float) -> void:
	portal_cooldown = maxf(0.0, portal_cooldown - delta)
	if _shot_path != "":
		_shot_tick()

func _load_json(p: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(p)
	if txt.is_empty():
		push_error("讀不到 %s" % p)
		return {}
	return JSON.parse_string(txt)

func load_map(id: String, from_id: String) -> void:
	var meta := _load_json("res://data/%s.meta.json" % id)
	if meta.is_empty():
		return
	if map_root:
		map_root.queue_free()

	current_id = id
	# 原生場景（maps/<id>/<id>.tscn，視覺重做完成的圖）優先；
	# 還沒重做的圖 fallback 到 three.js 烤出來的 blockout 底稿。
	var native := "res://maps/%s/%s.tscn" % [id, id]
	var use_native := ResourceLoader.exists(native)
	print("[map] %s → %s" % [id, native if use_native else "blockout"])
	var packed: PackedScene = load(native) if use_native else load("res://blockout/%s.glb" % id)
	map_root = packed.instantiate()
	add_child(map_root)
	var terr := map_root.get_node_or_null("Terrain")
	if terr and terr is MeshInstance3D:
		print("[map] Terrain override=", terr.material_override)

	# 原生場景可以自帶 WorldEnvironment（霧、氛圍是每張圖的個性）——
	# 有的話就讓 main 的預設環境讓位，離圖時還回來
	var map_env := map_root.find_child("WorldEnvironment", true, false)
	if _default_env == null:
		_default_env = $WorldEnvironment.environment
	$WorldEnvironment.environment = null if map_env else _default_env

	_build_trimesh_collision(map_root)
	_build_game_colliders(meta)
	_spawn_portals(meta)
	_place_player(meta, from_id)

	var info: Dictionary = registry.get(id, {})
	map_label.text = "%s  %s" % [info.get("zh", id), info.get("en", "")]

## 大 mesh（地形、合併後的建築群）做 trimesh 靜態碰撞
func _build_trimesh_collision(root: Node) -> void:
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D:
			var aabb: AABB = n.get_aabb()
			if maxf(aabb.size.x, aabb.size.z) >= TRIMESH_MIN_SPAN:
				n.create_trimesh_collision()

## web 版的遊戲碰撞箱（box / cylinder，手感調過的那份）
func _build_game_colliders(meta: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = "GameColliders"
	map_root.add_child(body)
	for c in meta.get("colliders", []):
		var shape := CollisionShape3D.new()
		var y: float = c.get("y", 0.0)
		var h: float = c.get("h", 1.0)
		if c.has("r"):
			var cyl := CylinderShape3D.new()
			cyl.radius = c.r
			cyl.height = h
			shape.shape = cyl
		else:
			var box := BoxShape3D.new()
			box.size = Vector3(c.hw * 2.0, h, c.hd * 2.0)
			shape.shape = box
		shape.position = Vector3(c.x, y + h * 0.5, c.z)
		body.add_child(shape)

## 傳送點：光柱示意 + Area3D 觸發
func _spawn_portals(meta: Dictionary) -> void:
	for p in meta.get("portals", []):
		if p.get("target") == null:
			continue
		var area := Area3D.new()
		area.name = "Portal_%s" % p.target
		area.position = Vector3(p.x, p.y + 1.0, p.z)
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 1.6
		cyl.height = 3.0
		shape.shape = cyl
		area.add_child(shape)

		var beam := MeshInstance3D.new()
		var m := CylinderMesh.new()
		m.top_radius = 0.35
		m.bottom_radius = 0.55
		m.height = 2.6
		beam.mesh = m
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.55, 0.9, 1.0, 0.35)
		mat.emission_enabled = true
		mat.emission = Color(0.55, 0.9, 1.0)
		mat.emission_energy_multiplier = 2.0
		beam.material_override = mat
		area.add_child(beam)

		area.body_entered.connect(_on_portal_entered.bind(String(p.target)))
		map_root.add_child(area)

func _on_portal_entered(body: Node3D, target: String) -> void:
	if body != player or portal_cooldown > 0.0:
		return
	# 目的地還沒烤（built:false）就不動 —— 跟 web 版「看到光＝走得過去」不同，
	# 這裡先把光留著當 TODO 標記
	if not FileAccess.file_exists("res://data/%s.meta.json" % target):
		return
	var from := current_id
	call_deferred("load_map", target, from)

## 從 from_id 進來 → 落在通往 from_id 的傳送點旁；首次啟動（沒有來源圖）
## 也落在第一個傳送點旁 —— 圖中心常常是建築物的正上方
func _place_player(meta: Dictionary, from_id: String) -> void:
	var spawn := Vector3(0.0, 40.0, 0.0)
	var portals: Array = meta.get("portals", [])
	if from_id == "" and portals.size() > 0:
		var p0: Dictionary = portals[0]
		spawn = Vector3(p0.x, p0.y + 2.0, p0.z)
	for p in portals:
		if p.get("target") == from_id:
			spawn = Vector3(p.x, p.y + 2.0, p.z)
			# 往圖中心退幾步，不要站在觸發區正中央
			var inward := (Vector3(0.0, spawn.y, 0.0) - spawn)
			inward.y = 0.0
			if inward.length() > 0.01:
				spawn += inward.normalized() * 4.0
			break
	player.velocity = Vector3.ZERO
	player.global_position = spawn
	portal_cooldown = PORTAL_COOLDOWN
