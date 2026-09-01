@tool
extends MultiMeshInstance3D

## 岸頂草皮 —— 讓草越過石岸壓頂垂下，縫合上下兩個平面。
##
## 為什麼存在：50m 審查判定護岸「邊緣沒有攀爬植栽或雜草侵入，上下兩個
## 平面直接以一條線相接」。碎石帶（bank_talus.gd）處理腳部，這支處理
## 頂部 —— 草叢跨在壓頂邊緣上，一半在岸上一半懸出去，那條硬邊就被
## 打斷了。
##
## 也順便鋪在竹垣腳下：真實圍籬底部一定長雜草，那圈草讓竹垣「長在
## 地上」而不是「插在地上」。
##
## 標高／原點（實測自 tools/asset_probe.py）：
##   Quaternius nature 資產原點在【底部】，與 Meshy 資產（幾何中心）相反。
##   放置算式：y = 地面 - local_bottom * scale
##
## @tool script：改任一 @export 觸發 setter 重建。
## 注意：MCP 掛上腳本時 _ready 不會觸發，需設一次 @export 踢它一下。

const PLANT_PATHS: Array[String] = [
	"res://assets/nature/Grass_Common_Short.gltf",
	"res://assets/nature/Grass_Wispy_Short.gltf",
	"res://assets/nature/Clover_1.gltf",
	"res://assets/nature/Fern_1.gltf",
]

const BANK_TOP := 2.955               # 石岸壓頂高度
const COPING_EDGE_X := -5.0416        # 壓頂臨水緣（實測 AABB）

## 三段石岸的 z 範圍（與 take_fence.gd / bank_talus.gd 一致）
## 五段（2026-09-01 擴段）：原本只做 78m，但 B1 町家沿岸 158m，
## 有 79.7m 的建築臨著沒有護岸的裸河。新增南延／北延兩段補齊。
## 段落由「端+N牆+端」模組長度回推，餘量吸收在開口寬度裡。
const SEGMENTS: Array[Vector2] = [
	Vector2(-74.0, -43.14),    # 南延段（端+2牆+端 30.86m）
	Vector2(-38.0, -17.14),    # 南段
	Vector2(-2.5, 18.36),      # 中段
	Vector2(29.14, 40.0),      # 北段（端+端 10.86m）
	Vector2(45.14, 86.0),      # 北延段（端+3牆+端 40.86m）
]

@export var variant: int = 0:
	set(v):
		variant = clampi(v, 0, PLANT_PATHS.size() - 1)
		_build()

@export var count_per_metre: float = 1.6:
	set(v):
		count_per_metre = maxf(v, 0.0)
		_build()

## 草叢分布的 x 範圍：負值往岸內，正值往河心懸出
@export var inset: float = 0.5:       # 往岸內最多多遠
	set(v):
		inset = maxf(v, 0.0)
		_build()

@export var overhang: float = 0.25:   # 越過壓頂緣懸出多遠
	set(v):
		overhang = maxf(v, 0.0)
		_build()

@export var scale_base: float = 0.42: # 草本地高 1.3m，×0.42 ≈ 0.55m
	set(v):
		scale_base = maxf(v, 0.01)
		_build()

@export var scale_jitter: float = 0.4:
	set(v):
		scale_jitter = clampf(v, 0.0, 0.9)
		_build()

@export var rng_seed: int = 3391:
	set(v):
		rng_seed = v
		_build()

func _ready() -> void:
	_build()

func _build() -> void:
	# 反序列化期間 @export 逐一賦值，setter 會在其他欄位就位前觸發
	if count_per_metre <= 0.0 or scale_base <= 0.0:
		return

	var mesh := _first_mesh(PLANT_PATHS[variant])
	if mesh == null:
		push_error("[coping] 取不到 mesh：%s" % PLANT_PATHS[variant])
		return

	var local_bottom := mesh.get_aabb().position.y

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed + variant * 457

	var spots: Array[Vector2] = []
	for seg in SEGMENTS:
		var n := int((seg.y - seg.x) * count_per_metre / PLANT_PATHS.size())
		for k in n:
			var z := rng.randf_range(seg.x, seg.y)
			# 集中在壓頂緣附近：緣內 inset ~ 緣外 overhang
			var x := COPING_EDGE_X + rng.randf_range(-inset, overhang)
			spots.append(Vector2(x, z))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size()

	for i in spots.size():
		var s: float = scale_base * rng.randf_range(
				1.0 - scale_jitter, 1.0 + scale_jitter)
		var y: float = BANK_TOP - local_bottom * s
		# 微幅前傾 —— 懸在邊緣的草會往外倒
		var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		b = b.rotated(Vector3.FORWARD, rng.randf_range(-0.18, 0.18))
		mm.set_instance_transform(i,
				Transform3D(b.scaled(Vector3(s, s, s)),
						Vector3(spots[i].x, y, spots[i].y)))

	multimesh = mm
	print("[coping] %s：%d 叢，實高 %.2fm"
			% [PLANT_PATHS[variant].get_file(), spots.size(),
			   (mesh.get_aabb().size.y) * scale_base])


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
