extends SceneTree
## P10 R6b ROUND 3 診断：下り ARM_PULL（SpringArm が縮む）の原因切り分け。
##   godot --headless --path godot --script res://tools/diag_village_v2_sando_camera.gd [-- --out=<json>]
## 参道の中心線を 0.25 m ごとに「下る玩家」として置き（足＝その点の最上面の歩ける面）、正式 TPS 相機と同じ
##   Pivot 高 1.65・pitch −0.18（player_camera_adapter.gd の初期値）・spring_length 8.5・margin 0.2 の SpringArm（形なし＝光線）を
##   進行方向の後ろへ伸ばし、当たる碰撞体・縮んだ長さ・ARM_PULL（< 0.55 × 8.5、walk_p10_final.gd と同じ判定）を記録。
## 斜坡碰撞の構成を差し替えて比べる：
##   A 地形のみ（ShrineApproachP10 の斜坡を外す）
##   B 踊り場なし（ROUND 1 相当の一本の斜坡）
##   C 現行 ROUND 2（踊り場 3）
##   D〜 候補（踊り場の奥行・位置違い）
## 石段の見える面（踏面・踊り場・袖石の上面）より相機が低い＝石の中に入る点も数える（階段 Mesh の影響の確認）。
const LIB := preload("res://tools/village_v2_shrine_approach_lib.gd")
var PITCH := -0.18   # --pitch= で上書き（提案の比較用：下り時に相機を上げた場合）
const PIVOT_H := 1.65
const ARM := 8.5
const MARGIN := 0.2
const PULL := 0.55

var V: Node3D
var cl: PackedVector2Array
var H: PackedFloat32Array


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.trim_prefix("--out=")
		if a.begins_with("--pitch="):
			PITCH = float(a.trim_prefix("--pitch="))
	V = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(V)
	await process_frame
	var sa := V.get_node_or_null(LIB.NODE_NAME)
	if sa:
		sa.free()
	await physics_frame
	await physics_frame
	cl = LIB.centerline()
	H = LIB.ramp_profile(V, cl)
	var configs := [
		["A_terrain_only", null],
		["B_no_landings", []],
		["C_round2_landings", LIB.LANDINGS],
		["D_landings_d1.2", [[50.0, 1.2], [62.6, 1.2], [75.6, 1.2]]],
		["E_landings_2_d1.2", [[56.0, 1.2], [70.0, 1.2]]],
	]
	var result := {}
	for c in configs:
		var body: StaticBody3D = null
		var st: Array = []
		if c[1] != null:
			st = LIB.steps(cl, H, c[1])
			body = _ramp_body(st)
			V.add_child(body)
		await physics_frame
		await physics_frame
		result[c[0]] = _walk(st, String(c[0]))
		if body:
			body.free()
		await physics_frame
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(result, "  "))
		f.close()
	quit(0)


func _ramp_body(st: Array) -> StaticBody3D:
	var rp := LIB.ramp_points(st, H)
	var faces := PackedVector3Array()
	var half := LIB.STEP_W * 0.5 + LIB.CURB_W
	for i in rp.size() - 1:
		var ka := int(rp[i][0])
		var kb := int(rp[i + 1][0])
		if kb <= ka:
			continue
		var ta := LIB.tangent(cl, ka)
		var tb := LIB.tangent(cl, kb)
		var na := Vector2(-ta.y, ta.x) * half
		var nb := Vector2(-tb.y, tb.x) * half
		var ya := float(rp[i][1])
		var yb := float(rp[i + 1][1])
		faces.append_array(PackedVector3Array([Vector3(cl[ka].x - na.x, ya, cl[ka].y - na.y), Vector3(cl[kb].x - nb.x, yb, cl[kb].y - nb.y), Vector3(cl[kb].x + nb.x, yb, cl[kb].y + nb.y),
			Vector3(cl[ka].x - na.x, ya, cl[ka].y - na.y), Vector3(cl[kb].x + nb.x, yb, cl[kb].y + nb.y), Vector3(cl[ka].x + na.x, ya, cl[ka].y + na.y)]))
	var shp := ConcavePolygonShape3D.new()
	shp.set_faces(faces)
	shp.backface_collision = true
	var b := StaticBody3D.new()
	b.name = "DiagRamp"
	var cs := CollisionShape3D.new()
	cs.shape = shp
	b.add_child(cs)
	return b


## 見える石の上面（踏面／踊り場＋袖石の上 0.11 まで）の高さ：中心線索引 k の段
func _visible_top(st: Array, k: int) -> float:
	for a: Dictionary in st:
		if k >= int(a["k0"]) and k <= int(a["k1"]):
			return lerpf(float(a["y0"]), float(a["y1"]), float(k - int(a["k0"])) / maxf(int(a["k1"]) - int(a["k0"]), 1)) + 0.11
	return NAN


func _nearest_k(p: Vector2) -> Array:
	var bk := 0
	var bd := INF
	for k in range(0, cl.size(), 2):
		var d := cl[k].distance_to(p)
		if d < bd:
			bd = d
			bk = k
	return [bk, bd]


func _walk(st: Array, tag: String) -> Dictionary:
	var sp := V.get_world_3d().direct_space_state
	var k_hi := int(st[st.size() - 1]["k1"]) + 40 if not st.is_empty() else int(100.0 / 0.05)
	var k_lo := int(st[0]["k0"]) - 40 if not st.is_empty() else int(36.0 / 0.05)
	k_hi = mini(k_hi, cl.size() - 1)
	var n := 0
	var pulled := 0
	var episodes := 0
	var on := false
	var lmin := INF
	var hits := {}
	var clip := 0
	var lens := []
	var samples := []
	var lmin_at := [0.0, INF, "", []]
	var k := k_hi
	while k >= k_lo:
		var p := cl[k]
		# 足：最上面の歩ける面
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 80, p.y), Vector3(p.x, -30, p.y))
		var h := sp.intersect_ray(q)
		if h.is_empty():
			k -= 5
			continue
		var foot: Vector3 = h["position"]
		var t := -LIB.tangent(cl, k)   # 下りの進行方向
		var yaw := atan2(-t.x, -t.y)
		var dir := Basis(Vector3.UP, yaw) * (Basis(Vector3.RIGHT, PITCH) * Vector3(0, 0, 1))
		var piv := foot + Vector3(0, PIVOT_H, 0)
		var rq := PhysicsRayQueryParameters3D.create(piv, piv + dir * ARM)
		var rh := sp.intersect_ray(rq)
		var L := ARM
		var who := "-"
		if not rh.is_empty():
			L = maxf(0.0, piv.distance_to(rh["position"]) - MARGIN)
			who = String((rh["collider"] as Node).name)
			hits[who] = int(hits.get(who, 0)) + 1
		n += 1
		lmin = minf(lmin, L)
		var pl := L < ARM * PULL
		if pl:
			pulled += 1
		if pl and not on:
			episodes += 1
		on = pl
		# 相機（Camera3D は腕の先から腕に沿って 1.039 m 手前・0.09 m 上：player_yoriichi.tscn）が見える石の上面より下（石の中）か
		if not st.is_empty():
			var up := Basis(Vector3.UP, yaw) * (Basis(Vector3.RIGHT, PITCH) * Vector3(0, 1, 0))
			var cam := piv + dir * (L - 1.039) + up * 0.09
			var nk: Array = _nearest_k(Vector2(cam.x, cam.z))
			var lat := float(nk[1])
			if lat <= LIB.STEP_W * 0.5 + LIB.CURB_W:
				var vt := _visible_top(st, int(nk[0])) - (0.11 if lat <= LIB.STEP_W * 0.5 else 0.0)
				if not is_nan(vt) and cam.y < vt + 0.05:
					clip += 1
		samples.append([snappedf(k * 0.05, 0.01), snappedf(L, 0.01), who])
		if L < lmin_at[1]:
			lmin_at = [snappedf(k * 0.05, 0.01), L, who, _v3(foot)]
		k -= 5
	var r := {"samples": n, "pulled": pulled, "pulled_ratio": snappedf(float(pulled) / maxf(n, 1), 0.001), "episodes": episodes, "min_len": snappedf(lmin, 0.01), "min_at": lmin_at, "hit_colliders": hits, "camera_in_stone": clip}
	# 区間ごと（s 10 m）の平均腕長
	var bins := {}
	for e in samples:
		var b := int(floor(float(e[0]) / 10.0)) * 10
		if not bins.has(b):
			bins[b] = [0.0, 0]
		bins[b][0] += float(e[1])
		bins[b][1] += 1
	var bs := []
	var keys := bins.keys()
	keys.sort()
	for b in keys:
		bs.append("%d:%.1f" % [b, float(bins[b][0]) / int(bins[b][1])])
	print("[CAM] %-20s 標本 %d（0.25 m）  縮み %d（%.0f %%）  回数 %d  最短 %.2f m @s %.1f（%s）  当たり %s  相機が石の中 %d" % [tag, n, pulled, 100.0 * pulled / maxf(n, 1), episodes, lmin, float(lmin_at[0]), String(lmin_at[2]), str(hits), clip])
	print("[CAM]   区間平均（s m:腕 m）", " ".join(bs))
	r["samples_s_len_collider"] = samples
	return r


func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
