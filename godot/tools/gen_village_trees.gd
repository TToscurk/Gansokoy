extends SceneTree
## 村緣樹群（B3 r5）。使用者提供的 Meshy 景觀資產，全部 OPAQUE 實體葉團，
## 沒有薄 alpha 卡——gl_compatibility 下不會碎成白點。
## 產出 res://maps/slice/gen/village_trees.tscn，於 slice.tscn 以單一節點實例。
##
## 規則：
##  - 每種樹烘成單一 ArrayMesh（底面 y=0、xz 置中）存成 gen/tree_*.res，
##    再以 MultiMesh 佈點；不逐棵 instance PackedScene（250 棵會是 2.8M 面）。
##  - 每個樹種一條獨立 RNG（per-layer RNG isolation），改動一種不會位移其他種。
##  - 每棵樹以射線取樣實際地形高度（需先載入 slice），不可寫死 y。
##  - 禁區：街廓本體、地標淨空、河道走廊，以及**鳥居往南的借景走廊**——
##    主街南望遠峰是已成立的構圖，種樹擋掉就毀了。

const OUT_SCENE := "res://maps/slice/gen/village_trees.tscn"
const SRC := "res://assets/landscape/"
## 手擺的櫻花樹群（可單獨選取的節點，非 MultiMesh）——不是本腳本產生的，
## 但掛在 VillageTrees 底下。重跑產生器時必須重新掛回去，否則整組會消失。
const SAKURA_SCENE := "res://maps/slice/gen/sakura_trees.tscn"

# 樹種：檔名、目標實高(m)、目標株數、最小間距(m)、隨機縮放範圍。
# r7 全面換成使用者提供的第二批 Tripo 景觀資產（D:\資產glb\景觀資產，12 件）。
# 前一批（r6，43k–48k 面／棵 + gltfpack 簡化版）整批備份在
#   assets/landscape/_tripo_r6_backup/   與  assets/_lod/_r6_tree_backup/
# 新批出廠就是 3.2k–4.9k 面／棵、單一材質、原點 BASE（min.y = 0.000），
# 不需要再跑 gltfpack —— 這裡與匯入前都不必再減面。
# ⚠ 新批全部 min.y = 0（BASE），舊的針葉樹2glb 是 CENTRE（min.y −0.5）。
#   _bake() 用 AABB 底邊對齊 y=0，兩種原點都吃得下，不必改。
# 針葉樹2glb 於 r6 曾被移出清單，r7 新批有對應模型但配額維持不變。
# 松樹.glb 在 r6 是橘紅楓（貼圖平均 H=17.1 / S=0.66），r7 已換成綠針葉樹
#（H=63.7 / S=0.58）。清單仍不收它——樹種數已夠，而且它與針葉林樹4 同一個
# 來源檔（新批 12 件對 13 個檔名，重複的那一個放在最不用到的位置）。
# 秋樹改由 楓樹.glb 提供，之後要做紅葉場景直接用那一件。
# 順序即優先權——共用間距集合會被先跑的樹種佔位，所以櫻花與雜木排最前面
# （概念圖裡櫻花就在村緣，排最後只搶得到 3 個位置）。
## 2026-09-10：移除 MachiCanal/Grove（B1_Street 與運河間誤植的 292 棵屏障林）
## 後，在人間之里既有的村緣外圍林上小幅提高株數（各 +25%）補回視覺量。
## 沿用既有規則（BLOCK/SIGHT/CANAL/EAST_RIVER_X 禁區 + 真實地面射線取樣），
## 不是另外發明佈點邏輯。
# ⚠ 2026-09-17 使用者裁定：櫻花樹／楓樹／普通樹／2大衫／針葉林樹4 底部有土台底座，
#   全面下架。原配額由底部乾淨的樹種承接（大衫、針葉樹1/2、針葉林樹3、鎮守之杜）。
#   下架清單勿再加回，否則重跑生成會讓髒底樹長回來。
const SPECIES: Array = [
	{"file": "鎮守之杜.glb",    "h": 8.0,  "n": 22, "gap": 12.0, "sv": 0.18, "seed": 4109},
	{"file": "針葉樹2glb.glb",  "h": 9.5,  "n": 55, "gap": 10.0, "sv": 0.22, "seed": 4108},
	{"file": "大衫.glb",        "h": 17.0, "n": 49, "gap": 15.0, "sv": 0.16, "seed": 4101},
	{"file": "大衫.glb",        "h": 19.5, "n": 33, "gap": 18.0, "sv": 0.14, "seed": 4102},
	{"file": "針葉樹1.glb",     "h": 12.5, "n": 44, "gap": 12.0, "sv": 0.18, "seed": 4103},
	{"file": "針葉林樹3.glb",   "h": 14.5, "n": 35, "gap": 13.0, "sv": 0.16, "seed": 4105},
	{"file": "針葉林樹3.glb",   "h": 15.5, "n": 20, "gap": 11.5, "sv": 0.16, "seed": 4106},
]
# 盆樹走另一條規則：只沿裏路地外緣點綴
const BONSAI := {"file": "盆樹.glb", "h": 2.6, "n": 22, "sv": 0.22, "seed": 4110}

# 佈點範圍
const X_MIN := 118.0
const X_MAX := 306.0
const Z_MIN := -226.0
const Z_MAX := 236.0

# 禁區
const BLOCK := Rect2(200.0, -72.0, 70.0, 184.0)        # 街廓本體（x,z,w,h）
const SIGHT := Rect2(213.0, 94.0, 44.0, 172.0)         # 鳥居往南的借景走廊
## 河道走廊。檔頭一直寫著「禁區：河道走廊」，但先前版本沒有實作——
## 結果 9 棵樹長在運河與石岸正上方，浮空 3.01 m（audit_village_tree_ground.gd 實測）。
## 範圍取自 slice 實測水面 AABB，左右各留 4 m 岸邊淨空：
##   運河 DownstreamWater/UpstreamWater/FeederWater  x 281..293
##   東側大河 EastRiverWater + 護岸 EastRiverRevetment  x 306.8 起
const CANAL := Rect2(277.0, -226.0, 20.0, 462.0)       # 運河（x 277..297）
const EAST_RIVER_X := 302.8                            # 此值以東是大河護岸，不種
const LANDMARKS: Array = [
	Vector3(233.2, -138.6, 52.0),   # 稗田邸
	Vector3(314.8, 34.6, 34.0),     # 寺子屋
	Vector3(225.2, -65.5, 30.0),    # 鈴奈庵
]

var _placed: Array = []   # 已放置點，跨樹種共用以維持間距
## 地面取樣用的物理世界（由 slice 場景提供）。null 時退回固定高度。
var _space: PhysicsDirectSpaceState3D = null
var _sunk: int = 0        # 取樣失敗、只能用固定高度的棵數
## 只打「地面」碰撞層用的 mask（理由見 _ground_y 註解）
const GROUND_MASK := 1 << 31


func _init() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


## 先把 slice 載進來，才有碰撞可以打射線。
## 舊版把每棵樹寫死在 y=-0.08，212 棵裡有 112 棵埋沒、9 棵浮空
## （audit_village_tree_ground.gd 實測），因為村緣地形根本不是平的。
func _run() -> void:
	var main: Node = null
	var main_scn: PackedScene = load("res://scenes/main.tscn")
	if main_scn != null:
		main = main_scn.instantiate()
		root.add_child(main)
		await _wait(3)
		main.load_map("slice", "trail")
		await _wait(90)
		_space = main.get_viewport().world_3d.direct_space_state
		print("GROUND 取樣就緒（slice 已載入）")
	else:
		push_warning("載不到 main.tscn，退回固定高度")

	var trees: Node3D = Node3D.new()
	trees.name = "VillageTrees"
	for sp in SPECIES:
		_build_species(trees, sp)
	# 盆樹沿裏路地外緣點綴——2026-09-10 使用者裁定移除（B1_Street 旁小河沿岸
	# 太密集，跟截圖形態不符村緣自然林感），改成不呼叫。若之後要恢復，呼叫
	# _build_bonsai(trees) 即可，函式本體保留不刪。
	# _build_bonsai(trees)
	_attach_sakura(trees)
	if _sunk > 0:
		print("GROUND %d 個候選點打不到地面，已跳過（未種樹）" % _sunk)
	var ps: PackedScene = PackedScene.new()
	var err: int = ps.pack(trees)
	if err != OK:
		push_error("pack failed: %d" % err)
	else:
		err = ResourceSaver.save(ps, OUT_SCENE)
		print("SAVE_RESULT %d" % err)
	quit()


## 對 (x,z) 由上而下打射線，回傳地面 y。取樣不到回傳 fallback。
## sink 是刻意讓樹根埋進土裡的量，避免根部與坡面之間出現縫。
##
## ⚠ 必須限定只打「地面」碰撞層，否則會撞到別的東西停住：
##   實測（diag_floating_tree_ray.gd）第一版沒設 mask，結果
##     大衫#7 / 普通樹#5  撞到 y=55 的「邊界牆_西／北」→ 種在半空的圍牆頂
##     盆樹#4 / #10       撞到「nagaya_西裏」長屋屋頂 → 種在屋頂上
##   地面群組（地面碰撞_刷筆用）layer = 2147483649 = bit1 | bit32，
##   建物碰撞與手動碰撞（含邊界牆）都是 layer = 1。
##   所以取 bit32（1 << 31）就只吃地面、濾掉建物與圍牆。
func _ground_y(x: float, z: float, fallback: float, sink: float) -> float:
	if _space == null:
		return fallback
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, 400.0, z), Vector3(x, -400.0, z), GROUND_MASK)
	var hit: Dictionary = _space.intersect_ray(q)
	if hit.is_empty():
		_sunk += 1
		return fallback
	return (hit.position as Vector3).y - sink


## 把 GLB 全部表面烘成一個 ArrayMesh：縮到目標高度、底面落 y=0、xz 置中。
func _bake(file: String, target_h: float) -> ArrayMesh:
	var scn: PackedScene = load(SRC + file)
	if scn == null:
		push_error("load failed: " + file)
		return null
	var inst: Node3D = scn.instantiate() as Node3D
	# 先量原始 AABB
	var bb: AABB = AABB()
	var has: bool = false
	var stack: Array = []
	for c in inst.get_children():
		stack.push_back([c, Transform3D.IDENTITY])
	var parts: Array = []
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var nd: Node = pair[0]
		var xf: Transform3D = pair[1]
		if nd is Node3D:
			xf = xf * (nd as Node3D).transform
		if nd is MeshInstance3D and (nd as MeshInstance3D).mesh != null:
			var mi: MeshInstance3D = nd
			parts.append([mi, xf])
			var a: AABB = xf * mi.mesh.get_aabb()
			if has:
				bb = bb.merge(a)
			else:
				bb = a
				has = true
		for c2 in nd.get_children():
			stack.push_back([c2, xf])
	if not has:
		push_error("no mesh in " + file)
		inst.free()
		return null

	var s: float = target_h / maxf(bb.size.y, 0.0001)
	var centre: Vector3 = bb.position + bb.size * 0.5
	var offset := Vector3(-centre.x * s, -bb.position.y * s, -centre.z * s)
	var to_world := Transform3D(Basis.IDENTITY, offset) \
		* Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)), Vector3.ZERO)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat: Material = null
	for p in parts:
		var mi2: MeshInstance3D = p[0]
		var xf2: Transform3D = to_world * (p[1] as Transform3D)
		for si in range(mi2.mesh.get_surface_count()):
			st.append_from(mi2.mesh, si, xf2)
			if mat == null:
				mat = mi2.mesh.surface_get_material(si)
				if mat == null:
					mat = mi2.get_active_material(si)
	var baked: ArrayMesh = st.commit()
	if mat != null:
		baked.surface_set_material(0, mat)
	var out_path: String = "res://maps/slice/gen/tree_%s.res" % file.get_basename()
	ResourceSaver.save(baked, out_path, ResourceSaver.FLAG_COMPRESS)
	inst.free()
	# 存完再 load 回來：這樣資源帶著 resource_path，打包時是 ExtResource 參照，
	# 網格不會被塞進 .tscn 文字（原本讓場景檔膨脹到 7.2 MB）。
	baked = load(out_path)
	print("BAKE %-12s h=%.1f tris=%d surfaces=%d" % [
		file, target_h, baked.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3,
		baked.get_surface_count()])
	return baked


## 佈點密度：離街廓愈遠愈稀，西／北側較密（概念圖的林緣在那一側）。
func _density(x: float, z: float) -> float:
	var dx: float = maxf(absf(x - 235.0) - 36.0, 0.0)
	var dz: float = maxf(absf(z - 20.0) - 92.0, 0.0)
	var d: float = sqrt(dx * dx + dz * dz)
	var near: float = 1.0 - smoothstep(6.0, 165.0, d)     # 靠街廓最密
	var west: float = 1.0 - smoothstep(150.0, 236.0, x)   # 西側林緣
	return clampf(maxf(near * 0.85, west * 0.55), 0.0, 1.0)


func _blocked(x: float, z: float) -> bool:
	if BLOCK.has_point(Vector2(x, z)):
		return true
	if SIGHT.has_point(Vector2(x, z)):
		return true
	if CANAL.has_point(Vector2(x, z)):
		return true
	if x >= EAST_RIVER_X:
		return true
	for lm in LANDMARKS:
		if Vector2(x - lm.x, z - lm.y).length() < lm.z:
			return true
	return false


func _too_close(x: float, z: float, gap: float) -> bool:
	for p in _placed:
		var pv: Vector2 = p[0]
		var need: float = maxf(gap, p[1])
		if Vector2(x - pv.x, z - pv.y).length() < need:
			return true
	return false


func _build_species(root: Node3D, sp: Dictionary) -> void:
	var mesh: ArrayMesh = _bake(sp["file"], sp["h"])
	if mesh == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = sp["seed"]
	var xforms: Array = []
	var tries: int = 0
	while xforms.size() < int(sp["n"]) and tries < 20000:
		tries += 1
		var x: float = rng.randf_range(X_MIN, X_MAX)
		var z: float = rng.randf_range(Z_MIN, Z_MAX)
		if _blocked(x, z):
			continue
		if rng.randf() > _density(x, z):
			continue
		if _too_close(x, z, sp["gap"]):
			continue
		# 先確認這點取得到地面，取不到就換一點——不要用 fallback 硬種，
		# 那正是舊版把樹塞在 y=-0.08、離地 55 m 的來源。
		var gy: float = _ground_y(x, z, NAN, 0.08)
		if is_nan(gy):
			continue
		_placed.append([Vector2(x, z), float(sp["gap"])])
		var sc: float = 1.0 + rng.randf_range(-float(sp["sv"]), float(sp["sv"]))
		var b := Basis.IDENTITY.rotated(Vector3.UP, rng.randf_range(0.0, TAU))
		b = b.scaled(Vector3(sc, sc, sc))
		xforms.append(Transform3D(b, Vector3(x, gy, z)))
	_emit(root, sp["file"].get_basename(), mesh, xforms)
	print("PLACE %-12s %d/%d (tries=%d)" % [sp["file"], xforms.size(), sp["n"], tries])


## 盆樹：只點綴在裏路地外緣，不進佈點主流程。
func _build_bonsai(root: Node3D) -> void:
	var mesh: ArrayMesh = _bake(BONSAI["file"], BONSAI["h"])
	if mesh == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = BONSAI["seed"]
	var xforms: Array = []
	var lanes: Array = [213.4, 256.6]   # 兩條裏路地的外緣
	for i in range(int(BONSAI["n"])):
		var lane: float = lanes[i % lanes.size()]
		var z: float = -46.0 + float(i) * 11.4 + rng.randf_range(-2.0, 2.0)
		if z > 78.0:
			continue
		var x: float = lane + rng.randf_range(-0.7, 0.7)
		var sc: float = 1.0 + rng.randf_range(-float(BONSAI["sv"]), float(BONSAI["sv"]))
		var b := Basis.IDENTITY.rotated(Vector3.UP, rng.randf_range(0.0, TAU))
		b = b.scaled(Vector3(sc, sc, sc))
		# 盆樹沿裏路地擺，之前撞到長屋屋頂被種到 y=4.1；取不到地面就跳過
		var gy: float = _ground_y(x, z, NAN, 0.05)
		if is_nan(gy):
			continue
		xforms.append(Transform3D(b, Vector3(x, gy, z)))
	_emit(root, "盆樹", mesh, xforms)
	print("PLACE 盆樹         %d" % xforms.size())


## 把手擺的櫻花樹群掛回 VillageTrees 底下。
## 這組是可單獨選取的 GLB 實例（使用者要求不用 MultiMesh），由
## gen_sakura_nodes.gd 產生、之後手動調過位置——本腳本只負責重新掛上，
## 絕不重算它的 transform。
func _attach_sakura(root: Node3D) -> void:
	if not ResourceLoader.exists(SAKURA_SCENE):
		print("PLACE 櫻花樹群       跳過（找不到 %s）" % SAKURA_SCENE)
		return
	var ps: PackedScene = load(SAKURA_SCENE)
	var inst: Node = ps.instantiate()
	inst.name = "櫻花樹群"
	root.add_child(inst)
	inst.owner = root
	# instantiate() 出來的子節點 owner 不是 root，直接 pack 會只存根節點。
	# 設 scene_file_path 讓它以「實例化子場景」的形式打包，子節點保持可選取。
	inst.scene_file_path = SAKURA_SCENE
	print("PLACE 櫻花樹群       %d 棵（手擺，實例參照）" % inst.get_child_count())


func _emit(root: Node3D, name_: String, mesh: ArrayMesh, xforms: Array) -> void:
	if xforms.is_empty():
		return
	# headless 跑的是 dummy renderer，set_instance_transform() 寫不進去
	# （回讀全是原點，242 棵樹整疊在 0,0,0）。直接組 buffer——
	# clear_street_vegetation.gd 早就是這樣讀寫的，stride 12 = 3x4 矩陣列優先。
	var buf := PackedFloat32Array()
	buf.resize(xforms.size() * 12)
	for i in range(xforms.size()):
		var t: Transform3D = xforms[i]
		var o: int = i * 12
		buf[o + 0] = t.basis.x.x; buf[o + 1] = t.basis.y.x
		buf[o + 2] = t.basis.z.x; buf[o + 3] = t.origin.x
		buf[o + 4] = t.basis.x.y; buf[o + 5] = t.basis.y.y
		buf[o + 6] = t.basis.z.y; buf[o + 7] = t.origin.y
		buf[o + 8] = t.basis.x.z; buf[o + 9] = t.basis.y.z
		buf[o + 10] = t.basis.z.z; buf[o + 11] = t.origin.z
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	mm.buffer = buf
	# MultiMesh 的 buffer 不會序列化進 .tscn 文字（本專案已知，veg_mm_*.res
	# 外置就是同一個原因）——第一版把 mm 直接掛上去，存出來只有
	# transform_format/instance_count/mesh，231 棵樹全部塌在原點。
	# 必須存成 .res 再 load 回來，讓它以外部資源被參照。
	var mm_path: String = "res://maps/slice/gen/treemm_%s.res" % name_
	ResourceSaver.save(mm, mm_path, ResourceSaver.FLAG_COMPRESS)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Trees_%s" % name_
	mmi.multimesh = load(mm_path)
	root.add_child(mmi)
	mmi.owner = root
