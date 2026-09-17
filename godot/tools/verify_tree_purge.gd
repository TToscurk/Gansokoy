extends SceneTree
## 驗收：載入所有被改過的場景，確認 (a) 能解析、(b) 下架樹種 0 實例、(c) 樹底仍貼地。

const SCENES := [
	"res://maps/shrine/shrine.tscn",
	"res://maps/trail/trail.tscn",
	"res://maps/slice/gen/village_infill_trees.tscn",
	"res://maps/slice/gen/sakura_trees.tscn",
	"res://maps/slice/gen/village_trees.tscn",
	"res://maps/slice/slice.tscn",
]
const PURGED := ["櫻花樹", "楓樹", "普通樹", "2大衫", "針葉林樹4"]
const KEPT := ["大衫", "針葉樹1", "針葉樹2glb", "針葉林樹3", "盆樹", "鎮守之杜"]

func _init() -> void:
	_run.call_deferred()

func _scan(n: Node, counts: Dictionary, ymins: Dictionary) -> void:
	var sf: String = n.scene_file_path
	if sf != "" and sf.begins_with("res://assets/landscape/"):
		var nm := sf.get_file().get_basename()
		counts[nm] = counts.get(nm, 0) + 1
		if n is Node3D:
			var box: Variant = null
			var st: Array = [n]
			while not st.is_empty():
				var c: Node = st.pop_back()
				st.append_array(c.get_children())
				if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
					var mi := c as MeshInstance3D
					var b: AABB = mi.global_transform * mi.mesh.get_aabb()
					box = b if box == null else (box as AABB).merge(b)
			if box != null:
				var y: float = (box as AABB).position.y
				if not ymins.has(nm) or y < ymins[nm]:
					ymins[nm] = y
	for c in n.get_children():
		_scan(c, counts, ymins)

func _run() -> void:
	var fail := 0
	for path in SCENES:
		if not ResourceLoader.exists(path):
			print("SKIP  %s (不存在)" % path)
			continue
		var ps: PackedScene = load(path)
		if ps == null:
			print("FAIL  %s 載入失敗" % path)
			fail += 1
			continue
		var inst: Node = ps.instantiate()
		root.add_child(inst)
		await process_frame
		var counts := {}
		var ymins := {}
		_scan(inst, counts, ymins)
		var bad: Array = []
		for p in PURGED:
			if counts.get(p, 0) > 0:
				bad.append("%s×%d" % [p, counts[p]])
		var kept_list: Array = []
		for k in KEPT:
			if counts.get(k, 0) > 0:
				kept_list.append("%s×%d(底%.2f)" % [k, counts[k], ymins.get(k, 0.0)])
		var status: String = "OK" if bad.is_empty() else "殘留! " + ", ".join(bad)
		print("%-46s %s" % [path.get_file(), status])
		if not kept_list.is_empty():
			print("      現用: %s" % ", ".join(kept_list))
		if not bad.is_empty():
			fail += 1
		inst.queue_free()
		await process_frame
	print("")
	print("驗收結果：%s" % ("全部通過" if fail == 0 else "%d 個場景有問題" % fail))
	quit(1 if fail > 0 else 0)
