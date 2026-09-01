@tool
extends Node3D

## 稻作株 —— 獨立節點，按格分組。
##
## 為什麼是獨立節點而不是 MultiMesh（2026-09-01 使用者裁決）：
##   我先前用 MultiMesh 的理由是「稻叢是密度層」「省指令數／token」。
##   使用者的回覆：「144 條指令會消耗很多 token 是嘛 …… 我現在想說
##   這完全不用省」，並要求稻草也改成節點。
##
##   MultiMesh 剝奪的是編輯能力，不是效能：
##     在編輯器裡選一叢稻      → 選不到（整個 MM 是一個節點）
##     拔掉擋路的那一叢        → 做不到
##     某格插秧、某格已收割    → 做不到（共用同一個 mesh）
##     手動微調某叢的角度大小  → 做不到
##
##   節點結構：PaddyRice / 格_00 / 稻_0 .. 稻_8
##   選整格就點「格_ij」，選單叢就點「稻_k」。
##
## 【重要】稻作株.glb 自帶一塊 1×1 方形底座地磚（頂點量測）：
##   10428 頂點，X/Z 恰好 -0.5 → 0.5，底部 2% 高度帶內 1367 頂點（13.1%）
##   base_color 是 image/jpeg，沒有 alpha 通道 → ALPHA_SCISSOR 救不了。
##   唯一解法是把底座沉到泥面之下，讓泥面蓋住，只留稻葉露出。
##
## 標高（實測 asset_probe.py，非 AABB 推定）：
##   稻作株本地 -0.27344 → 0.27344（原點在幾何中心）
##
## @tool script：改任一 @export 觸發 setter 重建。
## 注意：MCP 掛上腳本時 _ready 不會觸發，需設一次 @export 踢它一下。

const SCENE_PATH := "res://assets/riverbank/稻作株.glb"

const RICE_LOCAL_BOTTOM := -0.27344   # 模型本地最低點

## 泥面基準 —— 稻底沉到田格泥面頂之下 sink_below 公尺。
##
## 【重要】不要寫死常數（2026-09-01 修正）：
## 我原本寫 mud_top = 3.005，那是從 paddy_water 的 water_y 推算的。
## 但 water_y 是【節點原點】，不是泥面高度 —— 水田一格.glb 的 AABB
## 是 y -0.0145..+0.0187（中心偏移 +0.0021），乘上 scale 2.52 後
## 泥面實際落在 2.836..2.920，而不是我以為的 3.018..3.102。
## 結果稻底 2.945 高出泥面頂 2.920 整整 2.5cm，底座整片露出 →
## 實機再度出現「每叢稻底下一塊白色方塊」。
##
## 現在改成【實測】：從場景裡的 PaddyWater 直接量田格的 global AABB 頂，
## 量不到才退回 fallback。田格高度變了、water_y 改了、relief 調了，
## 稻叢都會自動跟上。
@export var paddy_path: NodePath = NodePath("../PaddyWater"):
	set(v):
		paddy_path = v
		_build()

## 量不到田格時的退路。
@export var mud_top_fallback: float = 2.92:
	set(v):
		mud_top_fallback = v
		_build()

## 底座沉入深度。太淺會露出資產自帶的土堆。
##
## 【2026-09-01 修正】稻作株.glb 沒有「1×1 方形底座地磚」——
## 我先前這樣宣稱是錯的。實際 GLB 量測：
##   10428 頂點，最底 1mm 內只有 12 個，且 XZ 只涵蓋
##   x −0.334..0.455 / z −0.500..0.330（不是完整 ±0.5 footprint）
##   但 y < −0.20 有 3159 個頂點 = 全模型的 30%
## → 那不是平板地磚，是**焊進同一個 primitive 的土堆**，
##   單一 material、單張 base_color JPEG。使用者自己先講對了：
##   「稻穗本身資產帶的土材質鑲嵌在一起」。
##
## 所以沒有東西可以切掉、也沒有 alpha 可以裁——土堆是委製內容的一部分。
## 唯一正解是沉到宿主面之下，只讓稻葉露出。
## 0.10 已覆蓋土堆高度（約 0.07m × scale）。
@export var sink_below: float = 0.10:
	set(v):
		sink_below = maxf(v, 0.0)
		_build()

const PLOT_X: Array[float] = [23.215, 35.0, 46.785]
const PLOT_Z: Array[float] = [-29.464, -17.678, -5.893, 5.893, 17.678, 29.464]

@export var per_plot: int = 9:
	set(v):
		per_plot = clampi(v, 0, 64)
		_build()

## 距格心的散布半徑。格 11m、田埂佔 1.7m，實際可用約 ±4.6m。
@export var spread_min: float = 1.6:
	set(v):
		spread_min = maxf(v, 0.0)
		_build()

@export var spread_max: float = 4.2:
	set(v):
		spread_max = maxf(v, spread_min)
		_build()

@export var scale_base: float = 1.5:
	set(v):
		scale_base = maxf(v, 0.05)
		_build()

@export var scale_jitter: float = 0.18:
	set(v):
		scale_jitter = clampf(v, 0.0, 0.9)
		_build()

@export var rng_seed: int = 20260901:
	set(v):
		rng_seed = v
		_build()

## 重建會**刪掉並重生所有稻叢**，你在編輯器裡對個別稻叢做的位移／旋轉
## 會被清掉。預設關閉，避免不小心洗掉手動調整。
@export var rebuild: bool = false:
	set(v):
		rebuild = v
		if v:
			_rebuild_all()


func _ready() -> void:
	# 已經有格子就不重建 —— 保住使用者的手動調整
	if get_child_count() == 0:
		_build()


## 就地更新：格與稻叢沿用既有節點，不刪除重生。
func _build() -> void:
	# 反序列化期間 @export 逐一賦值，setter 會在其他欄位就位前觸發
	if per_plot < 0 or scale_base <= 0.0 or spread_max <= 0.0:
		return
	if not is_inside_tree():
		return

	var mesh := _first_mesh()
	if mesh == null:
		push_error("[ine] 從 %s 取不到 mesh" % SCENE_PATH)
		return

	var root := get_tree().edited_scene_root if Engine.is_editor_hint() else null
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed          # 固定種子：重跑結果一致，便於前後比對

	# 實測泥面頂，不用寫死常數 —— 見 paddy_path 的說明
	var mud: float = _measure_mud_top()

	var total := 0
	for i in PLOT_X.size():
		for j in PLOT_Z.size():
			var gname := "格_%d%d" % [i, j]
			var grp := get_node_or_null(NodePath(gname)) as Node3D
			if grp == null:
				grp = Node3D.new()
				grp.name = gname
				add_child(grp)
				if root != null:
					grp.owner = root
			# 群組本身放在格心，稻叢用相對座標 —— 這樣你想整格移動
			# 只要拉「格_ij」，裡面的稻叢跟著走。
			grp.position = Vector3(PLOT_X[i], 0.0, PLOT_Z[j])

			for k in per_plot:
				var rname := "稻_%d" % k
				var mi := grp.get_node_or_null(NodePath(rname)) as MeshInstance3D
				if mi == null:
					mi = MeshInstance3D.new()
					mi.name = rname
					grp.add_child(mi)
					if root != null:
						mi.owner = root
				mi.mesh = mesh

				# 分象限散布，避免整叢擠在同一角
				var qx := -1.0 if (k % 4) in [0, 2] else 1.0
				var qz := -1.0 if (k % 4) in [0, 1] else 1.0
				var px: float = qx * rng.randf_range(spread_min, spread_max)
				var pz: float = qz * rng.randf_range(spread_min, spread_max)

				var s: float = scale_base * rng.randf_range(
						1.0 - scale_jitter, 1.0 + scale_jitter)
				# 底座沉到泥面之下，只留稻葉露出 —— 見 sink_below
				var py: float = (mud - sink_below) - RICE_LOCAL_BOTTOM * s

				mi.position = Vector3(px, py, pz)
				mi.rotation = Vector3(0.0, rng.randf_range(0.0, TAU), 0.0)
				mi.scale = Vector3(s, s, s)
				total += 1

			# per_plot 調小時，把多出來的稻叢移除
			for c in grp.get_children():
				var nm: String = c.name
				if nm.begins_with("稻_"):
					var idx := nm.substr(2).to_int()
					if idx >= per_plot:
						c.free()

	print("[ine] %d 叢稻作（%d 格 × %d 叢），泥面頂 y=%.3f，稻底 y=%.3f，獨立節點"
			% [total, PLOT_X.size() * PLOT_Z.size(), per_plot,
			   mud, mud - sink_below])


## 實測水田格的泥面頂（global），不用寫死常數。
## 田格 mesh 的 AABB 中心不在 y=0，寫死會算錯 —— 見 paddy_path 說明。
func _measure_mud_top() -> float:
	var paddy := get_node_or_null(paddy_path)
	if paddy == null:
		# 相對路徑在某些時機解析不到，退一步從父節點找
		var par := get_parent()
		if par != null:
			paddy = par.get_node_or_null(NodePath("PaddyWater"))
	if paddy == null:
		push_warning("[ine] 找不到 %s，用 fallback %.3f"
				% [String(paddy_path), mud_top_fallback])
		return mud_top_fallback
	var best := -INF
	for c in paddy.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var ab := mi.get_aabb()
		var g := mi.global_transform
		# 取 AABB 上表面四角，轉到世界座標後取最高
		for dx in [0.0, 1.0]:
			for dz in [0.0, 1.0]:
				var p := ab.position + Vector3(
						ab.size.x * dx, ab.size.y, ab.size.z * dz)
				best = maxf(best, (g * p).y)
	if best == -INF:
		push_warning("[ine] %s 底下沒有 MeshInstance3D，用 fallback"
				% String(paddy_path))
		return mud_top_fallback
	return best


## 全部刪掉重生 —— 只有勾 rebuild 才會跑
func _rebuild_all() -> void:
	for c in get_children():
		c.free()
	_build()


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
