extends SceneTree
## P13 W8 診断（唯読・headless）：嚴格な範囲（margin 0）で、LOD 切替帯に『同じ部位が 2 級同時に可視』になる部品対があるか。
##   部品の可視距離＝camera から各 GeometryInstance3D の世界 AABB 中心まで（RendererSceneCull と同じ）。camera は目標の +x 側に置く。
##   godot --headless --path . --script res://tools/p13/w8/w8_probe_double.gd -- B_P_SGT_002 B_P_MKT_032
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _center(g: GeometryInstance3D) -> Vector3:
	var a := g.global_transform * g.get_aabb()
	return a.get_center()


func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 6:
		await process_frame
	for id: String in OS.get_cmdline_user_args():
		var b := v.get_node("Districts").find_child(id, true, false)
		var kit := b.get_node("Kit")
		var c: Vector3 = (kit as Node3D).global_position
		var lods := []
		for k in 3:
			var arr := []
			for g in kit.get_node("LOD%d" % k).find_children("*", "GeometryInstance3D", true, false):
				arr.append(g)
			lods.append(arr)
		print("[W8D] ", id, " 部品 ", [lods[0].size(), lods[1].size(), lods[2].size()])
		for k in 3:
			print("[W8D]   LOD%d 名: %s" % [k, str(lods[k].map(func(g): return String(g.name)))])
		for edge in [[1, 2, 110.0], [0, 1, 40.0]]:
			var ka: int = edge[0]
			var kb: int = edge[1]
			var E: float = edge[2]
			print("[W8D]  境界 LOD%d→LOD%d  E=%.0f" % [ka, kb, E])
			var d := E - 10.0
			while d <= E + 10.01:
				var cam := c + Vector3(d, 1.7, 0.0)
				var va := []
				var vb := []
				for g: GeometryInstance3D in lods[ka]:
					var dc := cam.distance_to(_center(g))
					if dc >= g.visibility_range_begin and (dc < g.visibility_range_end or g.visibility_range_end == 0.0):
						va.append(String(g.name))
				for g: GeometryInstance3D in lods[kb]:
					var dc2 := cam.distance_to(_center(g))
					if dc2 >= g.visibility_range_begin and (dc2 < g.visibility_range_end or g.visibility_range_end == 0.0):
						vb.append(String(g.name))
				if (va.size() > 0 and vb.size() > 0) or d == E:
					print("[W8D]   d=%5.1f  LOD%d 可視 %d/%d  LOD%d 可視 %d/%d   共通名 %s" % [d, ka, va.size(), lods[ka].size(), kb, vb.size(), lods[kb].size(), str(va.filter(func(n): return n in vb))])
				d += 1.0
	quit(0)
