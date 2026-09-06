@tool
extends MultiMeshInstance3D

## 河床水下石 —— 半透明水面底下看得見的東西。
##
## 為什麼存在：河床 Bed 是一顆貼了 river_ishigaki_wet 的 BoxMesh，
## 頂面完全平。水面換成半透明著色器之後，透過水看下去就是一整片
## 均勻色板 —— 水有了透明度卻沒有「底」，反而更假。
##
## 水下石不需要細節，需要的是【深度線索】：大小不一的凸起讓視線
## 有東西可以對焦，水面的折射與深淺色才有參照。
##
## 標高：石頭坐在河床頂 BED_TOP，一律低於水面 —— 露出水面的石頭是
## 另一回事（那要跟流向、白沫一起做），這裡刻意全部沉在水下。
##
## Quaternius nature 資產原點在【底部】（實測自 tools/asset_probe.py），
## 與 Meshy 資產（幾何中心）相反：y = 河床頂 - local_bottom * scale。
##
## @tool script：改任一 @export 觸發 setter 重建。
## 注意：MCP 掛上腳本時 _ready 不會觸發，需設一次 @export 踢它一下。

const ROCK_PATHS: Array[String] = [
	"res://assets/nature/Pebble_Round_1.gltf",
	"res://assets/nature/Pebble_Round_3.gltf",
	"res://assets/nature/Pebble_Square_2.gltf",
	"res://assets/nature/Rock_Medium_1.gltf",
]

## 每種石頭的目標【高度】（公尺）—— 見 bank_talus.gd 的說明：
## 這四件本地尺寸差 24 倍，共用一個縮放倍率會讓 Rock_Medium_1
## 變成比房子還高的巨石。河床石比護腳碎石再小一號。
const ROCK_TARGET: Array[float] = [0.12, 0.17, 0.22, 0.42]

const BED_TOP := -0.225               # 河床頂（Bed: pos.y -0.35 + size.y/2 0.125）
const WEIR_Z := 23.35
const Y_UPPER := 0.72
const Y_LOWER := 0.09

## 河床可鋪範圍（Bed 是 13m 寬、z -82 → +94；留邊避免穿出護岸）
const X_MIN := -4.6
const X_MAX := 5.6
const Z_MIN := -80.0
const Z_MAX := 92.0

## 石頭頂端至少要低於水面這麼多 —— 全部沉在水下
const SUBMERGE_MARGIN := 0.04

@export var variant: int = 0:
	set(v):
		variant = clampi(v, 0, ROCK_PATHS.size() - 1)
		if is_inside_tree():
			_build()

@export var count: int = 150:
	set(v):
		count = clampi(v, 0, 4000)
		if is_inside_tree():
			_build()

@export var size_mult: float = 1.0:
	set(v):
		size_mult = maxf(v, 0.05)
		if is_inside_tree():
			_build()

@export var scale_jitter: float = 0.5:
	set(v):
		scale_jitter = clampf(v, 0.0, 0.9)
		if is_inside_tree():
			_build()

@export var rng_seed: int = 3307:
	set(v):
		rng_seed = v
		if is_inside_tree():
			_build()


func _ready() -> void:
	_build()


func _build() -> void:
	# 反序列化期間 @export 逐一賦值，setter 會在其他欄位就位前觸發
	if count <= 0 or size_mult <= 0.0:
		return

	var mesh := _first_mesh(ROCK_PATHS[variant])
	if mesh == null:
		push_error("[bedstone] 取不到 mesh：%s" % ROCK_PATHS[variant])
		return

	var aabb := mesh.get_aabb()
	var local_bottom := aabb.position.y
	var local_h: float = aabb.size.y
	if local_h <= 0.001:
		push_error("[bedstone] mesh 高度為 0：%s" % ROCK_PATHS[variant])
		return

	var base_scale: float = ROCK_TARGET[variant] * size_mult / local_h

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed + variant * 977

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count

	var placed := 0
	for i in count:
		var x: float = rng.randf_range(X_MIN, X_MAX)
		var z: float = rng.randf_range(Z_MIN, Z_MAX)
		var s: float = base_scale * rng.randf_range(
				1.0 - scale_jitter, 1.0 + scale_jitter)

		# 水位隨堰上下不同；石頭必須整顆沉在水面下。
		var wl: float = Y_UPPER if z > WEIR_Z else Y_LOWER
		var head_room: float = wl - SUBMERGE_MARGIN - BED_TOP
		var h: float = local_h * s
		if h > head_room:
			s *= head_room / h                 # 太高就壓扁到剛好沉沒
		var y: float = BED_TOP - local_bottom * s

		var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		b = b.rotated(Vector3.RIGHT, rng.randf_range(-0.3, 0.3))
		b = b.rotated(Vector3.FORWARD, rng.randf_range(-0.3, 0.3))
		mm.set_instance_transform(i,
				Transform3D(b.scaled(Vector3(s, s, s)), Vector3(x, y, z)))
		placed += 1

	multimesh = mm
	print("[bedstone] %s：%d 顆沉床石"
			% [ROCK_PATHS[variant].get_file(), placed])


## 從 GLB/glTF 場景取第一個 Mesh —— 不寫死 ::ArrayMesh_xxxx 的內部 id，
## 重新匯入資產時那個 id 會變，寫死會在某次 reimport 後靜默失效。
func _first_mesh(path: String) -> Mesh:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate()
	var found := _find_mesh_recursive(inst)
	inst.queue_free()
	return found


func _find_mesh_recursive(node: Node) -> Mesh:
	if node is MeshInstance3D and node.mesh != null:
		return node.mesh
	for child in node.get_children():
		var m := _find_mesh_recursive(child)
		if m != null:
			return m
	return null
