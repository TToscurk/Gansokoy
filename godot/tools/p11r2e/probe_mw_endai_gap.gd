extends SceneTree
## P11 R2E（只讀、headless）：市集西 縁台 062 周辺で玩家膠囊（r 0.30・h 1.70）が立てる格を 0.25 m 格で描く。
## 「歩いて回り込める通路があるか」＝ BLOCKED が路線（wp）の問題か、通路そのものが塞がっているかの切り分け。
const X0 := 226.0
const X1 := 236.0
const Z0 := -50.0
const Z1 := -42.0
const STEP := 0.25

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var terr := (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.30
	cap.height = 1.70
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	var names := {}
	var rows := []
	var z := Z1
	while z >= Z0 - 1e-6:
		var row := "%6.2f " % z
		var x := X0
		while x <= X1 + 1e-6:
			var rq := PhysicsRayQueryParameters3D.create(Vector3(x, 30, z), Vector3(x, -10, z))
			var ex: Array[RID] = []
			var g := NAN
			for t in 12:
				rq.exclude = ex
				var h := sp.intersect_ray(rq)
				if h.is_empty():
					break
				if h.rid == terr:
					g = h.position.y
					break
				ex.append(h.rid)
			var ch := "?"
			if not is_nan(g):
				# 足元から 0.36 m 上（step 0.35 で越えない高さ）に膠囊の底を置く
				q.transform = Transform3D(Basis(), Vector3(x, g + 0.36 + 0.85, z))
				q.exclude = [terr]
				var hits := sp.intersect_shape(q, 4)
				ch = "."
				for h in hits:
					var n := h["collider"] as Node
					var p := String(v.get_path_to(n))
					if p.begins_with("Population"):
						continue
					var key := p.get_slice("/", 0) + "/" + p.get_slice("/", 1)
					if not names.has(key):
						names[key] = String(char(65 + names.size()))
					ch = names[key]
					break
			row += ch
			x += STEP
		rows.append(row)
		z -= STEP
	print("[GAP] x %.1f→%.1f（0.25 m）、. ＝立てる" % [X0, X1])
	for r in rows:
		print("[GAP] ", r)
	print("[GAP] 凡例 ", names)
	quit(0)
