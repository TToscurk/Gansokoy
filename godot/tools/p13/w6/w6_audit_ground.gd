extends SceneTree
## P13 Wave 6 TASK B 診断（唯読・headless）：地面 overlay（Vegetation/*/Ground …）の三角形「内部」が実際の地形面より下に潜っていないか。
##   godot --headless --path . --script res://tools/p13/w6/w6_audit_ground.gd -- [out.json] [--filter=ShrineGroveP9] [--stride=N]
## 各三角形で重心座標 10 点（3 頂点・3 辺の中点・重心・内部 3 点）を取り、overlay の y − 地形（TerrainCollision 射線）y を測る。
##   d < 0 ＝ overlay が地形の下＝その点は地形の描画が出る（overlay の色ではなく地形の色が見える）。
## 頂点だけを見る既存 gate では見つからない「頂点間の弦が凸な稜線の下をくぐる」型の欠陥を検出する。
const SCENE := "res://maps/village_v2/village_v2.tscn"

var v: Node3D
var sp: PhysicsDirectSpaceState3D
var terr_rid: RID


func _init() -> void:
	_run.call_deferred()


func _terr(x: float, z: float, y0: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, y0 + 8.0, z), Vector3(x, y0 - 40.0, z))
	var ex: Array[RID] = []
	for t in 6:
		q.exclude = ex
		var h := sp.intersect_ray(q)
		if h.is_empty():
			return NAN
		if h.rid == terr_rid:
			return float(h.position.y)
		ex.append(h.rid)
	return NAN


func _pct(a: Array, p: float) -> float:
	if a.is_empty():
		return NAN
	var s := a.duplicate()
	s.sort()
	return float(s[clampi(int(float(s.size() - 1) * p), 0, s.size() - 1)])


func _run() -> void:
	var out_path := ""
	var filt := ""
	var stride_arg := 0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filt = a.trim_prefix("--filter=")
		elif a.begins_with("--stride="):
			stride_arg = int(a.trim_prefix("--stride="))
		elif not a.begins_with("--"):
			out_path = a
	v = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 10:
		await physics_frame
	sp = v.get_world_3d().direct_space_state
	terr_rid = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	var result := {}
	var W := [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(0.5, 0.5, 0), Vector3(0, 0.5, 0.5), Vector3(0.5, 0, 0.5), Vector3(1.0 / 3, 1.0 / 3, 1.0 / 3), Vector3(0.6, 0.2, 0.2), Vector3(0.2, 0.6, 0.2), Vector3(0.2, 0.2, 0.6)]
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var path := String(v.get_path_to(m))
		if not path.begins_with("Vegetation/"):
			continue
		var is_ground := false
		for comp: String in path.split("/"):
			if comp == "Ground" or comp.begins_with("Ground_"):
				is_ground = true
		if not is_ground:
			continue
		if filt != "" and not path.contains(filt):
			continue
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var xf := m.global_transform
		var d_all: Array = []
		var n_tri_total := 0
		var cells := {}
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ix = arr[Mesh.ARRAY_INDEX]
			var tri: PackedInt32Array
			if ix != null and (ix as PackedInt32Array).size() > 0:
				tri = ix
			else:
				tri = PackedInt32Array()
				tri.resize(vs.size())
				for k in vs.size():
					tri[k] = k
			var tn := tri.size() / 3
			n_tri_total += tn
			var stride := stride_arg if stride_arg > 0 else maxi(1, tn / 2500)
			for t in range(0, tn, stride):
				var a := xf * vs[tri[t * 3]]
				var b := xf * vs[tri[t * 3 + 1]]
				var c := xf * vs[tri[t * 3 + 2]]
				for w: Vector3 in W:
					var p := a * w.x + b * w.y + c * w.z
					var ty := _terr(p.x, p.z, p.y)
					if is_nan(ty):
						continue
					var d := p.y - ty
					d_all.append(d)
					if d < -0.005:
						var key := Vector2i(floori(p.x / 4.0), floori(p.z / 4.0))
						var e: Array = cells.get(key, [0, 0.0, p])
						e[0] += 1
						if d < e[1]:
							e[1] = d
							e[2] = p
						cells[key] = e
		if d_all.is_empty():
			continue
		var n := d_all.size()
		var under5 := d_all.filter(func(x): return x < -0.005).size()
		var under20 := d_all.filter(func(x): return x < -0.02).size()
		var under50 := d_all.filter(func(x): return x < -0.05).size()
		var top: Array = []
		var keys := cells.keys()
		keys.sort_custom(func(k1, k2): return int(cells[k1][0]) > int(cells[k2][0]))
		for k in keys.slice(0, 4):
			var e: Array = cells[k]
			top.append({"cell4m": [k.x * 4, k.y * 4], "n": e[0], "worst": snappedf(e[1], 0.001), "at": [snappedf(e[2].x, 0.1), snappedf(e[2].y, 0.01), snappedf(e[2].z, 0.1)]})
		result[path] = {"tri": n_tri_total, "samples": n, "d_p05": _pct(d_all, 0.05), "d_p50": _pct(d_all, 0.5), "d_min": _pct(d_all, 0.0),
			"under5mm_pct": 100.0 * under5 / n, "under20mm_pct": 100.0 * under20 / n, "under50mm_pct": 100.0 * under50 / n, "top_cells": top}
		var r: Dictionary = result[path]
		print("%-58s tri=%6d n=%6d d[p05 %+.3f p50 %+.3f min %+.3f] under5mm %5.1f%% under20mm %5.1f%% under50mm %5.1f%%" % [path, r.tri, r.samples, r.d_p05, r.d_p50, r.d_min, r.under5mm_pct, r.under20mm_pct, r.under50mm_pct])
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(result, "\t") + "\n")
		f.close()
	quit(0)
