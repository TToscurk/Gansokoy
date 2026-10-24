extends RefCounted
## 共用刀身命中判定（v24_isshin 候選；R9 起所有候選場景共用同一套，命中結果不因場景而不同）。
## 規則（沿用居合／二連斬／突刺／X 斬／道場已驗證的條件，範圍不放大）：
##   * 只算刀身：刀上 u ≥ 0.25（護手→刀尖 16 等分的第 4～16 點），刀柄、護手、握刀的手不算。
##   * 目標形狀＝木樁網格的實際半徑（圓柱底 0.26／頂 0.22，頭球 0.20）；可換成其他目標的 radius_fn(y)。
##   * 刀刃要切進表面 MIN_DEPTH（5 cm）才算命中。
##   * 幀間掃掠：上一幀→這一幀之間，刀的整個變換插值 4 段（護手位置線性、旋轉 slerp），取最早切入的那一段；
##     判定窗剛打開的那一幀，只檢查「窗打開之後」的那一段（不把開窗前刀已在木樁裡的位置算成命中）。
## 用法：每幀 combat.step() 之前 begin_frame()、之後 end_frame(sword.global_transform)；hit_test 回呼裡呼叫 test()。
const GUARD_LOCAL := Vector3(0, 0.0, 0)
const TIP_LOCAL := Vector3(0, 1.085, 0)       # Sword_Hand 本地座標：刀尖（刀模型 AABB y −0.38…1.085）
const SAMPLES := 16
const MIN_U_IDX := 4
const SUBSTEPS := 4
const MIN_DEPTH := 0.05
const Y_MIN := 0.05
const Y_MAX := 1.95

var prev_xf := Transform3D()
var last_xf := Transform3D()
var radius_fn: Callable = dummy_r
## R16c：幀間插值段數（預設＝SUBSTEPS＝原樣）；只有刀速極快的候選（炎舞 2 倍速，刀尖 145 m/s）由場景依技能設定調高，
## 讓每段的取樣間距和原速時相同（判定條件本身——刀身範圍、半徑、切入深度——不變）
var substeps := SUBSTEPS

static func dummy_r(y: float) -> float:
	if y > 1.6:
		return sqrt(maxf(0.0, 0.04 - pow(y - 1.75, 2.0)))
	return 0.26 - 0.025 * clampf(y, 0.0, 1.6)

func begin_frame() -> void:
	prev_xf = last_xf

func end_frame(sword_xf: Transform3D) -> void:
	last_xf = sword_xf

## cur＝這一幀的刀（Sword_Hand global_transform）；target＝目標地面中心（世界）；shot_t／dt／strikes：判定窗剪裁用
func test(cur: Transform3D, target: Vector3, shot_t: float, dt: float, strikes: Array, tip_v := Vector3.ZERO, tip_speed := 0.0) -> Dictionary:
	var t0 := shot_t - dt
	var wmin := 0.0
	for w in strikes:
		if shot_t >= float(w[0]) and shot_t <= float(w[1]) and t0 < float(w[0]) and dt > 0.0:
			wmin = clampf((float(w[0]) - t0) / dt, 0.0, 1.0)
	var prev := prev_xf if prev_xf != Transform3D() else cur
	for k in range(1, substeps + 1):
		var w2 := float(k) / float(substeps)
		if w2 < wmin - 1e-4:
			continue
		var xf := prev.interpolate_with(cur, w2)
		var a := xf * GUARD_LOCAL
		var b := xf * TIP_LOCAL
		var best := 0.0
		var hit := {}
		for i in range(MIN_U_IDX, SAMPLES + 1):
			var u := float(i) / float(SAMPLES)
			var p := a.lerp(b, u)
			var hv := Vector2(p.x - target.x, p.z - target.z)
			var r: float = radius_fn.call(p.y - target.y)
			var depth := r - hv.length()
			if p.y - target.y > Y_MIN and p.y - target.y < Y_MAX and depth > maxf(best, MIN_DEPTH):
				best = depth
				var n := hv.normalized() if hv.length() > 1e-3 else Vector2(0, -1)
				var dv := tip_v.normalized() if tip_v.length() > 0.5 else Vector3.DOWN
				hit = {"pos": Vector3(target.x + n.x * r, p.y, target.z + n.y * r), "dir": dv, "tip_speed": tip_speed, "blade_u": u, "depth": depth, "sub": w2}
		if not hit.is_empty():
			var e := entry(a, b, target)
			if not e.is_empty():
				hit["entry"] = e["p"]
				hit["entry_u"] = e["u"]
			return hit
	return {}

## 刀身從護手往刀尖走、第一次碰到目標表面的那一點（刀刃切進去的入口；火花／命中火焰放這裡）
func entry(a: Vector3, b: Vector3, target: Vector3) -> Dictionary:
	var prev_out := -1.0
	for i in range(0, 65):
		var u := float(i) / 64.0
		var p := a.lerp(b, u)
		var inside := Vector2(p.x - target.x, p.z - target.z).length() < float(radius_fn.call(p.y - target.y)) and p.y - target.y > Y_MIN
		if inside and prev_out >= 0.0:
			return {"p": a.lerp(b, (u + prev_out) * 0.5), "u": u}
		if not inside:
			prev_out = u
	return {}
