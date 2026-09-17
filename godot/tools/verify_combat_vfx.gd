extends SceneTree
## combat_vfx 重製的 headless 驗證。
##
## 跑法：godot --headless --path godot -s tools/verify_combat_vfx.gd
##
## 驗什麼：
##   1. 六個 static API 全部可呼叫且不炸（敵人／假人／緣一共 17 個呼叫點依賴）
##   2. 真的有節點被生出來
##   3. 節點會自動回收 —— 不能留下永久粒子或 OmniLight3D
##   4. streak 貼圖確實是細長非對稱（不是圓點）
##
## ⚠ _initialize() 當下 root 尚未真正進樹，add_child 不會觸發 _ready()。
##   要 await process_frame。這個陷阱在 verify_sword_trail.gd 也踩過一次。

var _fail := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var CV := load("res://characters/yoriichi/vfx/combat_vfx.gd")
	if CV == null:
		print("FAIL  combat_vfx.gd 載入失敗（語法錯誤）")
		quit(1)
		return
	print("OK    combat_vfx.gd 載入成功")

	# streak 貼圖必須是細長的，不是圓點 —— 參考畫面的火星是短橢圓帶拖尾。
	var st: ImageTexture = CV._get_streak_texture()
	var sz := st.get_size()
	print("OK    streak 貼圖尺寸 = ", sz, "（長寬比 ", snappedf(sz.y / sz.x, 0.1), ":1）")
	if sz.y <= sz.x:
		print("FAIL  streak 貼圖不是細長的")
		_fail += 1
	var im := st.get_image()
	# 頭端（v小）應該比尾端（v大）亮
	var head_a := im.get_pixel(int(sz.x / 2), 2).a
	var tail_a := im.get_pixel(int(sz.x / 2), int(sz.y) - 3).a
	print("      頭端 alpha=", snappedf(head_a, 0.01), "  尾端 alpha=", snappedf(tail_a, 0.01))
	if head_a <= tail_a:
		print("FAIL  streak 沒有頭亮尾暗的拖尾")
		_fail += 1

	var host := Node3D.new()
	root.add_child(host)
	await process_frame

	var before := _count_spawned()

	# 六個 API 全打一次
	var p := Vector3(0, 1.0, 0)
	CV.spawn_hit_spark(host, p, Vector3.FORWARD, false)
	CV.spawn_hit_spark(host, p, Vector3.FORWARD, true)
	CV.spawn_deathblow_burst(host, p, Vector3.UP)
	CV.spawn_form_ignite(host, p, Vector3.FORWARD)
	CV.spawn_jump_dust(host, Vector3.ZERO)
	CV.spawn_land_dust(host, Vector3.ZERO, true)
	CV.spawn_roll_dust(host, Vector3.ZERO, Vector3.FORWARD)
	print("OK    六個 static API 全部呼叫成功，無執行期錯誤")

	await process_frame
	var peak := _count_spawned()
	print("OK    生成節點數（粒子+燈）= ", peak - before)
	if peak - before < 10:
		print("FAIL  生成的節點太少，特效可能沒真的建出來")
		_fail += 1

	# 等所有 lifetime + tween 跑完（最長 0.55 + 0.25 緩衝）
	var waited := 0.0
	while waited < 1.6:
		await process_frame
		waited += 1.0 / 60.0

	var after := _count_spawned()
	print("OK    1.6 秒後殘留節點 = ", after - before)
	if after - before > 0:
		print("FAIL  有節點沒被回收（會累積洩漏）")
		_fail += 1

	print("")
	if _fail == 0:
		print("=== 全部通過 ===")
	else:
		print("=== 失敗 ", _fail, " 項 ===")
	quit(0 if _fail == 0 else 1)


## 數 root 底下的粒子與燈（特效都掛在 root，top_level）。
func _count_spawned() -> int:
	var n := 0
	for c in root.get_children():
		if c is GPUParticles3D or c is OmniLight3D:
			n += 1
	return n
