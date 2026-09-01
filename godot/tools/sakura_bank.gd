@tool
extends Node3D

## 岸邊櫻花 —— 獨立節點，村屋側（西岸）。
##
## 依據：docs/reference/人間之里概念圖/新版水護岸概念圖.png
##   判讀所得（憲章：圖是權威）：
##     * 粉白花樹 4–6 株，**全部集中在村屋這一側**，不在水田那側
##     * 分兩群：一群較大（樹冠寬約等於兩層樓木屋立面寬），
##       一群 2–3 株較小，夾在店屋屋頂與坡道之間
##     * 最大株樹冠底緣已高於護岸頂面，樹高約護岸可見高度的 2–3 倍
##     * 枝條向外伸出、部分懸挑到下方屋瓦與石砌護岸上方
##
## 為什麼是獨立節點而不是 MultiMesh（2026-09-01 使用者裁決）：
## 櫻花是審查會逐株看、逐株調的主視覺，不是密度層。
## 使用者已就水田／稻叢／田埂做過同樣裁決：「這完全不用省」。
##
## 資產量測（GLB 頂點，非 AABB 推定 —— 憲章第 34 條）：
##   櫻花樹.glb  14421 頂點，單一 material，三張 JPEG
##   X −0.5000..+0.5000  Y −0.4851..+0.4961  Z −0.4648..+0.4492
##   底部 5mm 內只有 23 個頂點（0.2%），且 XZ 僅涵蓋
##   x +0.014..+0.146 / z +0.177..+0.229 —— 不是完整 footprint，
##   所以**沒有自帶土台或地磚**，是板根直接張開。
##   原點在幾何中心（asset_probe 判定），底部在 −0.4851。

const SCENE_PATH := "res://assets/landscape/櫻花樹.glb"

## 模型本地底部 —— 座標由此推：position.y = 地面 − LOCAL_BOTTOM × scale
const LOCAL_BOTTOM := -0.4851
const LOCAL_H := 0.9812               # −0.4851 → +0.4961

## 岸頂高程（實測自場景，非記憶）：
##   石岸壓頂 2.955 / 步道頂 3.225
## 櫻花種在步道內側的土帶上，取步道頂。
const BANK_TOP := 3.225

## 護岸可見高度 = 壓頂 2.955 − 水面 0.090 = 2.865m
## 概念圖要求樹高為其 2–3 倍 → 5.7 ~ 8.6m
const BANK_VISIBLE_H := 2.865

## 西岸建築帶東緣 x = −7.36，步道帶 x −11.50..−6.50。
## 櫻花種在步道與建築之間、略偏水側，讓樹冠能懸挑到護岸上方
## （概念圖：枝條部分懸挑到下方屋瓦與石砌護岸上方）。
const TREE_X := -9.4

## 兩群的 z 座標。
##
## 空檔實測（MCP 量 B1_Street_Context 靠東 8 件建築在 z 軸的投影）：
##   z −95.0..−56.0 (39.0m) / −28.4..−14.5 (13.9m)
##   z  13.3..37.5  (24.2m) / 57.5..95.0  (37.5m)
##
## 概念圖是「兩群」不是均勻排列，所以只用中段兩個空檔 ——
## 南群 3 株落在 −28.4..−14.5，北群 2 株落在 13.3..37.5。
## 兩端的大空檔留白，避免變成行道樹。
const GROUP_A: Array[float] = [-26.0, -21.5, -16.5]   # 南群 3 株
const GROUP_B: Array[float] = [17.5, 24.0]            # 北群 2 株

## 每株的樹高（公尺）。概念圖：一株最大、其餘較小。
## 全部落在 5.7–8.6m 的帶內（護岸可見高度 2–3 倍）。
const HEIGHTS: Array[float] = [7.2, 5.9, 6.4, 8.4, 6.1]

## 每株的 Y 旋轉（弧度）—— 讓同一顆 mesh 不要看起來是複製貼上
const YAWS: Array[float] = [0.0, 2.1, 4.3, 1.2, 5.4]

## 每株相對 TREE_X 的橫向偏移，避免排成一直線
const X_OFF: Array[float] = [0.0, 1.3, -0.9, 0.6, -1.1]


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
	if not is_inside_tree():
		return

	var mesh := _first_mesh()
	if mesh == null:
		push_error("[sakura] 從 %s 取不到 mesh" % SCENE_PATH)
		return

	var root := get_tree().edited_scene_root if Engine.is_editor_hint() else null
	var zs: Array[float] = []
	zs.append_array(GROUP_A)
	zs.append_array(GROUP_B)

	var lo := 1e9
	var hi := -1e9
	for i in zs.size():
		var h: float = HEIGHTS[i % HEIGHTS.size()]
		var s: float = h / LOCAL_H
		# 底部落在岸頂：model_bottom + position.y × scale = 目標面（憲章複驗式）
		var py: float = BANK_TOP - LOCAL_BOTTOM * s
		var px: float = TREE_X + X_OFF[i % X_OFF.size()]

		var mi := _ensure_tree("櫻_%02d" % i, mesh, root)
		mi.transform = Transform3D(
				Basis(Vector3.UP, YAWS[i % YAWS.size()]).scaled(Vector3(s, s, s)),
				Vector3(px, py, zs[i]))
		lo = minf(lo, h)
		hi = maxf(hi, h)

	_trim(zs.size())
	print("[sakura] %d 株櫻花（%d 南群 + %d 北群），樹高 %.1f–%.1f m，"
			% [zs.size(), GROUP_A.size(), GROUP_B.size(), lo, hi]
			+ "護岸可見高 %.2fm 的 %.1f–%.1f 倍，底 y=%.3f，獨立節點"
			% [BANK_VISIBLE_H, lo / BANK_VISIBLE_H, hi / BANK_VISIBLE_H, BANK_TOP])


func _ensure_tree(nm: String, mesh: Mesh, root: Node) -> MeshInstance3D:
	var mi := get_node_or_null(NodePath(nm)) as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = nm
		add_child(mi)
		if root != null:
			mi.owner = root
	# 材質跟著 mesh 走（GLB 內嵌），完全不碰 material_override
	mi.mesh = mesh
	return mi


func _trim(keep: int) -> void:
	for c in get_children():
		var nm: String = c.name
		if nm.begins_with("櫻_") and nm.substr(2).to_int() >= keep:
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
