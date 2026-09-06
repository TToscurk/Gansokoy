@tool
extends Node3D

## 水田田埂（畦道）—— 獨立節點，按走向與線位分組。
##
## 為什麼是獨立節點而不是 MultiMesh（2026-09-01 使用者裁決）：
##   MultiMesh 是一個節點，使用者在編輯器裡點不到單一段田埂，
##   不能單獨拉、不能改單段高度、不能把某一段換成別的模組。
##   那些都是正常的美術審查動作。使用者的原話：
##   「144 條指令會消耗很多 token 是嘛…我現在想說這完全不用省」
##   接著是「田埂做節點」。指令數從來不是限制條件。
##
##   密度層（草、碎石、沉床石、遠景樹）留在 MultiMesh；
##   田埂是玩家會走、使用者會審的結構件，所以走節點。
##
## 節點結構（兩層，兩種粒度都選得到）：
##   AzeGrid/NS_x00 … NS_x03      南北向，每條線一個群組
##       └── 段_00 … 段_53         該線上的每一塊
##   AzeGrid/EW_z00 … EW_z06      東西向
##       └── 段_00 …
##
## 標高依據（實測自 tools/asset_probe.py，非 AABB 推定）：
##   畦道本地 X 0.2617（斷面寬）/ Y 0.0764（高）/ Z 1.0000（長軸）
##   17812 頂點，自帶 base_color / metallic_roughness / normal 三張 JPEG
##   原點在幾何中心，本地最高點 +0.03931
##
## rebuild 預設 false：子節點已序列化進 .tscn，_ready 只在空的時候才生成，
## 否則會洗掉使用者的手動調整。

const SCENE_PATH := "res://assets/riverbank/畦道.glb"

const AZE_LOCAL_TOP := 0.03931        # 模型本地最高點

const MODEL_W := 0.2617
const MODEL_LEN := 1.0

## X:Z 比例容許偏差。超過就發警告 —— 這顆模型上面烘了石頭與土紋，
## 非等比縮放會把紋理拉歪。
##
## 舊寫法的錯（2026-09-01 修正）：
##   sc = Vector3(width_scale, width_scale, length_scale + overlap)
##   = (6.5, 6.5, 12.1) → X 拉 6.5 倍、Z 拉 12.1 倍，差了 1.86 倍。
## 一段 12m 的田埂是把一塊 1m 的模型硬拉 12 倍，紋理縱向糊掉，
## 讀起來就是「一條被壓扁的長條」而不是路。
##
## 現在改成用 tiles 塊 1m 模型接續鋪滿，每塊只做微幅伸縮補餘量。
const SQUASH_LIMIT := 0.08

## 田埂頂絕對高度。
##
## 為什麼不是 3.0 —— 舊值讓田埂頂與地台頂齊平，水田水面因此沉在
## 地台之下，整片田區被褐色土面蓋住，遠看根本沒有水。
##
## 【注意】使用者於 2026-09-01 手動把 FieldGround 下拉到頂 2.817，
## 田埂露出因此從 0.12m 變成 0.303m（高寬比 1:14 → 1:5.6）。
## 這個常數沒有跟著動 —— 若之後要調，先量 FieldGround 的實際頂面，
## 不要從記憶裡的 3.0 推。
const FIELD_TOP := 3.12

## 東西向田埂的下沉量（公尺）。
##
## 為什麼需要（2026-09-01 修正）：
## 南北向與東西向兩組田埂在十字交叉點必然重疊，兩片頂面在同一高度
## → 共面 z-fighting。俯視時交叉點會閃成一塊**邊界銳利、無陰影的
## 淺灰白平板**，在深色水面之間非常顯眼。
##
## A/B 驗證（逐一開關節點，非截圖推測）：只留 AzeGrid 時白斑仍在，
## 且落點正是田埂交叉處；只留稻叢／水面／泥底／木樋時都沒有。
##
## 把東西向壓低 5mm，交叉點由南北向獨佔，深度測試就有明確勝負。
## 5mm 在 1.70m 寬的田埂上肉眼看不出高低差。
const CROSS_BIAS := 0.005

## 水田格心座標（與 ine_scatter.gd / paddy_water.gd 的 PLOT_X / PLOT_Z 一致）
const PLOT_X: Array[float] = [23.215, 35.0, 46.785]
const PLOT_Z: Array[float] = [-29.464, -17.678, -5.893, 5.893, 17.678, 29.464]
const STEP := 11.785                  # 格心間距

## 田埂寬 = 0.2617 × width_scale。
##
## 為什麼是 6.5 而不是原本的 3.0（2026-09-01 修正）：
## 3.0 給出 0.785m —— 那是真實日本水田的「畦」尺寸（一般 0.3–0.5m，
## 推手押車用的 0.6–0.9m），只能單人側身通過。使用者實際看畫面的
## 反應是「田裡的道路都變很窄」，這個判斷是對的：這條幹渠旁的田區
## 玩家要能走，需要的是「農道」等級（輕トラ可行 1.8–2.5m）。
##
## 6.5 → 1.70m，格淨寬仍有 10.08m。田埂:田格 = 1 : 5.9。
@export var width_scale: float = 6.5:
	set(v):
		width_scale = maxf(v, 0.01)
		_build()

@export var length_scale: float = 11.0:   # 段長，等於格距
	set(v):
		length_scale = maxf(v, 0.1)
		_build()

## 段與段之間的重疊量。
##
## 為什麼需要（2026-09-01 修正）：
## length_scale = 11.0 讓每段田埂剛好 11.0m，但格心間距 STEP 是 11.785m。
## 也就是每兩段之間留下 0.785m 的縫 —— 那正好是田埂本身的寬度，縫的
## 位置就在十字交叉點上。俯視時透過那個缺口會直接看到底下的 FieldGround
## 土面，在深色水面之間讀成「明亮的小方塊」。
@export var overlap: float = 1.1:
	set(v):
		overlap = clampf(v, 0.0, 3.0)
		_build()

## 重建會**刪掉並重生所有田埂**，你在編輯器裡對個別段做的位移／旋轉
## 會被清掉。預設關閉，避免不小心洗掉手動調整。
@export var rebuild: bool = false:
	set(v):
		rebuild = v
		if v:
			_rebuild_all()


func _ready() -> void:
	# 已經有子節點就不重建 —— 保住使用者的手動調整
	if get_child_count() == 0:
		_build()


func _rebuild_all() -> void:
	for c in get_children():
		c.free()
	_build()
	rebuild = false


func _build() -> void:
	# 反序列化期間 @export 逐一賦值，setter 會在其他欄位就位前觸發
	if width_scale <= 0.0 or length_scale <= 0.0:
		return
	if not is_inside_tree():
		return

	var mesh := _first_mesh()
	if mesh == null:
		push_error("[aze] 從 %s 取不到 mesh" % SCENE_PATH)
		return

	# 田埂線位置：每格中心 ± 半個格距，即格與格的交界
	var line_x: Array[float] = []
	for x in PLOT_X:
		line_x.append(x - STEP * 0.5)
	line_x.append(PLOT_X[PLOT_X.size() - 1] + STEP * 0.5)

	var line_z: Array[float] = []
	for z in PLOT_Z:
		line_z.append(z - STEP * 0.5)
	line_z.append(PLOT_Z[PLOT_Z.size() - 1] + STEP * 0.5)

	# 頂面齊田埂頂：模型頂 × scale 落在 FIELD_TOP
	var y: float = FIELD_TOP - AZE_LOCAL_TOP * width_scale
	# 每段的實際覆蓋長度（含重疊），以及要幾塊 1m 模型才鋪得滿
	var run: float = length_scale + overlap
	var tiles: int = maxi(1, ceili(run / (MODEL_LEN * width_scale)))
	# 均分：讓 tiles 塊剛好鋪滿 run，殘留的伸縮量控制在 SQUASH_LIMIT 內
	var tile_len: float = run / float(tiles)
	var z_scale: float = tile_len / MODEL_LEN
	var ratio: float = z_scale / width_scale

	var root := get_tree().edited_scene_root if Engine.is_editor_hint() else null
	var sc := Vector3(width_scale, width_scale, z_scale)
	var total := 0

	# 南北向：沿 x 的田埂線。長軸是模型的 Z，用 tiles 塊接續而非拉長一塊。
	for li in line_x.size():
		var gname := "NS_x%02d" % li
		var grp := _ensure_group(gname, root)
		var n := 0
		for z in PLOT_Z:
			for k in tiles:
				# 以段心為基準往兩端排：第 k 塊的中心
				var off: float = (float(k) + 0.5) * tile_len - run * 0.5
				var mi := _ensure_tile(grp, "段_%02d" % n, mesh, root)
				mi.transform = Transform3D(
						Basis.IDENTITY.scaled(sc),
						Vector3(line_x[li], y, z + off))
				n += 1
				total += 1
		_trim(grp, n)

	# 東西向：繞 Y 轉 90°，長軸轉到世界 X。
	# scale 在 Basis 的「局部」軸上作用，旋轉後才套用縮放 —— 所以這裡
	# 仍用同一組 (寬, 高, 長)，由旋轉負責把長軸擺到 X。用世界軸的
	# (長, 高, 寬) 會讓寬度乘到 length_scale 上，把田埂撐成 2.88m 寬。
	for li in line_z.size():
		var gname2 := "EW_z%02d" % li
		var grp2 := _ensure_group(gname2, root)
		var n2 := 0
		for x in PLOT_X:
			for k in tiles:
				var off2: float = (float(k) + 0.5) * tile_len - run * 0.5
				var mi2 := _ensure_tile(grp2, "段_%02d" % n2, mesh, root)
				# 壓低 CROSS_BIAS，避開與南北向的共面 z-fighting
				mi2.transform = Transform3D(
						Basis(Vector3.UP, PI * 0.5).scaled(sc),
						Vector3(x + off2, y - CROSS_BIAS, line_z[li]))
				n2 += 1
				total += 1
		_trim(grp2, n2)

	print("[aze] %d 塊田埂（%d 群組 = %d 南北 + %d 東西），寬 %.3fm 段長 %.3fm，X:Z = 1:%.2f，頂 %.3f，獨立節點"
			% [total, line_x.size() + line_z.size(),
			   line_x.size(), line_z.size(),
			   MODEL_W * width_scale, tile_len, ratio, FIELD_TOP])
	if absf(ratio - 1.0) > SQUASH_LIMIT:
		push_warning("[aze] 田埂 X:Z 比例 1:%.2f 超出 ±%.0f%%，貼圖會被拉伸"
				% [ratio, SQUASH_LIMIT * 100.0])


## 依名稱取得或建立線群組。使用者可以點群組整條選、展開選單塊。
func _ensure_group(nm: String, root: Node) -> Node3D:
	var g := get_node_or_null(NodePath(nm)) as Node3D
	if g == null:
		g = Node3D.new()
		g.name = nm
		add_child(g)
		if root != null:
			g.owner = root
	return g


## 依名稱取得或建立單塊田埂 —— 就地更新，不刪除重建。
## 刪除重建會在 runtime 觸發 Godot 4.x 的 parent-name hashtable 錯誤。
func _ensure_tile(grp: Node3D, nm: String, mesh: Mesh, root: Node) -> MeshInstance3D:
	var mi := grp.get_node_or_null(NodePath(nm)) as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = nm
		grp.add_child(mi)
		if root != null:
			mi.owner = root
	# 材質跟著 mesh 走（GLB 內嵌），完全不碰 material_override
	mi.mesh = mesh
	return mi


## 參數調小時，把多出來的段移除
func _trim(grp: Node3D, keep: int) -> void:
	for c in grp.get_children():
		var nm: String = c.name
		if nm.begins_with("段_") and nm.substr(2).to_int() >= keep:
			c.free()


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
