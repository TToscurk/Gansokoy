extends SceneTree
## 手動碰撞箱產生器：讀 data/slice_manual_collision.json，輸出成一個獨立場景。
##
## 為什麼是 JSON 而不是編輯器：碰撞箱是純數字（中心 + 尺寸），用文字檔改比在
## 3D 視窗裡拖曳更準、可比對、可版本控制。改完跑這支就生效，不必開編輯器。
##
## 產出 gen/manual_collision.scn，已 instance 進 slice.tscn。既有的
## building_collision / ground_collision / lamp_collision 完全不動——這是「再加一層」，
## 不是取代。
##
##   Godot --headless --path godot --script tools/gen_manual_collision.gd
const SRC := "res://data/slice_manual_collision.json"
const OUT := "res://maps/slice/gen/manual_collision.scn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var txt := FileAccess.get_file_as_string(SRC)
	if txt.is_empty():
		print("[手動碰撞] ✗ 讀不到 %s" % SRC)
		quit(1)
		return
	var data: Variant = JSON.parse_string(txt)
	if not (data is Dictionary) or not (data as Dictionary).has("boxes"):
		print("[手動碰撞] ✗ JSON 格式不對：最外層要是物件，且有 boxes 陣列")
		quit(1)
		return
	var root_node := Node3D.new()
	root_node.name = "手動碰撞"
	var made := 0
	var off := 0
	var bad := 0
	# ── 邊界牆：把玩家關在做好的區域內 ──
	# slice 原本一個邊界都沒有（trail 與 shrine 都有），而 UnifiedGround 是
	# 2500 m 見方的大地面 —— 走出村子後到處都站得住，只是什麼都沒有。
	var bd: Dictionary = (data as Dictionary).get("boundary", {})
	if not bd.is_empty() and bool(bd.get("enabled", true)):
		var x0 := float(bd.get("min_x", 0.0))
		var x1 := float(bd.get("max_x", 0.0))
		var z0 := float(bd.get("min_z", 0.0))
		var z1 := float(bd.get("max_z", 0.0))
		var by := float(bd.get("base_y", -5.0))
		var hh := float(bd.get("height", 60.0))
		var th := float(bd.get("thickness", 2.0))
		if x1 - x0 < 1.0 or z1 - z0 < 1.0:
			print("[手動碰撞] ✗ boundary：max 必須大於 min")
			bad += 1
		else:
			var cx := (x0 + x1) * 0.5
			var cz := (z0 + z1) * 0.5
			var cy := by + hh * 0.5
			var w := x1 - x0 + th * 2.0
			var d := z1 - z0 + th * 2.0
			# 牆立在範圍「外側」，牆內側恰好是 min/max 那條線
			var walls := [
				["邊界牆_西", Vector3(x0 - th * 0.5, cy, cz), Vector3(th, hh, d)],
				["邊界牆_東", Vector3(x1 + th * 0.5, cy, cz), Vector3(th, hh, d)],
				["邊界牆_北", Vector3(cx, cy, z0 - th * 0.5), Vector3(w, hh, th)],
				["邊界牆_南", Vector3(cx, cy, z1 + th * 0.5), Vector3(w, hh, th)],
			]
			for wl in walls:
				var wb := StaticBody3D.new()
				wb.name = String(wl[0])
				wb.collision_layer = 1
				wb.collision_mask = 0
				wb.position = wl[1]
				var wc := CollisionShape3D.new()
				var wbox := BoxShape3D.new()
				wbox.size = wl[2]
				wc.shape = wbox
				wb.add_child(wc)
				root_node.add_child(wb)
				wb.owner = root_node
				wc.owner = root_node
				made += 1
			print("[手動碰撞] 邊界牆 x[%.0f, %.0f] z[%.0f, %.0f] 高 %.0f m（%.0f × %.0f m 遊玩區）"
				% [x0, x1, z0, z1, hh, x1 - x0, z1 - z0])
	for b in (data as Dictionary)["boxes"]:
		if not (b is Dictionary):
			continue
		var e: Dictionary = b
		var nm := String(e.get("name", "box_%d" % made))
		if not bool(e.get("enabled", true)):
			off += 1
			continue
		var pos: Array = e.get("pos", [])
		var size: Array = e.get("size", [])
		if pos.size() != 3 or size.size() != 3:
			print("[手動碰撞] ✗ %s：pos/size 必須各是 3 個數字" % nm)
			bad += 1
			continue
		var sz := Vector3(float(size[0]), float(size[1]), float(size[2]))
		if sz.x <= 0.0 or sz.y <= 0.0 or sz.z <= 0.0:
			print("[手動碰撞] ✗ %s：size 不能有 0 或負數 %s" % [nm, str(sz)])
			bad += 1
			continue
		var body := StaticBody3D.new()
		body.name = nm
		# layer 1 = 玩家會撞到的東西（與 building_collision 一致）
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = sz
		col.shape = box
		body.add_child(col)
		root_node.add_child(body)
		body.owner = root_node
		col.owner = root_node
		made += 1
	var packed := PackedScene.new()
	packed.pack(root_node)
	var err := ResourceSaver.save(packed, OUT)
	print("[手動碰撞] 寫入 %s：%d 個箱子（停用 %d、格式錯 %d、err=%d）"
		% [OUT, made, off, bad, err])
	quit(1 if (err != OK or bad > 0) else 0)
