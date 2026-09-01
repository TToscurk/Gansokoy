@tool
extends MultiMeshInstance3D

## 沿石岸壓頂鋪設竹垣（MultiMesh，一個節點吃下整條岸線）。
##
## 為什麼是 MultiMesh：竹垣是重複的線性圍籬，60 支獨立節點 = 60 個
## draw call，而且每支要 3 條 MCP 指令去擺。MultiMesh 的指令數與支數
## 無關，密度、段落、間距都變成可調參數。
##
## 標高依據（實測自 tools/asset_probe.py，非 AABB 推定）：
##   竹垣本地高度 -0.498 → 0.5（原點在幾何中心）
##   石岸壓頂 2.955；底部貼齊壓頂
##
## 段落與石岸實體一致，開口處必須斷開——竹垣是岸頂圍籬，跨過親水
## 開口就變成把樓梯口封起來。SEGMENTS 直接對應三段石岸的 z 範圍。
##
## @tool script：改任一 @export 觸發 setter 重建。
## 注意：MCP 掛上腳本時 _ready 不會觸發，需設一次 @export 踢它一下。

const SCENE_PATH := "res://assets/landscape/竹垣.glb"

const TAKE_LOCAL_BOTTOM := -0.498     # 模型本地最低點
const BANK_TOP := 2.955               # 石岸壓頂絕對高度
const BANK_X := -5.85                 # 竹垣所在的岸頂 x

## 三段石岸的 z 範圍；開口處留空（親水階梯／濱水平台／水車輪室）
const SEGMENTS: Array[Vector2] = [
	Vector2(-72.60, -44.54),   # 南延段
	Vector2(-36.60, -18.54),   # 南段
	Vector2(-1.10, 16.96),     # 中段
	Vector2(30.54, 38.60),     # 北段
	Vector2(46.54, 84.60),     # 北延段
]

@export var spacing: float = 0.79:
	set(v):
		spacing = maxf(v, 0.05)
		_build()

@export var post_scale: float = 1.2:
	set(v):
		post_scale = v
		_build()

## 每支的 z 抖動與旋轉抖動，破除完美等距的機械感
@export var jitter_z: float = 0.0:
	set(v):
		jitter_z = v
		_build()

@export var jitter_yaw: float = 0.0:
	set(v):
		jitter_yaw = v
		_build()

@export var rng_seed: int = 20260901:
	set(v):
		rng_seed = v
		_build()

func _ready() -> void:
	_build()

func _build() -> void:
	var mesh := _first_mesh()
	if mesh == null:
		push_error("[take] 從 %s 取不到 mesh" % SCENE_PATH)
		return

	# 先數總支數，MultiMesh 需要先知道 instance_count
	var slots: Array[float] = []
	for seg in SEGMENTS:
		var z: float = seg.x
		while z <= seg.y + 0.001:
			slots.append(z)
			z += spacing

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = slots.size()

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	# 底部貼齊壓頂：模型底 × scale 落在 BANK_TOP
	var y: float = BANK_TOP - TAKE_LOCAL_BOTTOM * post_scale

	for i in slots.size():
		var z: float = slots[i] + rng.randf_range(-jitter_z, jitter_z)
		var yaw: float = rng.randf_range(-jitter_yaw, jitter_yaw)
		var b := Basis(Vector3.UP, yaw).scaled(
				Vector3(post_scale, post_scale, post_scale))
		mm.set_instance_transform(i, Transform3D(b, Vector3(BANK_X, y, z)))

	multimesh = mm
	print("[take] 鋪設 %d 支竹垣，%d 段，間距 %.3fm，底 %.3f"
			% [slots.size(), SEGMENTS.size(), spacing, y + TAKE_LOCAL_BOTTOM * post_scale])


## 從 GLB 場景取第一個 Mesh —— 不寫死 ::ArrayMesh_xxxx 的內部 id，
## 重新匯入資產時那個 id 會變，寫死會在某次 reimport 後靜默失效。
func _first_mesh() -> Mesh:
	var packed := load(SCENE_PATH) as PackedScene
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
