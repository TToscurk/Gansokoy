@tool
extends Node3D

## 兩段式親水階梯 —— 上段窄梯 → 中間平台 → 轉折 → 下段寬梯沒入水中。
##
## 依據：docs/reference/人間之里概念圖/新版水護岸概念圖.png
##   判讀所得（憲章：圖是權威）：
##     「先從上層石板步道以一段**較窄的直梯斜向下**，抵達一處中間平台／
##       緩台；在平台處**方向改變**，再以**一段更寬的階梯續下**，
##       最後化為數層很寬的條石台階一路沒入水中，
##       最下面幾階已浸在水裡、邊緣濕黑。」
##
## 場景現況（MCP 實測）：既有三組「親水階梯」（z −13、S −40.57、N +42.57）
## 全部是**單段直下**，沒有中間平台，也沒有轉折。本腳本補一組兩段式的，
## 不動既有三組 —— 概念圖上兩段式大階梯只有一處（中央），
## 其餘是短的直下梯，與場景現況相符。
##
## 資產量測（asset_probe.py，Blender MCP 直讀頂點 —— 憲章第 34 條）：
##   親水階梯一組.glb  18142 頂點  本地 −0.2197..+0.2207（原點幾何中心）
##     AABB 高 0.4404，**真實行走落差 0.4053**（差 0.0351 是底部凹陷／頂部脊）
##     → scale 一律用 0.4053 推，不用 AABB
##   濱水平台一塊.glb  13667 頂點  本地 −0.1309..+0.1318（原點幾何中心）
##     AABB 高 0.2627，真實行走落差 0.1933
##
## 標高鏈（實測自場景，非記憶；由下往上導出，見 skill 的 elevation chain）：
##   岸頂/壓頂  2.955
##   中間平台   2.105   ← 既有濱水平台頂，直接沿用
##   水面       0.090
##   上段落差 0.850m、下段落差 2.015m
##
## 為什麼上段要 2 組並排：
##   等比縮放下 scale 由落差決定 —— 上段 0.850/0.4053 = 2.10，
##   寬度也就只有 2.10m，一個人側身都勉強。
##   非等比拉寬會把踏面深度一起拉歪（憲章禁止破壞資產比例），
##   所以改成**同一 scale 的兩組並排**湊出 4.19m。
##   下段 1 組即 4.97m，天然比上段寬 —— 正是概念圖的「上窄下寬」。

const STEP_PATH := "res://assets/riverbank/親水階梯一組.glb"
const PLAT_PATH := "res://assets/riverbank/濱水平台一塊.glb"

## 真實行走落差（非 AABB）
const STEP_RISE := 0.4053
const STEP_BOTTOM := -0.2197
const STEP_SIDE := 1.0                # 平面邊長（本地）

const PLAT_RISE := 0.1933
const PLAT_BOTTOM := -0.1309

## 標高鏈
const BANK_TOP := 2.955               # 岸頂／壓頂
const PLAT_TOP := 2.105               # 中間平台頂
const WATER := 0.090                  # 下游水面

## 岸面 x —— 石岸內面約 −5.3，階梯往渠心（+x）方向下行
const BANK_FACE_X := -5.30

## 這組兩段式階梯的 z 中心。
##
## 選 z = −5.0：既有濱水平台就在 z −9..−1，中間平台可與其對齊成一體；
## 且此處在南段石岸（−36.60..−18.54）與中段（−1.10..16.96）之間的
## 開口帶內，不會撞到竹垣或壓頂石。
const CENTER_Z := -5.0

## 上段並排組數 —— 見上方「為什麼上段要 2 組並排」
@export var upper_count: int = 2:
	set(v):
		upper_count = maxi(v, 1)
		_build()

## 下段轉折角（度）。概念圖：「在平台處方向改變」。
##
## 【橫向進深的算術】（2026-09-01，兩次修正後定案）
## 岸面 x −5.30 到渠心 x 0.0，可用進深只有 5.30m。
## 階梯是等比縮放的，寬度 = 落差 / 0.4053，改不動：
##   上段落差 0.850 → 寬 2.10m
##   下段落差 2.015 → 寬 4.97m
## 首版讓兩段都朝渠心排，實測橫向吃掉 x −1.73..+5.12，
## **跨過渠心 5.12m**，等於用階梯把 13m 寬的渠道堵掉 8 成。
## 第二版只轉下段，改善到 74% 仍然太多。
##
## 算術上，只要兩段都吃橫向，總進深恆為
##   (0.850 + 2.015) / 0.4053 = 7.07m > 5.30m
## 不論平台高度設多少都超出 —— 降低平台只是把寬度在兩段之間搬動。
##
## 定案：**上段沿岸線走（繞 Y 轉 90°），只有下段吃橫向進深**。
## 這也更接近真實：親水階梯的上段本來就是順著護岸走的緩坡道，
## 到平台才轉身正對水面下去。橫向只需容納下段的 4.97m < 5.30m。
##
## turn_deg 是下段相對正交方向的斜度，讓它不要死板正對。
@export var turn_deg: float = 22.0:
	set(v):
		turn_deg = v
		_build()

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

	var step_mesh := _first_mesh(STEP_PATH)
	var plat_mesh := _first_mesh(PLAT_PATH)
	if step_mesh == null or plat_mesh == null:
		push_error("[hydrostair] 取不到 mesh")
		return

	var root := get_tree().edited_scene_root if Engine.is_editor_hint() else null

	# ---- 上段：岸頂 → 中間平台 ----
	# 上段【沿岸線】走，不吃橫向進深 —— 見下方「為什麼上段沿岸」。
	var up_rise: float = BANK_TOP - PLAT_TOP
	var su: float = up_rise / STEP_RISE
	var up_w: float = STEP_SIDE * su
	var g_up := _ensure_group("上段", root)
	for i in upper_count:
		var mi := _ensure_part(g_up, "梯_%02d" % i, step_mesh, root)
		# 底對齊平台頂：model_bottom × scale + position.y = PLAT_TOP（憲章複驗式）
		var py: float = PLAT_TOP - STEP_BOTTOM * su
		var z: float = CENTER_Z - up_w * 1.1 - (float(i) + 0.5) * up_w
		mi.transform = Transform3D(
				Basis(Vector3.UP, PI * 0.5).scaled(Vector3(su, su, su)),
				Vector3(BANK_FACE_X + up_w * 0.5, py, z))
	_trim(g_up, "梯_", upper_count)

	# ---- 中間平台：轉折處的緩台 ----
	var sp: float = up_w * 1.15 / STEP_SIDE      # 略寬於上段，讓轉身有餘裕
	var g_pl := _ensure_group("中間平台", root)
	var mp := _ensure_part(g_pl, "台_00", plat_mesh, root)
	mp.transform = Transform3D(
			Basis.IDENTITY.scaled(Vector3(sp, sp, sp)),
			Vector3(BANK_FACE_X + sp * 0.5,
					PLAT_TOP - PLAT_BOTTOM * sp,
					CENTER_Z - up_w * 0.55))
	_trim(g_pl, "台_", 1)

	# ---- 下段：中間平台 → 水面（轉折 90°，朝渠心下水）----
	# 只有下段吃橫向進深 —— 上段沿岸走，所以橫向只需容納下段一個梯寬。
	var dn_rise: float = PLAT_TOP - WATER
	var sd: float = dn_rise / STEP_RISE
	var dn_w: float = STEP_SIDE * sd
	var g_dn := _ensure_group("下段", root)
	var md := _ensure_part(g_dn, "梯_00", step_mesh, root)
	var yaw: float = deg_to_rad(turn_deg)
	# 底落在水面：最下幾階浸在水裡（概念圖：邊緣濕黑）
	var pyd: float = WATER - STEP_BOTTOM * sd
	var cx: float = BANK_FACE_X + dn_w * 0.5
	md.transform = Transform3D(
			Basis(Vector3.UP, yaw).scaled(Vector3(sd, sd, sd)),
			Vector3(cx, pyd, CENTER_Z + dn_w * 0.25))
	_trim(g_dn, "梯_", 1)

	print("[hydrostair] 兩段式親水階梯 @z%.1f：上段 %d 組 寬 %.2fm 落差 %.3fm"
			% [CENTER_Z, upper_count, up_w * upper_count, up_rise]
			+ " → 平台 %.2fm 頂 %.3f → 下段 寬 %.2fm 落差 %.3fm 轉折 %.0f°，"
			% [sp * STEP_SIDE, PLAT_TOP, dn_w, dn_rise, turn_deg]
			+ "上:下 = 1:%.2f，獨立節點" % [dn_w / (up_w * upper_count)])


func _ensure_group(nm: String, root: Node) -> Node3D:
	var g := get_node_or_null(NodePath(nm)) as Node3D
	if g == null:
		g = Node3D.new()
		g.name = nm
		add_child(g)
		if root != null:
			g.owner = root
	return g


func _ensure_part(grp: Node3D, nm: String, mesh: Mesh, root: Node) -> MeshInstance3D:
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


func _trim(grp: Node3D, prefix: String, keep: int) -> void:
	for c in grp.get_children():
		var nm: String = c.name
		if nm.begins_with(prefix) and nm.substr(prefix.length()).to_int() >= keep:
			c.free()


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
