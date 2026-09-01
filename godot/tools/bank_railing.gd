@tool
extends Node3D

## 濱水步道木欄杆 —— 立柱 + 兩道橫桿，沿步道臨水側外緣。
##
## 依據：docs/reference/人間之里概念圖/新版水護岸概念圖.png
##   判讀所得（憲章：圖是權威）：
##     * 左岸護岸頂端沿石板步道外緣有一長段木欄，跨越大半個左岸
##     * 樣式為**等距立柱 + 水平橫桿**，看得出約 **2 道橫桿**
##       （頂部一道扶手、其下再一道中桿），桿間留空，
##       **不是密排直柵**
##     * 高度相對站立人物約在腰部至腰上一點（約人身高的 1/2 弱）
##
## 為什麼是自建幾何而不是資產：
## 資產庫沒有欄杆件。`竹垣.glb` 是**密排直柵**且已用在石岸壓頂
## （x −5.85，141 支），與概念圖此處要的「立柱+橫桿」不同物；
## 把竹垣挪來充當橫桿欄會是「跨角色硬套資產」，憲章與 skill 都禁止。
## 欄杆是規則的線性構件（柱、桿都是箱體），自建幾何不涉及美術風格判斷，
## 也不會破壞任何委製資產的比例。若之後使用者委製了木欄資產，
## 換掉 _build_rail_mesh() 即可，佈點邏輯不動。
##
## 標高依據（實測自場景 MCP，非記憶）：
##   VillageWalkway_South / _North  x −11.50..−6.50  頂 y 3.225
##   石岸壓頂 2.955（竹垣在此，本腳本不碰）
##
## 高度取 1.05m：真實和風木欄 1.0–1.1m，成人腰上一點，
## 符合概念圖「腰部至腰上」的判讀。

## 步道臨水側外緣 —— 欄杆立在這條線上
const RAIL_X := -6.72

## 步道頂面，柱底坐在這裡
const WALK_TOP := 3.225

## 欄杆總高（柱頂）。真實和風木欄 1.0–1.1m。
const RAIL_H := 1.05

## 立柱斷面（公尺）。真實角柱約 10–12cm。
const POST_W := 0.11
## 立柱間距。真實木欄柱距 1.5–2.0m。
const POST_SPACING := 1.80

## 橫桿斷面
const BAR_W := 0.075
const BAR_T := 0.055

## 兩道橫桿的高度（自步道面起算）——
## 概念圖：頂部一道扶手 + 其下一道中桿
const BAR_HEIGHTS: Array[float] = [1.00, 0.55]

## 步道 z 範圍（實測）：南段 −74..−18、北段 2..86。
## 親水設施開口處要斷開 —— 欄杆跨過階梯口就把下水路徑封死了。
## 開口 z 由場景的 Waterworks 節點實測而來：
##   親水階梯 z −13、濱水平台/降台石梯 z −5、水車/堰 z 20~24
##   S_親水階梯_弱節點 z −40.57、N_親水階梯_弱節點 z +42.57
const SEGMENTS: Array[Vector2] = [
	Vector2(-74.0, -44.0),    # 南延段（S 弱節點 −40.57 前斷開）
	Vector2(-37.0, -18.0),    # 南段（親水階梯 −13 前斷開）
	Vector2(2.0, 17.0),       # 中段（水車/堰 20~24 前斷開）
	Vector2(28.0, 39.0),      # 北段（N 弱節點 +42.57 前斷開）
	Vector2(46.0, 86.0),      # 北延段
]

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

	var root := get_tree().edited_scene_root if Engine.is_editor_hint() else null
	var mat := load("res://assets/materials/rail_wood.tres") as Material

	var total_posts := 0
	var total_bars := 0

	for si in SEGMENTS.size():
		var seg: Vector2 = SEGMENTS[si]
		var grp := _ensure_group("段_%02d" % si, root)
		var span: float = seg.y - seg.x

		# ---- 立柱：等距，兩端一定要有柱 ----
		var n: int = maxi(2, int(round(span / POST_SPACING)) + 1)
		var step: float = span / float(n - 1)
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(POST_W, RAIL_H, POST_W)
		for i in n:
			var mi := _ensure_part(grp, "柱_%02d" % i, root)
			mi.mesh = post_mesh
			mi.material_override = mat
			# 柱底坐在步道面：box 原點在中心，故抬半高
			mi.position = Vector3(RAIL_X, WALK_TOP + RAIL_H * 0.5, seg.x + step * i)
		total_posts += n

		# ---- 橫桿：整段一根，貫穿所有柱 ----
		for bi in BAR_HEIGHTS.size():
			var bar_mesh := BoxMesh.new()
			bar_mesh.size = Vector3(BAR_T, BAR_W, span)
			var mi2 := _ensure_part(grp, "桿_%d" % bi, root)
			mi2.mesh = bar_mesh
			mi2.material_override = mat
			mi2.position = Vector3(
					RAIL_X,
					WALK_TOP + BAR_HEIGHTS[bi],
					seg.x + span * 0.5)
			total_bars += 1

		_trim_posts(grp, n)

	print("[rail] %d 根立柱 + %d 道橫桿，%d 段，高 %.2fm（柱距 %.2fm），x=%.2f 步道頂 %.3f，獨立節點"
			% [total_posts, total_bars, SEGMENTS.size(), RAIL_H, POST_SPACING,
			   RAIL_X, WALK_TOP])


func _ensure_group(nm: String, root: Node) -> Node3D:
	var g := get_node_or_null(NodePath(nm)) as Node3D
	if g == null:
		g = Node3D.new()
		g.name = nm
		add_child(g)
		if root != null:
			g.owner = root
	return g


func _ensure_part(grp: Node3D, nm: String, root: Node) -> MeshInstance3D:
	var mi := grp.get_node_or_null(NodePath(nm)) as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = nm
		grp.add_child(mi)
		if root != null:
			mi.owner = root
	return mi


func _trim_posts(grp: Node3D, keep: int) -> void:
	for c in grp.get_children():
		var nm: String = c.name
		if nm.begins_with("柱_") and nm.substr(2).to_int() >= keep:
			c.free()
