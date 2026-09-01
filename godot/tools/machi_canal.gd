@tool
extends Node3D

## 町中水路（用水堀）—— 三級退台護岸的參數化斷面。
##
## 依 docs/reference/人間之里概念圖/新版水護岸概念圖.png 判讀：
## 村側（左岸）是「牆—平台—牆—平台」的多級退台，每一階對應一個水位；
## 田側（右岸）是緩坡＋植生帶，一次緩降。兩岸刻意不對稱。
##
## 為什麼用程式生斷面而不是擺模型：退台的每一階高度、進深、收分都還在
## 校調中，尺寸一改就要重擺一次。斷面用參數描述，改一個數字整段重生。
## 這是 blockout 階段的做法 —— 定案後才換成真正的砌石模型。
##
## 座標系：渠心 x=0，水流沿 ±z。x 負向 = 村側，x 正向 = 田側。
## 常水位 y=0（世界座標由父節點位移決定）。

## ── 村側退台（由水面往上）──────────────────────────
## 每階 = (頂面高程, 平台進深)。牆高由相鄰兩階的高程差算出。
## 概念圖判讀值：P1 +0.40/1.35、P2 +1.50/2.25、P3 +3.00/2.75、P4 +5.00/4.00
@export var terraces: Array[Vector2] = [
	Vector2(0.40, 1.35),   # P1 洗滌／取水台（常淹沒層）
	Vector2(1.50, 2.25),   # P2 親水平台（豐水位淹沒）
	Vector2(3.00, 2.75),   # P3 中段步道（洩水孔集中段）
	Vector2(5.00, 4.00),   # P4 街道／護岸頂
]:
	set(v):
		terraces = v
		_rebuild()

## 塊石乾砌的收分（法勾配）：每高 1m 內收多少。概念圖判讀 1:0.3。
@export var batter: float = 0.3:
	set(v):
		batter = maxf(v, 0.0)
		_rebuild()

## 常水位水面半寬。概念圖《俯視》說町中水路 4–6m 寬；
## 《護岸》渲染圖看起來 10–14m。兩者矛盾，此處參數化待裁決。
@export var water_half: float = 3.0:
	set(v):
		water_half = maxf(v, 0.5)
		_rebuild()

## 渠床深度（常水位往下）
@export var bed_depth: float = 0.9:
	set(v):
		bed_depth = maxf(v, 0.1)
		_rebuild()

## 田側緩坡：(頂面高程, 水平進深)。概念圖：低於村側，一次緩降。
@export var field_bank: Vector2 = Vector2(1.8, 5.5):
	set(v):
		field_bank = v
		_rebuild()

## 樣板段長度（沿 z）
@export var length: float = 20.0:
	set(v):
		length = maxf(v, 1.0)
		_rebuild()

@export var rebuild: bool = false:
	set(_v):
		rebuild = false
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	# 反序列化期間 @export 逐一賦值，setter 可能在其他欄位就位前觸發
	if terraces == null or terraces.is_empty() or water_half <= 0.0:
		return

	for c in get_children():
		c.free()

	var profile := _build_profile()
	var mesh := _extrude(profile, length)

	var mi := MeshInstance3D.new()
	mi.name = "CanalSection"
	mi.mesh = mesh
	add_child(mi)
	if Engine.is_editor_hint() and get_tree() != null:
		mi.owner = get_tree().edited_scene_root

	print("[canal] 斷面 %d 點，村側頂 +%.2fm，水面寬 %.1fm，段長 %.0fm"
			% [profile.size(), terraces[-1].x, water_half * 2.0, length])


## 斷面折線，由田側外緣 → 渠床 → 村側外緣（x 由正到負）。
## 回傳 Vector2 陣列，x = 橫向、y = 高程。
func _build_profile() -> PackedVector2Array:
	var pts := PackedVector2Array()

	# ── 田側（x 正向）：外緣 → 緩坡 → 水際 ──
	var fb_top: float = field_bank.x
	var fb_run: float = field_bank.y
	pts.append(Vector2(water_half + fb_run + 3.0, fb_top))   # 田面外延
	pts.append(Vector2(water_half + fb_run, fb_top))         # 坡頂
	pts.append(Vector2(water_half, 0.0))                     # 水際（緩坡入水）

	# ── 渠床 ──
	pts.append(Vector2(water_half - 0.4, -bed_depth))
	pts.append(Vector2(-water_half + 0.4, -bed_depth))

	# ── 村側（x 負向）：水際 → 逐級退台 ──
	# 每一級：先垂直（帶收分）爬牆到該階高程，再往內走平台進深。
	var x: float = -water_half
	var y: float = -bed_depth
	pts.append(Vector2(x, y))

	for t in terraces:
		var top: float = t.x
		var depth: float = t.y
		var rise: float = top - y
		if rise <= 0.0:
			continue
		# 牆面帶收分：往內傾 batter × 高度
		x -= rise * batter
		y = top
		pts.append(Vector2(x, y))     # 牆頂
		x -= depth
		pts.append(Vector2(x, y))     # 平台內緣

	# 護岸頂再往村內延伸，接街道地面
	pts.append(Vector2(x - 3.0, terraces[-1].x))

	return pts


## 把斷面折線沿 z 擠出成 mesh。兩端封口，方便樣板段單獨審查。
func _extrude(profile: PackedVector2Array, len_z: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var z0: float = -len_z * 0.5
	var z1: float = len_z * 0.5

	# 側面（斷面掃出的帶狀面）
	for i in profile.size() - 1:
		var a := profile[i]
		var b := profile[i + 1]
		var p00 := Vector3(a.x, a.y, z0)
		var p01 := Vector3(a.x, a.y, z1)
		var p10 := Vector3(b.x, b.y, z0)
		var p11 := Vector3(b.x, b.y, z1)
		# 兩個三角形，法線朝上／朝渠內
		st.add_vertex(p00); st.add_vertex(p01); st.add_vertex(p11)
		st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p10)

	st.generate_normals()
	return st.commit()
