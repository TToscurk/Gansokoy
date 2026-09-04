extends SceneTree
## 針對性驗收：被簡化的兩個水口配件，以及去重後的石牆，碰撞面有沒有走樣。
##
##   Godot --headless --path godot --script tools/verify_waterworks_proxy.gd
##
## 方法：在兩個被簡化的物件與四面石牆周圍密集撒垂直射線，把命中高度與
## 「簡化前的基準」比較。基準來自 ground_collision.scn.bak（開刀前那份），
## 兩份同時載入到**各自的**PhysicsServer 世界裡，同一組射線各打一次。
##
## 判準：站立高度差 > 8.7 cm（格點的理論上界）即為異常。

const NEW := "res://maps/slice/gen/ground_collision.scn"
const OLD := "res://maps/slice/gen/ground_collision_baseline.scn"

## 取樣區：被簡化的兩個物件，加上被去重的兩面牆，各自 AABB 稍微外擴。
const AREAS := [
	{"n": "田泵水口_南（已簡化）", "x0": 289.0, "x1": 294.0, "z0": -19.0, "z1": -13.0},
	{"n": "分水堰（已簡化）", "x0": 280.0, "x1": 285.0, "z0": 32.0, "z1": 36.0},
	{"n": "牆_01（已去重）", "x0": 278.0, "x1": 283.0, "z0": -24.0, "z1": -12.0},
	{"n": "牆_05（已去重）", "x0": 278.0, "x1": 283.0, "z0": 12.0, "z1": 24.0},
	{"n": "親水階梯（未動，對照）", "x0": 277.0, "x1": 286.0, "z0": -8.0, "z1": 2.0},
	{"n": "石造堰檻（未動，對照）", "x0": 283.0, "x1": 294.0, "z0": 32.0, "z1": 36.0},
]
const STEP := 0.20


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var new_world := _world(NEW)
	var old_world := _world(OLD)
	if new_world == null or old_world == null:
		print("[VER] 世界建立失敗")
		quit(1)
		return
	for i in 4:
		await physics_frame

	var worst_all := 0.0
	var fails := 0
	print("[VER] %-26s %7s %9s %9s %9s %9s" % [
		"取樣區", "射線數", "新增失面", "新增多面", "最大高差", "平均高差"])
	for a in AREAS:
		var lost := 0     # 舊有面、新沒面（可能讓玩家掉下去）
		var gained := 0   # 舊沒面、新有面（可能讓玩家浮起）
		var n := 0
		var worst := 0.0
		var sum := 0.0
		var cmp := 0
		var x := float(a["x0"])
		while x <= float(a["x1"]):
			var z := float(a["z0"])
			while z <= float(a["z1"]):
				n += 1
				var yn := _ray(new_world, x, z)
				var yo := _ray(old_world, x, z)
				if is_nan(yn) and not is_nan(yo):
					lost += 1
				elif is_nan(yo) and not is_nan(yn):
					gained += 1
				elif not is_nan(yn) and not is_nan(yo):
					var d := absf(yn - yo)
					sum += d
					cmp += 1
					worst = maxf(worst, d)
				z += STEP
			x += STEP
		worst_all = maxf(worst_all, worst)
		var flag := ""
		if worst > 0.087 or lost > 0:
			flag = "  ← 超出 ±8.7cm 上界" if worst > 0.087 else "  ← 出現無底點"
			fails += 1
		print("[VER] %-26s %7d %9d %9d %8.3fm %8.3fm%s" % [
			a["n"], n, lost, gained, worst, sum / maxf(cmp, 1), flag])

	print("[VER] 全域最大高差 %.3f m（理論上界 0.087 m）；異常區 %d" % [worst_all, fails])
	_hotspots(new_world, old_world)
	print("[VER] done")
	quit(0)


## 超標點逐一列出：位置、新舊高度、以及該點是否落在玩家可能站立的高度帶。
## 薄殼在陡面上被格點吸附時，垂直射線的首擊可能從殼的正面翻到背面，
## 高度會跳一整個殼厚——那不是「地面下沉」，而是射線打到別的面。
## 分辨方法：看新高度是否仍在該處的水面/河床之間，且玩家是否構得到。
func _hotspots(new_world: World3D, old_world: World3D) -> void:
	print("[VER] --- 超標點明細（差 > 8.7 cm）---")
	var rows: Array = []
	for a in AREAS:
		var x := float(a["x0"])
		while x <= float(a["x1"]):
			var z := float(a["z0"])
			while z <= float(a["z1"]):
				var yn := _ray(new_world, x, z)
				var yo := _ray(old_world, x, z)
				if not is_nan(yn) and not is_nan(yo) and absf(yn - yo) > 0.087:
					rows.append({"x": x, "z": z, "n": yn, "o": yo, "d": absf(yn - yo)})
				z += STEP
			x += STEP
	rows.sort_custom(func(p, q): return p["d"] > q["d"])
	print("[VER]   共 %d 個超標點" % rows.size())
	var i := 0
	for r in rows:
		if i >= 12:
			break
		print("[VER]   x=%.1f z=%.1f  舊 y=%.3f → 新 y=%.3f  差 %.3f m" % [
			r["x"], r["z"], r["o"], r["n"], r["d"]])
		i += 1


## 把一份碰撞場景實例化到自己的 World3D，兩份互不干擾。
func _world(path: String) -> World3D:
	if not ResourceLoader.exists(path):
		print("[VER] 找不到 %s" % path)
		return null
	var packed := ResourceLoader.load(path, "PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if packed == null:
		return null
	var vp := SubViewport.new()
	root.add_child(vp)
	vp.world_3d = World3D.new()
	vp.add_child(packed.instantiate())
	return vp.world_3d


func _ray(w: World3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, 40.0, z), Vector3(x, -40.0, z), 0xFFFFFFFF)
	var hit := w.direct_space_state.intersect_ray(q)
	return NAN if hit.is_empty() else hit["position"].y
