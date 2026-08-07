# 稗田邸二樓 —— 阿求書房（傳送場景）
#
#   godot --headless --path godot --script tools/gen_hieda2f.gd
#
# 核心命題（2026-08-07 修正版）：一位外表看起來是**普通少女**的存在，
# 日常生活痕跡跟**不合常理堆積如山**的千年書寫工具/記錄並置。
# 反差靠「數量與時間感」撐起 —— 家具一律正常少女/成人比例，不做矮化。
#
# 中等超現實（比一樓明顯、比三樓克制）：
#   1. 書寫工具堆疊誇張化：整面牆的卷軸收納格（數百卷）+ 地上的書塔
#   2. 光束更飽和：不是自然日光的黃，是偏超現實的暖橙金
#   3. 輕微空間比例失準：東北角「說不出哪裡不對」的四個微效果（見 _warp 註解）
#   4. 書本微光：延續一樓的冷白，但正常光照下就該注意到（亮度先估一階、
#      渲染驗證後才定案 —— 一樓的教訓：先做暗、再驗證、再調）
#
# 外殼（已凍結的外觀量體）：
#   二層 21.88 × 11.96、淨高 3.10（絕對高 4.75 → 7.85）
#   窗帶 絕對高 5.97 → 7.03 = 本場景地板上 **1.22 → 2.28**，朝後院（-z）
#   （一層朝前庭 +z、二三層朝後院 —— 外觀 Blender +y 面 = Godot -z）
#
# 技術路線（一樓驗證過的教訓直接成為標準流程）：
#   ・地板 mesh 生成後**在產生器裡就射線實測**（_verify_floor）——
#     一樓踩過「三角形繞向朝下、渲染正常但 135 條射線只中 5 條」的坑。
#     驗不過就不存檔，直接 quit(1)。
#   ・發光元素一律先做暗 → 截圖驗證 → 再調。
#   ・假窗：障子外側是後院的池/枯山水縮小版，只對角度。
extends SceneTree

const OUT_DIR := "res://maps/hieda2f/"
const MAP_ID := "hieda2f"
const SEED := 7200

# ── 外殼（內淨尺寸）──
const HW := 10.72              # 半寬：外殼 21.88 - 牆厚
const HD := 5.76               # 半深：外殼 11.96 - 牆厚
const CEIL_H := 3.10           # 淨高（依外殼實測，不打破）
const GBAND_LO := 1.22         # 窗帶（外觀 5.97→7.03 − 二層地板 4.75）
const GBAND_HI := 2.28
const NAGESHI := 2.28

var lib = preload("res://tools/gen_lib.gd").new()
var _root: Node3D
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = SEED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "gen"))
	_root = Node3D.new()
	_root.name = "Hieda2F"
	_root.set_meta("own_colliders", true)
	lib.setup(_root, SEED)

	_build_floor()
	_build_walls()
	_build_ceiling()
	_build_stairwell()
	_build_scroll_wall()
	_build_desk()
	_build_daily_life()
	_build_piles()
	_build_light()
	_build_garden_backdrop()
	_build_env()

	# ── 地板射線實測（標準流程；驗不過不存檔）──
	var ok := await _verify_floor()
	if not ok:
		push_error("hieda2f：地板射線實測不通過，不存檔")
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
	return lib.pbr("2F床板", "planks", 0.55, Color(0.52, 0.45, 0.36))
func _m_dark() -> StandardMaterial3D:
	return lib.pbr("2F木部", "dark_wood", 0.45, Color(0.34, 0.33, 0.30))
func _m_wall() -> StandardMaterial3D:
	return lib.pbr("2F土壁", "plaster", 2.4, Color(0.89, 0.84, 0.72))
func _m_shoji_lit() -> StandardMaterial3D:
	# 二樓的光比一樓飽和一階：暖橙金，不是自然日光的黃
	var m := lib.pbr("2F障子透光", "shoji", 0.30, Color(1.0, 0.93, 0.80))
	m.emission_enabled = true
	m.emission = Color(1.0, 0.82, 0.52)
	m.emission_energy_multiplier = 2.0
	return m
func _m_tatami_a() -> StandardMaterial3D:
	return lib.pbr("2F疊A", "tatami", 0.42, Color(0.84, 0.80, 0.60))
func _m_tatami_b() -> StandardMaterial3D:
	return lib.pbr("2F疊B", "tatami", 0.42, Color(0.76, 0.72, 0.53))
func _m_washi(i: int) -> StandardMaterial3D:
	# 卷軸紙的三個色調：年代不同的紙不會同色 —— 時間感的一半在這裡
	# ⚠ 第一版 0.84/0.76/0.68 在 0.78 的環境光下是一牆發亮的蛋 —— 壓到
	# 「陰影格子裡的舊紙」的亮度，微光卷才有東西可以對比。
	var tones := [Color(0.66, 0.62, 0.53), Color(0.60, 0.55, 0.45), Color(0.53, 0.48, 0.38)]
	return lib.flat_mat("卷紙_%d" % (i % 3), tones[i % 3], 0.88)
func _m_pages() -> StandardMaterial3D:
	# 書本微光：冷白，比一樓（0.075/0.095/0.13）高一階 —— 正常光照下
	# 就該注意到。這是**起點估值**，截圖驗證後才定案（先暗後調的流程）。
	return lib.flat_mat("2F書口微光", Color(0.68, 0.72, 0.80), 0.6,
		Color(0.16, 0.20, 0.28))


# ── 地板：單一平面（y=0）+ 疊 ──
func _build_floor() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, -HW, HW, -HD, HD, 0.0)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, _m_planks())
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	lib.add(_root, mi, "Terrain")
	# 疊：棋盤格。階段口那一角（西南）讓開。
	var tg := lib.add(_root, Node3D.new(), "疊")
	var x0 := -8.19
	var z0 := -5.46
	for i in 9:
		for j in 12:
			var cx := x0 + 0.91 + float(i) * 1.82
			var cz := z0 + 0.455 + float(j) * 0.91
			if cx < -6.8 and cz < -3.0:
				continue                      # 階段口
			var mat := _m_tatami_a() if (i + j) % 2 == 0 else _m_tatami_b()
			lib.box(tg, "疊_%d_%d" % [i, j], Vector3(1.79, 0.028, 0.88), mat,
				Vector3(cx, 0.014, cz))


func _quad(st: SurfaceTool, x0: float, x1: float, z0: float, z1: float, y: float) -> void:
	# 繞向 = 一樓探針驗證過的那個朝向：從 +y 打射線要打得中
	# （trimesh 的 ConcavePolygonShape3D 預設不碰背面）
	var a := Vector3(x0, y, z0)
	var b := Vector3(x1, y, z0)
	var c := Vector3(x1, y, z1)
	var d := Vector3(x0, y, z1)
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)


# ── 牆・柱・長押（含東北角的「失準」）──
#
# 輕微空間比例失準（中等超現實・參考「說不出哪裡不對」的拿捏）：
# 集中在**東北角**（離入口最遠的角），四個微效果疊加，每一個單獨都
# 低於有意識察覺的門檻：
#   w1. 東牆的長押往北緣升 3cm（8m 拉 0.2°，看不出斜、但視線會「滑」）
#   w2. 東北角柱往上收細 6%（正常柱是直的 —— 透視好像多收了一點）
#   w3. 天井竿縁在東北象限扇開最多 2°（_build_ceiling）
#   w4. 卷軸格的格距往東遞減 0.38 → 0.30（_build_scroll_wall —— 那面牆
#       的透視讀起來比實際深）
# ⚠ 程度就到這裡。三樓才有「內部大於外部」的明顯扭曲。
func _build_walls() -> void:
	var g := lib.add(_root, Node3D.new(), "牆")
	var dark := _m_dark()
	var wall := _m_wall()

	# ── 南牆（-z，朝後院）：腰壁 + 障子帶 + 上壁 ──
	lib.box(g, "南腰壁", Vector3(HW * 2.0, GBAND_LO, 0.10),
		lib.pbr("2F腰壁", "shitami", 0.34, Color(0.48, 0.46, 0.42)),
		Vector3(0, GBAND_LO * 0.5, -HD - 0.06))
	lib.box(g, "南上壁", Vector3(HW * 2.0, CEIL_H - GBAND_HI, 0.10), wall,
		Vector3(0, (GBAND_HI + CEIL_H) * 0.5, -HD - 0.06))
	# 中央一間**拉開**（x -1.7..1.7）：「視線正對水池/枯山水」要有真的開口
	# 才成立 —— 幾何驗證：帶底 1.22、視高 1.5，站到窗前 0.5m 就看得到
	# 下方 6~9m 的池與砂紋；離遠了看到的是樹與遠山 —— 誠實的透視。
	# 拉開的兩片疊在開口西緣（略透光的板，關著的日子它們就是窗）。
	for side in [[-HW + 0.2, -1.7], [1.7, HW - 0.2]]:
		var xa2: float = side[0]
		var xb2: float = side[1]
		lib.box(g, "障子帶_%d" % int((xa2 + xb2) * 0.5), Vector3(xb2 - xa2, GBAND_HI - GBAND_LO, 0.05),
			_m_shoji_lit(), Vector3((xa2 + xb2) * 0.5, (GBAND_LO + GBAND_HI) * 0.5, -HD - 0.02))
		var x := xa2 + 0.10
		while x < xb2 - 0.05:
			lib.box(g, "組子縱_%d" % int(x * 100.0), Vector3(0.022, GBAND_HI - GBAND_LO, 0.03),
				dark, Vector3(x, (GBAND_LO + GBAND_HI) * 0.5, -HD + 0.02))
			x += 0.19
		for yy in [GBAND_LO, (GBAND_LO + GBAND_HI) * 0.5, GBAND_HI]:
			lib.box(g, "組子橫_%d_%d" % [int((xa2 + xb2) * 0.5), int(yy * 100.0)],
				Vector3(xb2 - xa2, 0.028, 0.03), dark,
				Vector3((xa2 + xb2) * 0.5, yy, -HD + 0.02))
	# 拉開疊在西緣的兩片（比帶亮一點 —— 兩層紙疊著）
	for k in 2:
		lib.box(g, "開障子_%d" % k, Vector3(1.65, GBAND_HI - GBAND_LO - 0.02, 0.03),
			_m_shoji_lit(), Vector3(-2.55 - float(k) * 0.02,
				(GBAND_LO + GBAND_HI) * 0.5, -HD + 0.06 + float(k) * 0.05))
	# 開口的框
	lib.box(g, "窗框上", Vector3(3.5, 0.06, 0.10), dark, Vector3(0, GBAND_HI + 0.03, -HD + 0.02))
	lib.box(g, "窗框下", Vector3(3.5, 0.06, 0.10), dark, Vector3(0, GBAND_LO - 0.03, -HD + 0.02))

	# ── 北牆（+z）：土壁（卷軸收納格貼在這面，_build_scroll_wall）──
	lib.box(g, "北壁", Vector3(HW * 2.0, CEIL_H, 0.10), wall, Vector3(0, CEIL_H * 0.5, HD + 0.06))
	# ── 西牆：押入（daily life 的收納）＋土壁 ──
	lib.box(g, "西壁", Vector3(0.10, CEIL_H, HD * 2.0), wall, Vector3(-HW - 0.06, CEIL_H * 0.5, 0))
	var fus := lib.flat_mat("2F襖紙", Color(0.82, 0.77, 0.66), 0.85)
	for k in 2:
		lib.box(g, "押入襖_%d" % k, Vector3(0.06, 1.85, 0.90), fus,
			Vector3(-HW + 0.10, 0.925, 1.6 + float(k) * 0.95))
		lib.box(g, "押入框_%d" % k, Vector3(0.07, 1.85, 0.05), dark,
			Vector3(-HW + 0.10, 0.925, 1.15 + float(k) * 0.95))
		lib.box(g, "押入引手_%d" % k, Vector3(0.02, 0.11, 0.06), dark,
			Vector3(-HW + 0.14, 1.0, 1.85 + float(k) * 0.95))
	# ── 東牆：土壁 ──
	lib.box(g, "東壁", Vector3(0.10, CEIL_H, HD * 2.0), wall, Vector3(HW + 0.06, CEIL_H * 0.5, 0))

	# ── 柱：正常的直柱……除了東北角那根（w2：往上收細 6%）──
	for px in [-10.6, -8.4, -6.2, -4.0, -1.8, 0.4, 2.6, 4.8, 7.0, 9.2]:
		lib.box(g, "南柱_%d" % int(px * 10.0), Vector3(0.15, CEIL_H, 0.15), dark,
			Vector3(px, CEIL_H * 0.5, -HD + 0.02))
		if px < 9.0:
			lib.box(g, "北柱_%d" % int(px * 10.0), Vector3(0.15, CEIL_H, 0.15), dark,
				Vector3(px, CEIL_H * 0.5, HD - 0.02))
	var ne := MeshInstance3D.new()
	var nem := BoxMesh.new()
	nem.size = Vector3(0.15, CEIL_H, 0.15)
	nem.material = dark
	ne.mesh = nem
	ne.position = Vector3(10.55, CEIL_H * 0.5, HD - 0.02)
	ne.scale = Vector3(1.0, 1.0, 1.0)
	# 往上收細：頂 0.94 底 1.0 —— 用剪切做不到，box 疊兩段近似
	lib.add(g, ne, "北柱_東北")
	var ne2 := lib.box(g, "北柱_東北上段", Vector3(0.141, CEIL_H * 0.5, 0.141), dark,
		Vector3(10.55, CEIL_H * 0.75, HD - 0.02))
	ne2.rotation.z = 0.004

	# ── 長押：南/北/西水平；東牆那條往北緣升 3cm（w1）──
	lib.box(g, "長押南", Vector3(HW * 2.0, 0.14, 0.06), dark, Vector3(0, NAGESHI + 0.07, -HD + 0.10))
	lib.box(g, "長押北", Vector3(HW * 2.0, 0.14, 0.06), dark, Vector3(0, NAGESHI + 0.07, HD - 0.10))
	var ln := lib.box(g, "長押東", Vector3(0.06, 0.14, HD * 2.0), dark,
		Vector3(HW - 0.10, NAGESHI + 0.085, 0))
	ln.rotation.x = 0.0026        # 8m 升 3cm ≈ 0.2°

	# ── 碰撞：四面牆 ──
	_collide(g, Vector3(HW * 2.0, CEIL_H, 0.3), Vector3(0, 0, -HD - 0.1))
	_collide(g, Vector3(HW * 2.0, CEIL_H, 0.3), Vector3(0, 0, HD + 0.1))
	_collide(g, Vector3(0.3, CEIL_H, HD * 2.0), Vector3(-HW - 0.1, 0, 0))
	_collide(g, Vector3(0.3, CEIL_H, HD * 2.0), Vector3(HW + 0.1, 0, 0))


# ── 天井：竿縁沿 z；東北象限扇開最多 2°（w3）──
func _build_ceiling() -> void:
	var g := lib.add(_root, Node3D.new(), "天井")
	lib.box(g, "天井板", Vector3(HW * 2.0, 0.08, HD * 2.0),
		lib.pbr("2F天井板", "planks", 1.6, Color(0.48, 0.44, 0.37)),
		Vector3(0, CEIL_H + 0.04, 0))
	var x := -HW + 0.8
	while x < HW - 0.3:
		var b := lib.box(g, "竿縁_%d" % int(x * 10.0), Vector3(0.055, 0.045, HD * 2.0),
			_m_dark(), Vector3(x, CEIL_H - 0.022, 0))
		# 東北象限（x > 4）：越往東越歪，最多 2°。單根看是直的，
		# 一排看有一種「收束點不在該在的地方」的微妙感。
		if x > 4.0:
			b.rotation.y = (x - 4.0) / (HW - 4.0) * 0.035
		x += 0.91
	# ⚠ 天花要有碰撞：牆碰撞箱頂 = 淨高，天花沒碰撞的話「牆頂」對
	# walk_test 是一排可站立的格點 —— 路線起點被吸附上去就沿著牆頂爬，
	# 三條路線全報假不通。（一樓同病，一樓的產生器也補了。）
	_collide(g, Vector3(HW * 2.0, 0.3, HD * 2.0), Vector3(0, CEIL_H, 0))


# ── 階段口（來自一樓；西南角）：口框 + 圍欄 + 暗井（實心，傳送場景不真開洞）──
func _build_stairwell() -> void:
	var g := lib.add(_root, Node3D.new(), "階段口")
	g.position = Vector3(-8.9, 0, -4.3)
	var dark := _m_dark()
	# 暗井：一片近黑的面，讀成「往下的洞」；實際地板是實心的（傳送場景）
	var wellm := StandardMaterial3D.new()
	wellm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wellm.albedo_color = Color(0.055, 0.048, 0.040)
	lib.box(g, "暗井", Vector3(2.0, 0.02, 1.1), wellm, Vector3(0, 0.035, 0))
	lib.box(g, "口框N", Vector3(2.2, 0.10, 0.08), dark, Vector3(0, 0.05, 0.60))
	lib.box(g, "口框S", Vector3(2.2, 0.10, 0.08), dark, Vector3(0, 0.05, -0.60))
	lib.box(g, "口框E", Vector3(0.08, 0.10, 1.15), dark, Vector3(1.08, 0.05, 0))
	# 圍欄（兩面，留南側上來的口）
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


# ── 卷軸收納格：整面北牆 —— 「不合常理地多」的主載體（數百卷）──
# 淺層（0.34 深），暗示這只是工作區的藏書，真正的大書庫在三樓。
# w4：格距往東遞減 0.38 → 0.30 —— 那面牆的透視讀起來比實際深。
func _build_scroll_wall() -> void:
	var g := lib.add(_root, Node3D.new(), "卷軸格")
	g.position = Vector3(0, 0, HD - 0.20)
	var dark := _m_dark()
	var frame := lib.pbr("格框", "planks", 0.8, Color(0.42, 0.36, 0.28))
	var x_lo := -9.6
	var x_hi := 8.8
	var y_lo := 0.22
	var rows := 5
	var row_h := (NAGESHI - 0.30 - y_lo) / float(rows)
	# 背板：暗色 —— 格子的深度感靠它，不然卷躺在發亮的 plaster 上
	lib.box(g, "格背板", Vector3(x_hi - x_lo + 0.2, NAGESHI - 0.30 - y_lo + 0.1, 0.04),
		lib.pbr("格背材", "planks", 1.2, Color(0.27, 0.24, 0.20)),
		Vector3((x_lo + x_hi) * 0.5, (y_lo + NAGESHI - 0.30) * 0.5, 0.16))
	# 橫板
	for r in rows + 1:
		lib.box(g, "棚板_%d" % r, Vector3(x_hi - x_lo + 0.2, 0.045, 0.34), frame,
			Vector3((x_lo + x_hi) * 0.5, y_lo + row_h * float(r), 0))
	# 縱隔板：格距往東遞減（w4）
	var pitches: Array[float] = []
	var xc := x_lo
	while xc < x_hi:
		pitches.append(xc)
		var t := clampf((xc - 4.0) / (x_hi - 4.0), 0.0, 1.0)
		xc += lerpf(0.38, 0.30, t)
	pitches.append(x_hi)
	for i in pitches.size():
		lib.box(g, "隔板_%d" % i, Vector3(0.03, NAGESHI - 0.30 - y_lo, 0.34), frame,
			Vector3(pitches[i], (y_lo + NAGESHI - 0.30) * 0.5, 0))
	# 卷軸：每格 1~3 卷，卷端（圓截面）朝外。三個紙色調 + 少數帶微光。
	# ⚠ mesh 共用：500 卷各自 new 一顆 CylinderMesh = 上千 draw call。
	# 3 個尺寸 × 4 個材質 = 12 顆共用 mesh，實例只挑用哪顆。
	var proto: Array[Mesh] = []
	for si in 3:
		var rr0: float = [0.058, 0.070, 0.082][si]
		for mi2 in 4:
			var cm := CylinderMesh.new()
			cm.top_radius = rr0
			cm.bottom_radius = rr0
			cm.height = 0.30
			cm.radial_segments = 8
			cm.material = _m_pages() if mi2 == 3 else _m_washi(mi2)
			proto.append(cm)
	var n_scroll := 0
	var n_glow := 0
	for r in rows:
		for i in pitches.size() - 1:
			var cw: float = pitches[i + 1] - pitches[i]
			var n: int = 1 + _rng.randi() % 3
			for k in n:
				var si2 := _rng.randi() % 3
				var glow := _rng.randf() < 0.14
				var mi3: int = si2 * 4 + (3 if glow else _rng.randi() % 3)
				var rr: float = [0.058, 0.070, 0.082][si2]
				var sx: float = pitches[i] + cw * (0.25 + 0.5 * _rng.randf())
				var sy: float = y_lo + row_h * float(r) + rr + 0.035
				var sc := MeshInstance3D.new()
				sc.mesh = proto[mi3]
				sc.position = Vector3(sx, sy, 0.0)
				sc.rotation.x = PI * 0.5
				lib.add(g, sc, "卷_%d" % n_scroll)
				n_scroll += 1
				if glow:
					n_glow += 1
	print("卷軸格：%d 卷（%d 卷帶微光）、格 %d 列 × %d 段" %
		[n_scroll, n_glow, pitches.size() - 1, rows])
	_collide(g, Vector3(x_hi - x_lo + 0.3, NAGESHI, 0.40), Vector3((x_lo + x_hi) * 0.5, 0, 0))


# ── 文机工作區：正常少女/成人比例的書桌，面向後院的光 ──
func _build_desk() -> void:
	var g := lib.add(_root, Node3D.new(), "文机")
	g.position = Vector3(-3.2, 0, -2.4)
	var dark := _m_dark()
	var lacquer := lib.pbr("2F漆几", "dark_wood", 0.9, Color(0.38, 0.35, 0.31))
	lacquer.roughness = 0.30
	# 文机：0.72 × 0.45、高 0.33 —— 常規座卓尺寸，不放大也不矮化。
	# 「超大」的反差已經交給卷軸牆的數量，桌子回到誠實的日常尺度。
	lib.box(g, "机面", Vector3(1.15, 0.06, 0.52), lacquer, Vector3(0, 0.30, 0))
	for sx in [-1.0, 1.0]:
		lib.box(g, "机脚_%d" % int(sx + 1.0), Vector3(0.06, 0.27, 0.44), dark,
			Vector3(sx * 0.50, 0.135, 0))
	_collide(g, Vector3(1.2, 0.36, 0.55))
	# 座布団（面向 -z 的光）
	lib.box(g, "座布団", Vector3(0.60, 0.09, 0.60),
		lib.pbr("2F座布", "tatami", 1.6, Color(0.46, 0.34, 0.30)),
		Vector3(0, 0.075, 0.62))
	# 机上：攤開的卷 + 硯箱 + 筆架 + 紙鎮
	var open_s := lib.add(g, Node3D.new(), "攤開的卷")
	open_s.position = Vector3(-0.12, 0.335, -0.02)
	open_s.rotation.y = 0.06
	lib.box(open_s, "紙面", Vector3(0.62, 0.012, 0.26), _m_pages(), Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		var ax := lib.cyl(open_s, "軸_%d" % int(sx + 1.0), 0.025, 0.025, 0.30, dark,
			Vector3(sx * 0.33, 0.008, 0), 8)
		ax.rotation.x = PI * 0.5
	lib.box(g, "硯箱", Vector3(0.24, 0.06, 0.16),
		lib.flat_mat("硯漆", Color(0.16, 0.15, 0.17), 0.35), Vector3(0.38, 0.365, -0.08))
	# 筆架：一根橫桿垂五支筆 —— 用的人每天在用
	lib.box(g, "筆架桿", Vector3(0.34, 0.02, 0.02), dark, Vector3(0.36, 0.56, 0.14))
	for sxp in [-0.14, -0.07, 0.0, 0.07, 0.14]:
		lib.cyl(g, "筆_%d" % int(sxp * 100.0), 0.008, 0.012, 0.17,
			lib.flat_mat("筆桿", Color(0.55, 0.42, 0.30), 0.7),
			Vector3(0.36 + sxp, 0.47, 0.14), 6)
	for sxl in [-1.0, 1.0]:
		lib.box(g, "筆架柱_%d" % int(sxl + 1.0), Vector3(0.02, 0.20, 0.02), dark,
			Vector3(0.36 + sxl * 0.16, 0.46, 0.14))


# ── 日常痕跡（普通少女的起居，正常比例，數量克制）──
func _build_daily_life() -> void:
	var g := lib.add(_root, Node3D.new(), "日常")
	var dark := _m_dark()
	# 茶盆（文机旁）：托盤 + 急須 + 茶碗一只
	var tray := lib.add(g, Node3D.new(), "茶盆")
	tray.position = Vector3(-4.6, 0.03, -1.6)
	lib.box(tray, "盤", Vector3(0.42, 0.03, 0.28), _m_dark(), Vector3(0, 0.015, 0))
	lib.cyl(tray, "急須", 0.075, 0.09, 0.11,
		lib.flat_mat("茶器", Color(0.45, 0.30, 0.24), 0.6), Vector3(-0.09, 0.09, 0), 10)
	lib.cyl(tray, "茶碗", 0.045, 0.035, 0.06,
		lib.flat_mat("茶碗釉", Color(0.72, 0.68, 0.60), 0.5), Vector3(0.10, 0.06, 0.04), 8)
	# 衣桁（東側）：一件羽織披著 —— 有人**住**在這裡
	var rack := lib.add(g, Node3D.new(), "衣桁")
	rack.position = Vector3(8.9, 0, -3.6)
	rack.rotation.y = -0.5
	for sxr in [-1.0, 1.0]:
		lib.box(rack, "桁柱_%d" % int(sxr + 1.0), Vector3(0.06, 1.55, 0.06), dark,
			Vector3(sxr * 0.75, 0.775, 0))
		lib.box(rack, "桁足_%d" % int(sxr + 1.0), Vector3(0.08, 0.05, 0.42), dark,
			Vector3(sxr * 0.75, 0.025, 0))
	lib.box(rack, "桁", Vector3(1.72, 0.05, 0.05), dark, Vector3(0, 1.50, 0))
	lib.box(rack, "羽織", Vector3(1.30, 0.85, 0.06),
		lib.pbr("羽織布", "tatami", 1.8, Color(0.42, 0.30, 0.38)),
		Vector3(0, 1.04, 0.0))
	_collide(rack, Vector3(1.8, 1.6, 0.5))
	# 火鉢 + 鐵瓶（房間中東側）
	var hib := lib.add(g, Node3D.new(), "火鉢")
	hib.position = Vector3(3.4, 0, 0.6)
	lib.cyl(hib, "鉢", 0.30, 0.34, 0.38,
		lib.pbr("火鉢陶", "stone_wall", 0.9, Color(0.40, 0.36, 0.33)), Vector3(0, 0.19, 0), 12)
	lib.cyl(hib, "灰", 0.26, 0.26, 0.03,
		lib.flat_mat("灰", Color(0.62, 0.60, 0.56), 0.95), Vector3(0, 0.375, 0), 12)
	lib.cyl(hib, "鐵瓶", 0.10, 0.12, 0.14,
		lib.flat_mat("鐵瓶黑", Color(0.14, 0.14, 0.15), 0.6), Vector3(0, 0.47, 0), 10)
	_collide(hib, Vector3(0.72, 0.55, 0.72))
	# 鏡台（西北角，押入旁）：小小的 —— 少女的房間，不是道場
	var mir := lib.add(g, Node3D.new(), "鏡台")
	mir.position = Vector3(-9.9, 0, 3.9)
	mir.rotation.y = 0.9
	lib.box(mir, "台", Vector3(0.44, 0.30, 0.26), _m_planks(), Vector3(0, 0.15, 0))
	lib.box(mir, "鏡框", Vector3(0.30, 0.42, 0.03), _m_dark(), Vector3(0, 0.56, -0.06))
	lib.box(mir, "鏡面", Vector3(0.24, 0.35, 0.01),
		lib.flat_mat("鏡", Color(0.75, 0.78, 0.80), 0.1), Vector3(0, 0.56, -0.045))
	_collide(mir, Vector3(0.5, 0.85, 0.35))


# ── 地上的堆積：書塔與卷軸山（誇張化的另一半，沿東牆）──
func _build_piles() -> void:
	var g := lib.add(_root, Node3D.new(), "堆積")
	var cover_a := lib.pbr("2F書皮藍", "tatami", 2.2, Color(0.30, 0.34, 0.44))
	var cover_b := lib.pbr("2F書皮茶", "tatami", 2.2, Color(0.42, 0.36, 0.28))
	# 書塔：沿東牆一排，高 0.5~1.25m —— 正常人不會在起居室堆這麼多書
	var spots := [
		Vector2(10.1, 3.2), Vector2(9.7, 2.2), Vector2(10.2, 1.2), Vector2(9.9, 0.0),
		Vector2(10.15, -1.2), Vector2(9.8, -2.2), Vector2(6.4, 4.9), Vector2(5.2, 5.0),
		Vector2(-6.9, 4.9), Vector2(-8.1, 4.8),
	]
	var bi := 0
	for sp in spots:
		var n := 8 + _rng.randi() % 10
		var jr := _rng.randf_range(-0.3, 0.3)
		for k in n:
			var bk := lib.add(g, Node3D.new(), "積書_%d" % bi)
			bk.position = Vector3(sp.x + _rng.randf_range(-0.025, 0.025),
				0.028 + 0.033 + float(k) * 0.062, sp.y + _rng.randf_range(-0.025, 0.025))
			bk.rotation.y = jr + _rng.randf_range(-0.12, 0.12)
			lib.box(bk, "皮", Vector3(0.26, 0.055, 0.34),
				cover_a if bi % 2 == 0 else cover_b, Vector3.ZERO)
			lib.box(bk, "口", Vector3(0.24, 0.012, 0.335), _m_pages(),
				Vector3(0, -0.018, 0.004))
			bi += 1
		_collide(g, Vector3(0.4, 0.033 + float(n) * 0.062, 0.4), Vector3(sp.x, 0, sp.y))
	print("書塔：%d 疊、%d 冊" % [spots.size(), bi])


# ── 光：飽和的暖橙金光束（先做暗 —— 截圖驗證後再調）──
func _build_light() -> void:
	var g := lib.add(_root, Node3D.new(), "光")
	for i in 3:
		var bx: float = [-6.8, -2.6, 2.2][i]
		var beam := lib.add(g, Node3D.new(), "光束_%d" % i)
		beam.position = Vector3(bx, 1.30, -4.15)
		beam.rotation.x = 0.40          # 從 -z 的窗帶往 +z 斜落
		for layer in 2:
			var mi := MeshInstance3D.new()
			var m := BoxMesh.new()
			m.size = Vector3(1.4 - float(layer) * 0.65, 0.03 + float(layer) * 0.015, 4.2)
			var mat := StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			# ⚠ 加法混合：alpha 混合在比它亮的背景（障子）前會**減光** ——
			# 側看是一片燻黑玻璃、端看是一顆蛋。光束只准提亮。
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			# 飽和暖橙 —— 起點刻意偏暗，驗證後調
			mat.albedo_color = Color(1.0, 0.80, 0.46, 0.05 + float(layer) * 0.03)
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.material = mat
			mi.mesh = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lib.add(beam, mi, "層_%d" % layer)
	for i in 3:
		var bx2: float = [-6.8, -2.6, 2.2][i]
		var sp := SpotLight3D.new()
		sp.position = Vector3(bx2, 2.05, -5.5)
		sp.rotation.x = 0.32            # 朝 +z 下斜（燈的 -z 軸轉向房內）
		sp.rotation.y = PI
		sp.light_color = Color(1.0, 0.78, 0.46)
		sp.light_energy = 2.2
		sp.spot_range = 10.0
		sp.spot_angle = 30.0
		sp.shadow_enabled = false
		lib.add(g, sp, "聚光_%d" % i)
	# 行灯 ×2（夜的光源；暖，跟書口的冷白分開）
	for k in 2:
		var pos: Vector3 = [Vector3(-1.6, 0, -1.2), Vector3(7.6, 0, 3.6)][k]
		var an := lib.add(g, Node3D.new(), "行灯_%d" % k)
		an.position = pos
		lib.box(an, "灯座", Vector3(0.30, 0.04, 0.30), _m_dark(), Vector3(0, 0.02, 0))
		var shade := lib.flat_mat("行灯紙", Color(1.0, 0.92, 0.74), 0.8,
			Color(0.55, 0.42, 0.22))
		lib.box(an, "灯袋", Vector3(0.26, 0.48, 0.26), shade, Vector3(0, 0.30, 0))
		lib.box(an, "灯蓋", Vector3(0.32, 0.03, 0.32), _m_dark(), Vector3(0, 0.56, 0))
		var li := OmniLight3D.new()
		li.position = Vector3(0, 0.35, 0)
		li.light_color = Color(1.0, 0.82, 0.55)
		li.light_energy = 0.9
		li.omni_range = 4.5
		li.shadow_enabled = false
		an.add_child(li)
		li.owner = _root
		_collide(an, Vector3(0.34, 0.6, 0.34))


# ── 假窗：後院的池／枯山水縮小版（-z 外側）──
func _build_garden_backdrop() -> void:
	var g := lib.add(_root, Node3D.new(), "假窗後院")
	# 地：砂洲色（枯山水的砂）
	# ⚠ 視線幾何：玩家最貼近窗也離窗面 ~0.7m（膠囊半徑＋牆碰撞），
	# 腰壁 1.22 讓 10m 內的地面全被遮住 —— 主構圖一律擺在 11m 外。
	lib.box(g, "砂地", Vector3(30.0, 0.2, 20.0),
		lib.flat_mat("枯山水砂", Color(0.78, 0.75, 0.66), 0.95),
		Vector3(0, -3.6, -HD - 10.0))
	# 同心圓砂紋（室外的裂縫語彙 —— 圓心在懸浮石正下方；跟室內的
	# 「散落碎片」刻意不同，這是 §已定案 5 的形態區隔）
	for r in 4:
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.9 + float(r) * 0.85
		t.outer_radius = 0.9 + float(r) * 0.85 + 0.10
		t.rings = 32
		t.ring_segments = 6
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.62, 0.58, 0.50)
		rm.roughness = 0.95
		t.material = rm
		ring.mesh = t
		ring.position = Vector3(-2.5, -3.47, -HD - 11.0)
		ring.scale = Vector3(1.35, 0.06, 1.35)
		lib.add(g, ring, "砂紋_%d" % r)
	# 懸浮石：浮在砂紋圓心上方 —— 靈氣裂縫的「因」
	var stone := MeshInstance3D.new()
	stone.mesh = lib.blob_mesh(97, 0.62, 0.30)
	stone.material_override = lib.pbr("浮石", "stone_wall", 0.85, Color(0.52, 0.52, 0.50))
	stone.position = Vector3(-2.5, -2.05, -HD - 11.0)
	stone.scale = Vector3(0.8, 0.65, 0.8)
	lib.add(g, stone, "懸浮石")
	# 石下的微光（裂縫的光 —— 遠景一小點就好）
	var gl := OmniLight3D.new()
	gl.position = Vector3(-2.5, -3.0, -HD - 11.0)
	gl.light_color = Color(1.0, 0.85, 0.60)
	gl.light_energy = 1.1
	gl.omni_range = 3.0
	gl.shadow_enabled = false
	lib.add(g, gl, "裂縫光")
	# 池（東側）：水面一片 + 岸石幾顆
	lib.cyl(g, "池面", 3.2, 3.2, 0.04,
		lib.flat_mat("池水", Color(0.30, 0.42, 0.42), 0.25), Vector3(5.8, -3.52, -HD - 11.5), 20)
	for k in 5:
		var rk := MeshInstance3D.new()
		rk.mesh = lib.blob_mesh(151 + k * 11, 0.5, 0.25)
		rk.material_override = lib.pbr("2F岸石", "stone_wall", 0.85, Color(0.46, 0.45, 0.42))
		var a := float(k) / 5.0 * TAU + 0.4
		rk.position = Vector3(5.8 + cos(a) * 3.3, -3.5, -HD - 11.5 + sin(a) * 3.1)
		rk.scale = Vector3.ONE * _rng.randf_range(0.4, 0.75)
		lib.add(g, rk, "岸石_%d" % k)
	# 楓兩株（後院的樹 —— 真資產，角度對就好）
	for k in 2:
		var mp := MeshInstance3D.new()
		mp.mesh = lib.prop_mesh("res://assets/models/hieda_maple_%s.glb" % ["a", "b"][k])
		mp.material_override = lib.foliage_vc_mat()
		mp.position = Vector3([-8.2, 8.6][k], -3.6, -HD - 10.0)
		mp.scale = Vector3.ONE * 0.9
		mp.rotation.y = _rng.randf_range(0.0, TAU)
		lib.add(g, mp, "庭楓_%d" % k)
	# 近景一株小楓：框住窗景左緣（透過窗看有前中遠三層才有深度）
	var mp2 := MeshInstance3D.new()
	mp2.mesh = lib.prop_mesh("res://assets/models/hieda_maple_c.glb")
	mp2.material_override = lib.foliage_vc_mat()
	mp2.position = Vector3(-5.2, -3.7, -HD - 3.2)
	mp2.scale = Vector3.ONE * 0.62
	lib.add(g, mp2, "近楓")
	# 生垣一條 + 遠山/天空背板
	lib.box(g, "生垣", Vector3(30.0, 1.1, 0.8),
		lib.flat_mat("2F生垣", Color(0.20, 0.30, 0.18), 0.95), Vector3(0, -3.0, -HD - 14.2))
	var hills := StandardMaterial3D.new()
	hills.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hills.albedo_color = Color(0.58, 0.64, 0.57)
	var hb := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(40.0, 4.0, 0.1)
	hm.material = hills
	hb.mesh = hm
	hb.position = Vector3(0, -1.4, -HD - 15.4)
	lib.add(g, hb, "遠山")
	var skym := StandardMaterial3D.new()
	skym.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skym.albedo_color = Color(0.91, 0.89, 0.82)
	var sb := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(40.0, 14.0, 0.1)
	sm.material = skym
	sb.mesh = sm
	sb.position = Vector3(0, 5.0, -HD - 15.5)
	lib.add(g, sb, "天空板")


# ── 氛圍 ──
func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.038, 0.032)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.86, 0.68)
	env.ambient_light_energy = 0.78
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.tonemap_white = 4.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.05
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.10
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	lib.add(_root, we, "WorldEnvironment")


# ── 地板射線實測（一樓的坑 → 這層的標準流程）──
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
	var xi := -HW + 1.0
	while xi < HW:
		var zi := -HD + 1.0
		while zi < HD:
			n_all += 1
			ray.from = Vector3(xi, 30.0, zi)
			ray.to = Vector3(xi, -10.0, zi)
			if not sps.intersect_ray(ray).is_empty():
				n_hit += 1
			zi += 1.5
		xi += 1.5
	# 臨時的 trimesh body 要拆掉再存檔 —— main.gd 載入時會自己再建一次
	var doomed: Array[Node] = []
	for c in terr.get_children():
		if String(c.name).contains("_col"):
			doomed.append(c)
	for c in doomed:
		terr.remove_child(c)
		c.free()
	get_root().remove_child(_root)
	print("地板射線實測：%d/%d 中（門檻 95%%）" % [n_hit, n_all])
	return float(n_hit) / float(n_all) >= 0.95


func _write_meta() -> void:
	var meta := {
		"id": MAP_ID,
		"note": "稗田邸二樓（阿求書房）—— 傳送場景。外殼照凍結的外觀量體"
			+ "（21.88×11.96、淨高 3.10、窗帶 1.22→2.28 朝後院 -z）。"
			+ "階段口 portal 的 target 等一樓/室外圖串接時填上（現為保留觸發區）。"
			+ "不進 mapRegistry：建築內部不是世界圖上的一格。",
		"playSize": [22, 12],
		"safe": true,
		"connections": [],
		"portals": [
			{"x": -8.9, "y": 0.0, "z": -3.2, "target": null},
		],
		"colliders": [],
	}
	var f := FileAccess.open("res://data/%s.meta.json" % MAP_ID, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, " "))
	f.close()
	print("wrote data/%s.meta.json" % MAP_ID)
