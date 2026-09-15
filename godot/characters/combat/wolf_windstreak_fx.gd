extends Node
class_name WolfWindStreakFX
## 山犬速度風線：跑步時往後掃的速度線，撲擊時另一套更誇張的版本。
##
## 與 wolf_vortex_fx.gd 同一套做法（Blender NURBS 曲線 + bevel trim 搬不進
## glTF，所以轉成靜態管狀網格 + shader trim）。差別在這組有**兩套曲線**：
##   run    —— 16 幀循環（0.67 s，與 Wolf_Run 同週期），跑步時一直播
##   pounce —— 97 幀一次性（活躍 f28–96），撲擊時播
##
## Blender 端 44 條風線各自有 A_WindStreak_NN 與 A_WindStreak_NN_Pounce 兩個
## action，本檔的 windstreak_fx.json 就是把兩套逐幀取樣下來的結果。
##
## ⚠ 風線的 trim 區間會跨越端點回繞（start > end），shader 有對應處理 ——
##   那正是「一條條往後掃過去」的視覺來源，不是資料錯誤。

const FX_SCENE := "res://assets/enemies/wolf/wolf_windstreak_fx.glb"
const FX_CURVE_PATH := "res://assets/enemies/wolf/windstreak_fx.json"
const SHADER := preload("res://characters/combat/wolf_windstreak.gdshader")

static var _curve: Dictionary = {}


static func _load_curve() -> Dictionary:
	if not _curve.is_empty():
		return _curve
	var txt := FileAccess.get_file_as_string(FX_CURVE_PATH)
	if txt.is_empty():
		push_warning("[狼風線] 讀不到 %s" % FX_CURVE_PATH)
		return {}
	var d: Variant = JSON.parse_string(txt)
	if not (d is Dictionary):
		push_warning("[狼風線] %s 格式不對" % FX_CURVE_PATH)
		return {}
	_curve = d
	return _curve


## 跑步循環一圈的秒數（16 幀 @ 24fps = 0.667 s，與 Wolf_Run 同週期）
static func run_loop_seconds() -> float:
	var c := _load_curve()
	if c.is_empty():
		return 16.0 / 24.0
	var fps := float(c.get("fps", 24.0))
	return float(int(c.get("run_frames", 17)) - 1) / fps


## 撲擊版的活躍起訖秒數（實測 f28–96）
static func pounce_window() -> Vector2:
	var c := _load_curve()
	if c.is_empty():
		return Vector2(28.0 / 24.0, 96.0 / 24.0)
	var fps := float(c.get("fps", 24.0))
	var act: Array = c.get("pounce_active", [28, 96])
	return Vector2(float(act[0]) / fps, float(act[1]) / fps)


## 建立風線節點群。wolf_mesh 的作用同 wolf_vortex_fx.make() —— 縮放與朝向
## 寫在狼的 GLB 實例節點上，風線必須共用同一個變換才會對齊。
static func make(visual_root: Node3D, wolf_mesh: Node3D) -> Dictionary:
	var result := {"root": null, "mats": []}
	if not ResourceLoader.exists(FX_SCENE):
		push_warning("[狼風線] 找不到 %s" % FX_SCENE)
		return result
	if wolf_mesh == null:
		push_warning("[狼風線] 沒有拿到狼的網格節點，風線無法對齊")
		return result
	var ps: PackedScene = load(FX_SCENE)
	var root: Node3D = ps.instantiate()
	root.name = "WindStreakFX"
	visual_root.add_child(root)
	root.transform = wolf_mesh.transform
	root.visible = false

	var mats: Array = []
	var stack: Array[Node] = [root]
	var found: Array[MeshInstance3D] = []
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			found.append(n as MeshInstance3D)
	# 依名稱排序，讓索引對得上 JSON 裡的順序（匯出時也是照名稱排的）
	found.sort_custom(func(a, b): return String(a.name) < String(b.name))
	for mi in found:
		var sm := ShaderMaterial.new()
		sm.shader = SHADER
		sm.set_shader_parameter("trim_start", 0.0)
		sm.set_shader_parameter("trim_end", 0.0)
		sm.set_shader_parameter("intensity", 0.0)
		mi.material_override = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 3.0
		mats.append(sm)

	result["root"] = root
	result["mats"] = mats
	return result


## 跑步風線：t 會自動循環，強度由 strength 控制（0 = 關）。
## strength 建議接「當前水平速度 / move_speed」，慢走時就不該有速度線。
static func tick_run(root: Node3D, mats: Array, t: float, strength: float) -> void:
	if root == null or not is_instance_valid(root):
		return
	if strength <= 0.01 or mats.is_empty():
		root.visible = false
		return
	var c := _load_curve()
	if c.is_empty():
		root.visible = false
		return
	root.visible = true

	var fps := float(c.get("fps", 24.0))
	var n: int = int(c.get("run_frames", 17))
	var rows: Array = c.get("run", [])
	# 循環：對總幀數取模
	var fpos: float = fmod(maxf(t, 0.0) * fps, float(n - 1))
	_apply(mats, rows, fpos, n, clampf(strength, 0.0, 1.0))


## 撲擊風線：一次性播放，t = 撲擊動畫經過秒數。
static func tick_pounce(root: Node3D, mats: Array, t: float) -> void:
	if root == null or not is_instance_valid(root):
		return
	var c := _load_curve()
	if c.is_empty() or mats.is_empty():
		root.visible = false
		return
	var win := pounce_window()
	if t < win.x or t > win.y:
		root.visible = false
		return
	root.visible = true

	var fps := float(c.get("fps", 24.0))
	var n: int = int(c.get("pounce_frames", 97))
	var rows: Array = c.get("pounce", [])
	var fade := minf(clampf((t - win.x) / 0.08, 0.0, 1.0),
		clampf((win.y - t) / 0.2, 0.0, 1.0))
	_apply(mats, rows, clampf(t * fps, 0.0, float(n - 1)), n, fade)


static func _apply(mats: Array, rows: Array, fpos: float, n: int, intensity: float) -> void:
	var i0 := int(floor(fpos))
	var i1 := (i0 + 1) % n
	var w := fpos - float(i0)
	for i in mats.size():
		if i >= rows.size():
			break
		var row: Dictionary = rows[i]
		var starts: Array = row.get("start", [])
		var ends: Array = row.get("end", [])
		if starts.size() <= i0 or ends.size() <= i0:
			continue
		var si1: int = mini(i1, starts.size() - 1)
		var ei1: int = mini(i1, ends.size() - 1)
		var sm := mats[i] as ShaderMaterial
		if sm == null:
			continue
		sm.set_shader_parameter("trim_start", lerpf(float(starts[i0]), float(starts[si1]), w))
		sm.set_shader_parameter("trim_end", lerpf(float(ends[i0]), float(ends[ei1]), w))
		sm.set_shader_parameter("intensity", intensity)


static func stop(root: Node3D, mats: Array) -> void:
	if root != null and is_instance_valid(root):
		root.visible = false
	for m in mats:
		var sm := m as ShaderMaterial
		if sm != null:
			sm.set_shader_parameter("intensity", 0.0)
			sm.set_shader_parameter("trim_start", 0.0)
			sm.set_shader_parameter("trim_end", 0.0)
