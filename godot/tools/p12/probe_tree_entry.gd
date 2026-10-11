extends SceneTree
## P12 Wave 1 bounded profiling（只讀、headless、1 回）：場景樹加入の約 2.5 s の内訳。
##   godot --headless --path . --script res://tools/p12/probe_tree_entry.gd
## 1) 通常どおり village_v2 を load→instantiate→add_child（同期）→次の physics frame→60 frame 落ち着き、を計時（Performance monitor 併記）。
## 2) 別インスタンスで、ルート直下の子を「元の順番で」1 つずつ add_child し、子サブツリーごとの同期加入時間・節点数・
##    CollisionObject／Shape 数・script 付き節点数を出す（近似：兄弟参照の順序依存があるため、通常起動の正確な分解ではない）。
const SCENE := "res://maps/village_v2/village_v2.tscn"

func _init() -> void:
	_run.call_deferred()

func _census(n: Node, c: Dictionary) -> void:
	c.nodes += 1
	if n.get_script() != null:
		c.scripts += 1
		var sp := (n.get_script() as Script).resource_path.get_file()
		c.script_names[sp] = int(c.script_names.get(sp, 0)) + 1
	if n is CollisionObject3D:
		c.bodies += 1
	if n is CollisionShape3D:
		c.shapes += 1
	if n is MeshInstance3D:
		c.meshes += 1
	if n is MultiMeshInstance3D:
		c.mm += 1
		c.mm_inst += (n as MultiMeshInstance3D).multimesh.instance_count if (n as MultiMeshInstance3D).multimesh else 0
	for ch in n.get_children():
		_census(ch, c)

func _run() -> void:
	var held := []
	var t0 := Time.get_ticks_usec()
	var ps := ResourceLoader.load(SCENE) as PackedScene
	held.append(ps)
	var t1 := Time.get_ticks_usec()
	var v := ps.instantiate()
	var t2 := Time.get_ticks_usec()
	root.add_child(v)
	var t3 := Time.get_ticks_usec()
	await physics_frame
	var t4 := Time.get_ticks_usec()
	for i in 60:
		await process_frame
	var t5 := Time.get_ticks_usec()
	print("[P12TREE] 通常：load %.0f／instantiate %.0f／add_child（同期）%.0f／→次 physics frame %.0f／+60 frame %.0f ms；物理 active objects %d、collision pairs %d" % [
		(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, (t4 - t3) / 1000.0, (t5 - t4) / 1000.0,
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)])
	v.queue_free()
	await process_frame
	await process_frame
	# 2) サブツリーごと（同じ PackedScene を再 instantiate；load はキャッシュ）
	var w := ps.instantiate()
	var holder := Node3D.new()
	holder.name = "VillageV2"
	var kids := []
	for c in w.get_children():
		kids.append(c)
	for c in kids:
		w.remove_child(c)
	root.add_child(w)
	var rows := []
	var tot := 0.0
	for c: Node in kids:
		var cen := {"nodes": 0, "scripts": 0, "bodies": 0, "shapes": 0, "meshes": 0, "mm": 0, "mm_inst": 0, "script_names": {}}
		_census(c, cen)
		var a := Time.get_ticks_usec()
		w.add_child(c)
		var ms := (Time.get_ticks_usec() - a) / 1000.0
		tot += ms
		rows.append([ms, String(c.name), cen])
	rows.sort_custom(func(x, y): return x[0] > y[0])
	print("[P12TREE] サブツリー別 同期 add_child 合計 %.0f ms（近似）" % tot)
	for r in rows:
		var c: Dictionary = r[2]
		if r[0] < 20.0:
			continue
		var sn: Array = (c.script_names as Dictionary).keys()
		sn.sort_custom(func(x, y): return int(c.script_names[x]) > int(c.script_names[y]))
		print("[P12TREE]   %7.0f ms %-22s 節点 %6d mesh %6d MM %3d(%d) body %4d shape %5d script %4d %s" % [r[0], r[1], c.nodes, c.meshes, c.mm, c.mm_inst, c.bodies, c.shapes, c.scripts,
			str(sn.slice(0, 3).map(func(k): return "%s×%d" % [k, c.script_names[k]]))])
	quit(0)
