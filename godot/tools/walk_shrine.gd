extends SceneTree
## 神社實機走查：沿主軸模擬玩家移動，量「真的走得過去嗎」+ fps。
##
##   Godot --path godot --script tools/walk_shrine.gd
##
## ⚠ 這支必須跑在**有渲染**的模式（不能 --headless），否則量不到 fps，
##   而且物理世界的碰撞體不會全部就位。
##
## 檢查三件 --playtest 不驗的事：
##   1. 走得動：沿路線每 0.5 m 前進，被卡住 = 該處有非預期碰撞
##   2. 爬得上：石階每一階的高度差不能超過角色 step height
##   3. 跑得動：全程 fps 與最差幀

const ROUTE := [
	[Vector3(0.0, 0.0, 53.0), "南端·獸道口"],
	[Vector3(0.0, 0.0, 44.0), "主鳥居"],
	[Vector3(0.0, 0.0, 20.0), "參道中段"],
	[Vector3(0.0, 0.0, 0.5), "石階底"],
	[Vector3(0.0, 0.0, -9.0), "石階頂"],
	[Vector3(0.0, 0.0, -12.5), "庭院踏步上"],
	[Vector3(0.0, 0.0, -18.0), "庭院前段"],
	[Vector3(0.0, 0.0, -23.0), "拜殿階前"],
	[Vector3(-14.0, 0.0, -21.0), "庭院西(社務所)"],
	[Vector3(14.0, 0.0, -15.0), "庭院東(手水舍)"],
	[Vector3(0.0, 0.0, -33.0), "庭院北緣"],
]

var _fps: Array = []
var _frame := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("[WALK] 開始")
	# ⚠ 必須走 main.tscn，不能直接 load shrine.tscn。
	#   地形碰撞是 main.gd 的 _build_trimesh_collision() 在載圖時才烘的
	#   （場景檔裡只有建築/石階的手做碰撞箱）。直接載 .tscn 的話射線
	#   全部打空，會誤報「整條路線無地面」——第一版就是這樣。
	var ps := load("res://scenes/main.tscn") as PackedScene
	if ps == null:
		print("[WALK] 找不到 main.tscn")
		quit(1)
		return
	var main := ps.instantiate()
	root.add_child(main)
	# 等 main.gd 的 _ready 跑完載圖 + 烘碰撞
	for i in 30:
		await process_frame
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.fov = 70.0
	# 藏起玩家膠囊（會擋自己的射線）
	var player := main.get_node_or_null("Player")
	if player != null:
		(player as Node3D).visible = false
	for i in 6:
		await process_frame
	var space := root.world_3d.direct_space_state

	# ── 1. 沿路線逐段掃描地面與障礙 ──
	print("[WALK] ── 路線可通行性 ──")
	var blocked_total := 0
	var blocked_names := {}
	for i in ROUTE.size() - 1:
		var a: Vector3 = ROUTE[i][0]
		var b: Vector3 = ROUTE[i + 1][0]
		var label: String = "%s → %s" % [ROUTE[i][1], ROUTE[i + 1][1]]
		var seg := (b - a)
		var steps := maxi(2, int(seg.length() / 0.5))
		var prev_y := INF
		var worst_rise := 0.0
		var worst_at := 0.0
		var no_ground := 0
		var blocked := 0
		for s in steps + 1:
			var t := float(s) / float(steps)
			var p := a.lerp(b, t)
			var gy := _ground(space, p.x, p.z)
			if gy == -INF:
				no_ground += 1
				continue
			# 台階高差：相鄰取樣點的地面落差
			if prev_y != INF:
				var rise := absf(gy - prev_y)
				if rise > worst_rise:
					worst_rise = rise
					worst_at = p.z
			prev_y = gy
			# 身體高度有沒有東西擋（腰高 0.9 m 打一顆球）
			# ⚠ 障礙判定不能靠名字。「月台碰撞」既是庭院的**站立面**也是
			#   一個 StaticBody，用名字排除會漏掉真障礙、不排除又全是假警報
			#   （第一版庭院段報 128 次被擋，實際是站在上面）。
			#   正解：射一條**腰高的水平短線**，看前方 0.6 m 有沒有東西擋住。
			#   站立面在腳下，水平線碰不到；真的牆或建築才會擋。
			var fwd := (b - a).normalized()
			var eye := Vector3(p.x, gy + 0.9, p.z)
			var rq := PhysicsRayQueryParameters3D.create(eye, eye + fwd * 0.6)
			var rh := space.intersect_ray(rq)
			if rh.has("position"):
				var col: Object = rh.get("collider")
				var nm := String(col.name) if col else "?"
				blocked_names[nm] = blocked_names.get(nm, 0) + 1
				blocked += 1
		blocked_total += blocked
		var flag := "✓"
		if no_ground > 0 or blocked > 0 or worst_rise > 0.45:
			flag = "✗"
		print("[WALK] %s %-24s 取樣 %3d：無地面 %d、被擋 %d、最大單步落差 %.2f m @ z=%.1f"
			% [flag, label, steps + 1, no_ground, blocked, worst_rise, worst_at])

	if not blocked_names.is_empty():
		print("[WALK] 擋路的碰撞體：%s" % str(blocked_names))

	# ── 2. 石階逐階爬升 ──
	print("[WALK] ── 石階（§23 級高 0.14-0.18）──")
	var z := 0.5
	var last := INF
	var rises: Array = []
	while z > -9.6:
		var gy := _ground(space, 0.0, z)
		if gy != -INF:
			if last != INF and absf(gy - last) > 0.02:
				rises.append(absf(gy - last))
			last = gy
		z -= 0.19
	var mx := 0.0
	for r in rises:
		mx = maxf(mx, float(r))
	print("[WALK] 石階段共量到 %d 個高差，最大 %.3f m %s"
		% [rises.size(), mx, "✓" if mx <= 0.30 else "✗ 有一階太高，會卡住"])

	# ── 3. fps ──
	print("[WALK] ── 效能（沿路線飛一圈）──")
	for i in ROUTE.size():
		var p: Vector3 = ROUTE[i][0]
		var gy := _ground(space, p.x, p.z)
		cam.global_position = Vector3(p.x, (gy if gy != -INF else 0.0) + 1.7, p.z)
		# 看向下一點
		var nxt: Vector3 = ROUTE[(i + 1) % ROUTE.size()][0]
		cam.look_at(Vector3(nxt.x, cam.global_position.y, nxt.z), Vector3.UP)
		for f in 12:
			await process_frame
			_fps.append(Engine.get_frames_per_second())
	var sum := 0.0
	var lo := 9999.0
	for f in _fps:
		sum += float(f)
		lo = minf(lo, float(f))
	print("[WALK] 平均 %.1f fps、最差 %.1f fps（%d 取樣）"
		% [sum / maxf(_fps.size(), 1), lo, _fps.size()])
	# 每個站點單獨報：找出哪個視角最重
	print("[WALK] ── 各站點 fps（後 8 幀平均，跳過鏡頭切換的第 1-4 幀）──")
	for i in ROUTE.size():
		var a := i * 12 + 4
		var b := mini(a + 8, _fps.size())
		if a >= _fps.size():
			break
		var t := 0.0
		for k in range(a, b):
			t += float(_fps[k])
		print("[WALK]   %-14s %.1f fps" % [str(ROUTE[i][1]), t / maxf(b - a, 1)])
	print("[WALK] done")
	quit(0)


## 地面高度：往下逐層打，跳過玩家、邊界牆、建築/石階/樹幹碰撞箱。
## ⚠ 只 visible=false 藏不掉玩家的碰撞體 —— 第一版量到「南端落差 1.71 m」
##   就是射線打到玩家膠囊頭頂（probe_walk_hits.gd 追出來的）。
func _ground(space: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var ex := []
	for k in 8:
		var q := PhysicsRayQueryParameters3D.create(
			Vector3(x, 200.0, z), Vector3(x, -60.0, z))
		var typed: Array[RID] = []
		for r in ex:
			typed.append(r)
		q.exclude = typed
		var hit := space.intersect_ray(q)
		if not hit.has("position"):
			return -INF
		var col: Object = hit.get("collider")
		var nm := String(col.name) if col != null else ""
		if nm.contains("邊界") or nm.contains("Boundary") or nm.contains("Player") 				or nm.contains("建築碰撞") or nm.contains("碰撞"):
			ex.append(hit["rid"])
			continue
		return hit["position"].y
	return -INF
