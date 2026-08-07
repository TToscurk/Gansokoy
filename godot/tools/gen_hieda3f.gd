# 稗田邸三樓 —— 大書庫（傳送場景）
#
#   godot --headless --path godot --script tools/gen_hieda3f.gd
#
# 全宅邸唯一的高規超現實樓層，三段式漸進的最終爆發點。
# 核心命題：千年份量的紀錄收藏在一個違反物理直覺的空間裡 ——
# 「內部大於外部」。
#
# 外殼（凍結，不可改）：三樓住在入母屋屋根的容許空間裡。
#   舉高 4.9m、棟絕對高 ≈12.75、二層頂 7.85 → 本場景地板 y=0、棟 y=4.90。
#   屋面斜率 tan = 4.90 / (11.96/2) = 0.8194（39.3°）——
#   **這是真實的幾何上限，不是無限高**。
#
# 「內部大於外部」靠視覺技術，不靠真的無限幾何：
#   1. 書架挑高貼著屋根的真實上限（中央排 3.55m，比一二樓的 2.3/2.0
#      明顯拔高一級）
#   2. 屋面內側近黑 + 光源集中在中低區 —— 書架頂**隱沒在黑暗裡**，
#      「看不見盡頭」取代「真的無限高」
#   3. 越往上微光書越密：「書越多、記錄越古老、光越密集但也越隱沒」
#
# 兩種光源同場但語言分開（規格明令）：
#   ・靈氣裂縫 = **琥珀白、碎片群隨機散落**（牆/書架縫/地面），全建築
#     最強的一級。不做同心圓 —— 那是室外（後院枯山水）的語言。
#   ・書本微光 = **冷白**，三段漸進的最高級。
#
# 技術路線（一二樓的教訓，全部照套）：
#   ・_verify_floor 射線實測，驗不過不存檔
#   ・屋面/天花全面碰撞 + **_verify_roof 頭頂覆蓋檢查**（二樓抓過
#     「牆頂可站立」——這層牆與書架更高，坑更大，直接做成驗證）
#   ・發光面一律 BLEND_MODE_ADD（alpha 混合在亮背景前會減光）
#   ・光先做暗 → 白天+夜景截圖驗證 → 再調
#   ・無對外開口（書庫密閉在屋根裡）—— 不需要假窗
extends SceneTree

const OUT_DIR := "res://maps/hieda3f/"
const MAP_ID := "hieda3f"
const SEED := 7300

# ── 屋根量體（內淨）──
const HW := 10.20              # 半寬（x）：妻壁在 ±10.2
const HD_FULL := 5.76          # 屋根落到 2F 外緣的半深
const KNEE_Z := 3.55           # 腰壁：|z| 到這裡截止（該處屋面高 1.99）
const RIDGE_H := 4.90          # 棟高（真實上限）
const PITCH := 0.8194          # 屋面斜率 tan（4.90 / 5.98）

var lib = preload("res://tools/gen_lib.gd").new()
var _root: Node3D
var _rng := RandomNumberGenerator.new()


func _roof_y(z: float) -> float:
	return RIDGE_H - absf(z) * PITCH


func _init() -> void:
	_rng.seed = SEED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "gen"))
	_root = Node3D.new()
	_root.name = "Hieda3F"
	_root.set_meta("own_colliders", true)
	lib.setup(_root, SEED)

	_build_floor()
	_build_shell()
	_build_stairwell()
	_build_shelves()
	_build_core()
	_build_cracks()
	_build_light()
	_build_env()

	var ok := await _verify_floor()
	var ok2 := await _verify_roof()
	if not (ok and ok2):
		push_error("hieda3f：實測不通過（地板 %s / 頭頂覆蓋 %s），不存檔" % [ok, ok2])
		quit(1)
		return

	var packed := PackedScene.new()
	packed.pack(_root)
	var err := ResourceSaver.save(packed, OUT_DIR + "%s.tscn" % MAP_ID)
	print("saved %s.tscn err=%d  節點 %d" % [MAP_ID, err, _count(_root)])
	_write_meta()
	quit()


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


func _collide(g: Node3D, size: Vector3, off := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	g.add_child(body)
	body.owner = _root
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	shape.shape = bx
	shape.position = off + Vector3(0, size.y * 0.5, 0)
	body.add_child(shape)
	shape.owner = _root


# ── 材質 ──
func _m_planks() -> StandardMaterial3D:
	return lib.pbr("3F床板", "planks", 0.55, Color(0.52, 0.46, 0.38))
func _m_dark() -> StandardMaterial3D:
	return lib.pbr("3F木部", "dark_wood", 0.45, Color(0.28, 0.27, 0.25))
func _m_roof_in() -> StandardMaterial3D:
	# 屋面內側：近黑。「看不見盡頭」的一半靠它吃光
	return lib.pbr("3F屋裏", "planks", 1.4, Color(0.135, 0.125, 0.115))
func _m_wall() -> StandardMaterial3D:
	# 妻壁/腰壁：比一二樓暗兩階、偏冷 —— 森然、微涼
	return lib.pbr("3F壁", "plaster", 2.4, Color(0.52, 0.50, 0.47))
func _m_shelf() -> StandardMaterial3D:
	return lib.pbr("3F架材", "planks", 0.8, Color(0.42, 0.37, 0.30))
func _m_book(i: int) -> StandardMaterial3D:
	var tones := [Color(0.34, 0.31, 0.27), Color(0.28, 0.30, 0.34), Color(0.38, 0.33, 0.24)]
	return lib.pbr("3F書列_%d" % (i % 3), "tatami", 2.6, tones[i % 3])
func _m_glow_book() -> StandardMaterial3D:
	# 書本微光：冷白，三段漸進的最高級（1F 0.11 → 2F 0.21 → 3F 起點 0.34，
	# 照流程先估後驗）
	return lib.flat_mat("3F書微光", Color(0.72, 0.77, 0.86), 0.6,
		Color(0.26, 0.32, 0.42))
func _m_crack() -> StandardMaterial3D:
	# 裂縫碎片：琥珀白，全建築最強 —— 亮度明顯、可見度高
	# 第一輪驗證：0.62 的琥珀在近黑環境裡只剩幾條細線 —— 加到「自體
	# 照亮周圍一小圈」的等級（這層的裂縫是全建築最強）
	return lib.flat_mat("3F裂縫", Color(1.0, 0.90, 0.68), 0.5,
		Color(1.55, 1.00, 0.42))


# ── 地板 ──
func _build_floor() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, -HW, HW, -KNEE_Z, KNEE_Z, 0.0)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, _m_planks())
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	lib.add(_root, mi, "Terrain")


func _quad(st: SurfaceTool, x0: float, x1: float, z0: float, z1: float, y: float) -> void:
	# 繞向 = 一樓探針驗證過的朝向（trimesh 預設不碰背面）
	var a := Vector3(x0, y, z0)
	var b := Vector3(x1, y, z0)
	var c := Vector3(x1, y, z1)
	var d := Vector3(x0, y, z1)
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)


# ── 殼：腰壁・妻壁・屋面內側・繫梁 ──
func _build_shell() -> void:
	var g := lib.add(_root, Node3D.new(), "殼")
	var wall := _m_wall()
	var dark := _m_dark()
	var knee_h := _roof_y(KNEE_Z)
	# 腰壁（±z）
	for sz in [-1.0, 1.0]:
		lib.box(g, "腰壁_%d" % int(sz + 1.0), Vector3(HW * 2.0, knee_h, 0.12), wall,
			Vector3(0, knee_h * 0.5, sz * (KNEE_Z + 0.07)))
		_collide(g, Vector3(HW * 2.0, knee_h + 0.1, 0.3), Vector3(0, 0, sz * (KNEE_Z + 0.15)))
	# 妻壁（±x）：從地板到屋面的山形牆
	for sx in [-1.0, 1.0]:
		lib.box(g, "妻壁下_%d" % int(sx + 1.0), Vector3(0.12, knee_h, KNEE_Z * 2.0), wall,
			Vector3(sx * (HW + 0.07), knee_h * 0.5, 0))
		# 山形上段：兩片斜切的近似（跟屋面收齊）
		var seg := 4
		for k in seg:
			var z0 := KNEE_Z * float(k) / float(seg)
			var z1 := KNEE_Z * float(k + 1) / float(seg)
			var h0 := _roof_y(z0)
			var hh := (h0 + _roof_y(z1)) * 0.5 - knee_h
			if hh <= 0.0:
				continue
			for szg in [-1.0, 1.0]:
				lib.box(g, "妻壁上_%d_%d_%d" % [int(sx + 1.0), k, int(szg + 1.0)],
					Vector3(0.12, hh, z1 - z0), wall,
					Vector3(sx * (HW + 0.07), knee_h + hh * 0.5, szg * (z0 + z1) * 0.5))
		_collide(g, Vector3(0.3, RIDGE_H, KNEE_Z * 2.0), Vector3(sx * (HW + 0.15), 0, 0))
	# 屋面內側：兩片斜板（近黑）＋ 棟木
	var slope_len := sqrt(pow(KNEE_Z + 0.4, 2.0) + pow(RIDGE_H - knee_h + 0.33, 2.0))
	for sz in [-1.0, 1.0]:
		var pl := lib.box(g, "屋裏_%d" % int(sz + 1.0),
			Vector3(HW * 2.0 + 0.3, 0.10, slope_len), _m_roof_in(), Vector3.ZERO)
		pl.position = Vector3(0, (RIDGE_H + knee_h) * 0.5 + 0.16, sz * (KNEE_Z + 0.4) * 0.5)
		pl.rotation.x = sz * atan(PITCH)
		# 屋面碰撞：跟著斜板走 —— 頭頂覆蓋的主體
		var body := StaticBody3D.new()
		g.add_child(body)
		body.owner = _root
		var shp := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(HW * 2.0 + 0.3, 0.3, slope_len + 0.5)
		shp.shape = bx
		shp.position = pl.position + Vector3(0, 0.1, 0)
		shp.rotation.x = pl.rotation.x
		body.add_child(shp)
		shp.owner = _root
	lib.box(g, "棟木", Vector3(HW * 2.0 + 0.3, 0.24, 0.30), dark, Vector3(0, RIDGE_H - 0.02, 0))
	# 繫梁（低位横材）＋束柱：閣樓的骨架，也是光與暗的分界線
	for bx2 in [-6.6, -2.2, 2.2, 6.6]:
		lib.box(g, "繫梁_%d" % int(bx2 * 10.0), Vector3(0.24, 0.28, KNEE_Z * 2.0 + 0.2), dark,
			Vector3(bx2, 2.72, 0))
		lib.box(g, "束柱_%d" % int(bx2 * 10.0), Vector3(0.18, RIDGE_H - 2.86 - 0.14, 0.18), dark,
			Vector3(bx2, (2.86 + RIDGE_H - 0.14) * 0.5, 0))


# ── 階段口（西端；來自二樓）──
func _build_stairwell() -> void:
	var g := lib.add(_root, Node3D.new(), "階段口")
	g.position = Vector3(-8.9, 0, -1.6)
	var dark := _m_dark()
	var wellm := StandardMaterial3D.new()
	wellm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wellm.albedo_color = Color(0.04, 0.036, 0.032)
	lib.box(g, "暗井", Vector3(2.0, 0.02, 1.1), wellm, Vector3(0, 0.035, 0))
	lib.box(g, "口框N", Vector3(2.2, 0.10, 0.08), dark, Vector3(0, 0.05, 0.60))
	lib.box(g, "口框S", Vector3(2.2, 0.10, 0.08), dark, Vector3(0, 0.05, -0.60))
	lib.box(g, "口框E", Vector3(0.08, 0.10, 1.15), dark, Vector3(1.08, 0.05, 0))
	for s in [[0.0, 0.62, 2.2, true], [1.10, 0.0, 1.2, false]]:
		var alx: bool = bool(s[3])
		var ln: float = float(s[2])
		lib.box(g, "欄_%d_%d" % [int(float(s[0]) * 10.0), int(float(s[1]) * 10.0)],
			Vector3(ln if alx else 0.06, 0.07, 0.06 if alx else ln), dark,
			Vector3(float(s[0]), 0.78, float(s[1])))
		var n := int(ln / 0.35)
		for k in n:
			var t := -ln * 0.5 + (float(k) + 0.5) * ln / float(n)
			lib.box(g, "欄束_%d_%d" % [int(float(s[0]) * 10.0), k],
				Vector3(0.05, 0.72, 0.05), dark,
				Vector3(float(s[0]) + (t if alx else 0.0), 0.39,
					float(s[1]) + (0.0 if alx else t)))
	_collide(g, Vector3(2.3, 0.9, 0.15), Vector3(0, 0, 0.62))
	_collide(g, Vector3(0.15, 0.9, 1.25), Vector3(1.10, 0, 0))


# ── 書架：這層真正的主體 ──
# 中央兩排（3.55m，貼屋根上限）夾出中軸廊；腰壁矮架（1.85m）貼兩側；
# 西妻壁高架（核心典籍在東端，東妻壁讓位）。
# 微光書密度往上遞增：t/頂層 ~45%，最下層 ~6%。
func _build_shelves() -> void:
	var g := lib.add(_root, Node3D.new(), "書架")
	var shelf := _m_shelf()
	# 共用書列 mesh：3 長度 × 3 色調 + 2 微光 = 11 顆
	var protos: Array[Mesh] = []
	for li in 3:
		var ln: float = [3.6, 2.9, 2.2][li]
		for mi2 in 3:
			var bm := BoxMesh.new()
			bm.size = Vector3(ln, 0.30, 0.24)
			bm.material = _m_book(mi2)
			protos.append(bm)
	var glow_protos: Array[Mesh] = []
	for gi in 2:
		var gm := BoxMesh.new()
		gm.size = Vector3([0.055, 0.075][gi], 0.30, 0.20)
		gm.material = _m_glow_book()
		glow_protos.append(gm)

	var n_books := 0
	var n_glow := 0
	# [中心z, 架高, 排長半, 名]
	# ⚠ 中央排 ±1.35 + 0.5 深的碰撞箱會把 |z|=2 的 walk_test 格點壓住
	# **5cm** —— 側走道實際淨寬 1.43m 走得過，但 CELL=2 的格點看不見
	# （一樓屏風縫的同款假陰性）。收到 ±1.30、碰撞 0.44 深，格點落得下，
	# 側走道才是被驗證過的，不是被吸附到中軸廊上假通過。
	var rows := [
		[-1.30, 3.55, 7.9, "中央南"], [1.30, 3.55, 7.9, "中央北"],
		[-3.28, 1.85, 8.6, "腰南"], [3.28, 1.85, 8.6, "腰北"],
	]
	for row in rows:
		var rz: float = row[0]
		var rh: float = row[1]
		var hl: float = row[2]
		var rg := lib.add(g, Node3D.new(), "架_%s" % String(row[3]))
		rg.position = Vector3(0, 0, rz)
		# 架體：側板 + 層板
		var tiers := int((rh - 0.10) / 0.44)
		for sx in [-1.0, 1.0]:
			lib.box(rg, "側板_%d" % int(sx + 1.0), Vector3(0.05, rh, 0.42), shelf,
				Vector3(sx * hl, rh * 0.5, 0))
		var nx := int(hl / 1.9)
		for k in nx * 2 - 1:
			lib.box(rg, "隔板_%d" % k, Vector3(0.04, rh, 0.40), shelf,
				Vector3(-hl + float(k + 1) * hl / float(nx), rh * 0.5, 0))
		for t in tiers + 1:
			lib.box(rg, "層板_%d" % t, Vector3(hl * 2.0, 0.045, 0.44), shelf,
				Vector3(0, 0.10 + float(t) * 0.44, 0))
		# 書列：每層兩面（腰架只朝內一面）
		var faces: Array[float] = []
		if rh > 2.0:
			faces.append(-1.0)
			faces.append(1.0)
		elif rz < 0.0:
			faces.append(1.0)
		else:
			faces.append(-1.0)
		for t in tiers:
			var ty := 0.10 + float(t) * 0.44 + 0.045 + 0.15
			var frac := float(t) / float(maxi(tiers - 1, 1))
			for fz in faces:
				var x := -hl + 0.25
				while x < hl - 0.35:
					var pi := _rng.randi() % protos.size()
					var bm2: BoxMesh = protos[pi]
					var ln2: float = bm2.size.x
					if x + ln2 > hl - 0.1:
						break
					var b := MeshInstance3D.new()
					b.mesh = bm2
					b.position = Vector3(x + ln2 * 0.5, ty, fz * 0.10)
					lib.add(rg, b, "列_%d" % n_books)
					n_books += 1
					# 微光書插在書列前緣：密度往上遞增（頂層才是最密的）
					var want := int(ln2 * (0.35 + frac * 2.6) * 0.5)
					for kk in want:
						var gb := MeshInstance3D.new()
						gb.mesh = glow_protos[_rng.randi() % 2]
						gb.position = Vector3(x + _rng.randf_range(0.1, ln2 - 0.1),
							ty, fz * 0.145)
						lib.add(rg, gb, "微_%d" % n_glow)
						n_glow += 1
					x += ln2 + _rng.randf_range(0.06, 0.30)
		_collide(rg, Vector3(hl * 2.0 + 0.1, rh, 0.44))
	# 西妻壁高架：貼牆一排，頂跟著屋面斜下去（4.3 → 2.2 的階梯輪廓）
	var wg := lib.add(g, Node3D.new(), "架_西妻")
	wg.position = Vector3(-9.85, 0, 0)
	var segs := [[0.0, 4.35], [1.35, 3.30], [2.45, 2.10]]
	for si in segs.size():
		var sz0: float = segs[si][0]
		var sh: float = segs[si][1]
		for szg in ([-1.0, 1.0] if si > 0 else [1.0]):
			var cz: float = szg * (sz0 + 0.55) if si > 0 else 0.0
			var sw: float = 1.1 if si > 0 else 2.6
			var col := lib.add(wg, Node3D.new(), "段_%d_%d" % [si, int(szg + 1.0)])
			col.position = Vector3(0, 0, cz)
			var tiers2 := int((sh - 0.1) / 0.44)
			for t2 in tiers2 + 1:
				lib.box(col, "板_%d" % t2, Vector3(0.40, 0.045, sw), _m_shelf(),
					Vector3(0, 0.10 + float(t2) * 0.44, 0))
			for t2 in tiers2:
				var ty2 := 0.10 + float(t2) * 0.44 + 0.045 + 0.15
				var frac2 := float(t2) / float(maxi(tiers2 - 1, 1))
				var b2 := MeshInstance3D.new()
				var bm3 := BoxMesh.new()
				bm3.size = Vector3(0.24, 0.30, sw - 0.14)
				bm3.material = _m_book(t2)
				b2.mesh = bm3
				b2.position = Vector3(0.09, ty2, 0)
				lib.add(col, b2, "列w_%d" % n_books)
				n_books += 1
				var want2 := 1 + int(frac2 * 3.0)
				for kk2 in want2:
					var gb2 := MeshInstance3D.new()
					gb2.mesh = glow_protos[_rng.randi() % 2]
					gb2.position = Vector3(0.19, ty2, _rng.randf_range(-sw * 0.35, sw * 0.35))
					gb2.rotation.y = PI * 0.5
					lib.add(col, gb2, "微w_%d" % n_glow)
					n_glow += 1
			if si == 0:
				break
	_collide(g, Vector3(0.6, 4.4, KNEE_Z * 2.0), Vector3(-9.85, 0, 0))
	print("書架：書列 %d 段、微光書 %d 冊（密度往上遞增）" % [n_books, n_glow])


# ── 核心錨點：東端的書見台 + 特別發光的古典籍（敘事錨，不是起居擺設）──
func _build_core() -> void:
	var g := lib.add(_root, Node3D.new(), "核心典籍")
	g.position = Vector3(8.4, 0, 0)
	var dark := _m_dark()
	lib.cyl(g, "台座", 0.85, 1.0, 0.22, lib.pbr("3F台石", "stone_wall", 0.6,
		Color(0.34, 0.34, 0.35)), Vector3(0, 0.11, 0), 12)
	lib.box(g, "書見台脚", Vector3(0.30, 0.85, 0.30), dark, Vector3(0, 0.62, 0))
	var top := lib.box(g, "書見台面", Vector3(1.05, 0.06, 0.75), dark, Vector3(0, 1.08, 0))
	top.rotation.x = -0.20
	# 典籍：攤開的巨冊 —— 這層最亮的冷白。頁緣浮著幾片散頁（高規超現實：
	# 這層才准浮）
	var book := lib.add(g, Node3D.new(), "典籍")
	book.position = Vector3(0, 1.14, -0.02)
	book.rotation.x = -0.20
	var pg := lib.flat_mat("3F典籍頁", Color(0.80, 0.85, 0.94), 0.5,
		Color(0.46, 0.56, 0.72))
	lib.box(book, "左頁", Vector3(0.44, 0.035, 0.62), pg, Vector3(-0.23, 0, 0))
	lib.box(book, "右頁", Vector3(0.44, 0.035, 0.62), pg, Vector3(0.23, 0, 0))
	lib.box(book, "書背", Vector3(0.06, 0.05, 0.62), dark, Vector3(0, -0.01, 0))
	for k in 4:
		var fp := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.26, 0.008, 0.36)
		fm.material = pg
		fp.mesh = fm
		fp.position = Vector3(_rng.randf_range(-0.5, 0.5),
			0.55 + float(k) * 0.42 + _rng.randf_range(-0.1, 0.1),
			_rng.randf_range(-0.35, 0.3))
		fp.rotation = Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(0.0, TAU),
			_rng.randf_range(-0.3, 0.3))
		lib.add(g, fp, "散頁_%d" % k)
	# 典籍的冷白光暈（ADD —— 只提亮）
	var halo := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	# 遠看不能變成一塊實心板：alpha 壓低、上寬下窄的錐度讓側影是梯形
	hm.top_radius = 1.05
	hm.bottom_radius = 0.38
	hm.height = 2.6
	hm.radial_segments = 12
	var hmat := StandardMaterial3D.new()
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.albedo_color = Color(0.55, 0.65, 0.85, 0.028)
	hmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	hm.material = hmat
	halo.mesh = hm
	halo.position = Vector3(0, 1.9, 0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lib.add(g, halo, "光暈")
	var li := OmniLight3D.new()
	li.position = Vector3(0, 1.7, 0)
	li.light_color = Color(0.72, 0.80, 0.95)
	li.light_energy = 1.65
	li.omni_range = 5.6
	li.shadow_enabled = false
	lib.add(g, li, "典籍光")
	_collide(g, Vector3(1.6, 1.35, 1.2))


# ── 靈氣裂縫：琥珀白碎片群，隨機散落（地面/牆面/書架縫）──
# 全建築最強的一級。不做同心圓 —— 那是室外的語言。
func _build_cracks() -> void:
	var g := lib.add(_root, Node3D.new(), "裂縫")
	var cm := _m_crack()
	var n := 0
	# 地面碎片：兩三個鬆散群 + 零星（隨機，不規則）
	var clusters := [Vector2(3.5, 0.4), Vector2(-4.2, -2.2), Vector2(6.8, 2.2)]
	for c in clusters:
		var cn := 5 + _rng.randi() % 4
		for k in cn:
			var p: Vector2 = c + Vector2(_rng.randf_range(-1.4, 1.4), _rng.randf_range(-1.0, 1.0))
			if absf(p.x) > HW - 0.5 or absf(p.y) > KNEE_Z - 0.4:
				continue
			_shard(g, Vector3(p.x, 0.015, p.y), false, n)
			n += 1
	for k in 8:
		var p2 := Vector2(_rng.randf_range(-HW + 1.0, HW - 1.0),
			_rng.randf_range(-KNEE_Z + 0.5, KNEE_Z - 0.5))
		_shard(g, Vector3(p2.x, 0.015, p2.y), false, n)
		n += 1
	# 牆面碎片（腰壁與妻壁上）
	for k in 6:
		var side := _rng.randi() % 3
		var pos: Vector3
		var vert := true
		if side == 0:
			pos = Vector3(_rng.randf_range(-8.0, 8.0), _rng.randf_range(0.4, 1.7), -KNEE_Z + 0.02)
		elif side == 1:
			pos = Vector3(_rng.randf_range(-8.0, 8.0), _rng.randf_range(0.4, 1.7), KNEE_Z - 0.02)
		else:
			pos = Vector3(HW - 0.02, _rng.randf_range(0.5, 2.6), _rng.randf_range(-2.0, 2.0))
		_shard(g, pos, vert, n)
		n += 1
	# 書架縫（中央排端面與層板間）
	for k in 5:
		var rz := -1.35 if k % 2 == 0 else 1.35
		_shard(g, Vector3(_rng.randf_range(-7.0, 7.0),
			_rng.randf_range(0.6, 3.2), rz + (0.32 if rz < 0 else -0.32)), true, n)
		n += 1
	# 琥珀點光：碎片群的光池（第二輪驗證把 ADD 貼地圓盤拿掉了 ——
	# 平面等 alpha 的圓盤有一圈 20 邊形的硬邊，而 omni 的衰減本來就是柔的；
	# 「碎片自體發光 + 燈打出光池」就夠，不要疊一層假的）
	for k in 3:
		var cl: Vector2 = clusters[k]
		var li := OmniLight3D.new()
		li.position = Vector3(cl.x, 0.5, cl.y)
		li.light_color = Color(1.0, 0.68, 0.32)
		li.light_energy = 1.4
		li.omni_range = 4.2
		li.shadow_enabled = false
		lib.add(g, li, "裂光_%d" % k)
	print("裂縫碎片：%d 片（隨機散落，無規則排列）" % n)


func _shard(g: Node3D, pos: Vector3, vertical: bool, i: int) -> void:
	var s := MeshInstance3D.new()
	var m := BoxMesh.new()
	var ln := _rng.randf_range(0.22, 0.85)
	var wd := _rng.randf_range(0.08, 0.22)
	m.size = Vector3(ln, 0.035, wd) if not vertical else Vector3(ln, wd, 0.035)
	m.material = _m_crack()
	s.mesh = m
	s.position = pos + (Vector3(0, 0.02, 0) if not vertical else Vector3.ZERO)
	if vertical:
		s.rotation.z = _rng.randf_range(-0.6, 0.6)
	else:
		s.rotation.y = _rng.randf_range(0.0, TAU)
	lib.add(g, s, "碎片_%d" % i)


# ── 光：集中在中低區。頂部刻意昏暗 —— 「上方深不可測」──
func _build_light() -> void:
	var g := lib.add(_root, Node3D.new(), "光")
	var dark := _m_dark()
	# 吊灯籠三盞：低垂在中軸廊上（光池只鋪在走道）
	for i in 3:
		var lx: float = [-5.4, 0.0, 5.4][i]
		var an := lib.add(g, Node3D.new(), "吊灯_%d" % i)
		an.position = Vector3(lx, 0, 0)
		lib.cyl(an, "鎖", 0.012, 0.012, RIDGE_H - 2.55, dark,
			Vector3(0, (RIDGE_H + 2.4) * 0.5 - 0.07, 0), 4)
		var shade := lib.flat_mat("3F灯紙", Color(1.0, 0.90, 0.72), 0.8,
			Color(0.50, 0.36, 0.18))
		lib.cyl(an, "灯袋", 0.17, 0.20, 0.42, shade, Vector3(0, 2.30, 0), 8)
		lib.cyl(an, "灯蓋", 0.24, 0.22, 0.04, dark, Vector3(0, 2.54, 0), 8)
		var li := OmniLight3D.new()
		li.position = Vector3(0, 2.1, 0)
		li.light_color = Color(1.0, 0.84, 0.58)
		li.light_energy = 1.35
		li.omni_range = 5.4
		li.shadow_enabled = false
		an.add_child(li)
		li.owner = _root


# ── 氛圍：森然、浩瀚、微涼 —— 環境光偏冷、壓低，暗部要真的暗 ──
func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.020, 0.020, 0.024)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.86)
	env.ambient_light_energy = 0.46
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.tonemap_white = 4.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.10
	env.adjustment_saturation = 1.02
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	lib.add(_root, we, "WorldEnvironment")


# ── 驗證：地板射線 + 頭頂覆蓋（標準流程）──
func _verify_floor() -> bool:
	get_root().add_child(_root)
	var terr := _root.get_node("Terrain") as MeshInstance3D
	terr.create_trimesh_collision()
	await physics_frame
	await physics_frame
	var sps := _root.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.new()
	var n_hit := 0
	var n_all := 0
	var xi := -HW + 0.8
	while xi < HW:
		var zi := -KNEE_Z + 0.6
		while zi < KNEE_Z:
			n_all += 1
			ray.from = Vector3(xi, 20.0, zi)
			ray.to = Vector3(xi, -10.0, zi)
			if not sps.intersect_ray(ray).is_empty():
				n_hit += 1
			zi += 1.2
		xi += 1.4
	print("地板射線實測：%d/%d 中（門檻 95%%）" % [n_hit, n_all])
	return float(n_hit) / float(n_all) >= 0.95


## 頭頂覆蓋：從每個室內取樣點往上打，一定要在 6m 內打到東西 ——
## 屋面/腰壁碰撞的破洞在這裡抓（二樓「牆頂可站立」的坑，這層做成驗證）。
## 跑完把 Terrain 的臨時 trimesh 拆掉再存檔。
func _verify_roof() -> bool:
	var sps := _root.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.new()
	var n_miss := 0
	var n_all := 0
	var xi := -HW + 0.8
	while xi < HW:
		var zi := -KNEE_Z + 0.6
		while zi < KNEE_Z:
			n_all += 1
			ray.from = Vector3(xi, 0.4, zi)
			ray.to = Vector3(xi, 6.5, zi)
			if sps.intersect_ray(ray).is_empty():
				n_miss += 1
			zi += 1.2
		xi += 1.4
	var terr := _root.get_node("Terrain") as MeshInstance3D
	var doomed: Array[Node] = []
	for c in terr.get_children():
		if String(c.name).contains("_col"):
			doomed.append(c)
	for c in doomed:
		terr.remove_child(c)
		c.free()
	get_root().remove_child(_root)
	print("頭頂覆蓋實測：%d/%d 有遮蔽（漏 %d）" % [n_all - n_miss, n_all, n_miss])
	return n_miss == 0


func _write_meta() -> void:
	var meta := {
		"id": MAP_ID,
		"note": "稗田邸三樓（大書庫）—— 傳送場景。住在入母屋屋根量體裡"
			+ "（舉高 4.90、屋面斜率 0.8194、腰壁切在 |z|=3.55）。"
			+ "『內部大於外部』靠視覺技術：書架貼真實上限 3.55m、頂部無光隱沒。"
			+ "階段口 portal target 待二樓串接時填上。不進 mapRegistry。",
		"playSize": [21, 8],
		"safe": true,
		"connections": [],
		"portals": [
			{"x": -8.9, "y": 0.0, "z": -0.5, "target": null},
		],
		"colliders": [],
	}
	var f := FileAccess.open("res://data/%s.meta.json" % MAP_ID, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, " "))
	f.close()
	print("wrote data/%s.meta.json" % MAP_ID)
