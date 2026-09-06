@tool
extends MeshInstance3D

## 岸壁水位痕 —— 石岸臨水面的吃水帶（濕石＋藻線）。
##
## 為什麼存在：現況石岸從壓頂到水面是同一份乾材質，水面與牆面以一條
## 幾何硬線相接。真實護岸最強的一條視覺訊息就是【吃水線】——線以下
## 長期泡水，顏色深、濕、長藻；線以上乾燥泛白。少了它，河讀起來沒有
## 水位，也就沒有深度，看起來像「水貼在牆上」。
##
## 這是這一輪最便宜、最有感的一項：不動任何既有幾何，只在牆面前方
## 1.2cm 生成一片貼皮，用頂點色做三段漸層：
##   底  y = 水面 - wet_drop   濕石（深、暗）
##   中  y = 水面 + 0.02       藻線（最濃，帶綠）
##   頂  y = 水面 + dry_fade   完全透明，淡出到乾燥牆面
##
## 材質是 vertex_color_use_as_albedo 的透明材質，所以顏色與透明度
## 全部由這裡的頂點色決定，不需要另外做貼圖。
##
## 上下游水位不同（分水堰 z=23.35 為界：上游 0.72、下游 0.09），
## 帶子跟著各段所在的水位走 —— 這也是「堰真的有落差」的證據。
##
## @tool script：改任一 @export 觸發 setter 重建。
## 注意：MCP 掛上腳本時 _ready 不會觸發，需設一次 @export 踢它一下。

const MAT := "res://assets/materials/bank_waterline.tres"

const BANK_FACE_X := -5.0416          # 石岸臨水面外緣（實測 AABB）
const WEIR_Z := 23.35
const Y_UPPER := 0.72
const Y_LOWER := 0.09

## 五段石岸的 z 範圍（與 bank_talus.gd / take_fence.gd 一致）
const SEGMENTS: Array[Vector2] = [
	Vector2(-74.0, -43.14),
	Vector2(-38.0, -17.14),
	Vector2(-2.5, 18.36),
	Vector2(29.14, 40.0),
	Vector2(45.14, 86.0),
]

## 往河心推出多少，避免與牆面 z-fighting
@export var offset: float = 0.012:
	set(v):
		offset = clampf(v, 0.001, 0.2)
		if is_inside_tree():
			_build()

## 吃水帶往下延伸多深
@export var wet_drop: float = 0.5:
	set(v):
		wet_drop = clampf(v, 0.05, 2.0)
		if is_inside_tree():
			_build()

## 水位線以上淡出到乾燥牆面的高度
@export var dry_fade: float = 0.22:
	set(v):
		dry_fade = clampf(v, 0.02, 1.0)
		if is_inside_tree():
			_build()

## 沿 z 的取樣格距 —— 頂點色沿長度有微擾，格距太大會看不出來
@export var cell: float = 1.0:
	set(v):
		cell = clampf(v, 0.2, 5.0)
		if is_inside_tree():
			_build()

## 水位高低的隨機起伏（公尺）—— 真實水痕不是一條完美水平線
@export var jitter: float = 0.045:
	set(v):
		jitter = clampf(v, 0.0, 0.3)
		if is_inside_tree():
			_build()

@export var rng_seed: int = 4471:
	set(v):
		rng_seed = v
		if is_inside_tree():
			_build()


func _ready() -> void:
	_build()


func _build() -> void:
	# 反序列化期間 @export 逐一賦值，setter 會在其他欄位就位前觸發
	if wet_drop <= 0.0 or dry_fade <= 0.0 or cell <= 0.0:
		return

	var mat := load(MAT) as Material
	if mat == null:
		push_error("[waterline] 取不到材質：%s" % MAT)
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var x: float = BANK_FACE_X + offset
	var total := 0

	for seg in SEGMENTS:
		var n := maxi(2, ceili((seg.y - seg.x) / cell))
		var prev_z: float = seg.x
		var prev_wl: float = _waterline(prev_z, rng)
		for k in range(1, n + 1):
			var z: float = lerpf(seg.x, seg.y, float(k) / float(n))
			var wl: float = _waterline(z, rng)
			_strip(st, x, prev_z, prev_wl, z, wl)
			prev_z = z
			prev_wl = wl
			total += 1

	mesh = st.commit()
	material_override = mat
	print("[waterline] %d 段吃水帶，深 %.2fm、淡出 %.2fm" % [total, wet_drop, dry_fade])


func _waterline(z: float, rng: RandomNumberGenerator) -> float:
	var base: float = Y_UPPER if z > WEIR_Z else Y_LOWER
	# 沿長度的緩慢起伏（不是逐點亂跳）＋ 一點細碎雜訊
	return base + sin(z * 0.21) * jitter + rng.randf_range(-jitter, jitter) * 0.35


## 三列頂點的帶狀：濕石 → 藻線 → 淡出
func _strip(st: SurfaceTool, x: float, z0: float, wl0: float,
		z1: float, wl1: float) -> void:
	var rows: Array[float] = [-wet_drop, 0.02, dry_fade]
	var cols: Array[Color] = [
		Color(0.10, 0.12, 0.11, 0.72),   # 濕石：暗、微綠
		Color(0.13, 0.19, 0.11, 0.88),   # 藻線：最濃
		Color(0.30, 0.34, 0.26, 0.0),    # 淡出
	]
	for r in 2:
		var ya0: float = wl0 + rows[r]
		var ya1: float = wl0 + rows[r + 1]
		var yb0: float = wl1 + rows[r]
		var yb1: float = wl1 + rows[r + 1]
		var ca: Color = cols[r]
		var cb: Color = cols[r + 1]
		_v(st, x, ya0, z0, ca)
		_v(st, x, ya1, z0, cb)
		_v(st, x, yb1, z1, cb)
		_v(st, x, ya0, z0, ca)
		_v(st, x, yb1, z1, cb)
		_v(st, x, yb0, z1, ca)


func _v(st: SurfaceTool, x: float, y: float, z: float, c: Color) -> void:
	st.set_normal(Vector3.RIGHT)
	st.set_uv(Vector2(z * 0.3, y))
	st.set_color(c)
	st.add_vertex(Vector3(x, y, z))
