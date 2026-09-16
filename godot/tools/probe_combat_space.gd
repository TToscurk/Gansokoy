extends SceneTree
## 戰鬥空間探針 —— 「這裡打不打得起來」的實測，不是目測。
##
##   Godot --headless --path godot --script tools/probe_combat_space.gd
##   Godot --headless --path godot --script tools/probe_combat_space.gd -- trail
##
## 為什麼要這支：隻狼式戰鬥的數字本身就是場地規格 ——
##   鎖定 22 m / 脫鎖 30 m（yoriichi_character.gd）
##   山犬突進 11 m/s、前搖 1.2 s，滑行 4–6 m（enemy_wolf.gd）
##   太陽龍 6 m 寬（continuous spin）、玩家翻滾 3.2 m
## 場地不夠大或中央有障礙物，戰鬥立刻退化成「撞樹」。
## 2026-09-16 使用者裁定：場地要先量再改，這支就是那個「量」。
##
## 量法（用真碰撞體，不重算產生器的高度函式）：
##   1. 碰撞建法與 main.gd `_build_trimesh_collision` 同規則：
##      own_colliders 的圖只做 Terrain 與 has_meta("needs_trimesh") 的 mesh。
##   2. 每個候選中心：從 y+60 射線取地面 y，再以 0.25 m 步進二分搜尋
##      「最大淨空半徑 r」——半徑內 1 m 網格 + 兩圈取樣點的玩家膠囊
##      （r0.3 / h1.7，與 player_yoriichi.tscn 同尺寸）不得與任何碰撞體相交，
##      且取樣點腳下必須有可站立地面（法線角 ≤ 52°，與 Player 的 floor_max_angle 同）。
##   3. 邊界牆（40 m 高隱形擋牆，名字含 Boundary／邊界）全程排除 —— 它們不是場地障礙。
##
## 驗收門檻（本計畫 §2.1）：r ≥ 12 m，中心點周邊高低差 ≤ 0.5 m。

const TRIMESH_MIN_SPAN := 15.0
## 玩家膠囊：與 characters/yoriichi/player_yoriichi.tscn 的 CapsuleShape3D 同值。
const BODY_RADIUS := 0.3
const BODY_HEIGHT := 1.7
const FLOOR_MAX_ANGLE := 0.907571     # Player root 的 floor_max_angle（52°）
const SEARCH_MAX := 18.0
const SEARCH_STEP := 0.25
## 膠囊離地高度。⚠ 貼著地面量（底端剛好落在 y=gy）會與地形網格自身相交，
## 每個候選點都會得到 r=0 的假結果（2026-09-16 第一次跑就是這樣）。
const BODY_LIFT := 0.06
## 玩家踏步高度（yoriichi_character.step_height）：比這小的地形落差不是障礙。
const STEP_UP := 0.6

## map → [ {name, xz} ]。座標來源見註解，不得目測填空。
const CANDIDATES := {
	"trail": [
		# 空地中心＝序章醒來點（data/trail.meta.json spawn，09-15 探針實測）
		{"name": "獸道大空地中心", "xz": Vector2(-13.78, -26.82)},
		{"name": "獸道空地北緣", "xz": Vector2(-14.08, -40.03)},
		{"name": "獸道屋台平台", "xz": Vector2(3.78, -71.60)},
		# MQ02 獵食者痕跡（trail_interactions.tscn 的 Area3D 座標）
		{"name": "獵食者痕跡", "xz": Vector2(0.90, -62.0)},
		# 獵食者戰鬥袋中心（gen_trail_v2.gd 的 T_FIGHT=0.7719；場景 meta 主脊反查）
		{"name": "獵食者戰鬥袋中心", "xz": Vector2(-1.13, -56.13)},
	],
	"shrine": [
		# 拜殿月台 34×23 @ (0, -22.5)：南帶與東翼（由 shrine.tscn 的月台碰撞實測）
		{"name": "神社前庭南帶", "xz": Vector2(0.0, -15.0)},
		{"name": "神社前庭東翼", "xz": Vector2(11.0, -26.0)},
		{"name": "神社參道中段", "xz": Vector2(0.0, 5.0)},
	],
	"slice": [
		# 人里既有地標（docs/plans/2026-09-16 的座標表）
		{"name": "村門內", "xz": Vector2(234.0, 92.0)},
		{"name": "火見櫓南", "xz": Vector2(243.0, -62.0)},
		{"name": "寺子屋南外", "xz": Vector2(315.0, 55.0)},
		{"name": "龍石像橋西岸", "xz": Vector2(400.0, -144.0)},
		{"name": "東岸農地", "xz": Vector2(400.0, -120.0)},
	],
}

var _boundary: Array[RID] = []
var _root: Node3D = null
var _report: Dictionary = {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("-"):
			only = a
	var maps: Array = CANDIDATES.keys() if only == "" else [only]
	for m in maps:
		if not CANDIDATES.has(m):
			print("[SPACE] 未知地圖：%s" % m)
			continue
		await _probe_map(String(m))
	var path := "res://data/combat_spaces.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_report, "  "))
		f.close()
		print("[SPACE] 已寫入 %s" % path)
	quit(0)


func _probe_map(id: String) -> void:
	var scene_path := "res://maps/%s/%s.tscn" % [id, id]
	var ps := load(scene_path) as PackedScene
	if ps == null:
		print("[SPACE] 載不到 %s" % scene_path)
		return
	_root = ps.instantiate() as Node3D
	root.add_child(_root)
	# 物理伺服器要幾帧才會認得新形狀。
	for i in 6:
		await physics_frame
	_boundary = _collect_boundary(_root)
	var n_col := _build_trimesh(_root)
	print("[SPACE] ─ %s（地形碰撞 %d、邊界牆排除 %d）──" % [id, n_col, _boundary.size()])

	var map_out: Array = []
	for c in CANDIDATES[id]:
		var xz: Vector2 = c["xz"]
		var gy := _ground_y(Vector3(xz.x, 60.0, xz.y))
		if is_nan(gy):
			print("[SPACE] %-14s %s  找不到地面" % [id, c["name"]])
			continue
		var clear_r := _clear_radius(Vector3(xz.x, gy, xz.y))
		# 逐圈診斷：哪一圈開始失敗、失敗點的腳高與中心差多少（判斷是坡度還是障礙）
		if clear_r < 12.0:
			print("[SPACE]   診斷 %s：" % c["name"])
			for rr in [6.0, 9.0, 12.0, 15.0]:
				print("[SPACE]     r=%4.1f m  %s" % [rr, _diagnose(Vector3(xz.x, gy, xz.y), rr)])
		var relief := _relief(Vector3(xz.x, gy, xz.y), 4.0)
		var blocker := _blocker_at(Vector3(xz.x, gy, xz.y), clear_r + SEARCH_STEP)
		var verdict := "OK" if clear_r >= 12.0 and relief <= 0.5 else "太小"
		print("[SPACE] %-6s %-16s x=%8.2f z=%8.2f  y=%6.2f  r=%5.2f m  起伏=%4.2f m  擋路=%s  → %s" % [
			id, c["name"], xz.x, xz.y, gy, clear_r, relief, blocker, verdict])
		map_out.append({
			"name": c["name"], "x": xz.x, "z": xz.y, "ground_y": gy,
			"clear_radius": clear_r, "relief_4m": relief,
			"blocker": blocker, "verdict": verdict,
		})
	_report[id] = map_out
	_root.queue_free()
	_root = null
	for i in 3:
		await physics_frame


## 與 main.gd `_build_trimesh_collision` 同規則（同步維護，改一邊要改兩邊）。
func _build_trimesh(r: Node) -> int:
	var n_col := 0
	var stack: Array[Node] = [r]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D:
			if not (String(n.name) == "Terrain" or n.has_meta("needs_trimesh")):
				continue
			if not (n as Node3D).is_visible_in_tree():
				continue
			var aabb: AABB = (n as MeshInstance3D).get_aabb()
			if maxf(aabb.size.x, aabb.size.z) >= TRIMESH_MIN_SPAN:
				(n as MeshInstance3D).create_trimesh_collision()
				n_col += 1
	return n_col


func _collect_boundary(r: Node) -> Array[RID]:
	var out: Array[RID] = []
	var stack: Array[Node] = [r]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is PhysicsBody3D:
			var nm := String(n.name)
			if nm.contains("Boundary") or nm.contains("邊界") or nm.contains("boundary"):
				out.append((n as PhysicsBody3D).get_rid())
	return out


func _capsule() -> CapsuleShape3D:
	var s := CapsuleShape3D.new()
	s.radius = BODY_RADIUS
	s.height = BODY_HEIGHT
	return s


## 某點能不能站人：從上往下射線，且地面法線角在 floor_max_angle 內。
func _ground_y(from: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(
		from, Vector3(from.x, from.y - 200.0, from.z))
	q.exclude = _boundary
	var hit := get_root().world_3d.direct_space_state.intersect_ray(q)
	return float(hit.position.y) if hit.has("position") else NAN


func _standable(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(
		p + Vector3(0, 1.2, 0), p + Vector3(0, -1.2, 0))
	q.exclude = _boundary
	var hit := get_root().world_3d.direct_space_state.intersect_ray(q)
	if not hit.has("position"):
		return false
	var n: Vector3 = hit["normal"]
	return n.angle_to(Vector3.UP) <= FLOOR_MAX_ANGLE


## 診斷用：回傳這個點「為什麼不淨空」的第一個理由。
func _why(ground: Vector3) -> String:
	var base := ground.y
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var gy := _ground_y(ground + Vector3(cos(a) * BODY_RADIUS, 2.0, sin(a) * BODY_RADIUS))
		if is_nan(gy):
			return "腳印取樣落地失敗"
		base = maxf(base, gy)
	if base - ground.y > STEP_UP:
		return "落差 %.2f m > 踏步 %.2f" % [base - ground.y, STEP_UP]
	if not _standable(Vector3(ground.x, base, ground.z)):
		return "站不住（坡度 > 52° 或無地面），base=%.2f" % base
	if _blocked(Vector3(ground.x, base + BODY_HEIGHT * 0.5, ground.z)):
		return "膠囊撞到「%s」，base=%.2f" % [_blocker_name(Vector3(ground.x, base + BODY_HEIGHT * 0.5, ground.z)), base]
	return ""


## 逐點掃一圈，印出第一個失敗點與理由。
func _diagnose(center: Vector3, r: float) -> String:
	for i in 24:
		var a := TAU * float(i) / 24.0
		var p := center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var gy := _ground_y(p + Vector3(0, 2.0, 0))
		if is_nan(gy):
			return "r=%.1f 方向 %.0f°：找不到地面" % [r, rad_to_deg(a)]
		var w := _why(Vector3(p.x, gy, p.z))
		if w != "":
			return "r=%.1f 方向 %.0f° x%.1f z%.1f 地面y%.2f：%s" % [r, rad_to_deg(a), p.x, p.z, gy, w]
	for gx in range(-int(r), int(r) + 1):
		for gz in range(-int(r), int(r) + 1):
			if Vector2(gx, gz).length() > r:
				continue
			var p := center + Vector3(float(gx), 0.0, float(gz))
			var gy := _ground_y(p + Vector3(0, 2.0, 0))
			if is_nan(gy):
				return "格點 x%.1f z%.1f：找不到地面" % [p.x, p.z]
			var w := _why(Vector3(p.x, gy, p.z))
			if w != "":
				return "格點 x%.1f z%.1f 地面y%.2f：%s" % [p.x, p.z, gy, w]
	return "淨空"


## 撞到誰（只回名字，診斷用）。
func _blocker_name(at: Vector3) -> String:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _capsule()
	q.transform = Transform3D(Basis(), at)
	q.exclude = _boundary
	var hits := get_root().world_3d.direct_space_state.intersect_shape(q, 4)
	for h in hits:
		var col: Object = h.get("collider")
		if col is Node:
			return _owner_name(col as Node)
	return "?"


## 這個點能不能站人（含「站上去之後身體不撞東西」）。
##
## 站位高度取**腳印四點的局部最高地面** —— 玩家有 step_height 0.6 m 的踏步，
## 站在 15 cm 的地形起伏上不算被擋。只拿射線落點當站位高度會把每一個小起伏
## 都判成障礙（2026-09-16 第一版就是這樣：空地中心量到 11.25 m，
## 擋路的其實是水池邊 10 cm 的落差）。
func _spot_ok(ground: Vector3) -> bool:
	var base := ground.y
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var gy := _ground_y(ground + Vector3(cos(a) * BODY_RADIUS, 2.0, sin(a) * BODY_RADIUS))
		if is_nan(gy):
			return false
		base = maxf(base, gy)
	if base - ground.y > STEP_UP:
		return false
	if not _standable(Vector3(ground.x, base, ground.z)):
		return false
	return not _blocked(Vector3(ground.x, base + BODY_HEIGHT * 0.5, ground.z))


## p 點的半徑內是否全空（且腳下有地）。
func _disc_free(center: Vector3, r: float) -> bool:
	if not _spot_ok(center):
		return false
	for ring in [0.5, 1.0]:
		var n := 12 if ring < 1.0 else 24
		for i in n:
			var a := TAU * float(i) / float(n)
			var p := center + Vector3(cos(a) * r * ring, 0.0, sin(a) * r * ring)
			var gy := _ground_y(p + Vector3(0, 2.0, 0))
			if is_nan(gy) or not _spot_ok(Vector3(p.x, gy, p.z)):
				return false
	# 1 m 網格：兩圈取樣會漏掉細長的障礙物（燈籠柱、祭石）。
	for gx in range(-int(r), int(r) + 1):
		for gz in range(-int(r), int(r) + 1):
			if Vector2(gx, gz).length() > r:
				continue
			var p := center + Vector3(float(gx), 0.0, float(gz))
			var gy := _ground_y(p + Vector3(0, 2.0, 0))
			if is_nan(gy) or not _spot_ok(Vector3(p.x, gy, p.z)):
				return false
	return true


func _blocked(at: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _capsule()
	q.transform = Transform3D(Basis(), at + Vector3(0, BODY_LIFT, 0))
	q.exclude = _boundary
	return not get_root().world_3d.direct_space_state.intersect_shape(q, 1).is_empty()


## 二分搜尋最大淨空半徑。
func _clear_radius(center: Vector3) -> float:
	if not _disc_free(center, SEARCH_STEP):
		return 0.0
	var lo := SEARCH_STEP
	var hi := SEARCH_MAX
	while hi - lo > SEARCH_STEP:
		var mid := (lo + hi) * 0.5
		if _disc_free(center, mid):
			lo = mid
		else:
			hi = mid
	return floorf(lo / SEARCH_STEP) * SEARCH_STEP


## 擋住的人是誰（回名字，不確定就回 RID 型別）。
func _blocker_at(center: Vector3, r: float) -> String:
	for ring in [1.0, 0.5]:
		var n := 24 if ring >= 1.0 else 12
		for i in n:
			var a := TAU * float(i) / float(n)
			var p := center + Vector3(cos(a) * r * ring, 0.0, sin(a) * r * ring)
			var gy := _ground_y(p + Vector3(0, 2.0, 0))
			if is_nan(gy):
				continue
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = _capsule()
			q.transform = Transform3D(Basis(), Vector3(p.x, gy + BODY_HEIGHT * 0.5, p.z))
			q.exclude = _boundary
			var hits := get_root().world_3d.direct_space_state.intersect_shape(q, 4)
			for h in hits:
				var col: Object = h.get("collider")
				if col is Node:
					# 帶上取樣點座標：不寫座標的話「誰擋住」無法回頭查證。
					return "%s@x%.1f z%.1f 地面y%.2f" % [_owner_name(col as Node), p.x, p.z, gy]
	return "（取樣點上沒有障礙，可能是地面斷差）"


## 碰撞體常常是匿名子節點（@CollisionShape3D@655），往上找到有名稱的祖先。
func _owner_name(n: Node) -> String:
	var cur: Node = n
	while cur != null:
		var nm := String(cur.name)
		if not nm.begins_with("@") and nm != "":
			return nm if cur.get_parent() == null else "%s/%s" % [String(cur.get_parent().name), nm]
		cur = cur.get_parent()
	return "?"


## 半徑內的ground高低差（判斷平整度）。
func _relief(center: Vector3, r: float) -> float:
	var lo := INF
	var hi := -INF
	for i in 8:
		var a := TAU * float(i) / 8.0
		var p := center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var gy := _ground_y(p + Vector3(0, 20.0, 0))
		if is_nan(gy):
			continue
		lo = minf(lo, gy)
		hi = maxf(hi, gy)
	if lo == INF:
		return 0.0
	return hi - lo