# 稗田邸一樓 —— 玄関／客間（傳送場景）
#
#   godot --headless --path godot --script tools/gen_hieda1f.gd
#
# 定位（docs/hieda-estate-features.md §內裝方向，使用者 2026-08-07 開工指令）：
#   ・對外、節制。超現實強度三段式的**最低階** —— 一樓唯一的載體是
#     「書本微光」（極淡、冷白，跟三樓將來的琥珀白刻意區隔）。
#   ・實際淨高 **3.90m，不打破外殼**。高聳感全部用構圖做：
#     柱的縱向節奏、光束、屏風直紋 —— 不加高天花板。
#   ・家具「超大」指**體積**不指高度：几面更寬、屏風更闊，都不站得更高。
#   ・明確不做：地面裂痕（三樓專用）、空間比例失準（二三樓語彙）。
#
# 外殼（已凍結的外觀量體，不越界）：
#   一層 25.48 × 14.56、淨高 3.90（基壇上 0.85 → 4.75）
#   障子帶 絕對高 2.03→3.17 = 本場景地板上 **1.18→2.32**（朝前庭）
#   玄関開口半寬 GATE_HW = 2.9（make_hieda.py 同名常數，門扉/唐破風照它讓路）
#
# 座標：本場景自成一格，地板 y=0、房間中心為原點。
#   前庭方向 = **+z**（外觀 glb 的 Blender -y 面；Godot z = -by）。
#   玩家從 +z 的玄関進來，回程 portal 是 target:null 的保留觸發區
#   （稗田邸室外圖還沒建；main.gd::_spawn_portals 已支援）。
#
# 技術路線（已定案）：傳送場景。窗外用**假窗** —— 障子外一片簡化背板
# （狛犬/參道縮小版，重用 komainu_a.glb / stone_lantern.glb），只對角度
# 與高度，不比照前庭完整精度。玄関門口一道空氣牆：布景是拿來看的，
# 不是拿來走的；將來 target 填上之後玩家在門口就被傳走，牆照樣不礙事。
extends SceneTree

const OUT_DIR := "res://maps/hieda1f/"
const MAP_ID := "hieda1f"
const SEED := 7100

# ── 外殼（內淨尺寸）──
const HW := 12.28              # 半寬（x）：外殼 25.48 - 牆厚
const HD := 7.05               # 半深（z）：外殼 14.56 - 牆厚
const CEIL_H := 3.90           # 實際淨高，不打破
const WALL_T := 0.22
const GATE_HW := 2.9           # 玄関開口半寬（對齊 make_hieda.py）
const DOOR_H := 2.60           # 玄関門楣
const BAND_LO := 1.18          # 障子帶（對齊外觀 z 2.03→3.17，扣掉基壇 0.85）
const BAND_HI := 2.32
const NAGESHI := 2.32          # 長押高度 = 障子帶上緣，全室拉同一條線

# ── 內部分區 ──
const DOMA_HW := 3.2           # 土間半寬
const DOMA_Z0 := 3.55          # 土間內緣（式台在這裡）
const DOMA_Y := -0.30          # 土間比板の間低
const FUSUMA_W := -10.4        # 西襖牆（再往西是收起來的私區，不進）
const FUSUMA_E := 9.2          # 東襖牆
const FUSUMA_H := 1.90

var lib = preload("res://tools/gen_lib.gd").new()
var _root: Node3D
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = SEED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "gen"))
	_root = Node3D.new()
	_root.name = "Hieda1F"
	_root.set_meta("own_colliders", true)
	lib.setup(_root, SEED)

	_build_floor()
	_build_walls()
	_build_ceiling()
	_build_tokonoma()
	_build_furniture()
	_build_books()
	_build_stairs()
	_build_light()
	_build_garden_backdrop()
	_build_env()

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


# ── 材質（一次定義，名字唯一 —— lib.pbr 用名字快取）──
func _m_planks() -> StandardMaterial3D:
	return lib.pbr("床板", "planks", 0.55, Color(0.52, 0.45, 0.36))
func _m_doma() -> StandardMaterial3D:
	return lib.pbr("土間叩き", "terrain_path", 0.8, Color(0.52, 0.47, 0.40))
func _m_dark() -> StandardMaterial3D:
	# 柱・長押・框：曬不到太陽的室內木部，比外觀的灰褐再深一點
	return lib.pbr("內木部", "dark_wood", 0.45, Color(0.34, 0.33, 0.30))
func _m_wall() -> StandardMaterial3D:
	# 聚楽土壁：暖灰土色。牆是背景，不能比屏風跟光搶戲
	# ⚠ 第一版用 arakabe（荒壁）—— 那張貼圖本身就紅，乘暖褐色調在暗室裡
	# 讀成**鏽紅磚倉庫**。室內的仕上げ是砂壁/漆喰，用 plaster 提亮。
	# uv 要夠密：0.5 攤在 9m 的單一 box 面上，斑點放大成軟木板。
	return lib.pbr("土壁", "plaster", 2.4, Color(0.90, 0.85, 0.74))
func _m_koshi() -> StandardMaterial3D:
	return lib.pbr("內腰壁", "shitami", 0.34, Color(0.46, 0.44, 0.40))
func _m_shoji_lit() -> StandardMaterial3D:
	# 障子帶：透光的和紙。金白色的光源本體 —— 這一片就是一樓的「窗」
	var m := lib.pbr("障子透光", "shoji", 0.30, Color(1.0, 0.96, 0.86))
	m.emission_enabled = true
	m.emission = Color(1.0, 0.90, 0.72)
	m.emission_energy_multiplier = 2.1
	return m
func _m_fusuma() -> StandardMaterial3D:
	# ⚠ shoji 貼圖烤了組子格 —— 貼在襖上整面牆變格子門。襖是**素紙**。
	return lib.flat_mat("襖紙", Color(0.82, 0.77, 0.66), 0.85)
func _m_tatami_a() -> StandardMaterial3D:
	return lib.pbr("疊A", "tatami", 0.42, Color(0.86, 0.82, 0.62))
func _m_tatami_b() -> StandardMaterial3D:
	# 棋盤格的第二色調：疊的織向交錯，遠看才不是一片綠地毯
	return lib.pbr("疊B", "tatami", 0.42, Color(0.78, 0.74, 0.55))


# ── 地板：一張 ArrayMesh 命名 Terrain（walk_test / check_map 的高度場）──
# 兩個面高度：板の間 y=0、土間 y=-0.30。兩種材質兩個 surface。
func _build_floor() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 板の間（土間以外的全部）：後半 + 土間兩側
	_quad(st, -HW, HW, -HD, DOMA_Z0, 0.0)
	_quad(st, -HW, -DOMA_HW, DOMA_Z0, HD, 0.0)
	_quad(st, DOMA_HW, HW, DOMA_Z0, HD, 0.0)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, _m_planks())
	# 土間（第二個 surface）+ 式台踏面的立面
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st2, -DOMA_HW, DOMA_HW, DOMA_Z0, HD, DOMA_Y)
	mesh = st2.commit(mesh)
	mesh.surface_set_material(1, _m_doma())
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	lib.add(_root, mi, "Terrain")
	# 碰撞：板の間三塊 + 土間一塊（trimesh 只給 Terrain 一份也可以，但
	# main.gd 的 TRIMESH_MIN_SPAN=15 只看整個 mesh 的 AABB —— 這裡整張
	# 24.6×14.1 過門檻，交給 trimesh 就好，box 只補土間邊緣的立面）
	# 式台：土間 → 板の間的一階（0.30 落差切成兩段，各 0.15）
	var g := lib.add(_root, Node3D.new(), "式台")
	lib.box(g, "踏板", Vector3(5.2, 0.14, 0.85), _m_planks(),
		Vector3(0, DOMA_Y + 0.07, DOMA_Z0 + 0.45))
	_collide(g, Vector3(5.2, 0.15, 0.85), Vector3(0, DOMA_Y, DOMA_Z0 + 0.45))
	# 疊：棋盤格兩色調（0.91 × 1.82），鋪在客間一側。四周留板縁。
	var tg := lib.add(_root, Node3D.new(), "疊")
	var x0 := -10.19
	var z0 := -6.85
	for i in 7:
		for j in 11:
			var mat := _m_tatami_a() if (i + j) % 2 == 0 else _m_tatami_b()
			lib.box(tg, "疊_%d_%d" % [i, j], Vector3(1.79, 0.028, 0.88), mat,
				Vector3(x0 + 0.91 + float(i) * 1.82, 0.014, z0 + 0.455 + float(j) * 0.91))


func _quad(st: SurfaceTool, x0: float, x1: float, z0: float, z1: float, y: float) -> void:
	# ⚠ 繞向決定的不只是渲染的正面 —— trimesh 的 ConcavePolygonShape3D 預設
	# backface_collision = false，繞向錯的地板從上往下的射線**全部穿過**：
	# walk_test 一格地面都掃不到（實測 135 條射線只有 5 條打中牆頂的箱）。
	# 這個朝向是探針驗證過的：從 +y 打射線要打得中。
	var a := Vector3(x0, y, z0)
	var b := Vector3(x1, y, z0)
	var c := Vector3(x1, y, z1)
	var d := Vector3(x0, y, z1)
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)


# ── 牆・柱・長押 ──
func _build_walls() -> void:
	var g := lib.add(_root, Node3D.new(), "牆")
	var dark := _m_dark()
	var wall := _m_wall()

	# ── 前牆（+z，朝前庭）：腰壁 + 障子帶 + 上壁，玄関開口讓路 ──
	for side in [[-HW, -GATE_HW], [GATE_HW, HW]]:
		var xa: float = side[0]
		var xb: float = side[1]
		var cx := (xa + xb) * 0.5
		var w := xb - xa
		lib.box(g, "前腰壁_%d" % int(cx), Vector3(w, BAND_LO, 0.10), _m_koshi(),
			Vector3(cx, BAND_LO * 0.5, HD + 0.06))
		lib.box(g, "前上壁_%d" % int(cx), Vector3(w, CEIL_H - BAND_HI, 0.10), wall,
			Vector3(cx, (BAND_HI + CEIL_H) * 0.5, HD + 0.06))
	# 障子帶：分成一間一間（柱位之間），組子直向為主
	_shoji_band(g, -HW, -GATE_HW)
	_shoji_band(g, GATE_HW, HW)
	# 玄関開口：門楣 + 楣上壁 + 門框柱
	lib.box(g, "門楣", Vector3(GATE_HW * 2.0 + 0.5, 0.22, 0.24), dark,
		Vector3(0, DOOR_H + 0.11, HD))
	lib.box(g, "楣上壁", Vector3(GATE_HW * 2.0, CEIL_H - DOOR_H - 0.22, 0.10), wall,
		Vector3(0, (DOOR_H + 0.22 + CEIL_H) * 0.5, HD + 0.06))
	# 大扉（雙開，往外敞開貼在外牆上 —— 玩家從這裡「剛走進來」）
	# ⚠ 第一版用旋轉開門，樞紐忘了從板中心挪到門緣 —— 門板斜插在門洞
	# 正中央，像一面立在土間的屏風。改成「拉到底」：平貼外牆，簡單而且對。
	for sx in [-1.0, 1.0]:
		lib.box(g, "大扉_%d" % int(sx + 1.0), Vector3(2.70, DOOR_H - 0.06, 0.09),
			lib.pbr("大扉板", "dark_wood", 0.5, Color(0.30, 0.28, 0.25)),
			Vector3(sx * (GATE_HW + 1.45), (DOOR_H - 0.06) * 0.5, HD + 0.30))
	# 外側簡化的向拝（唐破風的低精度暗示：兩根向拝柱 + 一片深簷板）
	for sx in [-1.0, 1.0]:
		lib.box(g, "向拝柱_%d" % int(sx + 1.0), Vector3(0.24, DOOR_H + 0.35, 0.24), dark,
			Vector3(sx * (GATE_HW - 0.35), (DOOR_H + 0.35) * 0.5 - 0.30, HD + 1.45))
	lib.box(g, "向拝天井", Vector3(GATE_HW * 2.0 + 0.8, 0.10, 1.9), dark,
		Vector3(0, DOOR_H + 0.30, HD + 0.95))

	# ── 後牆（-z）：土壁全面（床の間另做）──
	lib.box(g, "後壁", Vector3(HW * 2.0, CEIL_H, 0.10), wall,
		Vector3(0, CEIL_H * 0.5, -HD - 0.06))

	# ── 東西襖牆：襖 + 欄間壁。再過去的房間收著，不進。──
	for sx in [-1.0, 1.0]:
		var wx := FUSUMA_W if sx < 0.0 else FUSUMA_E
		var fg := lib.add(g, Node3D.new(), "襖牆_%d" % int(sx + 1.0))
		var n := int(floor((HD * 2.0 - 0.3) / 0.98))
		for k in n:
			var z := -HD + 0.15 + 0.49 + float(k) * 0.98
			lib.box(fg, "襖_%d" % k, Vector3(0.06, FUSUMA_H, 0.94), _m_fusuma(),
				Vector3(wx, FUSUMA_H * 0.5, z))
			lib.box(fg, "襖框_%d" % k, Vector3(0.07, FUSUMA_H, 0.05), dark,
				Vector3(wx, FUSUMA_H * 0.5, z - 0.49))
			# 引手：一顆小暗點，有它才讀成「拉得開的門」
			lib.box(fg, "引手_%d" % k, Vector3(0.02, 0.11, 0.06), dark,
				Vector3(wx + sx * -0.04, 1.02, z + 0.32))
		lib.box(fg, "鴨居_%d" % int(sx + 1.0), Vector3(0.14, 0.12, HD * 2.0), dark,
			Vector3(wx, FUSUMA_H + 0.06, 0))
		lib.box(fg, "欄間壁_%d" % int(sx + 1.0), Vector3(0.10, CEIL_H - FUSUMA_H - 0.12, HD * 2.0),
			wall, Vector3(wx, (FUSUMA_H + 0.12 + CEIL_H) * 0.5, 0))
		_collide(g, Vector3(0.2, CEIL_H, HD * 2.0), Vector3(wx, 0, 0))

	# ── 柱：縱向節奏的主角。前後牆 + 玄関界的獨立柱 ──
	# 高聳感靠這些 0.16m 的直線把視線往上帶，不靠加高天花板。
	var post_xs := [-12.2, -10.4, -8.5, -6.65, -4.8, -2.9, 2.9, 4.8, 6.65, 9.2, 12.2]
	for px in post_xs:
		lib.box(g, "前柱_%d" % int(px * 10.0), Vector3(0.16, CEIL_H, 0.16), dark,
			Vector3(px, CEIL_H * 0.5, HD - 0.02))
		lib.box(g, "後柱_%d" % int(px * 10.0), Vector3(0.16, CEIL_H, 0.16), dark,
			Vector3(px, CEIL_H * 0.5, -HD + 0.02))
	# 玄関 ↔ 客間界：獨立柱一對 + 差鴨居（框出「進到裡面了」的一道門檻）
	for sx in [-1.0, 1.0]:
		lib.box(g, "界柱_%d" % int(sx + 1.0), Vector3(0.17, CEIL_H, 0.17), dark,
			Vector3(sx * DOMA_HW, CEIL_H * 0.5, DOMA_Z0))
		_collide(g, Vector3(0.25, CEIL_H, 0.25), Vector3(sx * DOMA_HW, 0, DOMA_Z0))
	lib.box(g, "差鴨居", Vector3(DOMA_HW * 2.0 + 0.2, 0.24, 0.15), dark,
		Vector3(0, 2.55, DOMA_Z0))

	# ── 長押：全室同一條線（=障子帶上緣）。水平線只留這一條，
	# 它是柱列的「節」，拉齊之後縱向節奏才數得出來。──
	lib.box(g, "長押前", Vector3(HW * 2.0, 0.15, 0.06), dark, Vector3(0, NAGESHI + 0.075, HD - 0.10))
	lib.box(g, "長押後", Vector3(HW * 2.0, 0.15, 0.06), dark, Vector3(0, NAGESHI + 0.075, -HD + 0.10))

	# ── 碰撞：四面牆 + 玄関開口讓路 + 門口空氣牆 ──
	for side in [[-HW, -GATE_HW], [GATE_HW, HW]]:
		var cx2 := (float(side[0]) + float(side[1])) * 0.5
		_collide(g, Vector3(float(side[1]) - float(side[0]), CEIL_H, 0.3), Vector3(cx2, 0, HD + 0.1))
	_collide(g, Vector3(HW * 2.0, CEIL_H, 0.3), Vector3(0, 0, -HD - 0.1))
	# 空氣牆：玄関門口。布景（假窗前庭）是拿來看的不是拿來走的；
	# 將來 portal 的 target 填上，玩家走到這裡就被傳走，這面牆不礙事。
	_collide(g, Vector3(GATE_HW * 2.0 + 0.4, CEIL_H, 0.2), Vector3(0, DOMA_Y, HD + 0.28))


## 障子帶（xa→xb 之間，柱距切間）：組子**直向密、橫向疏** —— 這面牆
## 自己就是縱向構圖的一部分，不只是光源。
func _shoji_band(g: Node3D, xa: float, xb: float) -> void:
	var dark := _m_dark()
	lib.box(g, "障子帶_%d" % int((xa + xb) * 0.5), Vector3(xb - xa, BAND_HI - BAND_LO, 0.05),
		_m_shoji_lit(), Vector3((xa + xb) * 0.5, (BAND_LO + BAND_HI) * 0.5, HD + 0.02))
	var x := xa + 0.10
	while x < xb - 0.05:
		lib.box(g, "組子縱_%d" % int(x * 100.0), Vector3(0.022, BAND_HI - BAND_LO, 0.03), dark,
			Vector3(x, (BAND_LO + BAND_HI) * 0.5, HD - 0.02))
		x += 0.19
	for yy in [BAND_LO, BAND_LO + (BAND_HI - BAND_LO) * 0.5, BAND_HI]:
		lib.box(g, "組子橫_%d_%d" % [int((xa + xb) * 0.5), int(yy * 100.0)],
			Vector3(xb - xa, 0.028, 0.03), dark, Vector3((xa + xb) * 0.5, yy, HD - 0.02))


# ── 天井：暗色竿縁天井。暗的頂讀起來比實際高 —— 也是構圖的一部分 ──
func _build_ceiling() -> void:
	var g := lib.add(_root, Node3D.new(), "天井")
	lib.box(g, "天井板", Vector3(HW * 2.0, 0.08, HD * 2.0),
		lib.pbr("天井板材", "planks", 1.6, Color(0.50, 0.46, 0.38)),
		Vector3(0, CEIL_H + 0.04, 0))
	# 竿縁沿 z 走（朝向障子光的方向）：站在客間望向前庭時，這些線在
	# 透視裡收束向光 —— 跟柱一起把畫面拉「高」
	var x := -HW + 0.9
	while x < HW - 0.4:
		lib.box(g, "竿縁_%d" % int(x * 10.0), Vector3(0.055, 0.045, HD * 2.0),
			_m_dark(), Vector3(x, CEIL_H - 0.022, 0))
		x += 0.91
	# 一根化粧梁（玄関界的上方）：跟差鴨居同位，斷面收細、貼著天花
	lib.box(g, "梁", Vector3(HW * 2.0, 0.20, 0.26),
		lib.pbr("梁材", "dark_wood", 0.5, Color(0.30, 0.29, 0.26)),
		Vector3(0, CEIL_H - 0.10, DOMA_Z0))
	# ⚠ 天花碰撞：沒有的話牆頂對 walk_test 是一排「可站立」的格點
	# （二樓真的踩到：起點吸附上牆頂，三條路線全假不通）。
	_collide(g, Vector3(HW * 2.0, 0.3, HD * 2.0), Vector3(0, CEIL_H, 0))


# ── 床の間：後牆正中偏西。掛軸一幅、香炉一座 —— 擺設就這些。──
func _build_tokonoma() -> void:
	var g := lib.add(_root, Node3D.new(), "床の間")
	var dark := _m_dark()
	var x0 := -6.1
	var x1 := -2.5
	var cx := (x0 + x1) * 0.5
	# ⚠ 第一版只有床框＋掛軸，結果畫面裡「床の間不存在」—— 掛軸像貼在
	# 平牆上的開關面板。龕不能真的往後凹（會戳破凍結的外殼），深度全靠
	# 三件事的**錯覺**：袖壁把兩側包起來、龕內壁暗一階、龕內一盞暗燈。
	for sxw in [x0 + 0.15, x1 - 0.15]:
		lib.box(g, "袖壁_%d" % int(sxw * 10.0), Vector3(0.30, CEIL_H, 0.52), _m_wall(),
			Vector3(sxw, CEIL_H * 0.5, -6.79))
	lib.box(g, "床內壁", Vector3(x1 - x0 - 0.3, 2.55, 0.06),
		lib.pbr("床內壁材", "plaster", 2.4, Color(0.58, 0.53, 0.45)),
		Vector3(cx, 2.55 * 0.5, -7.00))
	# 床框 + 抬高的床板
	lib.box(g, "床框", Vector3(x1 - x0, 0.16, 0.12), dark, Vector3(cx, 0.08, -6.50))
	lib.box(g, "床板", Vector3(x1 - x0, 0.14, 0.55),
		lib.pbr("床の間板", "planks", 0.5, Color(0.46, 0.40, 0.32)),
		Vector3(cx, 0.07, -6.80))
	# 床柱（一根圓的 —— 全室唯一的圓柱，格最高的那根柱）
	lib.cyl(g, "床柱", 0.10, 0.11, CEIL_H, dark, Vector3(x1, CEIL_H * 0.5, -6.52), 10)
	# 下がり壁 + 落し掛け（龕的上框：一根深色橫木，畫出龕的「口」）
	lib.box(g, "下がり壁", Vector3(x1 - x0, CEIL_H - 2.55, 0.08), _m_wall(),
		Vector3(cx, (2.55 + CEIL_H) * 0.5, -6.50))
	lib.box(g, "落し掛け", Vector3(x1 - x0, 0.10, 0.10), dark, Vector3(cx, 2.55, -6.50))
	# 龕內的暗燈：讓掛軸從龕的陰影裡浮出來（不是讓龕消失）
	var tl := OmniLight3D.new()
	tl.position = Vector3(cx, 2.1, -6.72)
	tl.light_color = Color(1.0, 0.88, 0.70)
	tl.light_energy = 0.55
	tl.omni_range = 2.6
	tl.shadow_enabled = false
	lib.add(g, tl, "床の間灯")
	# 掛軸：紙本淡雅，一條深色縱筆 —— 極淡微光（冷白，幾乎看不出來）
	var paper := lib.flat_mat("掛軸紙", Color(0.72, 0.70, 0.64), 0.85,
		Color(0.035, 0.040, 0.050))
	lib.box(g, "掛軸", Vector3(0.56, 1.72, 0.02), paper, Vector3(cx, 1.75, -6.88))
	lib.box(g, "掛軸軸木", Vector3(0.62, 0.04, 0.04), dark, Vector3(cx, 0.90, -6.87))
	lib.box(g, "掛軸筆", Vector3(0.10, 1.30, 0.005),
		lib.flat_mat("掛軸墨", Color(0.18, 0.19, 0.22), 0.9),
		Vector3(cx - 0.05, 1.78, -6.862))
	# 香炉
	lib.cyl(g, "香炉", 0.09, 0.11, 0.12,
		lib.pbr("香炉銅", "stone_wall", 0.9, Color(0.35, 0.32, 0.26)),
		Vector3(cx + 1.1, 0.20, -6.80), 8)
	_collide(g, Vector3(x1 - x0, 0.3, 0.7), Vector3(cx, 0, -6.72))


# ── 家具：一張待客矮桌、一曲屏風、坐墊兩枚。「超大」在几面與屏風的
# **寬**，不在高 —— 高度全部壓低，天花相對就高。──
func _build_furniture() -> void:
	var g := lib.add(_root, Node3D.new(), "家具")
	var dark := _m_dark()
	# 待客矮桌：几面 2.6 × 1.5（尋常的兩倍面積），高只有 0.30
	var tg := lib.add(g, Node3D.new(), "矮桌")
	tg.position = Vector3(-4.3, 0.03, -0.6)
	var lacquer := lib.pbr("漆几", "dark_wood", 0.9, Color(0.38, 0.35, 0.31))
	lacquer.roughness = 0.30          # 漆面：微微反光，跟乾木部分開
	lib.box(tg, "几面", Vector3(2.60, 0.09, 1.50), lacquer, Vector3(0, 0.255, 0))
	lib.box(tg, "几裙", Vector3(2.30, 0.07, 1.20), lacquer, Vector3(0, 0.18, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			lib.box(tg, "几腳_%d_%d" % [int(sx + 1.0), int(sz + 1.0)],
				Vector3(0.10, 0.21, 0.10), dark, Vector3(sx * 1.10, 0.105, sz * 0.58))
	_collide(tg, Vector3(2.60, 0.32, 1.50))
	# 坐墊：客座兩枚（面向床の間那側是主位，留空 —— 主人還沒出場）
	for k in 2:
		var zab := lib.box(g, "坐墊_%d" % k, Vector3(0.62, 0.09, 0.62),
			lib.pbr("坐墊布", "tatami", 1.6, Color(0.32, 0.36, 0.46)),
			Vector3(-4.3 + (float(k) - 0.5) * 1.6, 0.075, 0.62))
		zab.rotation.y = _rng.randf_range(-0.06, 0.06)
	# 屏風：六曲一隻。高 1.72（不高於常規），總寬 ~5.6m（闊 —— 超大在這）。
	# 紋樣：抽象流動紋 —— 直向的流線，不是山水畫。
	var sg := lib.add(g, Node3D.new(), "屏風")
	# ⚠ 第一版貼在西襖牆前 0.3m —— 兩個都是米色直紋，屏風**融進牆裡**。
	# 站到桌後、斜置，跟牆脫開，才是一件「擺在空間裡的東西」。
	# ⚠⚠ 串接輪 portal_test 抓到：擺在 (-7.3,-3.3) 時屏風南端離箱階段
	# 只剩 4cm —— 上二樓的樓梯口被封在西南角的口袋裡。北移 + 收斜角，
	# 讓出 1.35m 的走道；樓梯也要看得見，玩家才找得到上樓的路。
	sg.position = Vector3(-6.9, 0, -1.9)
	sg.rotation.y = 0.30
	var gold := lib.flat_mat("屏風地", Color(0.70, 0.60, 0.40), 0.5)
	var st_a := lib.flat_mat("流紋深", Color(0.24, 0.32, 0.36), 0.7)
	var st_b := lib.flat_mat("流紋金", Color(0.72, 0.60, 0.34), 0.5)
	var zc := -2.35
	for k in 6:
		var pan := lib.add(sg, Node3D.new(), "曲_%d" % k)
		pan.position = Vector3((0.12 if k % 2 == 0 else -0.12), 0, zc + 0.47)
		pan.rotation.y = (0.38 if k % 2 == 0 else -0.38)
		lib.box(pan, "面", Vector3(0.05, 1.72, 0.94), gold, Vector3(0, 0.90, 0))
		lib.box(pan, "框上", Vector3(0.06, 0.05, 0.96), dark, Vector3(0, 1.74, 0))
		lib.box(pan, "框下", Vector3(0.06, 0.05, 0.96), dark, Vector3(0, 0.06, 0))
		# 每曲三條直向流線：位置抖動、兩色交替，粗細不一
		for s in 3:
			var mzt := st_a if (k + s) % 2 == 0 else st_b
			var lz := -0.30 + float(s) * 0.30 + _rng.randf_range(-0.06, 0.06)
			lib.box(pan, "流紋_%d" % s,
				Vector3(0.012, _rng.randf_range(1.15, 1.55), _rng.randf_range(0.035, 0.07)),
				mzt, Vector3(0.03, 0.92 + _rng.randf_range(-0.1, 0.1), lz))
		zc += 0.94
	_collide(sg, Vector3(0.5, 1.8, 5.7), Vector3(0, 0, 0.35))


# ── 書本微光：一樓超現實強度的**唯一**載體。冷白、極淡 ——
# 幾乎要仔細看才會注意到（跟三樓將來的琥珀白裂縫刻意分開兩種語言）。──
func _build_books() -> void:
	var g := lib.add(_root, Node3D.new(), "書")
	var dark := _m_dark()
	# 床脇：違い棚（兩層錯開的板）
	var x0 := -2.35
	var x1 := -0.95
	lib.box(g, "違い棚下", Vector3(1.05, 0.05, 0.50), _m_planks(), Vector3(x0 + 0.55, 0.72, -6.75))
	lib.box(g, "違い棚上", Vector3(1.05, 0.05, 0.50), _m_planks(), Vector3(x1 - 0.50, 1.18, -6.75))
	lib.box(g, "海老束", Vector3(0.06, 0.46, 0.06), dark, Vector3((x0 + x1) * 0.5, 0.95, -6.75))
	# 書冊：和綴じの本，一疊一疊。書口（頁緣）那一條帶極淡的冷白微光。
	var cover_a := lib.pbr("書皮藍", "tatami", 2.2, Color(0.30, 0.34, 0.44))
	var cover_b := lib.pbr("書皮茶", "tatami", 2.2, Color(0.42, 0.36, 0.28))
	# ⚠ 第一版 emission 0.36 —— 暗室裡是一排白燈管，超現實強度直接爆表。
	# 「幾乎需要仔細看才會注意到」= 亮度只比周圍紙面高一階。
	var pages := lib.flat_mat("書口微光", Color(0.74, 0.78, 0.84), 0.6,
		Color(0.075, 0.095, 0.13))
	var spots := [
		[x0 + 0.50, 0.745, -6.72, 4], [x1 - 0.55, 1.205, -6.72, 3],
		[x0 + 0.52, 0.02, -6.60, 5],
	]
	var bi := 0
	for sp in spots:
		var n: int = int(sp[3])
		for k in n:
			var y: float = float(sp[1]) + 0.033 + float(k) * 0.062
			var jx := _rng.randf_range(-0.03, 0.03)
			var rot := _rng.randf_range(-0.10, 0.10)
			var bk := lib.add(g, Node3D.new(), "書_%d" % bi)
			bk.position = Vector3(float(sp[0]) + jx, y, float(sp[2]))
			bk.rotation.y = rot
			lib.box(bk, "皮", Vector3(0.26, 0.055, 0.34),
				cover_a if bi % 2 == 0 else cover_b, Vector3.ZERO)
			# 書口：只露 0.012 的一條 —— 微光的載體，遠看只是書緣比較亮
			lib.box(bk, "口", Vector3(0.24, 0.012, 0.335), pages, Vector3(0.0, -0.018, 0.004))
			bi += 1
	# 矮桌上攤開的一卷（阿求家總有讀到一半的東西）
	var open_scroll := lib.add(_root.get_node("家具/矮桌"), Node3D.new(), "攤開的卷")
	open_scroll.position = Vector3(0.55, 0.305, -0.2)
	open_scroll.rotation.y = -0.35
	lib.box(open_scroll, "紙面", Vector3(0.72, 0.012, 0.30), pages, Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		lib.cyl(open_scroll, "軸_%d" % int(sx + 1.0), 0.028, 0.028, 0.34, dark,
			Vector3(sx * 0.38, 0.01, 0), 8)
	open_scroll.get_node("軸_0").rotation.x = PI * 0.5
	open_scroll.get_node("軸_2").rotation.x = PI * 0.5


# ── 箱階段：通往二層的暗示（蓋著，還上不去 —— 二層是下一輪）──
func _build_stairs() -> void:
	var g := lib.add(_root, Node3D.new(), "箱階段")
	g.position = Vector3(-9.85, 0, -5.9)
	var wood := lib.pbr("階段箱", "planks", 0.6, Color(0.54, 0.47, 0.37))
	for k in 6:
		lib.box(g, "段_%d" % k, Vector3(0.42, 0.34 * float(k + 1), 1.05), wood,
			Vector3(1.05 - float(k) * 0.42, 0.17 * float(k + 1), 0))
	lib.box(g, "側板", Vector3(2.60, 2.04, 0.05), wood, Vector3(0, 1.02, 0.55))
	# 天井的口：一圈框 + 蓋板（暗示上面有樓，現在是關的）
	lib.box(g, "口框", Vector3(2.2, 0.10, 1.2), _m_dark(), Vector3(-0.4, CEIL_H - 0.05, 0))
	_collide(g, Vector3(2.7, 2.1, 1.15), Vector3(0, 0, 0))


# ── 光：金白色的光束（帶狀障子 → 斜落到疊上）＋補光 ──
# 「誇張天花高度靠縱向線條」：光束是斜的縱線，也算構圖的一員。
# ⚠ 體積霧在 Compatibility 渲染器不生效（截圖都走 opengl3）——
# 光束用半透明斜柱做，不靠 volumetric fog。
func _build_light() -> void:
	var g := lib.add(_root, Node3D.new(), "光")
	# 光束：三道，從西側障子帶斜落。兩層嵌套（寬的淡、窄的稍亮）做柔邊。
	for i in 3:
		var bx: float = [-9.4, -6.6, -4.0][i]
		var beam := lib.add(g, Node3D.new(), "光束_%d" % i)
		beam.position = Vector3(bx, 1.15, 4.9)
		beam.rotation.x = -0.385
		for layer in 2:
			var mi := MeshInstance3D.new()
			var m := BoxMesh.new()
			m.size = Vector3(1.5 - float(layer) * 0.7, 0.03 + float(layer) * 0.015, 4.6)
			var mat := StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(1.0, 0.94, 0.80, 0.075 + float(layer) * 0.05)
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.material = mat
			mi.mesh = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lib.add(beam, mi, "層_%d" % layer)
	# 聚光：跟光束同位，把疊上照出一塊暖斑（光束的「落點」要真的亮）
	for i in 3:
		var bx2: float = [-9.4, -6.6, -4.0][i]
		var sp := SpotLight3D.new()
		sp.position = Vector3(bx2, 2.1, 6.7)
		sp.rotation.x = -0.30
		sp.light_color = Color(1.0, 0.90, 0.72)
		sp.light_energy = 2.3
		sp.spot_range = 10.5
		sp.spot_angle = 30.0
		sp.shadow_enabled = false
		lib.add(g, sp, "聚光_%d" % i)
	# 土間口的天光（門開著，外面亮）
	var dl := OmniLight3D.new()
	dl.position = Vector3(0, 2.2, 6.2)
	dl.light_color = Color(1.0, 0.95, 0.86)
	dl.light_energy = 1.1
	dl.omni_range = 6.0
	dl.shadow_enabled = false
	lib.add(g, dl, "門口光")


# ── 假窗：前庭的縮小版布景。只對角度與高度，不比照完整精度。──
func _build_garden_backdrop() -> void:
	var g := lib.add(_root, Node3D.new(), "假窗前庭")
	# 地面 + 參道（從門口三段石階下去）
	# ⚠ 草貼圖攤在 44m 的單一面上會拉伸成蜂窩紋（BoxMesh 的 UV 是 0..1
	# 鋪滿一面）。布景地面用素色最誠實。
	lib.box(g, "庭地", Vector3(44.0, 0.2, 16.5),
		lib.flat_mat("庭地素", Color(0.47, 0.53, 0.40), 0.95),
		Vector3(0, -0.85, HD + 8.35))
	for k in 3:
		lib.box(g, "階_%d" % k, Vector3(5.8, 0.15, 0.34),
			lib.pbr("階石", "stone_wall", 0.4, Color(0.72, 0.72, 0.68)),
			Vector3(0, DOMA_Y - 0.075 - 0.15 * float(k), HD + 0.30 + 0.34 * float(k)))
	lib.box(g, "參道", Vector3(3.6, 0.16, 14.0),
		lib.pbr("參道石", "stone_flag", 0.5, Color(0.80, 0.79, 0.74)),
		Vector3(0, -0.76, HD + 8.6))
	# ⚠ 串接後假窗改對「真正的室外」：這扇門通往 village 圖的稗田邸院落
	# （庭池在門外左前方、紅葉群在西、表門是藥醫門）—— 原本畫的是獨立版
	# 前庭的狛犬/參道，玩家走出門看到的卻是院落，迴圈就穿幫了。
	# 庭池（面向 +z 時 +x 在左手邊 = 世界東側，對上 village 的池位）
	lib.cyl(g, "庭池面", 4.0, 4.0, 0.05,
		lib.flat_mat("假窗池水", Color(0.30, 0.42, 0.42), 0.25),
		Vector3(3.4, -0.72, HD + 9.6), 18)
	for k in 4:
		var rk := MeshInstance3D.new()
		rk.mesh = lib.blob_mesh(211 + k * 13, 0.5, 0.25)
		rk.material_override = lib.pbr("假窗岸石", "stone_wall", 0.85, Color(0.48, 0.47, 0.44))
		var a := float(k) / 4.0 * TAU + 0.9
		rk.position = Vector3(3.4 + cos(a) * 4.1, -0.7, HD + 9.6 + sin(a) * 3.9)
		rk.scale = Vector3.ONE * _rng.randf_range(0.45, 0.8)
		lib.add(g, rk, "假窗岸石_%d" % k)
	# 春日燈籠一座（池畔 —— village 院落的那座）
	var lt := MeshInstance3D.new()
	lt.mesh = lib.prop_mesh("res://assets/models/stone_lantern.glb")
	lt.position = Vector3(7.6, -0.75, HD + 8.2)
	lt.scale = Vector3.ONE * 0.85
	lib.add(g, lt, "燈籠")
	# 築地塀一線（門兩側 —— 院落的圍牆；表門剪影在牆中央的缺口上）
	for sxw in [-1.0, 1.0]:
		lib.box(g, "假窗塀_%d" % int(sxw + 1.0), Vector3(14.0, 2.6, 0.5),
			lib.pbr("假窗塀壁", "plaster", 1.2, Color(0.80, 0.76, 0.66)),
			Vector3(sxw * 11.0, 0.55, HD + 13.4))
		lib.box(g, "假窗塀瓦_%d" % int(sxw + 1.0), Vector3(14.2, 0.22, 0.7),
			lib.pbr("假窗塀頂", "roof_kawara", 0.3, Color(0.60, 0.66, 0.78)),
			Vector3(sxw * 11.0, 1.95, HD + 13.4))
	# 表門的剪影（遠端收束）
	var dark := _m_dark()
	for sx in [-1.0, 1.0]:
		lib.box(g, "門柱_%d" % int(sx + 1.0), Vector3(0.5, 4.0, 0.5), dark,
			Vector3(sx * 3.4, 1.15, HD + 13.6))
	lib.box(g, "門樑", Vector3(7.6, 0.4, 0.6), dark, Vector3(0, 3.05, HD + 13.6))
	lib.box(g, "門屋根", Vector3(8.8, 0.25, 2.1),
		lib.pbr("門瓦遠", "roof_kawara", 0.3, Color(0.55, 0.62, 0.74)),
		Vector3(0, 3.5, HD + 13.6))
	# 兩側的樹：blob 版是「綠氣球」（光滑封閉曲面不帶資訊 —— 這專案
	# 自己抓過三次的病）。改放真的樹資產，遠、少、剪影對就好。
	for k in 4:
		var t := MeshInstance3D.new()
		t.mesh = lib.tree_mesh("res://assets/models/tree_round_a.glb")
		# 紅葉群在村圖院落的西側 —— 面向 +z 時是右手邊（-x）
		var sx2 := -1.0 if k < 3 else 1.0
		t.position = Vector3(sx2 * _rng.randf_range(7.5, 13.0), -0.8,
			HD + _rng.randf_range(8.5, 12.5))
		t.scale = Vector3.ONE * _rng.randf_range(1.0, 1.35)
		t.rotation.y = _rng.randf_range(0.0, TAU)
		lib.add(g, t, "庭樹_%d" % k)
	# 背板：遠山一條 + 天空一片（unshaded，只透過 5.8m 的門洞看）
	var hills := StandardMaterial3D.new()
	hills.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hills.albedo_color = Color(0.60, 0.66, 0.58)
	var hb := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(46.0, 3.4, 0.1)
	hm.material = hills
	hb.mesh = hm
	hb.position = Vector3(0, 0.8, HD + 15.9)
	lib.add(g, hb, "遠山")
	var skym := StandardMaterial3D.new()
	skym.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skym.albedo_color = Color(0.90, 0.89, 0.83)
	var sb := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(46.0, 12.0, 0.1)
	sm.material = skym
	sb.mesh = sm
	sb.position = Vector3(0, 7.4, HD + 16.0)
	lib.add(g, sb, "天空板")


# ── 氛圍：室內自己的 WorldEnvironment（暗、暖，glow 給障子與微光用）──
func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.040, 0.034)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.88, 0.72)
	env.ambient_light_energy = 0.80
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.tonemap_white = 4.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.05
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.05
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	lib.add(_root, we, "WorldEnvironment")


func _write_meta() -> void:
	var meta := {
		"id": MAP_ID,
		"note": "稗田邸一樓（玄関/客間）—— 傳送場景。外殼照凍結的外觀量體"
			+ "（25.48×14.56、淨高 3.90、障子帶 1.18→2.32 朝前庭 +z）。"
			+ "玄関 portal ↔ village（人間之里的稗田邸院落）；階段口 → hieda2f。"
			+ "不進 mapRegistry：這是建築內部，不是世界圖上的一格。",
		"playSize": [26, 16],
		"safe": true,
		"connections": [],
		# 串接（2026-08-07）：室外 = village 圖裡的稗田邸院落（獨立室外圖
		# 仍未建）。玄関 portal ↔ village 的玄関前 portal；階段口 → 2F。
		"portals": [
			{"x": 0.0, "y": DOMA_Y, "z": 6.2, "target": "village"},
			{"x": -8.2, "y": 0.0, "z": -4.9, "target": "hieda2f"},
		],
		"colliders": [],
	}
	var f := FileAccess.open("res://data/%s.meta.json" % MAP_ID, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, " "))
	f.close()
	print("wrote data/%s.meta.json" % MAP_ID)
