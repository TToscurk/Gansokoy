# 地標殘影碰撞檢查（使用者要求：搬入後要實測舊空殼碰撞箱真的沒了）
#
#   godot --headless --path godot --script tools/lm_ghost.gd
#
# 「節點數對」不算驗證 —— 真正要問的是**玩家會不會撞到看不見的東西**。
# 所以這支做兩件事：
#   1. 結構面：地標碰撞群組裡的 shape，逐一對照 LANDMARKS，
#      已搬入（有 build）的那幾座**一個都不該出現**。
#   2. 物理面：在已搬入地標的佔位方塊**原本會在的高度**放膠囊做 shape query，
#      撞到的碰撞體必須屬於真內容（有可見 mesh 的群組），不能是孤兒 StaticBody。
extends SceneTree

const MIGRATED := ["足洗邸"]          # 已搬入真內容的地標（跟 gen_town 的 build 鍵對應）
const SITES := {
	"寺子屋": Vector2(-26, -52), "鈴奈庵": Vector2(11.6, -52),
	"鎮守之杜": Vector2(-26, 2), "市場": Vector2(-26, 57),
	"足洗邸": Vector2(26, 112), "稗田邸": Vector2(-78, -164),
}

func _init() -> void:
	var root: Node3D = (load("res://maps/village/village.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	await physics_frame
	await physics_frame
	var fail := 0

	# ── 1. 結構面：佔位碰撞群組不該包含已搬入的地標 ──
	var stub_body := root.find_child("地標碰撞", true, false)
	var stub_shapes := 0
	var stub_pos: Array[Vector3] = []
	if stub_body != null:
		for c in stub_body.get_children():
			if c is CollisionShape3D:
				stub_shapes += 1
				stub_pos.append((c as CollisionShape3D).position)
	print("佔位碰撞箱 %d 個（應 = 未搬入的地標數 %d）"
		% [stub_shapes, SITES.size() - MIGRATED.size()])
	if stub_shapes != SITES.size() - MIGRATED.size():
		print("  ✗ 數量不符")
		fail += 1
	for nm in MIGRATED:
		var p: Vector2 = SITES[nm]
		for sp in stub_pos:
			if Vector2(sp.x, sp.z).distance_to(p) < 6.0:
				print("  ✗ %s 已搬入，卻仍有佔位碰撞箱在 (%.0f, %.0f)" % [nm, sp.x, sp.z])
				fail += 1
	if fail == 0:
		print("  ✓ 已搬入的地標都沒有留下佔位碰撞箱")

	# ── 2. 物理面：真的去撞撞看 ──
	var sps := root.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape_rid = cap.get_rid()
	q.collide_with_areas = false
	for nm in MIGRATED:
		var p: Vector2 = SITES[nm]
		var hits_ok := 0
		var hits_ghost := 0
		# 沿佔位方塊的舊範圍掃一圈，看撞到的東西是不是真內容底下的
		for dx in [-12.0, -6.0, 0.0, 6.0, 12.0]:
			for dz in [-8.0, 0.0, 8.0]:
				q.transform = Transform3D(Basis(), Vector3(p.x + dx, 3.0, p.y + dz))
				for hit in sps.intersect_shape(q, 8):
					var col: Node = hit.collider
					# 往上找有沒有可見 mesh 的祖先 —— 有就是真內容，沒有就是孤兒
					var n: Node = col
					var has_mesh := false
					var depth := 0
					while n != null and depth < 4:
						for ch in n.get_children():
							if ch is MeshInstance3D:
								has_mesh = true
								break
						if has_mesh:
							break
						n = n.get_parent()
						depth += 1
					if has_mesh:
						hits_ok += 1
					else:
						hits_ghost += 1
						print("  ✗ %s 撞到沒有可見幾何的碰撞體：%s @ (%.0f, %.0f)"
							% [nm, col.name, p.x + dx, p.y + dz])
						fail += 1
		print("%s：碰撞取樣 命中真內容 %d、孤兒碰撞 %d" % [nm, hits_ok, hits_ghost])
	print("\n══ 殘影碰撞檢查：%s ══" % ("通過 ✓" if fail == 0 else "%d 個問題 ✗" % fail))
	root.queue_free()
	quit(1 if fail > 0 else 0)
