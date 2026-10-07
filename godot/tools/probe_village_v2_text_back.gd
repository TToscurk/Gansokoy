extends SceneTree
## 字の裏面が玩家から見える位置にあるか（読み取り専用）：village_v2.tscn を読み、指定 Hero の字の領域で「鏡像」と判定された
## 三角形の重心から、その面の法線方向へ 0.6 m／1.2 m 先の点が建物の碰撞の中か、また重心→その点の射線が何かに当たるかを調べる。
## 使い方：godot --headless --path godot --script res://tools/probe_village_v2_text_back.gd
const L := preload("res://tools/village_v2_text_facing_lib.gd")
const TARGETS := {"res://assets/village_v2/kirisame/kirisame.scn": ["sign"], "res://assets/village_v2/suzunaan/suzunaan.scn": ["sign", "spines"],
	"res://assets/village_v2/terakoya/terakoya.scn": ["banner"]}

func _initialize():
	go.call_deferred()

func go():
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 3: await physics_frame
	var lib = L.new()
	var space := v.get_world_3d().direct_space_state
	for n in v.find_children("*", "", true, false):
		if not TARGETS.has(n.scene_file_path): continue
		var lod0: MeshInstance3D = n.find_child("LOD0", true, false)
		if lod0 == null: continue
		for si in lod0.mesh.get_surface_count():
			var mat: Material = lod0.mesh.surface_get_material(si)
			var tex = lib.mat_tex(mat) if mat else null
			if tex == null: continue
			var at: Dictionary = lib.atlas_for(tex.resource_path)
			if at.is_empty(): continue
			var arr := lod0.mesh.surface_get_arrays(si)
			var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]; var N: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var UV: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var I = arr[Mesh.ARRAY_INDEX]
			var idx: PackedInt32Array = I if I != null and (I as PackedInt32Array).size() > 0 else PackedInt32Array(range(V.size()))
			for reg in TARGETS[n.scene_file_path]:
				if not (at.regions as Dictionary).has(reg): continue
				var rect: Rect2 = at.regions[reg]
				var stats := {"mirrored": 0, "inside_06": 0, "inside_12": 0, "ray_hit_lt_1m": 0}
				for t in range(0, idx.size(), 3):
					var a := idx[t]; var b := idx[t + 1]; var c := idx[t + 2]
					if not rect.grow(0.0005).has_point((UV[a] + UV[b] + UV[c]) / 3.0): continue
					var e1 := V[b] - V[a]; var e2 := V[c] - V[a]; var d1 := UV[b] - UV[a]; var d2 := UV[c] - UV[a]
					var det := d1.x * d2.y - d1.y * d2.x
					if absf(det) < 1e-12: continue
					var T := (e1 * d2.y - e2 * d1.y) / det; var B := (e2 * d1.x - e1 * d2.x) / det
					var nl := (N[a] + N[b] + N[c]).normalized()
					if T.cross(B).dot(nl) < 0.0: continue
					stats.mirrored += 1
					var gt := lod0.global_transform
					var p := gt * ((V[a] + V[b] + V[c]) / 3.0)
					var nw := (gt.basis * nl).normalized()
					for dd in [[0.6, "inside_06"], [1.2, "inside_12"]]:
						var q := PhysicsPointQueryParameters3D.new()
						q.position = p + nw * float(dd[0]); q.collide_with_areas = false
						if not space.intersect_point(q, 1).is_empty(): stats[dd[1]] += 1
					var rq := PhysicsRayQueryParameters3D.create(p + nw * 0.02, p + nw * 1.0)
					if not space.intersect_ray(rq).is_empty(): stats.ray_hit_lt_1m += 1
				print("[BACK] %s %s @%s %s" % [n.scene_file_path.get_file(), reg, str(n.global_position.snapped(Vector3.ONE * 0.1)), JSON.stringify(stats)])
	quit(0)
