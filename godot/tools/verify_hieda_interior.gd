extends SceneTree
## 稗田邸室內：亮度實測 + 室內動線實走。
##
## 亮度不靠肉眼講「有點暗」——直接算算 render 出來的平均亮度與過暗像素比例。
## 動線不靠傳送——用真實輸入從落點走到同層的每個傳送區。

var failures := 0
var main: Node = null
var player: Node = null
var yaw: Node3D = null
var _floor_id := ""

## 室內平均亮度下限（0~1 線性）。低於此值畫面讀不出格局。
const MIN_MEAN_LUMA := 0.10
## 「幾乎全黑」像素（luma < 0.02）的比例上限。
const MAX_BLACK_RATIO := 0.42

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[IN] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _meta(id: String) -> Dictionary:
	var f := FileAccess.open("res://data/%s.meta.json" % id, FileAccess.READ)
	if f == null:
		return {}
	var j: Variant = JSON.parse_string(f.get_as_text())
	return j if j is Dictionary else {}

func _hold(a: String, down: bool) -> void:
	var e := InputEventAction.new()
	e.action = a
	e.pressed = down
	Input.parse_input_event(e)

## 從落點以真實輸入走向 target，回傳 {ok, dist, why}。不換圖，只看走不走得到。
func _walk_within(target: Vector3, limit: float) -> Dictionary:
	var t := 0.0
	var best := INF
	var last: Vector3 = player.global_position
	var last_t := 0.0
	_hold("move_forward", true)
	while t < limit:
		var delta := get_root().get_process_delta_time()
		var d: Vector3 = target - player.global_position
		d.y = 0.0
		var dist := d.length()
		best = minf(best, dist)
		if dist < 1.6:
			_hold("move_forward", false)
			return {"ok": true, "dist": dist, "why": "reached"}
		# 走到傳送區就會換圖 —— 那正是「走得到」的鐵證，不是卡住。
		if main.current_id != _floor_id:
			_hold("move_forward", false)
			return {"ok": true, "dist": dist, "why": "走到就傳送了（→ %s）" % main.current_id}
		if dist > 0.01:
			yaw.rotation.y = atan2(-d.normalized().x, -d.normalized().z)
		await physics_frame
		await process_frame
		t += delta
		if t - last_t >= 3.0:
			if last.distance_to(player.global_position) < 0.6:
				_hold("move_forward", false)
				return {"ok": false, "dist": best,
					"why": "卡在 %s（離目標 %.1f m）" % [str(player.global_position), dist]}
			last = player.global_position
			last_t = t
	_hold("move_forward", false)
	return {"ok": false, "dist": best, "why": "逾時（最近 %.1f m）" % best}

## render 一幀並回傳 {mean, black_ratio}。
func _measure(cam: Camera3D, pos: Vector3, look: Vector3) -> Dictionary:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	await _wait(8)
	var img: Image = main.get_viewport().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var total := 0.0
	var black := 0
	var n := 0
	# 取樣即可，不必逐像素；跳過頂端 60 px 的 HUD 文字。
	for y in range(60, h, 4):
		for x in range(0, w, 4):
			var c := img.get_pixel(x, y)
			var l: float = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			total += l
			if l < 0.02:
				black += 1
			n += 1
	return {"mean": total / maxf(n, 1), "black_ratio": float(black) / maxf(n, 1)}

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 75.0

	for spec in [["hieda1f", "slice"], ["hieda2f", "hieda1f"], ["hieda3f", "hieda2f"]]:
		var id: String = spec[0]
		_floor_id = id
		main.load_map(id, spec[1])
		await _wait(70)
		player = main.get_node_or_null("Player")
		player.visible = false
		if yaw == null:
			yaw = Node3D.new()
			main.add_child(yaw)
		player.input_yaw_node = yaw
		var p: Vector3 = player.global_position

		# --- 亮度：站在落點環顧四個方向 -----------------------------
		var sum_mean := 0.0
		var worst_black := 0.0
		for i in 4:
			var ang := TAU * float(i) / 4.0
			var look := p + Vector3(sin(ang), 0.0, cos(ang)) * 8.0 + Vector3(0, 1.3, 0)
			var m: Dictionary = await _measure(cam, p + Vector3(0, 1.6, 0), look)
			sum_mean += float(m.mean)
			worst_black = maxf(worst_black, float(m.black_ratio))
		var mean: float = sum_mean / 4.0
		print("[IN] %s 亮度：平均 luma=%.4f，最暗方向全黑比例=%.1f%%"
			% [id, mean, worst_black * 100.0])
		check("%s 室內夠亮（平均 luma %.3f ≥ %.2f）" % [id, mean, MIN_MEAN_LUMA],
			mean >= MIN_MEAN_LUMA)
		check("%s 沒有大片死黑（%.1f%% ≤ %.0f%%）" % [id, worst_black * 100.0, MAX_BLACK_RATIO * 100.0],
			worst_black <= MAX_BLACK_RATIO)

		# --- 動線：從落點走到同層其他傳送區 -------------------------
		for pt in _meta(id).get("portals", []):
			var tgt: String = str(pt.get("target", ""))
			if tgt.is_empty():
				continue
			player.global_position = p
			player.velocity = Vector3.ZERO
			await _wait(20)
			var goal := Vector3(float(pt.x), float(pt.y), float(pt.z))
			var flat := goal
			flat.y = p.y
			var start_dist: float = Vector2(p.x - goal.x, p.z - goal.z).length()
			var r: Dictionary = await _walk_within(flat, 30.0)
			print("[IN] %s → %s 口：起始 %.1f m，%s" % [id, tgt, start_dist, r.why])
			check("%s 走得到往 %s 的傳送區：%s" % [id, tgt, r.why], r.ok)
			# 走過去會觸發傳送，換圖就重載回來繼續測。
			if main.current_id != id:
				main.load_map(id, spec[1])
				await _wait(70)
				player = main.get_node_or_null("Player")
				player.visible = false
				player.input_yaw_node = yaw

	print("[IN] failures=%d" % failures)
	quit(failures)
