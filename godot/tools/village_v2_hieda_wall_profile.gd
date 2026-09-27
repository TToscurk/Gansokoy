extends SceneTree
## 稗田邸圍牆（P6）地形剖面：沿圍牆平面每 0.25 m 取地形碰撞高（牆厚 ±0.30 m 三條線取最低／最高），
## 寫 res://assets/village_v2/hieda_wall/src/terrain_profile.json 給 build_hieda_wall.py（Blender）讀。
##   godot --headless --path . --script res://tools/village_v2_hieda_wall_profile.gd
## 平面（大宅門 P0 地標 LANDMARK_HIEDA_GATE 局部座標；+z＝南、門在 x ±3.42 的袖牆端）：
##   南牆 z 0（門兩側）、北牆 z −50、西牆 x −13.5、東牆 x +23.5 → 世界 x 384.5–421.5、z −10 ～ −60，
##   在 P0 district MansionEstate（x 380–426、z −64 ～ −8）內；西牆外 1.5 m 是 CrossStreetMid 路端（半徑 3 m 圓頭）。
const SCENE := "res://maps/village_v2/village_v2.tscn"
const OUT := "res://assets/village_v2/hieda_wall/src/terrain_profile.json"
const PLAN := {"x0": -13.5, "x1": 23.5, "zs": 0.0, "zn": -50.0, "gate_half": 3.42}
const STEP := 0.25
const HALF := 0.30


func _init() -> void:
	var v := (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(v)
	await physics_frame
	await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var trid := (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	var a := v.get_node("Landmarks/LANDMARK_HIEDA_GATE") as Node3D
	var xf := a.global_transform
	var oy := xf.origin.y
	# 邊：名稱、起點、終點（局部 xz）；沿邊方向取樣，法向 ±HALF 取三條線
	var P: Dictionary = PLAN
	var sides := {
		"S_W": [Vector2(-P["gate_half"], P["zs"]), Vector2(P["x0"], P["zs"])],
		"S_E": [Vector2(P["gate_half"], P["zs"]), Vector2(P["x1"], P["zs"])],
		"E": [Vector2(P["x1"], P["zs"]), Vector2(P["x1"], P["zn"])],
		"N": [Vector2(P["x1"], P["zn"]), Vector2(P["x0"], P["zn"])],
		"W": [Vector2(P["x0"], P["zn"]), Vector2(P["x0"], P["zs"])],
	}
	var out := {"_note": "由 tools/village_v2_hieda_wall_profile.gd 產生；y＝地形高 − 大宅門地標原點 y（%.3f）" % oy,
		"anchor": "Landmarks/LANDMARK_HIEDA_GATE", "origin": [xf.origin.x, oy, xf.origin.z], "plan": PLAN,
		"step": STEP, "half": HALF, "sides": {}}
	var bad := 0
	for nm: String in sides:
		var p0: Vector2 = sides[nm][0]
		var p1: Vector2 = sides[nm][1]
		var L := p0.distance_to(p1)
		var d := (p1 - p0) / L
		var nrm := Vector2(-d.y, d.x)
		var n := int(ceil(L / STEP))
		var smp: Array = []
		for i in n + 1:
			var t := minf(i * STEP, L)
			var lo := INF
			var hi := -INF
			for k: float in [-1.0, 0.0, 1.0]:
				var q2: Vector2 = p0 + d * t + nrm * (HALF * k)
				var w := xf * Vector3(q2.x, 0, q2.y)
				var q := PhysicsRayQueryParameters3D.create(Vector3(w.x, 200, w.z), Vector3(w.x, -200, w.z))
				var ex: Array[RID] = []
				var h := NAN
				for _j in 8:
					q.exclude = ex
					var hit := sp.intersect_ray(q)
					if hit.is_empty():
						break
					if hit["rid"] == trid:
						h = hit["position"].y - oy
						break
					ex.append(hit["rid"])
				if is_nan(h):
					bad += 1
					continue
				lo = minf(lo, h)
				hi = maxf(hi, h)
			smp.append([snappedf(t, 0.001), snappedf(lo, 0.0001), snappedf(hi, 0.0001)])
		out["sides"][nm] = {"from": [p0.x, p0.y], "to": [p1.x, p1.y], "len": L, "samples": smp}
		var los: Array = smp.map(func(e: Array) -> float: return float(e[1]))
		print("[PROFILE] %s 長 %.2f m、%d 點、地形 %.3f～%.3f" % [nm, L, smp.size(), los.min(), los.max()])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "", false))
	f.close()
	print("[PROFILE] 寫出 %s；打不到地形 %d 點" % [OUT, bad])
	quit(1 if bad > 0 else 0)
