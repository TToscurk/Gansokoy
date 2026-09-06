@tool
extends MultiMeshInstance3D

## 場景外圍植生帶 —— 用樹林把原型的硬切邊界收掉。
##
## 為什麼存在：50m 審查的失敗點是「原型只有 76m 河段與地台，四周
## 憑空切斷」。樹林不解決地形問題，但它遮住視線盡頭，讓邊界讀起來
## 像「村子的外圍」而不是「模型的邊緣」。
##
## 為什麼是 MultiMesh：外圍樹是純密度層，數量會隨審查反覆調整。
## 獨立節點的話每棵 3-4 條 MCP 指令，改一次密度就要重來。
##
## ── scale 語意（2026-09-01 修正，別再改回去）────────────────
## 舊版用 `scale_base` 當「樹高」，那是針對 Meshy 的 普通樹.glb ——
## 那顆模型本地高度正好 1.0m，所以 scale 數值恰巧等於公尺數。
## 換成 Quaternius MegaKit 後這個等式不成立了，但 scale_base 沒跟著
## 改，結果 TwistedTree_3（本地 16.07m）× 18 = 289m，比玉山還高，
## 在 5m 審查圖裡變成右下角一坨「黃綠色半透明多面體」。
##
## 現在改成 `target_height`：直接寫「我要幾公尺高的樹」，
## scale = target_height / 本地高度，由腳本自己算。
## 換資產、換來源都不會再錯，也不必記得哪個模型本地高多少。
##
## 本地高度實測（Blender 直讀頂點，2026-09-01）：
##   CommonTree_1  7.26   CommonTree_4  9.44
##   Pine_2        7.38   TwistedTree_3 16.07
## Quaternius 資產原點在【底部】，與 Meshy（幾何中心）相反 ——
## 但本腳本用 mesh AABB 動態取底部值，不依賴這個假設。

## 可用樹種，隨機挑選製造混生林。
## Quaternius Stylized Nature MegaKit（CC0）—— 本身就是真實尺度。
const TREE_PATHS: Array[String] = [
	"res://assets/nature/CommonTree_1.gltf",
	"res://assets/nature/Pine_2.gltf",
	"res://assets/nature/TwistedTree_3.gltf",
	"res://assets/nature/CommonTree_4.gltf",
]

## 這個 MultiMesh 只吃一種 mesh —— 混生林靠多個節點各自負責一種樹。
@export var tree_index: int = 0:
	set(v):
		tree_index = clampi(v, 0, TREE_PATHS.size() - 1)
		_build()

const GROUND_TOP := 3.0               # 地台頂高

## 種植帶：沿場景四周，**退縮**離開渠道、水田與町家街。
## 每組 = (x起, z起, x寬, z深)，樹在此矩形內成簇散布。
##
## 退縮很重要，而且有兩次教訓：
##
##   一、先前村南／村北帶延伸到 x=-8，正好壓在石岸（x -7.6~-5.0）
##       上，樹幹擋滿岸線、把水車與町家切成剪影。
##
##   二、退到 x=-26 之後仍然錯 —— 那個值是照「石岸外 15m」算的，
##       完全沒把 B1 町家街算進去。町家群實際佔 x -62.3~-11.9，
##       村側南／北帶各有 436m² 疊在建築上，樹直接長在屋頂上。
##       量測依據：b1_street.tscn 的 68 個 transform + 父節點位移。
##
## 現在的內緣（2026-09-01 修正，改動前先重量建築範圍）：
##   村側外緣 x = -66（町家西緣 -62.3 再退 3.7m）
##   田側內緣 x = 60（水田東緣 56 之外）
##   南北帶只在建築群 z 範圍（-72.7~85）之外
## 地台已放大到 x -72~-6 / z -82~94，樹帶對齊這個新邊界。
const BANDS: Array[Rect2] = [
	Rect2(-108.0, -96.0, 42.0, 204.0),  # 村側西緣（外圍屏障，內緣 -66）
	Rect2(-108.0, -96.0, 96.0, 14.0),   # 村側南緣（z 內緣 -82，建築南端 -72.7 之外）
	Rect2(-108.0, 96.0, 96.0, 14.0),    # 村側北緣（z 內緣 96，建築北端 85 之外）
	Rect2(60.0, -96.0, 18.0, 204.0),    # 田側東緣
	Rect2(14.0, -96.0, 46.0, 13.0),     # 田側南緣
	Rect2(14.0, 97.0, 46.0, 13.0),      # 田側北緣
]

## 視廊：這些矩形內不種樹，保留看向主體的視線走廊。
## 對著水車（z≈20）、親水開口（z≈-10）各留一條，往西貫穿整條村側樹帶。
const CLEARINGS: Array[Rect2] = [
	Rect2(-108.0, 12.0, 60.0, 16.0),    # 村側：看向水車的橫向視廊
	Rect2(-108.0, -18.0, 60.0, 14.0),   # 村側：看向親水開口
]

@export var density: float = 0.022:   # 每平方公尺【樹】數（不是簇心數）
	set(v):
		density = maxf(v, 0.0)
		_build()

## 成簇：每個簇心周圍再長 N-1 棵，半徑內隨機。
## 均勻隨機散布出來是「點綴」不是「林」—— 真實林相是成簇的，
## 而屏障效果來自簇內重疊的樹冠，不是總株數。
@export var clump_size: int = 4:
	set(v):
		clump_size = maxi(v, 1)
		_build()

@export var clump_radius: float = 3.5:
	set(v):
		clump_radius = maxf(v, 0.1)
		_build()

## 目標樹高（公尺）—— 這是「我要多高的樹」，不是縮放倍率。
## 屋脊 12m，外圍林略高於屋脊、不壓過地標即可，預設 14m。
@export var target_height: float = 14.0:
	set(v):
		target_height = maxf(v, 0.1)
		_build()

@export var scale_jitter: float = 0.35:
	set(v):
		scale_jitter = clampf(v, 0.0, 0.9)
		_build()

@export var rng_seed: int = 4471:
	set(v):
		rng_seed = v
		_build()

func _ready() -> void:
	_build()

func _build() -> void:
	# 節點反序列化期間 @export 是逐一賦值的，setter 會在其他欄位就位前
	# 就被觸發。新增 @export 到既有節點時尤其會撞到（舊 .tscn 沒有該欄位，
	# 值停在型別預設 0）。用 0 當哨兵擋掉這些半成品狀態。
	if clump_size <= 0 or clump_radius <= 0.0 or density <= 0.0:
		return
	if target_height <= 0.0:
		return

	var mesh := _first_mesh(TREE_PATHS[tree_index])
	if mesh == null:
		push_error("[grove] 取不到 mesh：%s" % TREE_PATHS[tree_index])
		return

	var aabb := mesh.get_aabb()
	var local_bottom := aabb.position.y
	var local_height := aabb.size.y
	if local_height <= 0.001:
		push_error("[grove] mesh 高度為 0：%s" % TREE_PATHS[tree_index])
		return

	# 目標高度 → 縮放倍率。這一行就是本次修正的全部重點。
	var base_scale := target_height / local_height

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed + tree_index * 977    # 每種樹用不同序列，避免重疊

	# 先收集位置，才知道 instance_count。簇心均勻散，簇內圍繞簇心。
	var spots: Array[Vector3] = []
	for band in BANDS:
		# density 是「樹/m²」，先換算成這個節點該負責的樹數
		# （4 個節點各負責一種樹，所以除以樹種數），再換算成簇心數。
		#
		# 用 roundi 不用 int()：int() 是無條件捨去，小帶（696m²）
		# 算出 0.70 個簇心會被歸零，六條帶有四條完全不長樹。
		var trees_here: float = band.size.x * band.size.y * density \
				/ float(TREE_PATHS.size())
		var clumps := maxi(1, roundi(trees_here / float(clump_size)))
		for k in clumps:
			var cx := rng.randf_range(band.position.x, band.position.x + band.size.x)
			var cz := rng.randf_range(band.position.y, band.position.y + band.size.y)
			if _in_clearing(cx, cz):
				continue
			# 簇的大小也隨機，避免每叢都恰好 clump_size 棵
			var n := rng.randi_range(maxi(1, clump_size - 2), clump_size + 2)
			for j in n:
				var ang := rng.randf_range(0.0, TAU)
				# sqrt 讓簇內分布均勻而非集中在圓心
				var r := clump_radius * sqrt(rng.randf())
				var px := cx + cos(ang) * r
				var pz := cz + sin(ang) * r
				if _in_clearing(px, pz):
					continue
				spots.append(Vector3(px, 0.0, pz))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size()

	for i in spots.size():
		var s: float = base_scale * rng.randf_range(
				1.0 - scale_jitter, 1.0 + scale_jitter)
		# 底部貼地：模型底 × scale 落在 GROUND_TOP
		var y: float = GROUND_TOP - local_bottom * s
		# 隨機 Y 轉 + 微幅傾斜 —— 全部筆直會讓樹幹排成柵欄
		var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		b = b.rotated(Vector3.RIGHT, rng.randf_range(-0.06, 0.06))
		b = b.rotated(Vector3.FORWARD, rng.randf_range(-0.06, 0.06))
		mm.set_instance_transform(i,
				Transform3D(b.scaled(Vector3(s, s, s)),
						Vector3(spots[i].x, y, spots[i].z)))

	multimesh = mm
	print("[grove] %s：%d 棵，本地高 %.2fm ×%.3f → %.1fm，密度 %.3f/m²"
			% [TREE_PATHS[tree_index].get_file(), spots.size(),
			   local_height, base_scale, target_height, density])


## 視廊內不種樹 —— 保留看向水車、親水開口等主體的視線走廊。
func _in_clearing(x: float, z: float) -> bool:
	for c in CLEARINGS:
		if x >= c.position.x and x <= c.position.x + c.size.x \
				and z >= c.position.y and z <= c.position.y + c.size.y:
			return true
	return false


## 從 GLB 場景取第一個 Mesh —— 不寫死 ::ArrayMesh_xxxx 的內部 id，
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
