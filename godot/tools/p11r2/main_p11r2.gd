extends "res://scripts/main.gd"
## P11 R2 候補 C — Scene Transition（**検証用の候補・未統合**）。
## scripts/main.gd（他 session 所有）を変更せず、_place_player だけを override して検証する。
## 統合は docs/art_review/village_v2_p11/r2/patches/C_main_place_player.patch を所有者が適用する（本檔と同じ内容）。
##
## 変更点（使用者 P11 R2「修正人間之里離場時，角色先出現在 (0, 40, 0) 再掉落的問題。要求玩家直接落在合法且安全的目的地入口。
##   測試往返不同地圖、重複切換、碰撞淨空與角色朝向」）：
##   ① 来た地図の portal 探し：完全一致がなければ「人間之里」の別名（village_v2／slice／village）で再探索
##      （trail・hieda1f・kourindou は人間之里への portal を target "slice" で持つ；正式の slice 経路の挙動は不変）
##   ② それでも無ければ meta.spawn → 最初の portal。**(0, 40, 0) は使わない**
##   ③ 高さ：着地点の真上（portal の着地高さ＋オフセット＝天井より下）から真下へ射線を打ち、当たった床＋FOOT_CLEAR に置く
##      （空中から 1.2–2 m 落とす代わりに床に立たせる。床が見つからない・離れすぎの時だけ従来の高さ）
##   ④ 膠囊の淨空：置いた位置で体が何かに重なれば、足元を 0.1 m ずつ（最大 0.3 m、斜面）上げ、それでも重なれば portal から内向きに
##      0.5 m ずつ（最大 4 m）ずらして空きを探す。前の地図（queue_free 待ちで物理空間に残っている）の碰撞は見ない
##   ⑤ 向き：arrival_yaw が無い portal は「portal から地図内側へ」向く（背中が出口側）

const V_ALIASES := ["village_v2", "slice", "village"]
const FOOT_CLEAR := 0.05


func _find_arrival_portal(portals: Array, from_id: String) -> Dictionary:
	for p in portals:
		if p.get("target") == from_id:
			return p
	if from_id in V_ALIASES:
		for p in portals:
			if String(p.get("target", "")) in V_ALIASES:
				return p
	return {}


func _settle_on_floor(at: Vector3, inward: Vector3) -> Vector3:
	# 前の地図（map_root の外）はこの幀ではまだ queue_free 待ちで物理空間に残っている → 新しい地図の碰撞だけを見る
	var space := get_viewport().get_world_3d().direct_space_state
	var cap: Shape3D = null
	var cap_local := Transform3D.IDENTITY
	if player != null and player.has_method("_capsule_shape"):
		cap = player.call("_capsule_shape")
		cap_local = player.call("_capsule_local")
	for i in 9:
		var p := at + inward * (0.5 * i)
		var rq := PhysicsRayQueryParameters3D.create(p, p + Vector3(0, -6.0, 0), player.collision_mask)
		var ex: Array[RID] = [player.get_rid()]
		var hit := {}
		for k in 8:
			rq.exclude = ex
			var h := space.intersect_ray(rq)
			if h.is_empty():
				break
			var col := h.get("collider") as Node
			var nm := String(col.name) if col else ""
			if col == null or map_root == null or not map_root.is_ancestor_of(col) \
					or nm.contains("Boundary") or nm.contains("邊界") or nm.contains("boundary"):
				ex.append(h["rid"])
				continue
			hit = h
			break
		if hit.is_empty():
			continue
		var floor_y := float((hit["position"] as Vector3).y)
		if cap == null:
			return Vector3(p.x, floor_y + FOOT_CLEAR, p.z)
		# 斜面では膠囊の丸い底が上り側に触れるので、足元を 0.1 m ずつ（最大 0.3 m）上げて空きを探す
		for lift: float in [0.0, 0.1, 0.2, 0.3]:
			var stand := Vector3(p.x, floor_y + FOOT_CLEAR + lift, p.z)
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cap
			q.transform = Transform3D(Basis.IDENTITY, stand) * cap_local
			q.collision_mask = player.collision_mask
			q.exclude = [player.get_rid()]
			var blocked := false
			for r: Dictionary in space.intersect_shape(q, 16):
				var rc := r.get("collider") as Node
				if rc != null and map_root != null and map_root.is_ancestor_of(rc):
					blocked = true
					break
			if not blocked:
				return stand
	return at


func _place_player(meta: Dictionary, from_id: String) -> void:
	var portals: Array = meta.get("portals", [])
	if from_id == "" and meta.has("spawn"):
		super(meta, from_id)
		return
	var arrival_portal: Dictionary = {}
	if from_id != "":
		arrival_portal = _find_arrival_portal(portals, from_id)
	if arrival_portal.is_empty() and meta.has("spawn"):
		super(meta, "")
		return
	if arrival_portal.is_empty() and portals.size() > 0:
		arrival_portal = portals[0]
	if arrival_portal.is_empty():
		super(meta, from_id)
		return
	var arrival := _arrival_for_portal(arrival_portal)
	var inward := Vector3(-arrival.x, 0.0, -arrival.z)
	inward = inward.normalized() if inward.length() > 0.01 else Vector3.ZERO
	var stand := _settle_on_floor(arrival, inward)
	player.velocity = Vector3.ZERO
	player.global_position = stand
	var yaw := 0.0
	if arrival_portal.has("arrival_yaw"):
		yaw = float(arrival_portal.arrival_yaw)
	elif inward != Vector3.ZERO:
		yaw = atan2(-inward.x, -inward.z)
	if player.has_method("snap_yaw"):
		player.snap_yaw(yaw)
	else:
		player.rotation.y = yaw
	portal_cooldown = PORTAL_COOLDOWN
