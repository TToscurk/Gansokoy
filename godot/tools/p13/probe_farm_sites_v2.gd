extends SceneTree
## P13 W1B（只讀、headless）：農家候補（農舍＋納屋）の実景幾何確認。footprint は出簷込み、判定は辺上点＋箱 query。
## 地形高＝TerrainCollision の三角形だけ（RLib.terrain_sampler；牆頂・樹冠・屋根を拾わない）。
## 非地形碰撞＝箱 query（地形除外）。樹木・道具・NPC＝場景ノード位置（footprint＋余白内）。
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
## [名, 中心 x, z, 外形 sx, sz]
const SITES := [
	["A1_noka", 318.0, 82.0, 8.2, 10.3], ["A2_naya", 323.0, 71.0, 4.5, 6.1],
]

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 3:
		await physics_frame
	var S := RLib.terrain_sampler(v)
	var sp := v.get_world_3d().direct_space_state
	var terr := v.get_node("Collision/TerrainCollision") as StaticBody3D
	# 樹・道具・NPC 候補ノード（位置だけ）
	var things: Array = []
	for grp in ["Vegetation", "Props", "HumanUseP10", "HumanUseExpansionP10", "Population", "Landmarks"]:
		var g := v.get_node_or_null(grp)
		if g == null:
			continue
		for n in g.find_children("*", "Node3D", true, false):
			var nm := String(n.name)
			if n is MeshInstance3D or n is CollisionShape3D or nm.begins_with("LOD") or n is MultiMeshInstance3D:
				continue
			if n.get_child_count() == 0 and not (n is AnimatableBody3D):
				continue
			things.append([grp, nm, (n as Node3D).global_position])
	for s: Array in SITES:
		var c := Vector2(s[1], s[2])
		var hx: float = s[3] * 0.5
		var hz: float = s[4] * 0.5
		var hs: Array = []
		for ix in 7:
			for iz in 7:
				var p := c + Vector2(lerpf(-hx, hx, ix / 6.0), lerpf(-hz, hz, iz / 6.0))
				var h := S.h(p.x, p.y)
				if not is_nan(h):
					hs.append(h)
		var lo: float = hs.min() if not hs.is_empty() else NAN
		var hi: float = hs.max() if not hs.is_empty() else NAN
		var bx := BoxShape3D.new()
		bx.size = Vector3(s[3], 3.5, s[4])
		var qp := PhysicsShapeQueryParameters3D.new()
		qp.shape = bx
		qp.transform = Transform3D(Basis.IDENTITY, Vector3(c.x, hi + 1.85, c.y))
		qp.exclude = [terr.get_rid()]
		var hits: Array = []
		for r: Dictionary in sp.intersect_shape(qp, 8):
			hits.append(String(v.get_path_to(r["collider"] as Node)))
		var near: Array = []
		for t: Array in things:
			var p3: Vector3 = t[2]
			var dx := maxf(absf(p3.x - c.x) - hx, 0.0)
			var dz := maxf(absf(p3.z - c.y) - hz, 0.0)
			if Vector2(dx, dz).length() < 3.0:
				near.append("%s/%s(%.1f)" % [t[0], t[1], Vector2(dx, dz).length()])
		print("[FS2] %s (%.0f,%.0f) 地形 %.2f..%.2f（差 %.2f）49 点中 %d、碰撞 %s、3 m 内 %d %s" % [s[0], c.x, c.y, lo, hi, hi - lo, hs.size(), str(hits), near.size(), str(near.slice(0, 8))])
	quit(0)
