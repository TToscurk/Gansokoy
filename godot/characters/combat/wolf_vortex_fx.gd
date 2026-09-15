extends Node
class_name WolfVortexFX
## 山犬撲擊旋風：沿曲線 trim 的能量帶。
##
## ⚠ 為什麼不是直接從 GLB 播動畫：
##   Blender 端的旋風是 **NURBS 曲線 + 逐幀 bevel_factor_start/end** 做的
##   「沿曲線掃出來又消失」效果。glTF 規格沒有曲線型別、也沒有 bevel_factor
##   這種屬性 —— 直接匯出的話這些物件整批消失（2026-09-10 實測：匯出的
##   wolf_pounce.glb 裡 Vortex 節點數 = 0）。
##
##   解法：Blender 端把 bevel 開到全長、轉成**靜態管狀網格**匯出
##   （wolf_vortex_fx.glb，10 條共 18,440 面，拓樸每幀固定所以可行），
##   trim 動態改由 wolf_vortex.gdshader 在 GPU 上重現。
##
##   曲線轉網格時 UV.y 天生就是「沿曲線長度 0→1」，正好當 trim 座標，
##   不需要額外烘資料。
##
## 逐幀曲線讀 assets/enemies/wolf/vortex_fx.json（Blender 端逐幀取樣後匯出），
## 不是在這裡硬猜參數 —— 那份 JSON 才是動畫的實況權威。
##   fps           取樣幀率（24）
##   frames        總幀數（85 = f0–84）
##   curves[i]     第 i 條旋風的 start[] / end[] 逐幀值
##   active_first  / active_last  有幾何的幀區間（實測 f30–61）

const FX_SCENE := "res://assets/enemies/wolf/wolf_vortex_fx.glb"
const FX_CURVE_PATH := "res://assets/enemies/wolf/vortex_fx.json"
const SHADER := preload("res://characters/combat/wolf_vortex.gdshader")

static var _curve: Dictionary = {}


static func _load_curve() -> Dictionary:
	if not _curve.is_empty():
		return _curve
	var txt := FileAccess.get_file_as_string(FX_CURVE_PATH)
	if txt.is_empty():
		push_warning("[狼旋風] 讀不到 %s" % FX_CURVE_PATH)
		return {}
	var d: Variant = JSON.parse_string(txt)
	if not (d is Dictionary):
		push_warning("[狼旋風] %s 格式不對" % FX_CURVE_PATH)
		return {}
	_curve = d
	return _curve


## 旋風活躍的起訖秒數（對應動畫 f30–61）
static func active_window() -> Vector2:
	var c := _load_curve()
	if c.is_empty():
		return Vector2(30.0 / 24.0, 61.0 / 24.0)
	var fps := float(c.get("fps", 24.0))
	return Vector2(float(c.get("active_first", 30)) / fps,
		float(c.get("active_last", 61)) / fps)


## 建立旋風節點群。回傳 { root: Node3D, mats: Array[ShaderMaterial] }。
##
## ⚠ wolf_mesh 必須傳狼的 GLB 實例節點（Visual/wolf_pounce），不是 Visual 本身：
##   狼的縮放（2.06）與朝向修正（yaw+90°）是寫在那個**子節點**的 transform 上，
##   不是 Visual 上。旋風掛在 Visual 底下用單位變換的話，會是 1:1 的 Blender
##   原始尺寸 —— 比狼小 2.06 倍、而且轉向差 90°（2026-09-10 實測：旋風/狼身
##   尺寸比 0.416，使用者回報「旋風特小」）。
##   旋風的頂點座標與狼網格同樣來自 Blender 世界空間，所以兩者**必須套用完全
##   相同的變換**才會對齊。
static func make(visual_root: Node3D, wolf_mesh: Node3D) -> Dictionary:
	var result := {"root": null, "mats": []}
	if not ResourceLoader.exists(FX_SCENE):
		push_warning("[狼旋風] 找不到 %s" % FX_SCENE)
		return result
	if wolf_mesh == null:
		push_warning("[狼旋風] 沒有拿到狼的網格節點，旋風無法對齊")
		return result
	var ps: PackedScene = load(FX_SCENE)
	var root: Node3D = ps.instantiate()
	root.name = "VortexFX"
	visual_root.add_child(root)
	# 與狼網格共用同一個變換（縮放 + 朝向修正），確保對齊
	root.transform = wolf_mesh.transform
	root.visible = false

	# 每條旋風各自一份材質 —— trim 進度每條不同（Blender 端就是錯開相位的）
	var mats: Array = []
	var stack: Array[Node] = [root]
	var found: Array[MeshInstance3D] = []
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			found.append(n as MeshInstance3D)
	# 依名稱排序，讓索引對得上 JSON 裡的 curves[] 順序
	found.sort_custom(func(a, b): return String(a.name) < String(b.name))
	for mi in found:
		var sm := ShaderMaterial.new()
		sm.shader = SHADER
		sm.set_shader_parameter("trim_start", 0.0)
		sm.set_shader_parameter("trim_end", 0.0)
		sm.set_shader_parameter("intensity", 0.0)
		mi.material_override = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 旋風是加法混合的透明物件，關掉遮蔽剔除避免整條被誤剔
		mi.extra_cull_margin = 2.0
		mats.append(sm)

	result["root"] = root
	result["mats"] = mats
	return result


## 每幀更新。t = 撲擊動畫經過秒數。
static func tick(root: Node3D, mats: Array, t: float, scale_mult: float = 1.0) -> void:
	if root == null or not is_instance_valid(root):
		return
	var c := _load_curve()
	if c.is_empty() or mats.is_empty():
		root.visible = false
		return

	var fps := float(c.get("fps", 24.0))
	var total: int = int(c.get("frames", 85))
	var curves: Array = c.get("curves", [])
	var win := active_window()

	# 活躍區間外整組關掉 —— 省掉 18,440 面的繪製
	if t < win.x or t > win.y:
		root.visible = false
		return
	root.visible = true

	# 收招前 0.15 s 淡出，避免硬消失
	var fade_out := clampf((win.y - t) / 0.15, 0.0, 1.0)
	var fade_in := clampf((t - win.x) / 0.08, 0.0, 1.0)
	var intensity := minf(fade_in, fade_out)

	var fpos := clampf(t * fps, 0.0, float(total - 1))
	var i0 := int(floor(fpos))
	var i1 := mini(i0 + 1, total - 1)
	var w := fpos - float(i0)

	for i in mats.size():
		if i >= curves.size():
			break
		var row: Dictionary = curves[i]
		var starts: Array = row.get("start", [])
		var ends: Array = row.get("end", [])
		if starts.size() <= i1 or ends.size() <= i1:
			continue
		var s := lerpf(float(starts[i0]), float(starts[i1]), w)
		var e := lerpf(float(ends[i0]), float(ends[i1]), w)
		var sm := mats[i] as ShaderMaterial
		if sm == null:
			continue
		sm.set_shader_parameter("trim_start", s)
		sm.set_shader_parameter("trim_end", e)
		sm.set_shader_parameter("intensity", intensity)


## 收招：整組關掉。
static func stop(root: Node3D, mats: Array) -> void:
	if root != null and is_instance_valid(root):
		root.visible = false
	for m in mats:
		var sm := m as ShaderMaterial
		if sm != null:
			sm.set_shader_parameter("intensity", 0.0)
			sm.set_shader_parameter("trim_start", 0.0)
			sm.set_shader_parameter("trim_end", 0.0)
