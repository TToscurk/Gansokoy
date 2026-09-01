@tool
extends Node3D

## 幹渠水面 —— 帶頂點色的水面網格，餵給 assets/shaders/water.gdshader。
##
## 為什麼要有這支腳本（兩個獨立的錯，疊在一起）：
##
##   一、【中段根本沒有水】
##       舊場景只有兩塊 BoxMesh 水面：
##         UpstreamWater   z +40 → +94
##         DownstreamWater z -82 → -38
##       中間 z -38 → +40 這 78 公尺是空的。而石岸 -74 → +86、
##       水車／分水堰／親水階梯全部落在 z -26 → +24 —— 整段村落臨水面
##       與所有水利設施前面都沒有水，看到的是河床 Bed（river_ishigaki_wet）
##       那顆方塊的頂面。審查判讀「河面極平、沒有波紋、沒有反射」不是
##       材質問題，是那裡本來就不是水。
##
##   二、【BoxMesh 餵不動這個著色器】
##       water.gdshader 靠頂點色運作：COLOR.r = 靠岸程度、COLOR.gb = 流向。
##       BoxMesh 沒有頂點色，COLOR 預設全白 → bank = 1 → 整片被判成岸邊
##       泡沫。著色器自己的註解就寫著這會「看起來像鐵板」。
##
## 所以水面必須是【生成的、帶頂點色的網格】，不能是方塊：
##   COLOR.r  = 岸邊漸層（1 = 貼岸、0 = 河心）→ 深淺色、透明度、泡沫
##   COLOR.gb = 下游方向編碼（0.5 為零點）→ flow-map 捲動方向
##
## 白沫不是另外貼一張圖：堰下與水車尾水把 COLOR.r 拉高，著色器的
## foam 項就會在那裡自己長出來 —— 跟岸邊泡沫同一套邏輯，不會脫節。
##
## 標高鏈（與 ChannelGeometry 既有節點一致，改一處要一起改）：
##   上游水面 0.72 ── 分水堰 z=23.35 ── 下游水面 0.09
##
## @tool script：改任一 @export 觸發 setter 重建。
## 注意：MCP 掛上腳本時 _ready 不會觸發，需設一次 @export 踢它一下。

const MAT_UPPER := "res://assets/materials/canal_water_upper.tres"
const MAT_LOWER := "res://assets/materials/canal_water_lower.tres"

## 通道左右邊界（與 UpstreamWater/DownstreamWater 的 12m 寬一致）
const X_MIN := -6.0
const X_MAX := 6.0

## 分水堰位置 —— 上下游的分界
const WEIR_Z := 23.35

## 水面標高
const Y_UPPER := 0.72                 # 堰上游
const Y_LOWER := 0.09                 # 堰下游

## 通道全長（河道 Bed 是 z -82 → +94）
const Z_SOUTH := -82.0
const Z_NORTH := 94.0

## 水車尾水回流處 —— RaceTailDrop 在 z=18.4，落差 0.46m
const RACE_TAIL_Z := 18.4

## 網格密度：頂點波動與 flow-map 都需要足夠的頂點才看得出來。
## 1.5m 一格 → 全長約 118 段 × 8 格寬，仍是很輕的網格。
@export var cell: float = 1.5:
	set(v):
		cell = clampf(v, 0.4, 6.0)
		if is_inside_tree():
			_rebuild()

## 岸邊漸層帶寬 —— COLOR.r 從 1（貼岸）降到 0 的距離。
## 太窄則泡沫變成一條死線，太寬則整條河都是淺色。
@export var shore_band: float = 2.4:
	set(v):
		shore_band = clampf(v, 0.2, 5.0)
		if is_inside_tree():
			_rebuild()

## 堰下白沫的縱向長度（公尺）
@export var weir_foam_run: float = 7.0:
	set(v):
		weir_foam_run = maxf(v, 0.0)
		if is_inside_tree():
			_rebuild()

## 水車尾水白沫的縱向長度（公尺）
@export var race_foam_run: float = 4.0:
	set(v):
		race_foam_run = maxf(v, 0.0)
		if is_inside_tree():
			_rebuild()

@export var rebuild: bool = false:
	set(_v):
		rebuild = false
		if is_inside_tree():
			_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	# 反序列化期間 @export 逐一賦值，setter 會在其他欄位就位前觸發
	if cell <= 0.0 or shore_band <= 0.0:
		return

	var mat_up := load(MAT_UPPER) as Material
	var mat_lo := load(MAT_LOWER) as Material
	if mat_up == null or mat_lo == null:
		push_error("[canal] 取不到水材質，先確認 assets/materials/canal_water_*.tres")
		return

	# 下游段（含整個村落臨水面 —— 這就是先前缺掉的 78m）
	_reach("Reach_Lower", Z_SOUTH, WEIR_Z, Y_LOWER, mat_lo)
	# 上游段
	_reach("Reach_Upper", WEIR_Z, Z_NORTH, Y_UPPER, mat_up)

	print("[canal] 水面 %.1fm（下游 %.1f→%.1f、上游 %.1f→%.1f），格距 %.2fm"
			% [Z_NORTH - Z_SOUTH, Z_SOUTH, WEIR_Z, WEIR_Z, Z_NORTH, cell])


## 建一段水面。就地更新既有節點 —— 不刪除後同名重建，
## 那會在 free() 與 add_child() 之間撞上 Godot 的名稱雜湊表。
func _reach(node_name: String, z0: float, z1: float, y: float, mat: Material) -> void:
	var mi := get_node_or_null(NodePath(node_name)) as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = node_name
		add_child(mi)
		if Engine.is_editor_hint():
			mi.owner = get_tree().edited_scene_root
	mi.mesh = _build_mesh(z0, z1, y)
	mi.material_override = mat
	mi.position = Vector3.ZERO


func _build_mesh(z0: float, z1: float, y: float) -> ArrayMesh:
	var nx := maxi(2, ceili((X_MAX - X_MIN) / cell))
	var nz := maxi(2, ceili((z1 - z0) / cell))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for j in nz:
		for i in nx:
			var xa: float = lerpf(X_MIN, X_MAX, float(i) / float(nx))
			var xb: float = lerpf(X_MIN, X_MAX, float(i + 1) / float(nx))
			var za: float = lerpf(z0, z1, float(j) / float(nz))
			var zb: float = lerpf(z0, z1, float(j + 1) / float(nz))
			# 逆時針 → 法線朝上（render_mode 是 cull_disabled，但仍要正確）
			_quad(st, y, xa, xb, za, zb)

	st.generate_tangents()
	return st.commit()


func _quad(st: SurfaceTool, y: float, xa: float, xb: float,
		za: float, zb: float) -> void:
	var p00 := Vector3(xa, y, za)
	var p10 := Vector3(xb, y, za)
	var p11 := Vector3(xb, y, zb)
	var p01 := Vector3(xa, y, zb)
	_vert(st, p00)
	_vert(st, p01)
	_vert(st, p11)
	_vert(st, p00)
	_vert(st, p11)
	_vert(st, p10)


func _vert(st: SurfaceTool, p: Vector3) -> void:
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(p.x * 0.25, p.z * 0.25))
	st.set_color(_vertex_colour(p.x, p.z))
	st.add_vertex(p)


## 頂點色 = 著色器的輸入資料。
##   R  靠岸程度：1 貼岸、0 河心。著色器拿它算深淺色、透明度、泡沫。
##   GB 下游方向（0.5 為零點）。這條渠往 -Z 流 → dir(0,-1) → (0.5, 0.0)。
func _vertex_colour(x: float, z: float) -> Color:
	var d: float = minf(x - X_MIN, X_MAX - x)          # 離最近岸的距離
	var bank: float = clampf(1.0 - d / shore_band, 0.0, 1.0)
	bank = bank * bank * (3.0 - 2.0 * bank)            # smoothstep，避免硬邊

	# 堰下跌水的白沫：往下游 weir_foam_run 內把 bank 拉滿，
	# 著色器的 foam 項（smoothstep(0.90,1.0,bank)）就會在那裡自己長出來。
	if weir_foam_run > 0.0:
		var t: float = (WEIR_Z - z) / weir_foam_run
		if t >= 0.0 and t <= 1.0:
			bank = maxf(bank, 1.0 - t * t)

	# 水車尾水回流：範圍只在水車那一側（x < 0），不要糊到整條河寬
	if race_foam_run > 0.0 and x < 0.0:
		var tr2: float = (RACE_TAIL_Z - z) / race_foam_run
		if tr2 >= 0.0 and tr2 <= 1.0:
			var side: float = clampf(-x / 3.0, 0.0, 1.0)
			bank = maxf(bank, (1.0 - tr2 * tr2) * side)

	return Color(clampf(bank, 0.0, 1.0), 0.5, 0.0, 1.0)
