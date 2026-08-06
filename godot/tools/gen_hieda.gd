# 稗田邸的植栽 → MultiMesh。
#
# 為什麼需要這支：blockout 的面數一路漲到 92,854，其中 ~71,000（76%）是
# 樹、灌木、生垣 —— 而它們只是**同一份幾何重複很多次**。烘進單一 mesh 等於
# 把同一棵樹的三千個三角形存了八份。改成「單位模組 + 擺位表」之後：
#
#   hieda_blockout.glb   92,854 → 22,600 面（靜態：建築、牆、水池、枯山水、
#                                            飛石、燈籠、木戶、前庭拱門巨樹）
#   模組 10 種            25,130 面（每種只存一份）
#   實例 136 個           由 data/hieda_garden.instances.json 擺位
#
# 同樣的畫面，烘進單一 mesh 要 261,116 面。
#
# 擺位表由 assets/blender/make_hieda.py 跟幾何一起產出，座標**已經是 Godot
# 空間**（y 向上）—— 不要在這裡再做一次軸轉換。手抄一份到 .tscn 的話，
# 之後挪動任何一棵樹都會有一邊沒跟到。
#
# 用法（在組稗田邸那張圖的產生器裡）：
#     var hieda := preload("res://tools/gen_hieda.gd").new()
#     hieda.emit(lib, parent_node)
#
# 這支刻意**只做植栽**：稗田邸還不是一張獨立的 Godot 地圖（地形、碰撞、
# 出生點、傳送點都還沒有）。等那張圖開工時，這支直接被呼叫就好。
#
# ⚠⚠ 這批資產是照**獨立地圖**的尺度做的，塞不進村圖（village）裡那座稗田邸。
# 2026-08-06 實測：
#     這份擺位表的跨度            95.4 × 107.0 m（136 實例）
#     hieda_blockout.glb 本體     75.6 × 110.5 m
#     村圖稗田邸的保留區           42.4 ×  45.6 m
#   線性差 ~2.3×；而且扣掉主屋／緣側／長廊／離れ／庭池之後，村院塀內 38×41m
#   真正能種東西的只剩 **593 ㎡（38%）**，面積差 ~17×。
# 使用者定案：村院**另做小型植栽**（重用這 10 種模組、重排位置，見
# gen_town.gd 的 `_lm_hieda_planting`），這份擺位表原封不動留給獨立地圖。
# 所以 `maps/hieda/gen/*.res` 目前是刻意保留的孤兒 —— 不要以為它壞了就刪掉。
# hieda_garden.markers.json 裡那個 target 還是 null 的木戶 portal 同理。
extends RefCounted

const MANIFEST := "res://data/hieda_garden.instances.json"
const MODEL_DIR := "res://assets/models/"

## 依模組名字挑材質：葉子要雙面（cull 關掉），不然從背面看整片消失。
## 生垣與樹冠都是頂點色 + 雙面，跟 gen_village.gd 的 _emit_hedges() 同一組。
static func _is_foliage(name: String) -> bool:
	return name.contains("hedge") or name.contains("bush") \
		or name.contains("maple") or name.contains("pine")


## 把擺位表發成 MultiMeshInstance3D。回傳實際發出去的實例總數。
## lib = gen_lib 的實例（要 add() 與材質）；parent = 掛在哪個節點下。
func emit(lib, parent: Node3D) -> int:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		push_error("gen_hieda: 讀不到 %s —— 先跑 make_hieda.py" % MANIFEST)
		return 0
	var man: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(man) != TYPE_DICTIONARY or not man.has("modules"):
		push_error("gen_hieda: %s 格式不對（要有 modules）" % MANIFEST)
		return 0

	# ⚠ res:// 要先 globalize_path —— make_dir_recursive_absolute 吃的是實體路徑。
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://maps/hieda/gen"))
	var g: Node3D = lib.add(parent, Node3D.new(), "稗田邸植栽")
	var total := 0
	var names: Array = man["modules"].keys()
	names.sort()
	for name in names:
		var mod: Dictionary = man["modules"][name]
		var xforms: Array = mod.get("xforms", [])
		if xforms.is_empty():
			continue
		var mesh: Mesh = lib.prop_mesh(String(mod.get("glb", MODEL_DIR + name + ".glb")))
		var list: Array = []
		for xf in xforms:
			list.append(_xform(xf))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(mesh, list, [],
			"res://maps/hieda/gen/mm_%s.res" % name)
		if _is_foliage(name):
			mmi.material_override = lib.foliage_vc_mat()
		# 葉子是薄片，投影用 double-sided 才不會半邊沒影子
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		lib.add(g, mmi, "MM_%s" % name)
		total += list.size()
	print("hieda 植栽：%d 實例 / %d 種模組（%d draw call）"
		% [total, names.size(), names.size()])
	return total


## [x, y, z, yaw, sx, sy, sz] → Transform3D。
## yaw 是繞 +y 的角度，Blender 端已經換算過了（見 make_hieda.py 的 Inst）。
func _xform(xf: Array) -> Transform3D:
	# R·S（先在模組自己的軸上縮放再轉），不是 Basis.scaled() 的 S·R
	# （那是在世界軸上縮放）。目前的資料 sx==sz 所以兩者同值，但哪天有
	# 非等向的模組就會歪掉。Basis 沒有 scaled_local()，自己乘。
	var b := Basis(Vector3.UP, float(xf[3])) \
		* Basis.from_scale(Vector3(float(xf[4]), float(xf[5]), float(xf[6])))
	return Transform3D(b, Vector3(float(xf[0]), float(xf[1]), float(xf[2])))
