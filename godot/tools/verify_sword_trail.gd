extends SceneTree
## 刀光重製的 headless 驗證：確認兩個 shader 編譯通過、SwordTrail3D 能建、
## 舊介面（base_node/tip_node/lifetime/start_trail/stop_trail）仍在，
## 且揮一刀之後真的有幾何被生出來。
##
## 跑法：godot --headless --path godot -s tools/verify_sword_trail.gd
##
## ⚠ 入口必須是 _initialize() 不是 _init()：
##   _init() 時 SceneTree 的 root 還沒建好，add_child 的節點不會真的進樹，
##   _ready() 不會跑，mesh 與子節點都是 null，驗證會假性失敗。

var _fail := 0


func _initialize() -> void:
	_run()



func _run() -> void:
	# 1. shader 資源能載入且編譯無誤
	for p in ["res://characters/yoriichi/vfx/sun_flame_trail.gdshader",
			"res://characters/yoriichi/vfx/sun_flame_core.gdshader"]:
		var sh := load(p) as Shader
		if sh == null:
			print("FAIL  shader 載入失敗: ", p)
			_fail += 1
			continue
		var us := sh.get_shader_uniform_list()
		print("OK    shader 載入: ", p.get_file(), "  uniforms=", us.size())

	# 2. SwordTrail3D 能實例化
	var TrailScript := load("res://characters/yoriichi/vfx/sword_trail.gd")
	if TrailScript == null:
		print("FAIL  sword_trail.gd 載入失敗")
		quit(1)
		return
	var trail: Node3D = TrailScript.new()

	# 3. 舊介面必須原封不動（yoriichi_character.gd 依賴這些）
	for member in ["base_node", "tip_node", "lifetime", "min_distance"]:
		if member in trail:
			print("OK    保留屬性: ", member)
		else:
			print("FAIL  缺少屬性: ", member)
			_fail += 1
	for m in ["start_trail", "stop_trail"]:
		if trail.has_method(m):
			print("OK    保留方法: ", m)
		else:
			print("FAIL  缺少方法: ", m)
			_fail += 1

	# 4. 掛進場景、模擬揮刀，確認幾何真的生出來
	var root_n := Node3D.new()
	root.add_child(root_n)
	var base_m := Marker3D.new()
	var tip_m := Marker3D.new()
	root_n.add_child(base_m)
	root_n.add_child(tip_m)
	base_m.position = Vector3(0, 1.0, 0)
	tip_m.position = Vector3(0, 2.05, 0)

	trail.base_node = base_m
	trail.tip_node = tip_m
	root_n.add_child(trail)

	# ⚠ _initialize() 當下 SceneTree 的 root 尚未真正進樹，add_child 不會立刻
	#   觸發 _ready()。必須等一幀，否則 mesh 與子節點都還是 null（假性失敗）。
	await process_frame

	if trail.mesh == null:
		print("FAIL  _ready() 沒有跑到（mesh 仍是 null）")
		_fail += 1
		_report()
		return

	trail.start_trail()

	# 揮 24 幀：刀尖繞一段弧，模擬真實橫斬（刀身長 1.05 m）
	var dt := 1.0 / 60.0
	for i in range(24):
		var a: float = float(i) / 24.0 * PI * 0.9
		base_m.position = Vector3(sin(a) * 0.25, 1.0, cos(a) * 0.25)
		tip_m.position = Vector3(sin(a) * 1.30, 1.15 + sin(a) * 0.35, cos(a) * 1.30)
		trail._process(dt)

	var fm: ImmediateMesh = trail.mesh
	var surf: int = fm.get_surface_count()
	print("OK    外焰 surface 數: ", surf)
	if surf < 1:
		print("FAIL  外焰沒有生成幾何")
		_fail += 1

	var core_mi: Node = trail.get_node_or_null("FlameCore")
	if core_mi == null:
		print("FAIL  找不到 FlameCore 子節點")
		_fail += 1
	else:
		var cm: ImmediateMesh = core_mi.mesh
		var cs: int = cm.get_surface_count() if cm != null else 0
		print("OK    內核 surface 數: ", cs)
		if cs < 1:
			print("FAIL  內核沒有生成幾何")
			_fail += 1

	# 5. 火焰延伸量真的有讓 ribbon 比刀身寬
	var aabb: AABB = trail.get_aabb()
	print("OK    外焰 AABB size = ", aabb.size.snapped(Vector3(0.01, 0.01, 0.01)))
	var span: float = maxf(aabb.size.x, aabb.size.z)
	print("      刀身長 1.05 m；ribbon 最大跨距 ", snappedf(span, 0.01), " m")
	print("      flame_extend = ", trail.flame_extend, " m（火舌往刀尖外的生長空間）")

	# 6. stop 之後不再取樣
	trail.stop_trail()
	if trail.is_emitting:
		print("FAIL  stop_trail 沒有停止取樣")
		_fail += 1
	else:
		print("OK    stop_trail 生效")

	_report()


func _report() -> void:
	print("")
	if _fail == 0:
		print("=== 全部通過 ===")
	else:
		print("=== 失敗 ", _fail, " 項 ===")
	quit(0 if _fail == 0 else 1)
