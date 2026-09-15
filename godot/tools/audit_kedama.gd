extends SceneTree
## 毛玉體檢：量「逃跑路線的地形落差」與「眼睛是否被毛埋住」。
##
##   Godot --headless --path godot --script tools/audit_kedama.gd
##
## 這兩件事都是算得出來的，不必靠看截圖猜。

const TRAIL := "res://maps/trail/trail.tscn"
## 逃跑妖怪群（trail_interactions.tscn 實際值）
const GROUP_POS := Vector2(2.6, -78.0)
const FLEE_DIR := Vector3(1.0, 0.0, -0.3)
const FLEE_DIST := 18.0
## 受傷毛玉
const WOUNDED_POS := Vector2(-1.54 + 2.4, -90.74 - 2.0)


func _terrain_sampler(root: Node3D) -> Callable:
	var terrain: MeshInstance3D = null
	for c in root.get_children():
		if c is MeshInstance3D and str(c.name).findn("Terrain") >= 0:
			terrain = c
	var v: PackedVector3Array = terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var res := int(round(sqrt(float(v.size()))))
	var half := 120.0
	var step := 2.0 * half / float(res - 1)
	return func(x: float, z: float) -> float:
		var fi: float = clampf((x + half) / step, 0.0, float(res - 1))
		var fj: float = clampf((z + half) / step, 0.0, float(res - 1))
		var i0 := int(floor(fi)); var j0 := int(floor(fj))
		var i1: int = mini(i0 + 1, res - 1); var j1: int = mini(j0 + 1, res - 1)
		var tx := fi - float(i0); var tz := fj - float(j0)
		return lerpf(lerpf(v[j0 * res + i0].y, v[j0 * res + i1].y, tx),
			lerpf(v[j1 * res + i0].y, v[j1 * res + i1].y, tx), tz)


func _init() -> void:
	var root := (load(TRAIL) as PackedScene).instantiate() as Node3D
	var gy: Callable = _terrain_sampler(root)

	print("── 1. 逃跑路線地形落差（毛玉只改水平位置，y 不動）──")
	var dir := FLEE_DIR.normalized()
	var start_y: float = gy.call(GROUP_POS.x, GROUP_POS.y)
	var worst := 0.0
	var worst_d := 0.0
	for i in 19:
		var d := float(i) * (FLEE_DIST / 18.0)
		var x: float = GROUP_POS.x + dir.x * d
		var z: float = GROUP_POS.y + dir.z * d
		var h: float = gy.call(x, z)
		var drift: float = h - start_y
		if absf(drift) > absf(worst):
			worst = drift
			worst_d = d
		if i % 3 == 0:
			print("   逃 %5.1f m  地面 y=%6.2f  與起點差 %+.2f m %s"
				% [d, h, drift, "← 毛玉埋進土裡" if drift > 0.4 else ("← 毛玉浮空" if drift < -0.4 else "")])
	print("   最大落差 %+.2f m（逃 %.1f m 處）" % [worst, worst_d])

	print("── 2. 造型：眼睛 vs 毛 的徑向距離 ──")
	var radius := 0.32
	var fur_len := 0.14
	var eye_r := radius * 0.16
	var eye_out := radius * 0.96 + eye_r
	var fur_tip_min := radius + fur_len * 0.7
	var fur_tip_max := radius + fur_len * 1.3
	print("   眼球外緣 %.3f m" % eye_out)
	print("   毛尖     %.3f–%.3f m" % [fur_tip_min, fur_tip_max])
	if eye_out < fur_tip_min:
		print("   ✗ 眼睛整個陷在毛層裡（差 %.3f m），正面看不到眼睛" % (fur_tip_min - eye_out))
	else:
		print("   ✓ 眼睛露出毛層")

	print("── 3. 逃跑路線上的障礙物（樹幹碰撞）──")
	var trunk: Node = null
	for c in root.get_children():
		if str(c.name) == "樹幹碰撞":
			trunk = c
	var hits := 0
	if trunk != null:
		for sh in trunk.get_children():
			var sp: Vector3 = (sh as Node3D).position
			var q := Vector2(sp.x, sp.z)
			# 點到逃跑線段的距離
			var a := GROUP_POS
			var b := GROUP_POS + Vector2(dir.x, dir.z) * FLEE_DIST
			var ab := b - a
			var u := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			if q.distance_to(a + ab * u) < 0.7:
				hits += 1
	print("   逃跑直線 %.0f m 上會穿過 %d 根有碰撞的樹幹" % [FLEE_DIST, hits])
	quit(0)
