extends SceneTree
## P13 W7 診断（唯読・headless）：町家 1 棟の各 LOD の部品名 → 基底材質（surface ごと）の対応表を出す（ID 画像の部品を『屋根／壁／木』に分類するため）。
##   godot --headless --path . --script res://tools/p13/w7/w7_probe_parts.gd -- <building path> [out.json]
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 6:
		await process_frame
	var res := {}
	# 全 187 棟の部品名の接頭辞（数字を除いた型）→ 基底材質の集合
	var by_prefix := {}
	for b in v.get_node("Districts").find_children("B_*", "Node3D", true, false):
		var kit := b.get_node_or_null("Kit")
		if kit == null:
			continue
		for li in 3:
			var ln := kit.get_node_or_null("LOD%d" % li)
			if ln == null:
				continue
			for mi in ln.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				if m.mesh == null:
					continue
				var nm := String(m.name)
				var pre := ""
				for ch in nm:
					if ch >= "0" and ch <= "9":
						break
					pre += ch
				var key := "LOD%d/%s" % [li, pre]
				if not by_prefix.has(key):
					by_prefix[key] = {}
				for si in m.mesh.get_surface_count():
					var base := m.mesh.surface_get_material(si)
					var bn := base.resource_path.get_file() if base != null else "(null)"
					by_prefix[key][bn] = int((by_prefix[key] as Dictionary).get(bn, 0)) + 1
	for k in by_prefix.keys():
		print("[W7P2] ", k, " → ", by_prefix[k])
	if args.size() > 0:
		var f := FileAccess.open(args[0], FileAccess.WRITE)
		f.store_string(JSON.stringify(by_prefix, "\t"))
		f.close()
	quit(0)
