extends SceneTree
## P10 R6b ROUND 3 — 參道の「歩ける面」検証（提案：P9 R4-2 scope-aware／walkable-surface verifier correction）。回歸 tag SWALK。
##   Godot --headless --path godot --script res://tools/verify_village_v2_sando_walkable.gd
## 使用者 ROUND 3 §2：P9 R4-2 の封存 gate（verify_village_v2_shrine_grove.gd --scene）は「參道＋前庭を地形＋0.55 m から上の膠囊で實走」
##   ＝足場を常に P1 地形とみなす。ROUND 2 の踊り場（盛土）では斜坡碰撞＝本当の足場が地形より最大 1.1 m 上 → 膠囊が足場そのものに当たる。
##   高さの閾値を上げたり碰撞を無視したりせず、「足場＝その点の最上面の歩ける面（P1 地形 or 參道の斜坡碰撞）」に置き直し、次を同時に検査する：
##   W1 歩ける面の位置：石段の範囲では斜坡碰撞（実際の碰撞）と見える踏面の差 ≤ 半蹴上＋0.03（足が石に浮かない・沈まない）
##   W2 玩家の膠囊（player_yoriichi.tscn の実寸）の淨空：足場＋0.30 m に置き、足場（地形・斜坡）以外の碰撞体と接触 0（中心線＋左右）
##   W3 高さの連続：0.25 m ごとの足場の差 ≤ 0.25·tan(floor_max_angle)＋0.02（段差・崖・穴なし；踊り場の上下も同じ）
##   W4 踊り場の縁と両脇：見える袖石の外縁 ≤ 斜坡の半幅＋0.05（見える石の上に碰撞が無い所を作らない）；脇へ降りた玩家が
##      下り方向 8 m 以内で「足場との差 ≤ step_height」の所へ戻れる（閉じ込めなし）
##   W5 NPC：初期位置が石段の上にない・巡回路が石段を横切らない（不搬）
##   W6 正式 TPS 相機（Pivot 1.65・pitch −0.18・腕 8.5・margin 0.2、Camera3D は腕に沿って 1.039 手前・0.09 上）：上り／下りとも相機が
##      見える石・地形の中に入らない（腕の縮み自体は正しい碰撞挙動＝INFO として回数・最短・割合を出す）
##   W7 P9 R4-2 と同じ経路（參道＋前庭、0.5 m、一の鳥居の箱は同じ扱い）を、足場＝最上面の歩ける面にして膠囊實走 → 被擋 0
## 永久反向（each must FAIL）：N1 參道に箱（1 m）を置く／N2 踊り場の斜坡を 0.5 m 持ち上げて段差／N3 踊り場の斜坡を抜く（穴）／
##   N4 斜坡を幅 2.0 m に細くする（見える袖石の下に碰撞なし）／N5 相機の碰撞を切る（腕 8.5 m 固定＝相機が斜面に潜る）
## 参考（INFO）：P9 R4-2 封存 gate と同じ「地形基準」の膠囊でこの場景を測ると被擋がいくつ出るか（＝封存 gate の誤検出の量）。
const LIB := preload("res://tools/village_v2_shrine_approach_lib.gd")
const SG := preload("res://tools/village_v2_shrine_grove_lib.gd")
const GL := preload("res://tools/village_v2_hieda_garden_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const PLAYER := "res://characters/yoriichi/player_yoriichi.tscn"
const PITCH := -0.18
const PIVOT_H := 1.65
const ARM := 8.5
const MARGIN := 0.2
const CAM_BACK := 1.039
const CAM_UP := 0.09

var fails := 0
var quiet := false
var V: Node3D
var L: Dictionary
var cl: PackedVector2Array
var H: PackedFloat32Array
var st: Array
var terrain: StaticBody3D
var ramp: StaticBody3D
var ramp_shape: CollisionShape3D
var cap_r := 0.3
var cap_h := 1.7
var floor_max := deg_to_rad(45.0)
var step_h := 0.6


func _ok(c: bool, msg: String) -> bool:
	if not quiet:
		print("[SWALK] ", "PASS " if c else "FAIL ", msg)
	if not c:
		fails += 1
	return c


func _info(msg: String) -> void:
	if not quiet:
		print("[SWALK] INFO ", msg)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	# 玩家の実寸（木に足さず、プロパティだけ読む）
	var pl := (load(PLAYER) as PackedScene).instantiate()
	if pl is CharacterBody3D:
		floor_max = (pl as CharacterBody3D).floor_max_angle
	for c in pl.find_children("*", "CollisionShape3D", false, false):
		if (c as CollisionShape3D).shape is CapsuleShape3D:
			cap_r = ((c as CollisionShape3D).shape as CapsuleShape3D).radius
			cap_h = ((c as CollisionShape3D).shape as CapsuleShape3D).height
	if "step_height" in pl:
		step_h = float(pl.get("step_height"))
	# P11 R2 診斷：--step-override=<m> で玩家の step_height の想定値だけ差し替える（既定は玩家の値のまま；P11 R2 候補 A＝0.35 の事前確認）
	for u: String in OS.get_cmdline_user_args():
		if u.begins_with("--step-override="):
			step_h = float(u.trim_prefix("--step-override="))
	pl.free()
	V = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(V)
	L = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	for i in 4:
		await process_frame
	await physics_frame
	await physics_frame
	terrain = V.get_node("Collision/TerrainCollision") as StaticBody3D
	var sa := V.get_node(LIB.NODE_NAME)
	ramp = sa.get_node("RampCollision") as StaticBody3D
	ramp_shape = ramp.get_node("Ramp") as CollisionShape3D
	cl = LIB.centerline()
	# 地形だけの高さ（斜坡を外して読む）→ build と同じ計画
	ramp_shape.disabled = true
	await physics_frame
	H = LIB.ramp_profile(V, cl)
	ramp_shape.disabled = false
	await physics_frame
	await physics_frame
	st = LIB.steps(cl, H)
	_info("玩家 膠囊 r %.2f h %.2f、floor_max_angle %.1f°、step_height %.2f；石段 %d（踊り場 %d）" % [cap_r, cap_h, rad_to_deg(floor_max), step_h, st.size(), st.filter(func(a): return a["kind"] == "landing").size()])
	await _checks({"cam_collide": true})
	await _negatives()
	_info_old_probe()
	print("[SWALK] 結果：%d 項失敗" % fails)
	quit(fails)


## 足場：その点の最上面の「歩ける面」（P1 地形 or 參道の斜坡碰撞）。他の碰撞体（木・燈籠・鳥居）は飛ばして下を読む。
func _floor(p: Vector2) -> float:
	var sp := V.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 90.0, p.y), Vector3(p.x, -30.0, p.y))
	var ex: Array[RID] = []
	for t in 24:
		q.exclude = ex
		var h := sp.intersect_ray(q)
		if h.is_empty():
			return NAN
		var c: Object = h["collider"]
		if c == terrain or c == ramp:
			return float(h["position"].y)
		ex.append(h["rid"])
	return NAN


func _capsule_hits(p: Vector2, fy: float, lift := 0.30) -> Array:
	var sp := V.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = cap_r
	cap.height = cap_h
	var qp := PhysicsShapeQueryParameters3D.new()
	qp.shape = cap
	qp.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, fy + lift + cap_h * 0.5, p.y))
	qp.exclude = [terrain.get_rid(), ramp.get_rid()]
	var out := []
	for r in sp.intersect_shape(qp, 4):
		out.append(String((r["collider"] as Node).name))
	return out


## 石段の見える踏面の高さ（中心線索引 k を含む段）
func _tread(k: int) -> float:
	for a: Dictionary in st:
		if k >= int(a["k0"]) and k <= int(a["k1"]):
			return lerpf(float(a["y0"]), float(a["y1"]), float(k - int(a["k0"])) / maxf(int(a["k1"]) - int(a["k0"]), 1))
	return NAN


func _checks(cfg: Dictionary) -> void:
	var k0 := int(st[0]["k0"])
	var k1 := int(st[st.size() - 1]["k1"])
	var half := LIB.STEP_W * 0.5 + LIB.CURB_W
	var walk_half := LIB.STEP_W * 0.5 - cap_r - 0.05
	# W1 歩ける面の位置
	var dev := 0.0
	var dev_bad := 0
	var nan_n := 0
	for k in range(k0, k1 + 1, 5):
		var a := cl[k]
		var f := _floor(a)
		var tr := _tread(k)
		if is_nan(f) or is_nan(tr):
			nan_n += 1
			continue
		var d := absf(f - tr)
		dev = maxf(dev, d)
		if d > float(LIB.RISER[1]) * 0.5 + 0.03:
			dev_bad += 1
	_ok(dev_bad == 0 and nan_n == 0, "W1 歩ける面＝斜坡碰撞と見える踏面の差 最大 %.3f m（≤ 半蹴上 %.2f＋0.03）、外れ %d、足場なし %d" % [dev, float(LIB.RISER[1]) * 0.5, dev_bad, nan_n])
	# W2 膠囊の淨空（中心線＋左右）／W3 高さの連続
	var blocked := []
	var jump_bad := []
	var max_jump := 0.0
	var lim := 0.25 * tan(floor_max) + 0.02
	for lat: float in [-walk_half, 0.0, walk_half]:
		var prev := NAN
		for k in range(k0 - 40, mini(k1 + 40, cl.size() - 1), 5):
			var t := LIB.tangent(cl, k)
			var nrm := Vector2(-t.y, t.x)
			var p := cl[k] + nrm * lat
			var f := _floor(p)
			if is_nan(f):
				jump_bad.append("足場なし s %.1f lat %.1f" % [k * 0.05, lat])
				prev = NAN
				continue
			var hh := _capsule_hits(p, f)
			if not hh.is_empty():
				blocked.append("s %.1f lat %+.1f %s" % [k * 0.05, lat, hh[0]])
			if not is_nan(prev):
				var dj := absf(f - prev)
				max_jump = maxf(max_jump, dj)
				if dj > lim:
					jump_bad.append("s %.1f lat %+.1f Δ %.2f" % [k * 0.05, lat, dj])
			prev = f
	_ok(blocked.is_empty(), "W2 玩家膠囊（r %.2f h %.2f、足場＋0.30）を石段の中心線と左右 ±%.2f m に置く：接触 %d%s" % [cap_r, cap_h, walk_half, blocked.size(), "" if blocked.is_empty() else " ✗ " + str(blocked.slice(0, 4))])
	_ok(jump_bad.is_empty(), "W3 高さの連続：0.25 m ごとの足場の差 最大 %.3f m（≤ 0.25·tan(%.0f°)＋0.02＝%.3f）%s" % [max_jump, rad_to_deg(floor_max), lim, "" if jump_bad.is_empty() else " ✗ " + str(jump_bad.slice(0, 4))])
	# W4 踊り場の縁と両脇
	var edge_bad := []
	var trap := []
	var curb_out := LIB.STEP_W * 0.5 + 0.03 + 0.24   # 袖石の外縁の最大（lib：hw＋jit 0.03＋幅 0.24）
	if curb_out > half + 0.05:
		edge_bad.append("袖石の外縁 %.2f ＞ 斜坡の半幅 %.2f＋0.05" % [curb_out, half])
	var rh := _ramp_half()
	if rh + 0.05 < curb_out:
		edge_bad.append("斜坡の半幅（実測）%.2f＋0.05 ＜ 袖石の外縁 %.2f" % [rh, curb_out])
	for a: Dictionary in st:
		if String(a["kind"]) != "landing":
			continue
		for f2: float in [0.2, 0.5, 0.8]:
			var k := int(lerpf(float(a["k0"]), float(a["k1"]), f2))
			var t := LIB.tangent(cl, k)
			var nrm := Vector2(-t.y, t.x)
			for sd: float in [-1.0, 1.0]:
				var inside := _floor(cl[k] + nrm * sd * (half - 0.05))
				if is_nan(inside) or absf(inside - float(a["y0"])) > 0.15:
					edge_bad.append("踊り場 s %.1f 縁の内側の足場 %.2f（踊り場 %.2f）" % [k * 0.05, inside, float(a["y0"])])
				# 脇に降りた玩家：下り方向へ同じ横位置を辿り、斜坡との差 ≤ step_height の所まで ≤ 8 m
				var ok_back := false
				var min_d := INF
				for m in range(0, 161, 4):
					var kk := k - m
					if kk < 0:
						break
					var tt := LIB.tangent(cl, kk)
					var nn := Vector2(-tt.y, tt.x)
					var out_p := cl[kk] + nn * sd * (half + 0.4)
					var in_p := cl[kk] + nn * sd * (half - 0.1)
					var fo := _floor(out_p)
					var fi := _floor(in_p)
					if not is_nan(fo) and not is_nan(fi):
						min_d = minf(min_d, fi - fo)
					if not is_nan(fo) and not is_nan(fi) and fi - fo <= step_h:
						ok_back = true
						break
				if not ok_back:
					# P11 R2：診斷として 8 m 以内で最も低かった「斜坡と脇の地面の段差」も出す（判定は不変）
					trap.append("踊り場 s %.1f %s 側（8 m 以内の最小段差 %.2f m）" % [k * 0.05, "右" if sd > 0 else "左", min_d])
	if not trap.is_empty():
		_info("W4 脇へ降りて 8 m 以内に戻れない所 %d：%s" % [trap.size(), str(trap)])
	_ok(edge_bad.is_empty() and trap.is_empty(), "W4 踊り場の縁と両脇：見える袖石の外縁 ≤ 斜坡の半幅＋0.05、縁の内側＝踊り場の高さ、脇へ降りても 8 m 以内に戻れる%s" % ("" if edge_bad.is_empty() and trap.is_empty() else " ✗ " + str((edge_bad + trap).slice(0, 4))))
	# W5 NPC
	var bad5 := []
	var n_patrol := 0
	var pop := V.get_node_or_null("Population")
	if pop:
		for b in pop.find_children("*", "AnimatableBody3D", true, false):
			var np := Vector2((b as Node3D).global_position.x, (b as Node3D).global_position.z)
			var nk := _nearest_k(np)
			if float(nk[1]) <= half + 0.3 and int(nk[0]) >= k0 and int(nk[0]) <= k1:
				bad5.append("%s 在石段上" % b.name)
			if "path_xz" in b:
				var px: PackedVector2Array = b.get("path_xz")
				if px.size() >= 2:
					n_patrol += 1
					for i2 in px.size() - 1:
						for k in range(k0, k1 + 1, 10):
							var q3 := Geometry2D.get_closest_point_to_segment(cl[k], px[i2], px[i2 + 1])
							if q3.distance_to(cl[k]) < half + 0.3:
								bad5.append("%s 巡回路橫切石段" % b.name)
								break
	_ok(bad5.is_empty() and n_patrol > 0, "W5 NPC：初期位置が石段の上 0・巡回 %d 條が石段を横切らない（NPC 不搬）%s" % [n_patrol, "" if bad5.is_empty() else " ✗ " + str(bad5.slice(0, 4))])
	# W6 正式 TPS 相機
	var cam := _camera_walk(bool(cfg["cam_collide"]))
	_ok(int(cam["in_stone"]) == 0, "W6 TPS 相機（上り＋下り %d 点）：相機が見える石・地形の中 %d 点" % [int(cam["n"]), int(cam["in_stone"])])
	_info("W6 腕の縮み（正しい碰撞挙動）：下り %d／%d 点（%.0f %%）・%d 回・最短 %.2f m、上り %d／%d 点" % [int(cam["down_pulled"]), int(cam["down_n"]), 100.0 * int(cam["down_pulled"]) / maxf(1, int(cam["down_n"])), int(cam["down_episodes"]), float(cam["down_min"]), int(cam["up_pulled"]), int(cam["up_n"])])
	# W7 P9 R4-2 と同じ経路（足場＝最上面の歩ける面）
	var road: Array = SG.road_pts(L)
	var routes: Array = [road.slice(1), [Vector2(266.0, -208.0), Vector2(258.0, -214.0), Vector2(258.0, -221.5)], [Vector2(250.5, -216.0), Vector2(266.0, -216.0)]]
	var blk := []
	var probes := 0
	for route: Array in routes:
		for e: Array in GL.resample(route, 0.5):
			var p: Vector2 = e[0]
			if SG.TORII_BOX.grow(0.2).has_point(p) and absf((p - SG.TORII).dot(Vector2(0.927, 0.375))) > 1.6:
				continue
			var f := _floor(p)
			probes += 1
			if is_nan(f):
				blk.append("(%.1f,%.1f) 足場なし" % [p.x, p.y])
				continue
			var hh := _capsule_hits(p, f, 0.55)
			if not hh.is_empty():
				blk.append("(%.1f,%.1f) %s" % [p.x, p.y, hh[0]])
	_ok(blk.is_empty() and probes > 100, "W7 P9 R4-2 と同じ經路（參道＋前庭 %d 点、膠囊は足場＋0.55＝封存 gate と同じ高さ、足場＝最上面の歩ける面）被擋 %d%s" % [probes, blk.size(), "" if blk.is_empty() else " ✗ " + str(blk.slice(0, 3))])


func _nearest_k(p: Vector2) -> Array:
	var bk := 0
	var bd := INF
	for k in range(0, cl.size(), 2):
		var d := cl[k].distance_to(p)
		if d < bd:
			bd = d
			bk = k
	return [bk, bd]


## 斜坡碰撞の実際の半幅（石段中央付近で横へ光線を落として最外の斜坡ヒット）
func _ramp_half() -> float:
	var sp := V.get_world_3d().direct_space_state
	var k := (int(st[0]["k0"]) + int(st[st.size() - 1]["k1"])) / 2
	var t := LIB.tangent(cl, k)
	var nrm := Vector2(-t.y, t.x)
	var best := 0.0
	for i in 80:
		var off := i * 0.025
		var p := cl[k] + nrm * off
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 90, p.y), Vector3(p.x, -30, p.y))
		q.exclude = [terrain.get_rid()]
		var hh := sp.intersect_ray(q)
		var hit_ramp := false
		var ex: Array[RID] = [terrain.get_rid()]
		for tt in 16:
			q.exclude = ex
			hh = sp.intersect_ray(q)
			if hh.is_empty():
				break
			if hh["collider"] == ramp:
				hit_ramp = true
				break
			ex.append(hh["rid"])
		if hit_ramp:
			best = off
	return best


## 正式 TPS 相機を中心線に沿って上り・下りで置く（diag_village_v2_sando_camera.gd と同じ幾何）
func _camera_walk(collide: bool) -> Dictionary:
	var sp := V.get_world_3d().direct_space_state
	var r := {"n": 0, "in_stone": 0, "down_n": 0, "down_pulled": 0, "down_episodes": 0, "down_min": INF, "up_n": 0, "up_pulled": 0}
	var k_lo := maxi(int(st[0]["k0"]) - 40, 0)
	var k_hi := mini(int(st[st.size() - 1]["k1"]) + 40, cl.size() - 1)
	for dirn in ["down", "up"]:
		var on := false
		var k := k_hi if dirn == "down" else k_lo
		while (k >= k_lo) if dirn == "down" else (k <= k_hi):
			var f := _floor(cl[k])
			if not is_nan(f):
				var t := -LIB.tangent(cl, k) if dirn == "down" else LIB.tangent(cl, k)
				var yaw := atan2(-t.x, -t.y)
				var bas := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PITCH)
				var dir := bas * Vector3(0, 0, 1)
				var up := bas * Vector3(0, 1, 0)
				var piv := Vector3(cl[k].x, f + PIVOT_H, cl[k].y)
				var Lh := ARM
				if collide:
					var rq := PhysicsRayQueryParameters3D.create(piv, piv + dir * ARM)
					var rh := sp.intersect_ray(rq)
					if not rh.is_empty():
						Lh = maxf(0.0, piv.distance_to(rh["position"]) - MARGIN)
				var cam := piv + dir * maxf(Lh - CAM_BACK, 0.0) + up * CAM_UP
				var fc := _floor(Vector2(cam.x, cam.z))
				var nk := _nearest_k(Vector2(cam.x, cam.z))
				var vis := fc
				if float(nk[1]) <= LIB.STEP_W * 0.5 + LIB.CURB_W:
					var tr := _tread(int(nk[0]))
					if not is_nan(tr):
						vis = maxf(vis, tr + (LIB.CURB_UP if float(nk[1]) > LIB.STEP_W * 0.5 else 0.0))
				r["n"] = int(r["n"]) + 1
				if not is_nan(vis) and cam.y < vis + 0.05:
					r["in_stone"] = int(r["in_stone"]) + 1
				var pulled := Lh < ARM * 0.55
				if dirn == "down":
					r["down_n"] = int(r["down_n"]) + 1
					r["down_min"] = minf(float(r["down_min"]), Lh)
					if pulled:
						r["down_pulled"] = int(r["down_pulled"]) + 1
						if not on:
							r["down_episodes"] = int(r["down_episodes"]) + 1
					on = pulled
				else:
					r["up_n"] = int(r["up_n"]) + 1
					if pulled:
						r["up_pulled"] = int(r["up_pulled"]) + 1
			k += -5 if dirn == "down" else 5
	return r


## 反向用：斜坡碰撞の形を差し替える（raise＝[k0,k1,dy]、hole＝[k0,k1]、half＝半幅）
func _ramp_faces(raise := [], hole := [], half := -1.0) -> ConcavePolygonShape3D:
	var rp := LIB.ramp_points(st, H)
	var hw := (LIB.STEP_W * 0.5 + LIB.CURB_W) if half < 0.0 else half
	var faces := PackedVector3Array()
	for i in rp.size() - 1:
		var ka := int(rp[i][0])
		var kb := int(rp[i + 1][0])
		if kb <= ka:
			continue
		if not hole.is_empty() and kb > int(hole[0]) and ka < int(hole[1]):
			continue
		var ya := float(rp[i][1])
		var yb := float(rp[i + 1][1])
		if not raise.is_empty():
			if ka >= int(raise[0]) and ka <= int(raise[1]):
				ya += float(raise[2])
			if kb >= int(raise[0]) and kb <= int(raise[1]):
				yb += float(raise[2])
		var ta := LIB.tangent(cl, ka)
		var tb := LIB.tangent(cl, kb)
		var na := Vector2(-ta.y, ta.x) * hw
		var nb := Vector2(-tb.y, tb.x) * hw
		faces.append_array(PackedVector3Array([Vector3(cl[ka].x - na.x, ya, cl[ka].y - na.y), Vector3(cl[kb].x - nb.x, yb, cl[kb].y - nb.y), Vector3(cl[kb].x + nb.x, yb, cl[kb].y + nb.y),
			Vector3(cl[ka].x - na.x, ya, cl[ka].y - na.y), Vector3(cl[kb].x + nb.x, yb, cl[kb].y + nb.y), Vector3(cl[ka].x + na.x, ya, cl[ka].y + na.y)]))
	var shp := ConcavePolygonShape3D.new()
	shp.set_faces(faces)
	shp.backface_collision = true
	return shp


func _negatives() -> void:
	print("[SWALK] 永久反向（每案必須讓 gate 失敗）")
	var orig := ramp_shape.shape
	var land: Array = st.filter(func(a): return a["kind"] == "landing")
	var la: Dictionary = land[1]
	var cases := [
		["N1 參道（s 70 m）に 1 m の箱", "box"],
		["N2 踊り場の斜坡を 0.5 m 持ち上げる（段差）", "raise"],
		["N3 踊り場の斜坡を抜く（穴）", "hole"],
		["N4 斜坡を幅 2.0 m に細くする（袖石の下に碰撞なし）", "narrow"],
		["N5 相機の碰撞を切る（腕 8.5 m 固定）", "nocam"],
	]
	var neg_fail := 0
	for c in cases:
		var kind: String = c[1]
		var extra: Node = null
		var cfg := {"cam_collide": true}
		match kind:
			"box":
				var b := StaticBody3D.new()
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(1, 1, 1)
				cs.shape = bs
				b.add_child(cs)
				var k := int(70.0 / 0.05)
				b.position = Vector3(cl[k].x, _floor(cl[k]) + 0.5, cl[k].y)
				V.add_child(b)
				extra = b
			"raise":
				ramp_shape.shape = _ramp_faces([int(la["k0"]) + 3, int(la["k1"]) - 3, 0.5])
			"hole":
				ramp_shape.shape = _ramp_faces([], [int(la["k0"]) - 2, int(la["k1"]) + 2])
			"narrow":
				ramp_shape.shape = _ramp_faces([], [], 1.0)
			"nocam":
				cfg["cam_collide"] = false
		await physics_frame
		await physics_frame
		var f0 := fails
		quiet = true
		await _checks(cfg)
		quiet = false
		var tripped := fails > f0
		fails = f0
		print("[SWALK]   %s：%s" % [c[0], "PASS（gate 正確失敗）" if tripped else "FAIL（gate 沒抓到）"])
		if not tripped:
			neg_fail += 1
		if extra:
			extra.free()
		ramp_shape.shape = orig
		await physics_frame
		await physics_frame
	_ok(neg_fail == 0, "反向 %d/%d" % [cases.size() - neg_fail, cases.size()])


## 参考：P9 R4-2 封存 gate と同じ「地形基準」の膠囊（地形＋0.55 から上、地形だけ除外）でこの場景を測る
func _info_old_probe() -> void:
	var sp := V.get_world_3d().direct_space_state
	var road: Array = SG.road_pts(L)
	var routes: Array = [road.slice(1), [Vector2(266.0, -208.0), Vector2(258.0, -214.0), Vector2(258.0, -221.5)], [Vector2(250.5, -216.0), Vector2(266.0, -216.0)]]
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	var n := 0
	var blk := 0
	var gap := 0.0
	for route: Array in routes:
		for e: Array in GL.resample(route, 0.5):
			var p: Vector2 = e[0]
			if SG.TORII_BOX.grow(0.2).has_point(p) and absf((p - SG.TORII).dot(Vector2(0.927, 0.375))) > 1.6:
				continue
			var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 90, p.y), Vector3(p.x, -30, p.y))
			q.collide_with_bodies = true
			var ex: Array[RID] = []
			var ty := NAN
			for t in 24:
				q.exclude = ex
				var h := sp.intersect_ray(q)
				if h.is_empty():
					break
				if h["collider"] == terrain:
					ty = float(h["position"].y)
					break
				ex.append(h["rid"])
			if is_nan(ty):
				continue
			var qp := PhysicsShapeQueryParameters3D.new()
			qp.shape = cap
			qp.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, ty + 0.3 + 0.85 + 0.25, p.y))
			qp.exclude = [terrain.get_rid()]
			n += 1
			var r := sp.intersect_shape(qp, 1)
			if not r.is_empty():
				blk += 1
				gap = maxf(gap, _floor(p) - ty)
	_info("参考：P9 R4-2 封存 gate と同じ地形基準の膠囊でこの場景を測ると %d 点中 %d 点が被擋（そこでの足場は地形より最大 %.2f m 上＝踊り場の盛土の上を歩く面）" % [n, blk, gap])
