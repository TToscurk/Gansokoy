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
		elif a.begins_with("--shots="):     # 資產正面照：一次載圖、連拍多張
			_shots_file = a.substr(8)
		elif a.begins_with("--shotdir="):
			_shot_dir = a.substr(10)
	load_map(start, "")
	# ⚠ 撮影モードではプレイヤーを隠す。
	# `$Player` は未テクスチャの白いカプセル。スポーン地点に立ったまま
	# **Phase 1.5 以降ほぼ全ての審図カットに写り込んでいた** —— しかも
	# slice.tscn には存在しないので、シーングラフをいくら probe しても
	# 見つからない。村民を隔離し、箒を暗くし、立て看板を作り直し、太陽の
	# 円盤まで疑ってから、ようやく「撮影者自身が写っていた」と判明した。
	# ⚠ ここに置くこと：`load_map()` は上で**先に**走るので、その中に
	#   `_shots.is_empty()` の判定を書いても永遠に成立しない（一度やった）。
	# 教訓：シーンに無い白い物体は、シーンの外（ランナー側）を疑う。
	if _shot_path != "" or _shots_file != "":
		player.visible = false
	if _shots_file != "":
		_shots = _load_json_array(_shots_file)
		_shot_cam_node = Camera3D.new()
		add_child(_shot_cam_node)
		_shot_cam_node.current = true
		_aim_shot(0)
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
## ── 資產正面照（ADR-016）──
## 每個具體的建築與地標登記一組固定機位，改完自動全拍一輪。
## 一次載圖連拍，不然 15 張要重開 15 次 Godot。
var _shots_file := ""
var _shot_dir := "/tmp"
var _shots: Array = []
var _shot_i := 0
var _shot_cam_node: Camera3D = null
var _shot_wait := 0

func _load_json_array(path: String) -> Array:
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		push_error("讀不到 shots 清單 %s" % path)
		return []
	var v = JSON.parse_string(txt)
	return v if v is Array else []

func _aim_shot(i: int) -> void:
	var e: Dictionary = _shots[i]
	var c: Array = e.get("cam", [0, 10, 10])
	var l: Array = e.get("look", [0, 0, 0])
	_shot_cam_node.position = Vector3(c[0], c[1], c[2])
	_shot_cam_node.look_at(Vector3(l[0], l[1], l[2]))
	# 可指定時刻。ADR-016 要求每張正面照都要親眼看過 —— 但預設的 17:5x
	# 斜陽會把半數畫面壓進陰影裡，看不出資產做得對不對。
	# 要檢查造型的鏡頭就寫 "time": 11，讓太陽在高處。
	if e.has("time"):
		DayNight.flowing = false
		DayNight.set_hour(float(e["time"]))
	_shot_wait = 0

func _shotlist_tick() -> void:
	_shot_wait += 1
	if _shot_wait < 30:
		return
	var e: Dictionary = _shots[_shot_i]
	var out := "%s/%s.png" % [_shot_dir, String(e.get("name", "shot%d" % _shot_i))]
	get_viewport().get_texture().get_image().save_png(out)
	print("  ✓ ", e.get("name", ""), " -> ", out)
	_shot_i += 1
	if _shot_i >= _shots.size():
		print("資產正面照完成：%d 張" % _shots.size())
		get_tree().quit()
		return
	_aim_shot(_shot_i)
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
	$UI/ClockLabel.text = DayNight.clock_text()
	if _shot_path != "":
		_shot_tick()
	elif not _shots.is_empty():
		_shotlist_tick()

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

	# 佈局重新生成的原生圖（如獸道的新森林）自帶碰撞，web 版碰撞箱對不上
	var own: bool = map_root.get_meta("own_colliders", false)
	_build_trimesh_collision(map_root, own)
	if not own:
		_build_game_colliders(meta)
	_spawn_portals(meta)
	_place_player(meta, from_id)

	var info: Dictionary = registry.get(id, {})
	map_label.text = "%s  %s" % [info.get("zh", id), info.get("en", "")]

## 大 mesh 做 trimesh 靜態碰撞。
##
## own_colliders 的原生圖只做地形 —— 它們的建物已經自己放了手做碰撞箱
## （人間之里就有 458 個）。原本這裡不分青紅皂白掃全場，等於在 458 個
## 箱子上面又疊了 2262 個三角網碰撞體，每一片屋頂、每一段牆各一個。
## 「有點卡」有一大半是這個。
func _build_trimesh_collision(root: Node, own_colliders: bool) -> int:
	var n_col := 0
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D:
			if own_colliders and not (String(n.name) == "Terrain" or n.has_meta("needs_trimesh")):
				continue
			var aabb: AABB = n.get_aabb()
			if maxf(aabb.size.x, aabb.size.z) >= TRIMESH_MIN_SPAN:
				n.create_trimesh_collision()
				n_col += 1
	print("[map] trimesh 碰撞 %d 個（own_colliders=%s）" % [n_col, own_colliders])
	return n_col

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
##
## target 為 null／空字串 = **保留中的觸發區**：Area3D 與偵測照樣建起來，
## 只是不執行場景切換、也不畫光柱（還不能走的出口不該亮著邀請玩家）。
## 之後在 meta.json 的 portals[].target 填上目的地，這裡不用改任何一行
## 就會自動變成正常傳送點。
## （首例：稗田邸後院小徑終點的木戶，座標見 data/hieda_garden.markers.json，
## 由 make_hieda.py 跟幾何一起產出，不是手抄的。）
func _spawn_portals(meta: Dictionary) -> void:
	for p in meta.get("portals", []):
		var tgt: Variant = p.get("target")
		var reserved: bool = tgt == null or String(tgt).is_empty()

		var area := Area3D.new()
		area.name = "Portal_%s" % ("保留" if reserved else String(tgt))
		area.position = Vector3(p.x, p.y + 1.0, p.z)
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 1.6
		cyl.height = 3.0
		shape.shape = cyl
		area.add_child(shape)

		if not reserved:
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

		if reserved:
			area.body_entered.connect(_on_portal_reserved.bind(area.name))
		else:
			area.body_entered.connect(_on_portal_entered.bind(String(tgt)))
		map_root.add_child(area)

## 保留中的觸發區：偵測邏輯已經接好，只差目的地。
func _on_portal_reserved(body: Node3D, who: String) -> void:
	if body != player or portal_cooldown > 0.0:
		return
	portal_cooldown = PORTAL_COOLDOWN
	if OS.is_debug_build():
		print("[portal] %s：觸發區已作用，但尚未指定目的地" % who)

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
			# Low-ceiling interiors may override the default 2 m drop height.
			# The horizontal inward offset remains identical for every portal.
			var arrival_y_offset: float = float(p.get("arrival_y_offset", 2.0))
			spawn = Vector3(p.x, p.y + arrival_y_offset, p.z)
			# 往圖中心退幾步，不要站在觸發區正中央
			var inward := (Vector3(0.0, spawn.y, 0.0) - spawn)
			inward.y = 0.0
			if inward.length() > 0.01:
				spawn += inward.normalized() * 4.0
			break
	player.velocity = Vector3.ZERO
	player.global_position = spawn
	portal_cooldown = PORTAL_COOLDOWN
