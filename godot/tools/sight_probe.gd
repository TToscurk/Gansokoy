extends SceneTree

# PHASE 3.2A：本通の「途切れない視線距離」を実測する使い捨てプローブ。
# 眼高 1.6m から水平 ±35°（画面中央域）に 1° 刻みでレイを撃ち、
#   ・最寄／中央値の到達距離
#   ・60m 以内で遮られたレイの割合（＝近景に質量があるか）
#   ・120m 以内で遮られた割合
# を出す。路面チャネル（|x|≤4）を平行に撃つやり方は、両側の町家が
# 一度も路上へ出ない以上いつでも「地図の端」を返すので使わない。

const EYE := 1.6
const MAXD := 500.0
const HALF_FOV := 35

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "res://maps/village/village.tscn"
	var scn: PackedScene = load(path)
	var root := scn.instantiate()
	get_root().add_child(root)
	_trimesh(root)
	await process_frame
	await process_frame
	var space := root.get_viewport().world_3d.direct_space_state

	print("── %s ──" % path)
	var stations := [
		{"n": "北門 z=-168 → 南", "p": Vector2(0.0, -168.0), "d": 1.0},
		{"n": "火の番の辻 z=-132 → 南", "p": Vector2(0.0, -132.0), "d": 1.0},
		{"n": "z=-60 → 南", "p": Vector2(0.0, -60.0), "d": 1.0},
		{"n": "広場端 z=+30 → 北", "p": Vector2(0.0, 30.0), "d": -1.0},
		{"n": "広場端 z=+30 → 南", "p": Vector2(0.0, 30.0), "d": 1.0},
	]
	for st in stations:
		var p: Vector2 = st.p
		var dz: float = st.d
		var y0 := _y(space, p.x, p.y) + EYE
		var hits: Array[float] = []
		var names := {}
		for i in range(-HALF_FOV, HALF_FOV + 1):
			var a := deg_to_rad(float(i))
			var dir := Vector3(sin(a) * dz, 0.0, cos(a) * dz)
			var o := Vector3(p.x, y0, p.y)
			var q := PhysicsRayQueryParameters3D.create(o, o + dir * MAXD)
			var r := space.intersect_ray(q)
			if r.is_empty():
				hits.append(MAXD)
			else:
				var d: float = o.distance_to(r.position)
				hits.append(d)
				var nm := String((r.collider as Node).name)
				names[nm] = minf(float(names.get(nm, MAXD)), d)
		var n := hits.size()
		var near_60 := 0
		var near_120 := 0
		for h in hits:
			if h < 60.0:
				near_60 += 1
			if h < 120.0:
				near_120 += 1
		var s := hits.duplicate()
		s.sort()
		# 消失点そのもの（±8°＝画面中央のわずかな帯）だけを別に見る
		var axis: Array[float] = []
		for i in range(-8, 9):
			axis.append(hits[i + HALF_FOV])
		axis.sort()
		var lst: Array = names.keys()
		lst.sort_custom(func(a, b): return float(names[a]) < float(names[b]))
		var top := []
		for k in lst.slice(0, 3):
			top.append("%s@%.0f" % [k, names[k]])
		print("%-24s 最寄 %6.1f 中央値 %6.1f  軸±8°中央値 %6.1f  <60m %3d%%  <120m %3d%%  | %s"
			% [st.n, s[0], s[n / 2], axis[axis.size() / 2],
			int(round(100.0 * near_60 / n)), int(round(100.0 * near_120 / n)),
			", ".join(top)])
	quit()

func _y(space: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60.0, z), Vector3(x, -20.0, z))
	var r := space.intersect_ray(q)
	return float(r.position.y) if not r.is_empty() else 0.0

func _trimesh(n: Node) -> void:
	for c in n.get_children():
		_trimesh(c)
	if n is MeshInstance3D and n.has_meta("needs_trimesh"):
		(n as MeshInstance3D).create_trimesh_collision()
