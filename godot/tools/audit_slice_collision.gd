extends SceneTree
## Collision readiness audit for maps/slice: does the character actually get
## stopped by buildings, walls, water and the canal, and does it stand on the
## ground rather than fall through?
##
## Why: the player already exists (scenes/player.tscn, capsule r=0.45 h=1.7)
## and main.gd builds collision at load — but slice was never in walk_test's
## route table and slice.meta.json has no colliders, so nothing has proved any
## of this. main.gd only trimeshes meshes with XZ span >= 15 m, and a machiya is
## 6–10 m, which predicts buildings are walk-through. Test, do not assume.
##
## Method: load main.tscn the way the game does (map=slice), then fire
## capsule-shaped shape casts along ground-level probes and report what each
## one hits.

const RADIUS := 0.45
const HEIGHT := 1.7
const LAYER_GROUND := 1 << 31

var _main: Node = null


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	_main.load_map("slice", "")
	for i in 6:
		await physics_frame

	var map: Node = _main.map_root
	var space: PhysicsDirectSpaceState3D = map.get_world_3d().direct_space_state

	# ── inventory ──
	var bodies := _count(map, "StaticBody3D")
	var shapes := _count(map, "CollisionShape3D")
	var shape_kinds := {}
	for cs in _find_all(map, "CollisionShape3D"):
		var k := "null"
		if (cs as CollisionShape3D).shape != null:
			k = (cs as CollisionShape3D).shape.get_class()
		shape_kinds[k] = shape_kinds.get(k, 0) + 1
	print("[碰撞] StaticBody3D %d，CollisionShape3D %d，形狀 %s" % [bodies, shapes, shape_kinds])

	# Layer usage: the player capsule is on layer 1 mask 1 by default; anything
	# only on layer 32 (the paint-brush ground) is invisible to it.
	var layer_hist := {}
	for sb in _find_all(map, "StaticBody3D"):
		var l: int = (sb as StaticBody3D).collision_layer
		layer_hist[l] = layer_hist.get(l, 0) + 1
	print("[碰撞] StaticBody3D 圖層分布 %s（玩家 mask=%d）" % [layer_hist, _main.player.collision_mask])

	# ── probes ──
	# Each: name, world XZ, expected. "solid" = capsule must be blocked,
	# "open" = capsule must be free, "ground" = a downward ray must hit.
	#
	# Coordinates MEASURED by tools/probe_audit_targets.gd (2026-09-03), not
	# guessed. The previous table pre-dated the B1 street rebuild: its
	# "machiya_西_00" probe actually sat inside shouka_西_03, "kura_東_09" no
	# longer exists, and the stone bank probe expected a wall that is a
	# retaining wall whose top (y=0.05) is BELOW village ground (y=0.36).
	var probes := [
		{"n": "主街中線 (出生點)", "p": Vector2(235, 16), "want": "open"},
		{"n": "主街北端 鳥居前", "p": Vector2(235, 60), "want": "open"},
		{"n": "町家 machiya_西_00 內部", "p": Vector2(225.5, -55.9), "want": "solid"},
		{"n": "商家 shouka_西_03 內部", "p": Vector2(226.9, -24.5), "want": "solid"},
		{"n": "小町家 komachiya_東_00 內部", "p": Vector2(244.3, -56.7), "want": "solid"},
		{"n": "倉庫_Mesh 內部", "p": Vector2(244.6, 63.0), "want": "solid"},
		{"n": "倉庫2_Mesh 內部", "p": Vector2(243.6, -34.4), "want": "solid"},
		# 鯢吞亭 2026-09-04 由使用者手動移到 (213.6, -94.4)（原 267.2, -5.5
		# 且縮放 0.51）。探針座標必須跟著建築走，否則量的是空地，會誤報
		# 「穿牆」——那不是碰撞壞了，是探針指錯地方。
		{"n": "鯢吞亭 內部", "p": Vector2(213.6, -94.4), "want": "solid"},
		{"n": "霧雨店 內部", "p": Vector2(244.2, -7.3), "want": "solid"},
		{"n": "鈴奈庵 內部", "p": Vector2(227.1, -67.7), "want": "solid"},
		{"n": "寺子屋 內部", "p": Vector2(314.8, 34.6), "want": "solid"},
		# Torii legs are NOT point-probed: the trimesh is a hollow shell, and a
		# capsule teleported inside a 2 m column touches nothing (probe_torii_section
		# 2026-09-03). They are swept from outside below.
		{"n": "大鳥居 中央通道", "p": Vector2(236, 102), "want": "open"},
		{"n": "大鳥居2 中央通道", "p": Vector2(235.2, -80.7), "want": "open"},
		{"n": "東河 水面上", "p": Vector2(438, 20), "want": "water"},
		{"n": "村水路 MachiCanal 上", "p": Vector2(285, -22), "want": "water"},
		{"n": "龍石像橋 橋頂", "p": Vector2(423.3, -143.9), "want": "ground"},
		{"n": "西側田野 (無建物)", "p": Vector2(150, 16), "want": "open"},
	]

	var fails := 0
	print("%-30s %8s %8s %8s  %s" % ["探針", "地面Y", "膠囊", "期望", "判定"])
	for pr in probes:
		var xz: Vector2 = pr["p"]
		var ground := _ground_y(space, Vector3(xz.x, 60.0, xz.y))
		var g_str := "無" if is_nan(ground) else "%.2f" % ground
		var capsule_hit := ""
		if not is_nan(ground):
			# Probe at STREET walking height, not on whatever surface the ray
			# found first. Otherwise the ray lands on a torii crossbeam (13 m up)
			# or a wall cap, finds clear air above it, and reports "walk-through"
			# for a post that is obviously solid.
			var walk_y: float = minf(ground, 1.0)
			capsule_hit = _capsule_hit(space, Vector3(xz.x, walk_y + HEIGHT * 0.5 + 0.05, xz.y))
		var blocked := capsule_hit != ""
		var verdict := ""
		match pr["want"]:
			"open":
				if is_nan(ground): verdict = "✗ 沒地面，會掉下去"
				elif blocked: verdict = "✗ 被 %s 擋住" % capsule_hit
				else: verdict = "✓"
			"solid":
				if not blocked: verdict = "✗ 穿牆"
				else: verdict = "✓ 擋住(%s)" % capsule_hit
			"water":
				if is_nan(ground): verdict = "✗ 無底，會掉到世界外"
				else: verdict = "✓ 有底 y=%.2f" % ground
			"ground":
				# Standing ON a surface: the capsule sits with its base on the
				# hit, so intersect_shape naturally touches it. Only "no floor"
				# is a failure here; walkability is proven by the sweep audit.
				if is_nan(ground): verdict = "✗ 沒地面，會掉下去"
				else: verdict = "✓ 有面 y=%.2f" % ground
		if verdict.begins_with("✗"):
			fails += 1
		print("%-30s %8s %8s %8s  %s" % [pr["n"], g_str, "擋" if blocked else "通", pr["want"], verdict])

	# ── walls you approach from outside ──
	# Sweep height: capsule base must clear the ground at the start point
	# (street is y≈0.3 by the torii), so centre y = ground + 0.85 + margin.
	#
	# VillageStoneBank tops out at y=0.05 while village ground is 0.36, so a
	# point probe from the village side finds nothing to hit — it is not a wall
	# you bump into, it is the drop into the canal. The real test is whether a
	# capsule down on the canal bed can climb out through it.
	var sweeps := [
		{"n": "走向大鳥居 左柱", "a": Vector3(231, 1.3, 96), "b": Vector3(231, 1.3, 106)},
		{"n": "走向大鳥居 右柱", "a": Vector3(241, 1.3, 96), "b": Vector3(241, 1.3, 106)},
		{"n": "走向大鳥居2 左柱", "a": Vector3(231.2, 1.3, -86), "b": Vector3(231.2, 1.3, -76)},
		{"n": "走向大鳥居2 右柱", "a": Vector3(240.2, 1.3, -86), "b": Vector3(240.2, 1.3, -76)},
		{"n": "水路底→石砌護岸 (西岸)", "a": Vector3(284, -1.5, -22), "b": Vector3(276, -1.5, -22)},
		{"n": "水路底→石砌護岸 (西岸, 北段)", "a": Vector3(284, -1.5, 40), "b": Vector3(276, -1.5, 40)},
	]
	for s in sweeps:
		var r := _sweep(space, s["a"], s["b"])
		var ok: bool = r["fraction"] < 0.999
		if not ok:
			fails += 1
		print("%-30s %8s %8s %8s  %s" % [s["n"], "", "擋" if ok else "通", "solid",
			("✓ 擋住(%s) 走了 %.0f%%" % [r["hit"], r["fraction"] * 100.0]) if ok else "✗ 穿牆，走了 100%"])

	print("[碰撞] 失敗 %d / %d" % [fails, probes.size() + sweeps.size()])
	print("done")
	quit(0)


func _sweep(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS
	shape.height = HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, a)
	q.motion = b - a
	q.collision_mask = _main.player.collision_mask
	q.exclude = [_main.player.get_rid()]
	var r := space.cast_motion(q)
	var hit := ""
	if r[0] < 0.999:
		q.transform.origin = a + q.motion * r[1]
		q.motion = Vector3.ZERO
		var hits := space.intersect_shape(q, 1)
		if not hits.is_empty():
			var c: Node = hits[0]["collider"]
			hit = "%s/%s" % [c.get_parent().name, c.name]
	return {"fraction": r[0], "hit": hit}


func _ground_y(space: PhysicsDirectSpaceState3D, from: Vector3) -> float:
	# Player-visible layers only (its mask), NOT the paint-brush layer 32.
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -200, 0), _main.player.collision_mask)
	q.exclude = [_main.player.get_rid()]
	var hit := space.intersect_ray(q)
	return NAN if hit.is_empty() else hit["position"].y


func _capsule_hit(space: PhysicsDirectSpaceState3D, centre: Vector3) -> String:
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS
	shape.height = HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, centre)
	q.collision_mask = _main.player.collision_mask
	# The spawn-point probe used to hit the player's own capsule.
	q.exclude = [_main.player.get_rid()]
	var hits := space.intersect_shape(q, 4)
	if hits.is_empty():
		return ""
	var col: Node = hits[0]["collider"]
	# Name the owner one level up so "GameColliders" and mesh names both read.
	var parent := col.get_parent()
	return String(col.name) if parent == null else "%s/%s" % [parent.name, col.name]


func _count(n: Node, cls: String) -> int:
	return _find_all(n, cls).size()


func _find_all(n: Node, cls: String) -> Array:
	var out := []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_all(c, cls))
	return out
