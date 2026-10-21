extends "res://tools/verify_shrine_v2_walk.gd"
## 錄影用：真控制器沿 verify_shrine_v2_walk.gd 的 ROUTE 走一遍（去程），不做任何檢查。
##   godot --path godot --resolution 1280x720 --write-movie <out.avi> --fixed-fps 60 --script tools/shrine_v2/record_walk.gd
## Movie Maker 以固定幀率逐幀輸出（60 fps＝物理 tick 1:1），播放速度＝遊戲原速。
## 轉檔：ffmpeg -i out.avi -c:v libx264 -crf 20 -pix_fmt yuv420p out.mp4


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	# 命令列要帶 `-- --map=shrine_v2` 讓 main 直接開候選圖：先開村再 load_map 的話，村的非同步出生（237.1, 40, 71.7）
	# 會在切圖後的下一幀把玩家傳回村裡座標 → 掉出世界（Movie Maker 模式實測；無頭／一般視窗模式碰巧沒踩到）。
	if main.current_id != MAP_ID:
		main.load_map(MAP_ID, "")
	await _settle(60)
	player = main.get_node_or_null("Player")
	yaw = Node3D.new()
	main.add_child(yaw)
	player.input_yaw_node = yaw
	print("[REC] 出生 %s on_floor=%s 地圖=%s" % [_v(player.global_position), str(player.is_on_floor()), main.current_id])
	await _skip_dialogue()
	print("[REC] 對話後 %s on_floor=%s" % [_v(player.global_position), str(player.is_on_floor())])
	await _settle(60)
	print("[REC] 起跑前 %s on_floor=%s" % [_v(player.global_position), str(player.is_on_floor())])
	for r in ROUTE:
		var res: Dictionary = await _walk_to(Vector3(float(r[1]), float(r[3]), float(r[2])), String(r[0]), "")
		print("[REC] %s %s" % [r[0], res.reason])
		if not res.arrived:
			break
	await _settle(120)
	print("[REC] done")
	quit()
