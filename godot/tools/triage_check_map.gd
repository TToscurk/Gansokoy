extends SceneTree
## check_map 回報的 12 個問題是真缺陷還是誤報？
##
##   Godot --headless --path godot --script tools/triage_check_map.gd
##
## 兩類：
##  (1) 11 片「水面埋在地面下」——全在 MachiCanal 水路裡。水路是**下挖**的
##      渠道，水面本來就低於村道；check_map 若拿 UnifiedGround 當比較基準，
##      那是拿村道高度去比渠底水面，必然全部「埋住」。要判定真偽，得看水面
##      正上方到底有沒有實體地面擋著（射線從水面往上打）。
##  (2) 2 個空的 MultiMesh（GrassFlower / GrassTall）——0 個實例代表那層在
##      引擎裡完全看不見，這個無論如何都是真的，只是要確認是否刻意清空。

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.load_map("slice", "")
	for i in 8:
		await physics_frame
	var space: PhysicsDirectSpaceState3D = main.map_root.get_world_3d().direct_space_state

	print("[TRIAGE] === 水面「被埋」查證 ===")
	print("[TRIAGE] 方法：從水面中心往上打射線。真的被埋 → 上方有實體；")
	print("[TRIAGE]       只是位於渠底 → 上方是空的（看得到天空）。")
	print("[TRIAGE] %-18s %9s %10s %s" % ["水面", "水面Y", "上方遮蔽", "判定"])

	var names := ["UpstreamWater", "DownstreamWater", "WeirDrop", "WheelRaceWater",
		"WheelRaceDrop", "RaceTailDrop", "Reach_Lower", "Reach_Upper",
		"FeederWater", "FeederSplash", "FeederNappe"]
	var truly_buried := 0
	for nm in names:
		var node := main.map_root.find_child(nm, true, false) as MeshInstance3D
		if node == null:
			print("[TRIAGE] %-18s 找不到節點" % nm)
			continue
		var wb := node.global_transform * node.get_aabb()
		var c := wb.get_center()
		var top := wb.end.y
		# 從水面上方 0.2 m 往上打 40 m，看有沒有東西擋著
		var q := PhysicsRayQueryParameters3D.create(
			Vector3(c.x, top + 0.2, c.z), Vector3(c.x, top + 40.0, c.z), 0xFFFFFFFF)
		var hit := space.intersect_ray(q)
		var blocked := ""
		if hit.is_empty():
			blocked = "無（露天）"
		else:
			blocked = "%s @ y=%.2f" % [
				String((hit["collider"] as Node).name), hit["position"].y]
			truly_buried += 1
		print("[TRIAGE] %-18s %9.2f %10s %s" % [
			nm, top, "有" if not hit.is_empty() else "無",
			blocked + ("   ← 真的被蓋住" if not hit.is_empty() else "   ✓ 位於渠底，非缺陷")])

	print("[TRIAGE] → 11 片中真正被實體蓋住的：%d 片" % truly_buried)

	print("[TRIAGE] === 空 MultiMesh 查證 ===")
	for nm in ["GrassFlower", "GrassTall", "草筆刷_矮草", "草筆刷_高草", "草筆刷_牆根雜草"]:
		var n: Node = main.map_root.find_child(nm, true, false)
		if n == null:
			print("[TRIAGE] %-14s 找不到" % nm)
			continue
		if n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			var cnt := 0 if mm == null else mm.instance_count
			print("[TRIAGE] %-14s %d 個實例  可見=%s %s" % [
				nm, cnt, (n as Node3D).visible,
				"← 空層" if cnt == 0 else ""])

	print("[TRIAGE] done")
	quit(0)
