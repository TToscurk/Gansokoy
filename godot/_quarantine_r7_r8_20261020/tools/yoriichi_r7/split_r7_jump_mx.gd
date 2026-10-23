extends SceneTree
## R7 P5 普通跳躍：把重定向後的 Sword And Shield Running Jump（jmx_ss_running_jump.res，水平已 freeze）拆成三段候選資源。
##   godot --headless --path godot -s res://tools/yoriichi_r7/split_r7_jump_mx.gd
## 實測拆點（probe_r7_jump_mx.gd，30 fps）：f00–f02 右腳承重（跑步中）、f03 左腳離地＝離地、f14 骨盆最高、f22 右腳觸地、f25＝f00（跑步循環）。
## 素材沒有原地預備段，地面段（蹬地／落地承重）的腳在 freeze 後會滑 0.14–0.36 m → 地面段腿＋骨盆沿用既有 r61（腳固定），
## 上半身與整段空中用 MX。骨盆高度：空中段扣掉素材自身騰空拋物線，只留姿勢造成的骨盆相對變化（物理騰空由控制器負責）。
## 父類時間軸（不改）：JumpStart 從 0.33 播、×1.6、0.567 起跳（物理）；Fall 原速；Land ×1.5。
const OUT := "res://characters/yoriichi/v24_r7/jump_mx/"
const MX := "res://characters/yoriichi/v24_r7/jump_mx/jmx_ss_running_jump.res"
const R61_UP := "res://characters/yoriichi/v24/anims_r61/r61_jump_up.res"
const R61_LAND := "res://characters/yoriichi/v24/anims_r61/r61_land.res"
const FPS := 30.0
const SKIP := 0.33
const TAKEOFF := 0.567
const START_SPEED := 1.6
const JUMP_V := 8.2
const GRAVITY := 20.0
const F_OFF := 3.0      # 離地
const F_APEX := 14.0
const F_FALL_END := 21.0
const F_CONTACT := 22.0
const F_END := 25.0

var mx: Animation
var up: Animation
var land: Animation
var hips_pos_t := -1
var y0 := 0.0   # r61 起跳格骨盆高（track 空間）
var y1 := 0.0   # r61 落地首格骨盆高
var arc_h := 0.0
var s03 := 0.0
var s22 := 0.0

func _initialize() -> void:
	mx = load(MX)
	up = load(R61_UP)
	land = load(R61_LAND)
	for t in mx.get_track_count():
		if mx.track_get_type(t) == Animation.TYPE_POSITION_3D:
			hips_pos_t = t
		assert(str(mx.track_get_path(t)) == str(up.track_get_path(t)) and str(mx.track_get_path(t)) == str(land.track_get_path(t)))
	y0 = (up.position_track_interpolate(hips_pos_t, TAKEOFF) as Vector3).y
	y1 = (land.position_track_interpolate(hips_pos_t, 0.0) as Vector3).y
	s03 = _mx_hips(F_OFF).y
	s22 = _mx_hips(F_CONTACT).y
	# 拋物線高度 H：使頂點格的殘差＝起落線性值 + 0.03（空中略收腿抬骨盆，不疊素材騰空）
	var u := (F_APEX - F_OFF) / (F_CONTACT - F_OFF)
	var lin := (s03 - y0) * (1.0 - u) + (s22 - y1) * u
	arc_h = (_mx_hips(F_APEX).y - lin - (lerpf(y0, y1, u) + 0.03)) / (4.0 * u * (1.0 - u))
	var rows := []
	for f in range(3, 23):
		rows.append([f, snappedf(_mx_hips(f).y, 0.001), snappedf(_air_y(f), 0.001)])
	print("JSPLIT y0=%.3f y1=%.3f arc_h=%.3f  [f, src_y, pose_y]=%s" % [y0, y1, arc_h, JSON.stringify(rows)])
	_save(_build_start(), "r7_jump_mx_start")
	_save(_build_air(), "r7_jump_mx_air")
	_save(_build_land(), "r7_jump_mx_land")
	quit()

func _mx_hips(f: float) -> Vector3:
	return mx.position_track_interpolate(hips_pos_t, clampf(f / FPS, 0.0, mx.length))

## 空中段骨盆＝素材骨盆 − 素材騰空拋物線（起落兩端對齊 r61 起跳／落地格高度）。
func _air_y(f: float) -> float:
	var u := clampf((f - F_OFF) / (F_CONTACT - F_OFF), 0.0, 1.0)
	return _mx_hips(f).y - ((s03 - y0) * (1.0 - u) + (s22 - y1) * u + arc_h * 4.0 * u * (1.0 - u))

func _is_lower(path: String) -> bool:
	for k in ["Hips", "UpLeg", "Leg", "Foot", "Toe"]:
		if path.ends_with(k) or path.contains(":mixamorig_" + k) or path.contains("Left" + k) or path.contains("Right" + k):
			return true
	return false

func _pose(a: Animation, t: float) -> Dictionary:
	var d := {}
	t = clampf(t, 0.0, a.length)
	for i in a.get_track_count():
		match a.track_get_type(i):
			Animation.TYPE_POSITION_3D: d[i] = a.position_track_interpolate(i, t)
			Animation.TYPE_ROTATION_3D: d[i] = a.rotation_track_interpolate(i, t)
	return d

func _mx_pose(f: float) -> Dictionary:
	var d := _pose(mx, f / FPS)
	var v: Vector3 = d[hips_pos_t]
	d[hips_pos_t] = Vector3(v.x, _air_y(f), v.z)
	return d

## 依骨分組混合：w_lower／w_upper＝b 的權重。
func _mix(a: Dictionary, b: Dictionary, w_lower: float, w_upper: float) -> Dictionary:
	var d := {}
	for i in a:
		var w := w_lower if _is_lower(str(mx.track_get_path(i))) else w_upper
		if a[i] is Quaternion:
			d[i] = (a[i] as Quaternion).slerp(b[i], w)
		else:
			d[i] = (a[i] as Vector3).lerp(b[i], w)
	return d

func _ss(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

func _make(length: float, sampler: Callable, loop := false) -> Animation:
	var out := Animation.new()
	out.length = length
	out.step = 1.0 / FPS
	out.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for i in mx.get_track_count():
		var t := out.add_track(mx.track_get_type(i))
		out.track_set_path(t, mx.track_get_path(i))
		out.track_set_interpolation_type(t, mx.track_get_interpolation_type(i))
	var n := int(ceil(length * FPS - 1e-4))
	for k in n + 1:
		var tt := minf(k / FPS, length)
		var p: Dictionary = sampler.call(tt)
		for i in p:
			out.track_insert_key(i, tt, p[i])
	return out

## 起跳段（res 時間）：[0,0.33) r61 原樣（父類跳過）；[0.33,0.567] 腿＋骨盆＝r61 蹬地（腳固定），上半身漸入 MX f00→f03 擺臂；
## 0.567 物理起跳後 → MX f03→f14，腿 0.1 res（≈0.06 s）內由 r61 起跳格接上；上升 0.41 s × 1.6 = 0.656 res；之後頂點慢放到 1.40。
func _build_start() -> Animation:
	var rise_res := (JUMP_V / GRAVITY) * START_SPEED
	var apex_res := TAKEOFF + rise_res
	var r61_off := _pose(up, TAKEOFF)
	var f := func(t: float) -> Dictionary:
		if t < SKIP:
			return _pose(up, t)
		if t <= TAKEOFF:
			var u := (t - SKIP) / (TAKEOFF - SKIP)
			return _mix(_pose(up, t), _mx_pose(F_OFF * u), 0.0, _ss(u))
		if t <= apex_res:
			var u2 := (t - TAKEOFF) / rise_res
			var fr := F_OFF + (F_APEX - F_OFF) * u2
			var wl := _ss((t - TAKEOFF) / 0.1)
			return _mix(r61_off, _mx_pose(fr), wl, 1.0)
		return _mx_pose(F_APEX + 0.5 * (t - apex_res) / (1.40 - apex_res))
	var a := _make(1.40, f)
	a.set_meta("r7_jump_mx", {"apex_res": apex_res, "takeoff": TAKEOFF, "skip": SKIP, "src": "ss_running_jump f00-f14 + r61_jump_up legs 0.33-0.567"})
	return a

## 空中段（Fall，原速，不循環播放——R7 _ready 會把 loop 設回 NONE）：0→0.41 s MX f14.5→f21（一般跳躍頂點到落地）。
## 實測：MX 下降段是跑步大跨步（右腳後伸 0.3 m），直接接 r61 落地會在觸地後把承重腳拖 0.06 m/格 → 最後 0.14 s 腿＋骨盆收向 r61 落地首格
## （雙腳低、近平行，同 r61 落地前的作法），上半身維持 MX。之後 4 s 長滯空：腿停在收好的落地準備姿勢，只留 MX 上半身微擺。
func _build_air() -> Animation:
	var desc := JUMP_V / GRAVITY
	var land0 := _pose(land, 0.0)
	var f := func(t: float) -> Dictionary:
		if t <= desc:
			var w := _ss((t - (desc - 0.14)) / 0.14)
			return _mix(_mx_pose(lerpf(F_APEX + 0.5, F_FALL_END, t / desc)), land0, w, 0.0)
		var ph := (t - desc) / 1.4 * TAU
		return _mix(_mx_pose(20.25 + 0.75 * cos(ph)), land0, 1.0, 0.0)
	var a := _make(desc + 4.2, f)
	a.set_meta("r7_jump_mx", {"desc": desc, "src": "ss_running_jump f14.5-f21 (legs ease to r61_land f0 in last 0.14 s) + upper sway f19.5-f21"})
	return a

## 落地段（Land，×1.5）：腿＋骨盆＝r61 落地承重（雙腳固定，不滑）；上半身 MX f22→f25（0.15 res ≈ 0.1 s）後漸回 r61 收勢（0.6 res）。
func _build_land() -> Animation:
	var f := func(t: float) -> Dictionary:
		var base := _pose(land, t)
		if t <= 0.15:
			return _mix(base, _mx_pose(lerpf(F_CONTACT, F_END, t / 0.15)), 0.0, 1.0)
		return _mix(base, _mx_pose(F_END), 0.0, 1.0 - _ss((t - 0.15) / 0.45))
	var a := _make(land.length, f)
	a.set_meta("r7_jump_mx", {"src": "r61_land legs + ss_running_jump f22-f25 upper"})
	return a

func _save(a: Animation, key: String) -> void:
	print("JSPLIT_SAVED ", key, " len=", snappedf(a.length, 0.001), " err=", ResourceSaver.save(a, OUT + key + ".res"))
