extends SceneTree
## 獸道 V0.1 白模產生器（T05–T08/T10/T11 的 V0.1 版）。
##   godot --headless --path godot --script res://tools/beast_path/generate_beast_path.gd [-- --no-forest --only=S02]
## 輸出：
##   maps/beast_path/{s01_entrance,s02_deep_forest,s03_crossroads,s04_boss_clearing}.tscn
##   maps/beast_path/beast_path.tscn         （main.gd 的載圖慣例是 maps/<id>/<id>.tscn；規格書寫的 beast_path_root 以專案慣例為準）
##   maps/beast_path/gen/*.res               （地形網格、地形碰撞；大資料不進 .tscn）
##   maps/beast_path/gen/forest_plan.json    （森林擺放資料＝可重建來源）
##   data/beast_path.meta.json               （出生點、傳送點）
## 唯一資料來源：tools/beast_path/layout_beast_path.json。不改任何既有 village_v2 檔案。
## 本檔產生的是白模（WHITEBOX / ART_REVIEW）：道具是基本幾何代理，樹／竹／灌木／倒木重用 V2 已核准的 veg_kit／bamboo_kit。
## 全部是基本幾何或既有資產 prefab → 可 --headless 執行（沒有 MultiMesh，不受 MultiMesh Build Rule 限制）。

const BPLib := preload("res://tools/beast_path/bp_lib.gd")
const TerrainGen := preload("res://tools/beast_path/terrain_generator.gd")
const PropBuilder := preload("res://tools/beast_path/prop_builder.gd")
const ForestPlanner := preload("res://tools/beast_path/forest_planner.gd")
const FxBuilder := preload("res://tools/beast_path/fx_builder.gd")
const S01Ground := preload("res://tools/beast_path/s01_ground.gd")      # S01 R1：S01 專用地表情境（獨立於 S04 的 bp_lib.ground_channels）
const S01Wall := preload("res://tools/beast_path/s01_wall.gd")          # S01 R2：谷壁點綴（只在 S01；fp.s01_wall 為空＝R1 行為不變）
const ZoneGround := preload("res://tools/beast_path/zone_ground.gd")    # 全區美術完成：S02／S03 森林地表（layout.zone_ground.enabled）

const OUT_DIR := "res://maps/beast_path/"
const GEN_DIR := "res://maps/beast_path/gen/"
const META_PATH := "res://data/beast_path.meta.json"
const LOG_SCENE := "res://assets/village_v2/veg_kit/trees/log_a.tscn"
const LOG_LEN := 6.6

var lib: BPLib
var props: PropBuilder
var fp: ForestPlanner
var no_forest := false
var only := ""
var _poi_nodes := {}              # scene_id → Array[Node3D]
var _deferred: Array = []
var _exit_seal: Dictionary = {}
var _san := [0]
var _ground_ctx := {}             # S04 天然地表：canopy／rock_d 場（樹冠遮蔭、離岩腳距離）
var _ground_ctx_s01 := {}         # S01 R1：S01 地表情境（layout.s01_ground.enabled 才有）
var _ground_ctx_zone := {}        # S02／S03 森林地表（layout.zone_ground.enabled 才有）


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--no-forest":
			no_forest = true
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GEN_DIR))
	# V1.2：岩石網格每次全部重生。先清掉上一版留下的（退役岩片的網格不再殘留在磁碟上；V1.1→V1.2 時發現殘留了 104 個孤兒檔）
	var rd := DirAccess.open(GEN_DIR + "rocks")
	if rd != null:
		for fn in rd.get_files():
			if fn.ends_with(".res"):
				rd.remove(fn)
	lib = BPLib.new()
	lib.setup(true, true)
	TerrainGen.write_rock_material(lib)          # 岩片／巨石的網格引用這個 .tres → 必須先於 _build_pois
	props = PropBuilder.new()
	props.setup(lib)
	for r: Dictionary in lib.rects:
		_poi_nodes[String(r["id"])] = []
	_build_pois()
	_build_pool_shore()
	fp = ForestPlanner.new()
	fp.setup(lib, props.footprints)
	_write_forest_inputs()
	fp.drop_boxes = props.face_boxes
	if not no_forest:
		fp.plan()
		if fp.freeze_error != "":
			push_error("[forest] " + fp.freeze_error)
			quit(1)
			return
		_register_pin_anchors()
		if not fp.s01_info.is_empty():
			print("[forest] S01 候選：", fp.s01_info)
		print("[forest] ", fp.stats, "  凍結區（V0.1 原樣載入）：", fp.frozen_scenes)
		print("[forest] S04＝V1.2 凍結：原樣 %d、重新落地 %d、剔除 %d  剔除=%s  落地=%s" % [fp.s04_kept, fp.s04_reground.size(), fp.s04_dropped.size(), str(fp.s04_dropped), str(fp.s04_reground)])
	_build_deferred()
	_prep_ground()
	for sc: Dictionary in lib.L["scenes"]:
		if only != "" and String(sc["id"]) != only:
			continue
		_build_scene(sc)
	_build_root()
	_write_meta()
	_write_plan()
	print("[rocks] ", props.rock_stats)
	print("[gen] 完成 %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)


# ---------------------------------------------------------------- POI
func _poi_pos(poi: Dictionary) -> Vector2:
	if poi.has("at"):
		var a: Dictionary = poi["at"]
		if a.has("br") and a.has("u0"):
			var bp: BPLib.Poly = lib.branches[String(a["br"])]
			return bp.pos_at((float(a["u0"]) + float(a["u1"])) * 0.5 * bp.length)
		if a.has("st") and a.has("ds0"):
			return lib.main.pos_at(lib.st_s(String(a["st"])) + (float(a["ds0"]) + float(a["ds1"])) * 0.5)
		return lib.resolve(a)["p"]
	if poi.has("st0"):
		var s0 := lib.st_s(String(poi["st0"])) + float(poi.get("ds0", 0.0))
		var s1 := lib.st_s(String(poi["st1"])) + float(poi.get("ds1", 0.0))
		return lib.main.pos_at((s0 + s1) * 0.5)
	return Vector2.ZERO


func _add_poi(poi: Dictionary) -> void:
	var node: Node3D = null
	if String(poi["kind"]) == "log":
		node = _log_kit(poi)
	else:
		node = props.build(poi)
	if node == null:
		return
	var sc := lib.scene_id_of_z(_poi_pos(poi).y)
	(_poi_nodes[sc] as Array).append(node)


## V1.2 D：潭岸濕石。潭的水陸邊界原本是一條硬線（形狀乾淨、沒有任何東西跨在線上）。
## 沿「實際岸線」（由潭心往外掃，地形高度第一次 ≥ 水位處）擺大小不一的苔石，一部分半沒入水、一部分在岸上；
## 瀑布正下方的角度（北）留空，讓落水點保持乾淨；朝戰場的南側只放小石／碎石（tiny 無碰撞），不擋踩潭台地。
func _build_pool_shore() -> void:
	var P: Dictionary = lib.L["boss_arena"]["pool"]
	var pc := Vector2(float(P["x"]), float(P["z"]))
	var wl := lib.water_y_at_stream("stream_trib", 0.0)
	var holder := Node3D.new()
	holder.name = "PoolShore"
	var rr := RandomNumberGenerator.new()
	rr.seed = 40721
	# 角度（度，0＝+x、90＝+z＝朝戰場）：[角, 尺寸, 離岸線偏移 m（負＝入水）, 苔]
	var spec: Array = [
		[-158.0, "medium", 0.2, 0.8], [-132.0, "small", -0.3, 0.7], [-48.0, "small", -0.2, 0.7], [-24.0, "cobble", 0.1, 0.7],
		[-3.0, "small", 0.5, 0.6], [22.0, "tiny", -0.2, 0.5], [48.0, "tiny", 0.3, 0.5], [73.0, "small", 0.9, 0.5],
		[104.0, "tiny", 0.2, 0.5], [132.0, "small", 0.6, 0.55], [160.0, "cobble", 0.2, 0.65], [183.0, "small", -0.4, 0.7],
		[-170.0, "tiny", -0.6, 0.6], [8.0, "tiny", -0.5, 0.6]]
	var n := 0
	for e: Array in spec:
		var a: float = e[0]
		var dir := Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a)))
		var rs := 2.5
		while rs < 9.5 and lib.h_at(pc.x + dir.x * rs, pc.y + dir.y * rs) < wl - 0.02:
			rs += 0.1
		var q := pc + dir * (rs + float(e[2]) + rr.randf_range(-0.25, 0.25))
		if lib.scene_id_of_z(q.y) != "S04":
			continue
		var sz := String(e[1])
		var south := a > 5.0 and a < 175.0                  # 朝戰場、可走的潭台地側：不給碰撞（碎石）或只給小石
		var nd := props.make_rock(holder, "pool_shore_%d" % n, q, sz, float(e[3]), rr.randf() * TAU, not south)
		if nd != null:
			props._fp("pool_shore_%d" % n, q, 0.9 if sz != "tiny" else 0.4)
			n += 1
	(_poi_nodes["S04"] as Array).append(holder)
	print("[pool] 潭岸石 %d 顆" % n)


func _build_pois() -> void:
	for poi: Dictionary in lib.L["pois"]:
		var k := String(poi["kind"])
		if k == "spawn" or k == "portal_marker":
			continue
		if k == "shimenawa":
			_deferred.append(poi)
			continue
		_add_poi(poi)
	var face: Array = []
	for poi: Dictionary in _arena_pois():
		if String(poi["kind"]) == "shimenawa":
			_deferred.append(poi)
		elif String(poi["kind"]) == "face_rock":
			face.append(poi)
		else:
			_add_poi(poi)
	# V1.3：崖面岩塊放在 V1.2 的 POI 之後建、並還原 props 的共用亂數狀態。
	#   props.build() 每個 POI 都會用 id 重設 _rng，但「最後一個 POI 用剩的狀態」會流進下一步的潭岸石（_rock_radius 用 _rng 抽半徑）；
	#   V1.3 第一版把崖面岩塊排在最後 → 潭岸石 14 顆的半徑整組換掉（位置／旋轉不變，高度差 1–3 cm，網格全部重生）。
	#   還原後潭岸石＝V1.2 原樣（verify：pool.shore_v12_kept）。
	var st := props._rng.state
	for poi: Dictionary in face:
		_add_poi(poi)
	props._rng.state = st


## 倒木：重用 veg_kit/log_a（核准資產，長 6.6 m，長軸＝本地 X），按兩端地形傾斜
func _log_kit(poi: Dictionary) -> Node3D:
	var at := lib.resolve(poi["at"])
	var p: Vector2 = at["p"]
	var yaw := deg_to_rad(float(poi.get("yaw_deg", 0.0)))
	var length := float(poi.get("len", LOG_LEN))
	var s := length / LOG_LEN
	var d2 := Vector2(sin(yaw), cos(yaw))
	var a2 := p - d2 * length * 0.5
	var b2 := p + d2 * length * 0.5
	var ya := lib.h_at(a2.x, a2.y)
	var yb := lib.h_at(b2.x, b2.y)
	var ym := (ya + yb) * 0.5 + 0.03
	var xax := Vector3(d2.x, (yb - ya) / length, d2.y).normalized()
	var zax := xax.cross(Vector3.UP).normalized()
	var yax := zax.cross(xax).normalized()
	var inst := (load(LOG_SCENE) as PackedScene).instantiate() as Node3D
	inst.name = String(poi["id"])
	inst.transform = Transform3D(Basis(xax, yax, zax).scaled(Vector3.ONE * s), Vector3(p.x, ym, p.y))
	inst.set_meta("bp_id", String(poi["id"]))
	inst.set_meta("bp_kind", "log")
	inst.set_meta("bp_spec", String(poi.get("spec", "")))
	inst.set_meta("bp_asset", "veg_kit/log_a")
	props._fp(String(poi["id"]), p, length * 0.5 + 0.8)
	return inst


## BOSS 場（B02–B05、祭壇、破鳥居、出口封印）→ 轉成 POI 交給同一個 builder
func _arena_pois() -> Array:
	var A: Dictionary = lib.L["boss_arena"]
	var out: Array = []
	var c0 := lib.arena_c()
	var i := 0
	for c: Dictionary in A["cover"]:
		var p := lib.arena_pos(float(c["deg"]), float(c["r"]))
		var at := {"x": p.x, "z": p.y}
		if String(c["kind"]) == "rock":
			out.append({"id": "arena_cover_%d" % i, "kind": "rock", "spec": "B04", "at": at, "size": c["size"], "moss": 0.35})
		else:
			out.append({"id": "arena_cover_%d" % i, "kind": "log", "spec": "B04", "at": at, "yaw_deg": 90.0 - float(c["deg"]), "len": float(c["len"])})
		i += 1
	i = 0
	for b: Dictionary in A["boundary"]:
		var p2 := lib.arena_pos(float(b["deg"]), float(b["r"]))
		out.append({"id": "arena_rootrock_%d" % i, "kind": "rock", "spec": "B02", "at": {"x": p2.x, "z": p2.y}, "size": "large", "moss": 0.55})
		var p3 := lib.arena_pos(float(b["deg"]) + 7.0, float(b["r"]) + 1.2)
		out.append({"id": "arena_roots_%d" % i, "kind": "roots", "spec": "B02", "at": {"x": p3.x, "z": p3.y}, "r": 2.2, "natural": true})
		i += 1
	# V1.2 A：場邊石燈籠已退役（layout 的 _retired_lanterns），不再產生
	# V1.2 B：岩壁改成「岩石群」。每顆逐一明寫在 layout.boss_arena.rock_groups（不抽亂數）：
	#   id＝arena_wall_<群>_<序>；yaw＝切線方向(−deg)＋yaw 偏角，或 yaw_abs 直接指定；JL／JR 是 V1.1 守門岩的原參數。
	#   hero＝要不要用 Blender Hero Rock（V1.2 F；沒有該資產就退回程序岩片）。
	for grp: Dictionary in A.get("rock_groups", []):
		var kk := 0
		for m: Dictionary in grp["members"]:
			var sp := lib.arena_pos(float(m["deg"]), float(m["r"]))
			var yaw_deg := float(m["yaw_abs"]) if m.has("yaw_abs") else -float(m["deg"]) + float(m.get("yaw", 0.0))
			out.append({"id": "arena_wall_%s_%d" % [grp["id"], kk], "kind": "cliff_slab", "spec": "B-WALL", "at": {"x": sp.x, "z": sp.y},
				"w": float(m["w"]), "h": float(m["h"]), "d": float(m["d"]), "yaw_deg": yaw_deg, "moss": float(m.get("moss", 0.5)), "hero": String(m.get("hero", "")), "form": String(m.get("form", "slab"))})
			kk += 1
	i = 0
	for fl: Dictionary in A.get("flank", []):
		out.append({"id": "arena_flank_%d" % i, "kind": "cliff_slab", "spec": "B-WALL", "at": {"x": float(fl["x"]), "z": float(fl["z"])},
			"w": float(fl["w"]), "h": float(fl["h"]), "d": float(fl["d"]), "yaw_deg": float(fl.get("yaw", 0.0)), "moss": 0.6})
		i += 1
	# V1.3：北崖崖面的岩塊（把崖前岩柱和崖頂連成同一塊石頭；逐顆明寫在 layout.boss_arena.cliff_face，不抽亂數）
	for cf: Dictionary in A.get("cliff_face", []):
		var e := cf.duplicate()
		e["id"] = "cliff_face_%s" % String(cf["id"])
		e["kind"] = "face_rock"
		e["spec"] = "B-WALL"
		e["at"] = {"x": float(cf["x"]), "z": -437.0}
		out.append(e)
	# V1.1：場邊六根石柱與箱型祭壇已移除（layout 的 _retired_pillars／_retired_altar）；結界石柱只留出口封印那對（有敘事功能）。
	# V1.2 A：東北出口的『破鳥居』（紅圓柱）與出口石柱已退役（layout 的 _retired_torii_broken）。
	# 出口封印的視覺＝兩棵老杉（forest.pins: exit_seal_tree_L/R，真樹）＋風化的注連繩；碰撞不變（ExitSealBlock 在 _build_markers）。
	var xs: Dictionary = A["exit_seal"]
	out.append({"id": "exit_shimenawa", "kind": "shimenawa", "spec": "B08", "between": ["exit_seal_tree_L", "exit_seal_tree_R"], "h": float(xs["rope_h"]), "weathered": true})
	var em := lib.resolve({"br": "exit_shrine", "u": float(xs["u"])})
	_exit_seal = {"p": em["p"], "yaw": em["yaw"]}
	return out


func _register_pin_anchors() -> void:
	for t: Dictionary in fp.trees:
		var pin := String(t["pin"])
		if pin == "":
			continue
		var hh := float((fp.kit[String(t["id"])] as Dictionary)["h"]) * float(t["s"])
		props.anchors[pin] = {"p": Vector3(float(t["x"]), float(t["y"]), float(t["z"])), "h": hh, "r": float(t["r"])}


func _build_deferred() -> void:
	for poi: Dictionary in _deferred:
		var node := props.build_deferred(poi)
		if node == null:
			continue
		var between: Array = poi["between"]
		var a: Dictionary = props.anchors[String(between[0])]
		var sc := lib.scene_id_of_z((a["p"] as Vector3).z)
		(_poi_nodes[sc] as Array).append(node)


# ---------------------------------------------------------------- S04 天然地表情境（V1.1）
## 地表權重的「原因」來自場景裡已經規劃好的東西：樹的位置（落葉聚在樹冠下）、岩壁／巨石腳印（碎石與苔）。
func _prep_ground() -> void:
	TerrainGen.write_ground_material(lib)
	TerrainGen.write_water_materials(lib)
	var crowns: Array = []
	if fp != null:
		for t: Dictionary in fp.trees:
			if String(t["scene"]) != "S04":
				continue
			var kind := String(t["kind"])
			if kind != "tree" and kind != "pin" and kind != "landmark":
				continue
			var hh := float((fp.kit[String(t["id"])] as Dictionary)["h"]) * float(t["s"])
			crowns.append({"x": float(t["x"]), "z": float(t["z"]), "reach": clampf(hh * 0.30, 2.0, 8.0), "w": clampf(hh / 20.0, 0.4, 1.3)})
	var rocks: Array = []
	for f: Dictionary in props.footprints:
		var id := String(f["id"])
		if id.begins_with("arena_wall") or id.begins_with("arena_flank") or id.begins_with("arena_cover") or id.begins_with("arena_rootrock") or id.begins_with("pool_shore") or id.begins_with("fall_") or id.contains("_rub") or id.contains("rock"):
			rocks.append({"p": f["p"], "r": float(f["r"])})
	_ground_ctx = {"canopy": lib.build_canopy_field(crowns), "rock_d": lib.build_rockprox_field(rocks)}
	# 供 probe_ground.gd 離線調地表分布（不必重生整個場景）
	var gf := FileAccess.open("user://beast_path_gctx.bin", FileAccess.WRITE)
	if gf != null:
		for key: String in ["canopy", "rock_d"]:
			gf.store_32((_ground_ctx[key] as PackedFloat32Array).size())
			gf.store_buffer((_ground_ctx[key] as PackedFloat32Array).to_byte_array())
		gf.close()
	print("[ground] 樹冠 %d 棵、岩腳 %d 處" % [crowns.size(), rocks.size()])
	_write_meadow_inputs(rocks)
	_prep_ground_s01()
	_prep_ground_zone()


## 全區美術完成：S02／S03 共用一份森林地表情境（同一個 S01 shader＋13 通道）。S01 接縫用 S01 自己的通道收尾、S04 接縫用 S04 的通道收尾。
func _prep_ground_zone() -> void:
	_ground_ctx_zone = {}
	var zg: Dictionary = lib.L.get("zone_ground", {})
	if not bool(zg.get("enabled", false)):
		return
	if only != "" and only != "S02" and only != "S03":
		return
	var s01c := _ground_ctx_s01
	if s01c.is_empty() and bool((lib.L.get("s01_ground", {}) as Dictionary).get("enabled", false)):
		s01c = S01Ground.build_ctx(lib, fp.trees if fp != null else [], fp.kit if fp != null else {}, props.footprints, fp.s01_wall if fp != null else {})
	TerrainGen.write_ground_material_zone(lib, ZoneGround.MAT_PATH)
	_ground_ctx_zone = ZoneGround.build_ctx_zone(lib, fp.trees if fp != null else [], fp.kit if fp != null else {}, props.footprints, s01c, _ground_ctx)
	print("[ground] S02／S03 森林地表：樹冠 %d 棵、岩腳 %d 處" % [int(_ground_ctx_zone["n_crowns"]), int(_ground_ctx_zone["n_rocks"])])


## S01 R1：S01 專用地表情境。只在重生 S01（或全部）時寫材質、建情境；--only=S02／S03／S04 不碰它。
func _prep_ground_s01() -> void:
	_ground_ctx_s01 = {}
	var sg: Dictionary = lib.L.get("s01_ground", {})
	if not bool(sg.get("enabled", false)):
		return
	if only != "" and only != "S01":
		return
	TerrainGen.write_ground_material_s01(lib)
	_ground_ctx_s01 = S01Ground.build_ctx(lib, fp.trees if fp != null else [], fp.kit if fp != null else {}, props.footprints, fp.s01_wall if fp != null else {})
	print("[ground] S01 地表情境：樹冠 %d 棵、岩腳 %d 處、手放特徵 %d 個" % [int(_ground_ctx_s01["n_crowns"]), int(_ground_ctx_s01["n_rocks"]), (sg.get("features", []) as Array).size()])


## V1.2 C：草叢層（bake_meadow_s04.gd）的輸入——岩腳落地線（含倒木、岩腳碎石）與 S04 樹幹圓。
## 烘焙要在非 headless 行程跑，所以規劃輸入先存檔；內容雜湊會寫進草叢場景的 meta，verify 以此偵測「岩／樹變了但草還是舊的」。
func _write_meadow_inputs(rocks: Array) -> void:
	var feet: Array = []
	for f: Dictionary in props.footprints:
		var id := String(f["id"])
		if id.begins_with("arena_wall") or id.begins_with("arena_flank") or id.begins_with("arena_cover") or id.begins_with("arena_rootrock") or id.contains("_rub") or id.contains("rock"):
			var q: Vector2 = f["p"]
			feet.append({"id": id, "p": [snappedf(q.x, 0.001), snappedf(q.y, 0.001)], "r": snappedf(float(f["r"]), 0.001)})
	var stems: Array = []
	if fp != null:
		for t: Dictionary in fp.trees:
			if String(t["scene"]) != "S04":
				continue
			var kind := String(t["kind"])
			if kind == "tree" or kind == "pin" or kind == "landmark" or kind == "dead":
				stems.append([snappedf(float(t["x"]), 0.001), snappedf(float(t["z"]), 0.001), snappedf(maxf(float(t["r"]), 0.2), 0.001)])
	var f := FileAccess.open(GEN_DIR + "s04_meadow_inputs.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"feet": feet, "stems": stems}, "\t"))
		f.close()
	print("[ground] 草叢輸入：岩腳 %d、樹幹 %d" % [feet.size(), stems.size()])


# ---------------------------------------------------------------- 場景
## 設 owner（讓節點進 PackedScene）。實例根（scene_file_path 非空）只設它自己，不進內部。
func _own_tree(n: Node, owner_: Node) -> void:
	for c in n.get_children():
		c.owner = owner_
		if c.scene_file_path == "":
			_own_tree(c, owner_)


## 把 builder 產生的未命名節點（@MeshInstance3D@12）改成穩定的名字
func _sanitize(n: Node) -> void:
	for c in n.get_children():
		if String(c.name).contains("@"):
			_san[0] += 1
			c.name = "%s_%d" % [c.get_class(), _san[0]]
		if c.scene_file_path == "":
			_sanitize(c)


func _save_res(res: Resource, fname: String) -> Resource:
	var path := GEN_DIR + fname
	var e := ResourceSaver.save(res, path)
	if e != OK:
		push_error("存 %s 失敗：%s" % [path, error_string(e)])
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


func _build_scene(sc: Dictionary) -> void:
	var sid := String(sc["id"])
	var lo := sid.to_lower()
	var root := Node3D.new()
	root.name = String(sc["root"])
	root.set_meta("bp_scene", sid)
	root.set_meta("bp_version", "0.1-whitebox")
	root.set_meta("bp_status", "WHITEBOX / ART_REVIEW")
	# ---- 地形
	var tctx := {}
	if sid == "S04":
		tctx = _ground_ctx
	elif sid == "S01" and not _ground_ctx_s01.is_empty():
		tctx = _ground_ctx_s01
	elif (sid == "S02" or sid == "S03") and not _ground_ctx_zone.is_empty():
		tctx = _ground_ctx_zone
	var td := TerrainGen.build_tile(lib, sc, tctx)
	if sid == "S01" and tctx.has("face"):
		var gst: Dictionary = tctx["s01"].stats
		print("[ground] S01 谷壁面鑲嵌：陡坡頂點 %d、植被覆蓋平均 %.2f" % [int(gst.get("face_cells", 0)), float(gst.get("face_veg", 0.0)) / maxf(float(gst.get("face_cells", 1)), 1.0)])
	var mesh := _save_res(td["mesh"], "%s_terrain.res" % lo) as Mesh
	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	root.add_child(mi)
	var sb := StaticBody3D.new()
	sb.name = "TerrainBody"
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	cs.name = "TerrainShape"
	cs.shape = _save_res(mesh.create_trimesh_shape(), "%s_terrain_shape.res" % lo) as Shape3D
	sb.add_child(cs)
	# ---- 水
	var wmat: Material = null
	if sid == "S04":
		wmat = TerrainGen._mat(TerrainGen.STREAM_MAT_PATH)
	elif (sid == "S02" or sid == "S03") and bool((lib.L.get("zone_ground", {}) as Dictionary).get("enabled", false)):
		wmat = TerrainGen.write_water_zone()           # 全區美術完成：S02／S03 溪水＝S04 同一個水 shader（新材質檔）
	var wm := TerrainGen.build_water(lib, sc, wmat)
	if wm != null:
		var wi := MeshInstance3D.new()
		wi.name = "Water"
		wi.mesh = wm
		wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wi)
	if sid == "S04":
		var wf := MeshInstance3D.new()
		wf.name = "Waterfall"
		wf.mesh = TerrainGen.build_waterfall(lib)
		wf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wf)
		var imp: Vector3 = (wf.mesh as ArrayMesh).get_meta("bp_impact")
		var wg := TerrainGen.waterfall_geom(lib)
		root.add_child(FxBuilder.waterfall_mist(imp, float(wg["w_base"])))
		root.add_child(FxBuilder.waterfall_spray(imp, float(wg["w_base"])))
		var pool := MeshInstance3D.new()
		pool.name = "PoolSurface"
		pool.mesh = TerrainGen.build_pool(lib)
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(pool)
	# ---- 道具
	var pr := Node3D.new()
	pr.name = "Props"
	root.add_child(pr)
	for n: Node3D in (_poi_nodes[sid] as Array):
		pr.add_child(n)
	# ---- 抓痕
	var cl := Node3D.new()
	cl.name = "ClawMarks"
	root.add_child(cl)
	if not no_forest:
		_build_claw_marks(cl, sid)
	# ---- 標記
	var mk := Node3D.new()
	mk.name = "Markers"
	root.add_child(mk)
	_build_markers(mk, sid)
	# ---- S01 R2：谷壁點綴（岩露頭／坡腳碎石／露根）。fp.s01_wall 只有 S01 候選 mode＝r2 才有；R1／replay 不會進這裡
	if sid == "S01" and not no_forest and fp != null and not fp.s01_wall.is_empty():
		var wd := S01Wall.build(lib, props, fp.s01_wall, fp.s01_wall.get("roots", []))
		root.add_child(wd["node"])
		print("[wall] S01 谷壁點綴：", wd["stats"])
	elif sid == "S01" and not no_forest:
		var nc := S01Wall.clear_meshes()                # R1／replay：沒有谷壁點綴；清掉 R2 留下的網格檔（檔案樹回到 R1 原樣）
		if nc > 0:
			print("[wall] S01 沒有谷壁點綴（mode≠r2）：清掉 %d 個舊的谷壁岩網格檔" % nc)
	# ---- procedural 節點統一設 owner（Forest 之外）
	_sanitize(root)
	for c in root.get_children():
		c.owner = root
		if c.scene_file_path == "":
			_own_tree(c, root)
	# ---- 森林（prefab 實例；內部節點不設 owner → 存成實例參照）
	var forest := Node3D.new()
	forest.name = "Forest"
	root.add_child(forest)
	forest.owner = root
	if sid == "S04":
		_attach_meadow(root)
		_attach_shadow_budget(root)
	if sid == "S01" and not no_forest:
		_attach_s01_dress(root)
	if (sid == "S02" or sid == "S03") and not no_forest:
		_attach_zone_dress(root, sid)
	var zcand: Dictionary = (lib.L.get("forest", {}) as Dictionary).get("zone_candidate", {})
	var drop_kinds: Array = ((zcand.get(sid, {}) as Dictionary).get("drop_kinds", []) as Array) if bool(zcand.get("enabled", false)) else []
	var counts := {"tree": 0, "bamboo": 0, "under": 0, "dead": 0, "dropped": 0}
	if not no_forest:
		var idx := 0
		for t: Dictionary in fp.trees:
			if String(t["scene"]) != sid:
				continue
			if drop_kinds.has(String(t["kind"])):
				counts["dropped"] = int(counts["dropped"]) + 1       # 候選：V0.1 林下 prefab 不載入（凍結檔原樣保留；林床改由 zone_dress）
				continue
			var inst := (load(fp.scene_path(String(t["id"]))) as PackedScene).instantiate() as Node3D
			inst.name = "%s_%d" % [String(t["id"]), idx]
			idx += 1
			if t.has("xf"):
				# 凍結的樹：用 V0.1 場景裡實際存檔的 transform（tscn 的 12 個數字＝列優先 3×3＋原點）→ 逐位元還原
				var m: Array = t["xf"]
				inst.transform = Transform3D(Basis(Vector3(m[0], m[3], m[6]), Vector3(m[1], m[4], m[7]), Vector3(m[2], m[5], m[8])), Vector3(m[9], m[10], m[11]))
			elif t.has("lean"):
				# S01 R1：候選樹可帶微傾（生長方向）：lean＝[軸x, 軸z, 角度 rad]，軸在水平面（世界座標）。
				# 順序：樹先繞自己的垂直軸轉 yaw，再在世界座標裡傾斜（所以傾向不會被 yaw 轉走），最後縮放；樹根留在原地。
				var ln: Array = t["lean"]
				var bl := Basis(Vector3(float(ln[0]), 0.0, float(ln[1])).normalized(), float(ln[2])) * Basis(Vector3.UP, float(t["yaw"]))
				inst.transform = Transform3D(bl.scaled(Vector3.ONE * float(t["s"])), Vector3(float(t["x"]), float(t["y"]), float(t["z"])))
			else:
				inst.position = Vector3(float(t["x"]), float(t["y"]), float(t["z"]))
				inst.rotation.y = float(t["yaw"])
				inst.scale = Vector3.ONE * float(t["s"])
			inst.set_meta("bp_kind", String(t["kind"]))
			if String(t["pin"]) != "":
				inst.set_meta("bp_pin", String(t["pin"]))
			forest.add_child(inst)
			inst.owner = root
			var kind := String(t["kind"])
			var ck := "tree" if (kind == "tree" or kind == "pin" or kind == "landmark") else kind
			counts[ck] = int(counts.get(ck, 0)) + 1
	var ps := PackedScene.new()
	var e := ps.pack(root)
	if e != OK:
		push_error("pack %s：%s" % [sid, error_string(e)])
	var path := OUT_DIR + String(sc["file"])
	e = ResourceSaver.save(ps, path)
	print("[scene] %s → %s  verts=%d tris=%d  props=%d  forest=%s  (%s)" % [sid, path, td["nv"], td["ntri"], (_poi_nodes[sid] as Array).size(), str(counts), error_string(e)])
	root.free()


const SHADOW_BUDGET_SCRIPT := "res://maps/beast_path/s04_shadow_budget.gd"
const ATMOSPHERE_SCRIPT := "res://maps/beast_path/bp_atmosphere.gd"


## V1.2 G：S04 的樹影只在「影子線段碰得到戰場」時才畫（依太陽仰角與方位；執行期腳本，原因與量測見腳本檔頭）
func _attach_shadow_budget(root: Node3D) -> void:
	var sb := Node.new()
	sb.name = "ShadowBudget"
	sb.set_script(load(SHADOW_BUDGET_SCRIPT))
	var sbd: Dictionary = lib.L["boss_arena"].get("shadow_budget", {})
	sb.set("margin", float(sbd.get("margin", 34.0)))
	sb.set("min_radius", float(sbd.get("min_r", 40.0)))
	sb.set("max_radius", float(sbd.get("max_r", 100.0)))
	sb.set("fallback_radius", float(sbd.get("fallback_r", 60.0)))
	sb.set("slope_k", float(sbd.get("slope_k", 1.3)))
	sb.set("center", lib.arena_c())
	root.add_child(sb)
	sb.owner = root


const MEADOW_SCN := "res://maps/beast_path/gen/s04_meadow.scn"


## V1.2 C：S04 草叢層（MultiMesh 要在非 headless 烘焙，見 bake_meadow_s04.gd）。檔案存在才掛；流程＝生成 → 烘焙 → 再生成一次。
func _attach_meadow(root: Node3D) -> void:
	if not ResourceLoader.exists(MEADOW_SCN):
		print("[meadow] 尚未烘焙（%s 不存在）→ S04 暫無草叢層" % MEADOW_SCN)
		return
	var inst := (load(MEADOW_SCN) as PackedScene).instantiate() as Node3D
	inst.name = "MeadowS04"
	root.add_child(inst)
	inst.owner = root
	print("[meadow] 掛上 MeadowS04：近級 %s 叢／中級 %s 叢" % [str(inst.get_meta("items", -1)), str(inst.get_meta("mid_items", -1))])


## S01 R4 Demo：Blender 環境資產層（bake_s01_dress.gd 非 headless 烘焙）。s01_dress.json 的 enabled＝false 或 .scn 不存在 → 不掛（S01＝R3 Stage 1）。
const S01_DRESS_SCN := "res://maps/beast_path/gen/s01_dress.scn"
const S01_DRESS_CFG := "res://tools/beast_path/s01_dress.json"


func _attach_s01_dress(root: Node3D) -> void:
	var cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(S01_DRESS_CFG)) if FileAccess.file_exists(S01_DRESS_CFG) else null
	if not (cfg is Dictionary) or not bool((cfg as Dictionary).get("enabled", false)):
		print("[dress] S01 環境資產層關閉（%s enabled≠true）" % S01_DRESS_CFG)
		return
	if not ResourceLoader.exists(S01_DRESS_SCN):
		print("[dress] 尚未烘焙（%s 不存在）→ S01 暫無環境資產層" % S01_DRESS_SCN)
		return
	var inst := (load(S01_DRESS_SCN) as PackedScene).instantiate() as Node3D
	inst.name = "S01Dress"
	root.add_child(inst)
	inst.owner = root
	print("[dress] 掛上 S01Dress：岩／木 %s 件（碰撞 %s）、地被 %s 叢" % [str(inst.get_meta("hard", -1)), str(inst.get_meta("collide", -1)), str(inst.get_meta("items", -1))])


## 全區美術完成：S02／S03 的 Blender 林床層（bake_zone_dress.gd 非 headless 烘焙）。tools/beast_path/<s0x>_dress.json 的 enabled＝false 或 .scn 不存在 → 不掛。
func _attach_zone_dress(root: Node3D, sid: String) -> void:
	var lo := sid.to_lower()
	var cfgp := "res://tools/beast_path/%s_dress.json" % lo
	var scn := "res://maps/beast_path/gen/%s_dress.scn" % lo
	var cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(cfgp)) if FileAccess.file_exists(cfgp) else null
	if not (cfg is Dictionary) or not bool((cfg as Dictionary).get("enabled", false)):
		print("[dress] %s 林床層關閉（%s enabled≠true）" % [sid, cfgp])
		return
	if not ResourceLoader.exists(scn):
		print("[dress] %s 尚未烘焙（%s 不存在）" % [sid, scn])
		return
	var inst := (load(scn) as PackedScene).instantiate() as Node3D
	inst.name = "%sDress" % sid
	root.add_child(inst)
	inst.owner = root
	print("[dress] 掛上 %sDress：岩／木 %s 件（碰撞 %s）、地被 %s 叢" % [sid, str(inst.get_meta("hard", -1)), str(inst.get_meta("collide", -1)), str(inst.get_meta("items", -1))])


func _build_claw_marks(parent: Node3D, sid: String) -> void:
	for cm: Dictionary in fp.claw_marks:
		var p: Vector3 = cm["p"]
		if lib.scene_id_of_z(p.z) != sid:
			continue
		var n: Vector3 = cm["n"]
		var holder := Node3D.new()
		holder.name = "Claw_%s" % String(cm["id"])
		holder.transform = Transform3D(Basis.looking_at(n, Vector3.UP), p + Vector3(0, 1.5, 0))     # 本地 −Z 朝外
		parent.add_child(holder)
		for k in 3:
			var m := MeshInstance3D.new()
			m.name = "Slash%d" % k
			var bm := BoxMesh.new()
			bm.size = Vector3(0.05, 0.62, 0.025)
			m.mesh = bm
			m.material_override = props.mat(Color(0.10, 0.07, 0.05), 0.95)
			m.position = Vector3(-0.14 + 0.14 * float(k), 0.0, 0.004)
			m.rotation_degrees = Vector3(0, 0, -18)
			holder.add_child(m)


func _marker(parent: Node3D, nm: String, pos: Vector3, yaw: float, role: String) -> Marker3D:
	var m := Marker3D.new()
	m.name = nm
	m.position = pos
	m.rotation.y = yaw
	m.set_meta("bp_role", role)
	parent.add_child(m)
	return m


func _build_markers(parent: Node3D, sid: String) -> void:
	if sid == "S01":
		for poi: Dictionary in lib.L["pois"]:
			if String(poi["kind"]) == "spawn":
				var a: Dictionary = poi["at"]
				_marker(parent, "Spawn_S01", Vector3(float(a["x"]), lib.h_at(float(a["x"]), float(a["z"])) + 0.1, float(a["z"])), deg_to_rad(float(poi.get("yaw_deg", 0.0))), "player_spawn")
		_marker(parent, "Portal_Village", Vector3(0, lib.h_at(0.0, 6.0), 6.0), 0.0, "portal_to_village_v2")
	if sid == "S04":
		var A: Dictionary = lib.L["boss_arena"]
		var c0 := lib.arena_c()
		var ps := lib.arena_pos(float(A["player_spawn"]["deg"]), float(A["player_spawn"]["r"]))
		_marker(parent, "PlayerSpawn_Arena", Vector3(ps.x, lib.h_at(ps.x, ps.y) + 0.1, ps.y), BPLib.yaw_of((c0 - ps).normalized()), "arena_player_spawn")
		var bs := lib.arena_pos(float(A["boss_spawn"]["deg"]), float(A["boss_spawn"]["r"]))
		_marker(parent, "BossSpawn", Vector3(bs.x, lib.h_at(bs.x, bs.y) + 0.1, bs.y), BPLib.yaw_of((ps - bs).normalized()), "boss_spawn")
		var tr := Area3D.new()
		tr.name = "BossTrigger"
		tr.position = Vector3(c0.x, lib.h_at(c0.x, c0.y) + 1.5, c0.y)
		tr.monitoring = true
		tr.set_meta("bp_role", "boss_trigger")
		var ts := CollisionShape3D.new()
		ts.name = "TriggerShape"
		var cyl := CylinderShape3D.new()
		cyl.radius = float(A["trigger_r"])
		cyl.height = 5.0
		ts.shape = cyl
		tr.add_child(ts)
		parent.add_child(tr)
		# 出口封印的擋塊（戰後解除＝T25；V0.1 常閉）
		if not _exit_seal.is_empty():
			var sp: Vector2 = _exit_seal["p"]
			var seal := StaticBody3D.new()
			seal.name = "ExitSealBlock"
			seal.position = Vector3(sp.x, lib.h_at(sp.x, sp.y) + 1.3, sp.y)
			seal.rotation.y = float(_exit_seal["yaw"])
			seal.set_meta("bp_role", "exit_seal")
			seal.set_meta("bp_unlock", "boss_defeated")
			var ss := CollisionShape3D.new()
			ss.name = "SealShape"
			var bx := BoxShape3D.new()
			bx.size = Vector3(5.2, 2.6, 0.5)
			ss.shape = bx
			seal.add_child(ss)
			parent.add_child(seal)
		# 保留出口（往博麗神社方向）
		var ex: Dictionary = lib.resolve({"br": "exit_shrine", "u": 1.0})
		var exp_: Vector2 = ex["p"]
		_marker(parent, "Exit_Shrine_Reserved", Vector3(exp_.x, lib.h_at(exp_.x, exp_.y) + 0.1, exp_.y), 0.0, "reserved_exit_shrine")
	if sid == "S03":
		var ex2: Dictionary = lib.resolve({"br": "bamboo", "u": 1.0})
		var ebp: Vector2 = ex2["p"]
		_marker(parent, "Exit_Bamboo_Reserved", Vector3(ebp.x, lib.h_at(ebp.x, ebp.y) + 0.1, ebp.y), 0.0, "reserved_exit_bamboo")


# ---------------------------------------------------------------- 根場景／meta／計畫
func _build_root() -> void:
	var root := Node3D.new()
	root.name = "BeastPath"
	root.set_meta("own_colliders", true)
	root.set_meta("bp_version", "0.1-whitebox")
	root.set_meta("bp_status", "WHITEBOX / ART_REVIEW（未 ART_APPROVED）")
	for sc: Dictionary in lib.L["scenes"]:
		var path := OUT_DIR + String(sc["file"])
		if not ResourceLoader.exists(path):
			continue
		var ps := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var inst := ps.instantiate()
		root.add_child(inst)
		inst.owner = root
	# V1.3：地圖大氣——只覆寫 main Environment 的 fog_sky_affect／fog_aerial_perspective（理由與量測見 bp_atmosphere.gd）
	var atm: Dictionary = lib.L.get("atmosphere", {})
	if not atm.is_empty() and bool(atm.get("enabled", true)):
		var we := WorldEnvironment.new()
		we.name = "BP_Atmosphere"
		we.set_script(load(ATMOSPHERE_SCRIPT))
		we.set("fog_sky_affect", float(atm.get("fog_sky_affect", 0.35)))
		we.set("fog_aerial_perspective", float(atm.get("fog_aerial_perspective", 0.0)))
		var bz: Array = atm.get("blend_z", [-340.0, -366.0])
		we.set("blend_z0", float(bz[0]))
		we.set("blend_z1", float(bz[1]))
		var dk: Array = atm.get("day_k", [0.40, 0.85])
		we.set("day_k0", float(dk[0]))
		we.set("day_k1", float(dk[1]))
		root.add_child(we)
		we.owner = root
	var pk := PackedScene.new()
	pk.pack(root)
	var e := ResourceSaver.save(pk, OUT_DIR + "beast_path.tscn")
	print("[root] beast_path.tscn  (%s)" % error_string(e))
	root.free()


func _write_meta() -> void:
	var gy_v := lib.h_at(0.0, 6.0)
	var portals: Array = [
		{"_note": "南：人間之里 V2（村莊端銜接，T26）。y＝該點地面高；抵達點由 main.gd 往世界原點方向內縮 4 m（原點在本圖南端，所以入口傳送點放在 z=+6 → 抵達 z=+2、在路上）。V2→獸道 的傳送目前由 village_v2.meta.json 停用（使用者裁定），本檔不動它。",
			"x": 0.0, "y": snappedf(gy_v, 0.01), "z": 6.0, "target": "village_v2", "arrival_ground_y": snappedf(gy_v, 0.01), "arrival_y_offset": 1.2, "arrival_yaw": 0.0},
	]
	var ex: Dictionary = lib.resolve({"br": "exit_shrine", "u": 1.0})
	var exp_: Vector2 = ex["p"]
	portals.append({"_note": "保留：往博麗神社方向（戰後出口，T26 先保留）", "x": snappedf(exp_.x, 0.01), "y": snappedf(lib.h_at(exp_.x, exp_.y), 0.01), "z": snappedf(exp_.y, 0.01), "target": ""})
	var eb: Dictionary = lib.resolve({"br": "bamboo", "u": 1.0})
	var ebp: Vector2 = eb["p"]
	portals.append({"_note": "保留：往迷途竹林方向（支線出口）", "x": snappedf(ebp.x, 0.01), "y": snappedf(lib.h_at(ebp.x, ebp.y), 0.01), "z": snappedf(ebp.y, 0.01), "target": ""})
	var meta := {
		"_note": "獸道 V0.1 白模（WHITEBOX / ART_REVIEW）。由 tools/beast_path/generate_beast_path.gd 產生，勿手改。",
		"id": "beast_path",
		"playSize": [220.0, 520.0],
		"safe": true,
		"mobTheme": "",
		"connections": ["village_v2"],
		"spawn": {"x": 0.0, "z": -12.0, "yaw": 0.0, "note": "S01 入口；y 由射線量地面"},
		"portals": portals,
		"colliders": [],
	}
	var f := FileAccess.open(META_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t") + "\n")
	f.close()
	print("[meta] ", META_PATH)


## S01 R1：森林規劃的輸入（道具腳印）。verify 用同樣的輸入、同樣的 seed 重算 S01 候選，證明它可重現。
func _write_forest_inputs() -> void:
	var feet: Array = []
	for f: Dictionary in props.footprints:
		var q: Vector2 = f["p"]
		feet.append({"id": String(f["id"]), "p": [q.x, q.y], "r": float(f["r"])})        # 不量化：verify 重算時看到的腳印要和規劃當時一模一樣
	var fo := FileAccess.open(GEN_DIR + "s01_forest_inputs.json", FileAccess.WRITE)
	if fo != null:
		fo.store_string(JSON.stringify({"footprints": feet}, "", false, true) + "\n")
		fo.close()
	print("[forest] S01 規劃輸入：道具腳印 %d 個" % feet.size())


func _write_plan() -> void:
	if no_forest:
		return
	var out: Array = []
	for t: Dictionary in fp.trees:
		var ent := {"id": t["id"], "x": snappedf(float(t["x"]), 0.01), "z": snappedf(float(t["z"]), 0.01), "y": snappedf(float(t["y"]), 0.01),
			"s": snappedf(float(t["s"]), 0.001), "yaw": snappedf(float(t["yaw"]), 0.001), "scene": t["scene"], "kind": t["kind"], "pin": t["pin"]}
		if t.has("lean"):
			var ln: Array = t["lean"]
			ent["lean"] = [snappedf(float(ln[0]), 0.001), snappedf(float(ln[1]), 0.001), snappedf(float(ln[2]), 0.0001)]
		out.append(ent)
	var f := FileAccess.open(GEN_DIR + "forest_plan.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"seed": lib.L["forest"]["seed"], "stats": fp.stats, "trees": out}, "\t") + "\n")
	f.close()
