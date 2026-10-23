extends SceneTree
## 鈴奈庵門前找小鈴站位：載入 village_v2，對候選點做 3×3 向下射線（最上面可走表面）＋膠囊重疊查詢。
## godot --headless --path godot -s res://tools/kosuzu/probe_kosuzu_spot.gd
const ENTRY_LOCAL := Vector3(0, 0, 5.045)
var scene: Node
var n := 0

func _initialize() -> void:
	scene = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	get_root().add_child(scene)

func _physics_process(_d: float) -> bool:
	n += 1
	if n < 5: return false
	var hero: Node3D = scene.get_node("Landmarks/LANDMARK_SUZUNAAN/Hero")
	var H := hero.global_transform
	var ss := (scene as Node3D).get_world_3d().direct_space_state
	print("HERO entry_world=%s fwd=%s" % [str(H * ENTRY_LOCAL), str((H.basis * Vector3.FORWARD * -1).normalized())])
	for c in [Vector2(1.3, 6.4), Vector2(-1.3, 6.4), Vector2(1.6, 6.9), Vector2(-1.6, 6.9), Vector2(2.2, 6.2), Vector2(0, 7.2)]:
		var p := H * Vector3(c.x, 0, c.y)
		var ys := []; var who := {}
		for dx in [-0.25, 0.0, 0.25]:
			for dz in [-0.25, 0.0, 0.25]:
				var q := PhysicsRayQueryParameters3D.create(p + Vector3(dx, 6, dz), p + Vector3(dx, -6, dz))
				var r := ss.intersect_ray(q)
				if r: ys.append(r.position.y); who[str(r.collider.name)] = true
		ys.sort()
		var y: float = ys[ys.size() / 2] if ys.size() else NAN
		var cap := CapsuleShape3D.new(); cap.radius = 0.22; cap.height = 1.5
		var sq := PhysicsShapeQueryParameters3D.new(); sq.shape = cap
		sq.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, y + 0.75 + 0.03, p.z))
		var hits := ss.intersect_shape(sq, 16)
		var hn := []
		for h in hits: hn.append(str(h.collider.get_path()).replace("/root/", "").right(70))
		print("CAND local=%s world=(%.2f, %.3f, %.2f) relief=%.3f surf=%s overlaps=%s" % [str(c), p.x, y, p.z, (ys[-1] - ys[0]) if ys.size() else -1.0, str(who.keys()), str(hn)])
	return true
