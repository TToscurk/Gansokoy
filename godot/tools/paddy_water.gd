@tool
extends Node3D

## 水田 —— 18 格獨立節點，使用者委製的 水田一格.glb。
##
## 為什麼是獨立節點而不是 MultiMesh（2026-09-01 使用者裁決）：
##   我先前用 MultiMesh 的理由是「一個節點、指令數少、省 token」。
##   使用者的回覆：「144 條指令會消耗很多 token 是嘛 …… 我現在想說
##   這完全不用省 …… 我認為你現在這個做法我覺得不是我要的」。
##
##   MultiMesh 真正的代價不是效能，是**剝奪編輯能力**：
##     在編輯器裡選一格田      → 選不到（整個 MM 是一個節點）
##     單獨移動／升降某一格    → 做不到
##     某格休耕、某格插秧      → 做不到（共用同一個 mesh）
##     做高低不一的梯田        → 做不到
##   使用者手動調整時只能拉整個地台、不能拉單格田，正是因為這個。
##
##   18 個 MeshInstance3D = 18 個 draw call，在這個規模完全不是問題。
##
## 【重要】UV 是 Meshy 自動展開的打包佈局，不可平鋪：
##   抽樣 x-0.480 z-0.494 -> u0.828 v0.702
##        x-0.492 z-0.043 -> u0.815 v0.831
##   XZ 與 UV 沒有線性對應，一張圖裡是多個不連續的島。
##   UV 佔滿 0..1（0 個頂點越界）→ 整張貼圖就是為「這一格」設計的。
##   結論：它是「一格田」不是「可平鋪的田面」，整塊放大是唯一正確用法。
##
## 【重要】這顆模型不是平板：
##   Y 分佈 min -0.0145 / p25 -0.0013 / med +0.0060 / p75 +0.0098 / max +0.0187
##   連續分佈、無雙平面尖峰 —— 那 12327 個頂點是在描述泥面的凹凸。
##   XZ 放大而 Y 不動會把起伏壓成 1/s，等於抹平。Y 必須跟著等比。
##
## 標高（2026-09-01 使用者手動調整後）：
##   使用者把 FieldGround 下拉到 y=2.617（頂 2.817），讓田埂露出 0.303m。
##   舊值地台頂 3.000 讓田埂只露 0.12m，寬 1.70m 高 0.12m = 1:14，
##   讀起來是一條線不是路 —— 使用者的診斷「田道被蓋住了」正確。
##
## @tool script：改任一 @export 觸發 setter 重建。
## 注意：MCP 掛上腳本時 _ready 不會觸發，需設一次 @export 踢它一下。

const SCENE_PATH := "res://assets/riverbank/水田一格.glb"

## 材質覆寫 —— 保留使用者委製的三張貼圖，只改反射參數。
##
## 為什麼需要（實測，非推測）：
##   game_eval 讀出 GLB 匯入後：roughness=1.0 metallic=1.0 rough_channel=1
##   ORM 貼圖通道統計：G(rough) avg 96/255=0.376、B(metal) avg ≈0
##   Godot 算式是 roughness_scalar × texture，scalar 已是上限 1.0，
##   **無法再往上調**，實際粗糙度只有 0.376 → 整片田變鏡面。
##
## 覆寫只動反射：albedo / normal / roughness 全部引用同樣的 sidecar JPEG，
## 只把 metallic 歸零、specular_mode 設 DISABLED、normal_scale 提高。
const MAT_OVERRIDE := "res://assets/materials/paddy_field_override.tres"

const MODEL_SIDE := 1.0               # 模型本地邊長（X/Z）
const MODEL_H := 0.0332               # 模型本地高度跨度（泥面起伏）
const WATER_Y := 3.06                 # 水田面預設高度
const PLOT := 11.0                    # 單格邊長（田埂之間的淨寬）

## 水田格心座標（與 aze_grid.gd / ine_scatter.gd 的 PLOT_X / PLOT_Z 一致）
const PLOT_X: Array[float] = [23.215, 35.0, 46.785]
const PLOT_Z: Array[float] = [-29.464, -17.678, -5.893, 5.893, 17.678, 29.464]

## 水面比格子略小，讓田埂壓住邊緣。田埂寬 1.70m（半寬 0.85m），
## 各邊再讓 0.15m 給坡腳。
@export var inset: float = 1.0:
	set(v):
		inset = maxf(v, 0.0)
		_build()

@export var water_y: float = WATER_Y:
	set(v):
		water_y = v
		_build()

## 泥面起伏倍率。1.0 = 跟 XZ 等比（9m 格 → 起伏 0.30m，太誇張）。
## 0.28 給出約 8cm，接近真實水田整平後的 3–8cm。
## 絕不能設到 1/s ≈ 0.11 以下 —— 那等於把起伏抹平。
@export var relief: float = 0.28:
	set(v):
		relief = clampf(v, 0.02, 3.0)
		_build()

## 關掉就用 GLB 自帶材質（鏡面較強）。留著方便 A/B 比對。
@export var use_override: bool = true:
	set(v):
		use_override = v
		_build()

## 重建會**刪掉並重生所有格子**，你在編輯器裡對個別格子做的位移／旋轉
## 會被清掉。預設關閉，避免不小心洗掉手動調整。
## 要重新生成時才勾起來。
@export var rebuild: bool = false:
	set(v):
		rebuild = v
		if v:
			_build()


func _ready() -> void:
	# 已經有格子就不重建 —— 保住使用者的手動調整
	if get_child_count() == 0:
		_build()


func _build() -> void:
	# 反序列化期間 @export 逐一賦值，setter 會在其他欄位就位前觸發
	if inset < 0.0 or water_y == 0.0 or relief <= 0.0:
		return
	if not is_inside_tree():
		return

	var mesh := _first_mesh()
	if mesh == null:
		push_error("[paddy] 從 %s 取不到 mesh" % SCENE_PATH)
		return

	var side: float = PLOT - inset * 2.0
	if side <= 0.0:
		push_error("[paddy] inset 太大，格子沒了")
		return

	var s: float = side / MODEL_SIDE
	# Y 跟著 XZ 等比再乘 relief，否則泥面起伏被壓成 1/s
	var sy: float = s * relief

	var om: Material = null
	if use_override:
		om = load(MAT_OVERRIDE) as Material
		if om == null:
			push_error("[paddy] 取不到覆寫材質：%s" % MAT_OVERRIDE)

	var root := get_tree().edited_scene_root if Engine.is_editor_hint() else null

	var n := 0
	for i in PLOT_X.size():
		for j in PLOT_Z.size():
			# 命名帶格號，編輯器裡一眼看得出是哪一格
			var nm := "田_%d%d" % [i, j]
			var mi := get_node_or_null(NodePath(nm)) as MeshInstance3D
			if mi == null:
				mi = MeshInstance3D.new()
				mi.name = nm
				add_child(mi)
				if root != null:
					mi.owner = root
			mi.mesh = mesh
			mi.material_override = om
			mi.position = Vector3(PLOT_X[i], water_y, PLOT_Z[j])
			mi.scale = Vector3(s, sy, s)
			n += 1

	print("[paddy] %d 格獨立水田節點，邊長 %.2fm，泥面起伏 %.3fm，田面 y=%.3f，覆寫材質 %s"
			% [n, side, MODEL_H * sy, water_y,
			   "on" if use_override else "off"])


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
