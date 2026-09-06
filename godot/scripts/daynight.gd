extends Node
## 晝夜系統（autoload：DayNight）—— 全地圖統一，web 版 Environment 的接班人。
## 轉動 Main/Sun、調光色與強度；HUD 時鐘由 main.gd 讀 hour 顯示。

signal hour_changed(hour: float)

## 遊戲內時刻 0..24
## 預設時刻。正午是最平的光 —— 沒有長影子、沒有色溫，建築的面看不出明暗。
## 下午 15:40 的斜陽有方向感，同一個村子立刻不一樣。
var hour := 15.7
var flowing := true
## 現實幾秒 = 遊戲一天（預設 20 分鐘一天）
var day_seconds := 1200.0
var _bound_map: Node = null
var _lit_hour := -1.0
var _lamp_searched := false
var _env_node: WorldEnvironment = null
var _lamp_nodes: Array[Node] = []
var _lamp_paper: StandardMaterial3D = null

const DAY_COLOR := Color(1.0, 0.956, 0.87)
const DAWN_COLOR := Color(1.0, 0.62, 0.38)
const NIGHT_COLOR := Color(0.55, 0.65, 0.95)

func _ready() -> void:
	# `godot ... -- --hour=21` 固定時刻並停鐘。审图必須能在**同一個時刻**
	# 拍 before / after —— 一天 20 分鐘的話，兩張圖差 4 分鐘就跨了 5 個鐘頭，
	# 比較的是日照不是改動。
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hour="):
			flowing = false
			set_hour(a.substr(7).to_float())

func _process(delta: float) -> void:
	if flowing:
		set_hour(fmod(hour + delta * 24.0 / day_seconds, 24.0))
	# ⚠ 掛け直しの契機は「地図が入れ替わった時」だけ。`Main/Sun` は Main の
	#   _ready より前から木にいるので、autoload の初回 set_hour は**成功して
	#   しまう** —— その時点で `load_map()` はまだ走っておらず、街燈も地図側の
	#   Environment も存在しない。停鐘（--hour）だと set_hour は二度と呼ばれず、
	#   正午に提灯が点いたままになる。かといって毎フレーム掛け直すと、街燈を
	#   持たない地図（trail・shrine・hieda…）で `find_child` の全木走査が毎
	#   フレーム走る。地図ルートの同一性を見るのが両方を避ける最小の判定。
	var current_map: Node = _current_map()
	var rebound := current_map != _bound_map
	if rebound:
		_bound_map = current_map
		_env_node = null
		_lamp_nodes.clear()
		_lamp_paper = null
		_lamp_searched = false
	# 時刻のほうは 0.02h（＝実時間 1 秒ぶん）動いてから掛け直す。環境光は
	# 数分かけて動く量なので、毎フレーム書き直す意味がない。
	if rebound or absf(hour - _lit_hour) > 0.02:
		_lit_hour = hour
		_apply_ambient()
		_apply_lamps()

func set_hour(h: float) -> void:
	hour = fmod(h + 24.0, 24.0)
	hour_changed.emit(hour)
	var sun := get_tree().root.get_node_or_null("Main/Sun") as DirectionalLight3D
	if sun == null:
		return
	# 6:00 日出、12:00 最高、18:00 日落；夜間當月光用
	var t := (hour - 6.0) / 12.0
	var day := t >= 0.0 and t <= 1.0
	var elev: float
	if day:
		elev = sin(PI * t) * 72.0 + 6.0
	else:
		var tn := fmod(t + 1.0, 1.0)
		elev = sin(PI * tn) * 40.0 + 8.0
	var azim := -40.0 + (t if day else fmod(t + 1.0, 1.0)) * 80.0
	sun.rotation_degrees = Vector3(-elev, azim, 0.0)
	if day:
		var low := clampf(1.0 - sin(PI * t) * 1.6, 0.0, 1.0)   # 晨昏 → 1
		sun.light_color = DAY_COLOR.lerp(DAWN_COLOR, low)
		sun.light_energy = lerpf(0.35, 1.35, clampf(sin(PI * t) * 1.4, 0.0, 1.0))
	else:
		sun.light_color = NIGHT_COLOR
		# 0.12 は「月が出ている」だけで「見える」ではなかった。日没後、
		# 環境光が空と一緒に落ちるので、村は影側も路面もまとめて黒に潰れる。
		sun.light_energy = 0.30


## ── 環境光（アンビエント）─────────────────────────────────────
## 昼の影側が真っ黒になるのも、夜が読めないのも、原因は同じ一点：
## `ambient_light_source = SKY` のまま**時刻に対して何もしていない**こと。
## 空のシェーダが暗くなれば環境光もゼロまで落ちる。太陽の当たらない面には
## 光源が一つも残らない —— だから漆喰も柱も同じ黒になる。
## 時刻ごとに「空からいくら貰うか（sky_contribution）」と「自前の下限色を
## いくら足すか（ambient_light_color / energy）」を動かして、影側に必ず
## 材質が残る量の下限を敷く。
const AMBIENT_DAY := Color(0.62, 0.66, 0.74)
const AMBIENT_DUSK := Color(0.42, 0.38, 0.42)
const AMBIENT_NIGHT := Color(0.20, 0.26, 0.40)

func _apply_ambient() -> void:
	# 若地圖已有「天象系統」，環境光、霧色、空色與天頂貢獻均由天象系統獨佔驅動，
	# 此處不得覆寫，避免雙系統每秒數值跳變造成天空／陰影閃爍。
	var current_map: Node = _current_map()
	if current_map != null and _has_sky_system(current_map):
		return
	# 室內圖（稗田邸等）由 interior_lighting.gd 獨佔驅動環境光：屋內看不到
	# 天空，把 sky_contribution 拉回 0.43 等於把近半亮度交給一片看不見的天空，
	# 實測畫面平均亮度掉到 0.17（室外 slice 是 0.46），天花板整片死黑。
	# 這裡不覆寫，室內就沒有日夜——那本來就對：屋裡看不到太陽。
	if current_map != null and current_map.has_meta("interior_lighting"):
		return
	var env := _active_environment()
	if env == null:
		return
	if _env_node != null and (_env_node.name == "天空環境" or _has_sky_system(_env_node.get_parent())):
		return
	# 0 = 真夜中、1 = 正午。日の出前後 1.2h でなめらかに渡す。
	var k := clampf((sin(PI * (hour - 6.0) / 12.0) + 0.18) / 1.18, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(hour - 18.2) / 2.4, 0.0, 1.0)
	var tint := AMBIENT_NIGHT.lerp(AMBIENT_DAY, k).lerp(AMBIENT_DUSK, dusk * 0.7)
	env.ambient_light_color = tint
	# 夜は空そのものが光源として死ぬので、空への依存を下げて下限色に寄せる。
	env.ambient_light_sky_contribution = lerpf(0.22, 0.55, k)
	# ⚠ 昼側を上げすぎない。正午 1.08（＝元の 0.72 から +50%）は影側の黒は
	#   確かに消えたが、漆喰も土も瓦も一様に明るくなり、軒下の影が無くなって
	#   曇天レンダのように平らになった（12:00 の審図で確認）。潰れていたのは
	#   **夜側**なので、持ち上げるのも夜側だけでいい。正午は元の 0.72 から
	#   わずかに上げるに留める。
	env.ambient_light_energy = lerpf(0.58, 0.82, k)
	# コントラスト 1.08 は昼の締まりには効くが、暗部では黒を潰す方向に効く。
	if env.adjustment_enabled:
		env.adjustment_contrast = lerpf(0.98, 1.08, k)
	# 距離霧が昼の灰色のままだと、夜の遠景だけ白っぽく浮く。
	env.fog_light_color = Color(0.34, 0.38, 0.50).lerp(Color(0.78, 0.80, 0.82), k)
	env.fog_light_energy = lerpf(0.55, 1.0, k)


func _active_environment() -> Environment:
	if is_instance_valid(_env_node) and _env_node.environment != null:
		return _env_node.environment
	_env_node = _find_world_environment(get_tree().root)
	return _env_node.environment if _env_node != null else null


func _current_map() -> Node:
	## main.gd が `load_map()` ごとに差し替える地図ルート。これが変わった時
	## だけ環境光と行灯を束ね直す。
	var main := get_tree().root.get_node_or_null("Main")
	return main.map_root if main != null else null


func _find_world_environment(node: Node) -> WorldEnvironment:
	for child in node.get_children():
		if child is WorldEnvironment and child.environment != null:
			return child
		var found := _find_world_environment(child)
		if found != null:
			return found
	return null


func _has_sky_system(node: Node) -> bool:
	if node == null:
		return false
	if node.name == "天象系統" or node is 天象系統:
		return true
	for child in node.get_children():
		if _has_sky_system(child):
			return true
	return false


## ── 行灯 ───────────────────────────────────────────────────
## 街燈は生成時に「常時点灯」で焼かれている。正午の審図で提灯が煌々と
## 光っていたのはそのため。灯は日没前後だけ入れる。
func _apply_lamps() -> void:
	var lamps := _lamps()
	if lamps.is_empty():
		return
	# 17:00 に点り始め 18:6 で全点灯、朝は 5:24〜6:30 で落とす。
	var lit: float = clampf((hour - 17.0) / 1.1, 0.0, 1.0)
	if hour < 12.0:
		lit = clampf((6.5 - hour) / 1.1, 0.0, 1.0)
	for lamp in lamps:
		var light := lamp.get_node_or_null("光") as OmniLight3D
		if light != null:
			light.light_energy = 1.35 * lit
			light.visible = lit > 0.01
	if _lamp_paper != null:
		_lamp_paper.emission_energy_multiplier = 1.9 * lit


func _lamps() -> Array[Node]:
	if _lamp_searched:
		return _lamp_nodes
	if _bound_map == null:
		return _lamp_nodes
	_lamp_searched = true
	# 新路燈是地圖根節點下的獨立物件；用 Godot group 作不可見標籤尋找，
	# 不為了控制燈光而把它們重新塞進共同父節點。
	for candidate in get_tree().get_nodes_in_group("village_lamps"):
		if candidate == _bound_map or _bound_map.is_ancestor_of(candidate):
			_lamp_nodes.append(candidate)
	if not _lamp_nodes.is_empty():
		return _lamp_nodes
	# 舊場景相容：尚未重生的地圖仍可控制「街燈」容器中的辻行灯。
	var legacy_group := _bound_map.find_child("街燈", true, false)
	if legacy_group != null:
		_lamp_nodes.assign(legacy_group.get_children())
	if not _lamp_nodes.is_empty():
		# 行灯紙は 1 枚の共有マテリアル。1 個掴めば全灯に効く。
		var fukuro := _lamp_nodes[0].get_node_or_null("火袋")
		if fukuro is MeshInstance3D and fukuro.mesh != null:
			var mat: Material = fukuro.mesh.surface_get_material(0)
			if mat is StandardMaterial3D and mat.emission_enabled:
				_lamp_paper = mat
	return _lamp_nodes


func clock_text() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]
