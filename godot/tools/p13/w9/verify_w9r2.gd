extends SceneTree
## P13 W9 Round 2／2.1 gate：ArchW9R2P13（建築外形サンプル）を「保存された場景」から独立に検査する ＋ 反向案例。
##   godot --headless --path godot --script res://tools/p13/w9/verify_w9r2.gd
## 見るもの：掛載（1 回・順序）／各棟の id・body 追従／LOD 範囲・三角面予算／張り出し上限／戸口前の淨空／通行の頭上淨空／
##   enabled の往復（Kit の visible が完全に元へ戻る）／碰撞は庇柱・玄関柱（Posts）＋登録済みの外形碰撞箱（Shell）だけ（Posts は柱ごとに位置・太さ・高さ・layer／mask を meta と、
##   Shell は箱ごとに位置・寸法・回転・layer／mask と有効状態を collision_fit.json と突き合わせ）／R1 の吊り物を隠す件数（R1 の中身は他に触れない）／
##   [2.1] 庇の構造規則（幅・深さ・勾配＝排水・腕木の間隔・深い庇は庇柱・前縁の高さ）／屋根の収め（棟の段積み・鬼瓦・垂木尻・懸魚）／
##   [2.1] 他 overlay（P10 の看板・幟・提灯・商品・NPC、R1、隣の建物）の実体との非干渉。
const L := preload("res://tools/p13/w9/w9r2_lib.gd")

const MAX_TRI0 := 30000        # 1 棟 LOD0
const MAX_TRI0_AVG := 15550      # 1 棟あたりの平均上限（Phase 3 の 420000／27 棟）。棟が増えても平均の基準は同じ：Phase 4 で 11 棟増（主街 7＋西巷 4）→ 合計 = 平均 × 棟数。LOD0 は 40 m 以内だけ描画（それ以遠は L1 の 30–130 tri）
const MAX_TRI1 := 500          # 1 棟 LOD1
const SIDE_OVER := 1.35        # 左右（妻・桁行）への張り出し上限 [m]（P4 massing の外側）
const BACK_OVER := 1.35
const FRONT_OVER := 2.6        # 前（街側）への張り出し上限 [m]：深い庇＋日除け
const HEAD_LO := 1.1           # 壁の外（z>zf+0.7）で、この帯に三角形があれば通行の頭に当たる
const HEAD_HI := 1.8
const DOOR_PAD := 0.05
const DOOR_BODY := 1.45        # 戸口の前：最低点がこれ未満の三角形は通行を塞ぐ（胴・足）
const WALL_FLUSH := 0.2        # 壁面に張り付く装飾（窓枠・海鼠壁・戸）は他 overlay の「壁際に立つ物」と重なって当然 → 貫入検査は z>zf+0.2 のみ
const HUG := 0.7               # 壁にへばりつく帯（樽・薪・縁台など）の厚み [m]
# 庇の構造規則
const EAVE_MAX_DEPTH := 1.55   # これより深い庇は庇柱を 2 本以上
const EAVE_MIN_P := 0.15       # 排水勾配（壁側が高く、通り側へ下がる）
const EAVE_MAX_GAP := 1.3      # 腕木の最大間隔
const EAVE_MIN_FRONT := 2.0    # 庇の前縁の下端高さ（頭が当たらない）
# R1 の吊り物（overlay が同じ toggle で隠す種類）
const R1_HANG := ["sudare", "kaki", "sugi", "zaru", "zori"]
const TSUMA := ["B_P_MKT_009", "B_P_MKT_010", "B_P_RSW_062", "B_P_MKT_020", "B_P_RSW_014", "B_P_RSW_075", "B_P_MKT_028", "B_P_MKT_003"]   # 妻入（懸魚が要る）
const R2_BASE := "0ca148f"      # R2 の直前（R1 最終）。village_v2.tscn はここから追加のみ・≤3 行
const NEIGHBOR_SHRINK := 0.12  # 隣棟の massing 箱をこれだけ縮めて、屋根・庇の貫入を拾う（Kit 自身の軒も少し重なるため）
const NEIGHBOR_Y := 2.0        # 隣棟への貫入は屋根・庇の高さ（局部 y > 2.0）だけ
const OCC_SHRINK := 0.04       # 他 overlay の AABB をこれだけ縮めて判定（接触は許す・貫入を拾う）

var passed := 0
var failed := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("[W9R2G] PASS ", msg)
	else:
		failed += 1
		print("[W9R2G] FAIL ", msg)


func _init() -> void:
	_run.call_deferred()


## メッシュの形状検査（ローカル座標）。戻り値：tri、aabb、帯違反数、戸口違反数、最悪の位置（診断用）
static func analyze(mesh: Mesh, w: float, d: float, door_cx: float, door_w: float, posts: Array = []) -> Dictionary:
	var zf := d / 2.0
	var tri := 0
	var head := 0
	var door := 0
	var worst: PackedStringArray = []
	var ab := AABB()
	var first := true
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for p in v:
			if first:
				ab = AABB(p, Vector3.ZERO)
				first = false
			else:
				ab = ab.expand(p)
		for t in idx.size() / 3:
			var a := v[idx[t * 3]]
			var b := v[idx[t * 3 + 1]]
			var c := v[idx[t * 3 + 2]]
			tri += 1
			var h_hit := false
			var d_hit := false
			var in_door := false
			var ymin := minf(a.y, minf(b.y, c.y))
			for q: Vector3 in [a, b, c, (a + b + c) / 3.0]:
				if q.z > zf + HUG and q.y > HEAD_LO and q.y < HEAD_HI:
					h_hit = true
				if q.z > zf + 0.25 and q.z < zf + 1.6 and q.x > door_cx - door_w / 2.0 - DOOR_PAD and q.x < door_cx + door_w / 2.0 + DOOR_PAD \
						and q.y > 0.35 and q.y < HEAD_HI:
					in_door = true
			# 戸口の前：領域内にあり、足元〜胴（最低点が 1.45 m 未満）に達する三角形。頭上へ斜めに伸びる棒（開け戸の突っ支い）は障害物でない
			d_hit = in_door and ymin < DOOR_BODY
			# 庇柱（meta の x・先端の z）は構造材なので頭上帯の対象から外す
			if h_hit:
				for pp in posts:
					if absf(a.x - float(pp[0])) < 0.2 and absf(a.z - float(pp[1])) < 0.2 and absf(c.x - float(pp[0])) < 0.2:
						h_hit = false
						break
			if h_hit:
				head += 1
				if worst.size() < 3:
					worst.append("head@(%.2f,%.2f,%.2f)" % [a.x, a.y, a.z])
			if d_hit:
				door += 1
				if worst.size() < 6:
					worst.append("door@(%.2f,%.2f,%.2f)" % [a.x, a.y, a.z])
	return {"tri": tri, "aabb": ab, "head": head, "door": door, "worst": ", ".join(worst)}


static func over_ok(ab: AABB, w: float, d: float) -> bool:
	var zf := d / 2.0
	return ab.position.x >= -w / 2.0 - SIDE_OVER and ab.end.x <= w / 2.0 + SIDE_OVER \
		and ab.position.z >= -zf - BACK_OVER and ab.end.z <= zf + FRONT_OVER


## 庇柱・玄関柱の碰撞（Posts）を meta の posts と突き合わせる。違反の理由を返す（空＝適合）。
## exp＝meta の posts（{x,z,top,w}）／got＝[[局部位置, BoxShape3D.size, layer, mask], …]／body_layer・body_mask＝建物 body の値。
static func post_issues(exp: Array, got: Array, body_layer: int, body_mask: int) -> PackedStringArray:
	var out: PackedStringArray = []
	if exp.size() != got.size():
		out.append("柱 %d 本に対し碰撞 %d 個" % [exp.size(), got.size()])
		return out
	for i in exp.size():
		var e: Dictionary = exp[i]
		var g: Array = got[i]
		var pos: Vector3 = g[0]
		var sz: Vector3 = g[1]
		if Vector2(pos.x - float(e["x"]), pos.z - float(e["z"])).length() > 0.005:
			out.append("柱 %d の碰撞位置が柱とずれる" % i)
		if sz.x < float(e["w"]) + 0.02 or sz.z < float(e["w"]) + 0.02:
			out.append("柱 %d の碰撞が柱より細い（%.2f）" % [i, sz.x])
		if sz.y < float(e["top"]) - 0.05:
			out.append("柱 %d の碰撞が柱の高さに届かない（%.2f < %.2f）" % [i, sz.y, float(e["top"])])
		if int(g[2]) != body_layer or int(g[3]) != body_mask:
			out.append("柱 %d の layer／mask が body と違う" % i)
	return out


## 外形碰撞箱（<建築>/Shell）1 棟分の照合。exp＝collision_fit.json の boxes（建物局部・x0..x1 など）、
## got＝[[position, size, 回転が単位, layer, mask, BoxShape3D か], ...]（Shell の CollisionShape3D ごと）。違反の理由を返す（空＝適合）。
## 拒否：Shell が無い（json に登録あり）／未登録の Shell（json に無い）／箱の数の違い／位置・寸法・回転の違い（±0.005 m）／重複（同じ箱に 2 つ）／
##       json に無い箱／layer・mask が body と違う／BoxShape3D 以外。
static func shell_issues(exp: Array, got: Array, body_layer: int, body_mask: int) -> PackedStringArray:
	var out: PackedStringArray = []
	if exp.size() > 0 and got.is_empty():
		out.append("Shell が無い（collision_fit.json に %d 箱が登録）" % exp.size())
		return out
	if exp.is_empty() and got.size() > 0:
		out.append("未登録の Shell（collision_fit.json に無い・%d 箱）" % got.size())
		return out
	if exp.size() != got.size():
		out.append("箱の数 %d（json %d）" % [got.size(), exp.size()])
	var used: Array = []
	used.resize(got.size())
	used.fill(0)
	for i in exp.size():
		var e: Dictionary = exp[i]
		var c := Vector3((float(e["x0"]) + float(e["x1"])) / 2.0, (float(e["y0"]) + float(e["y1"])) / 2.0, (float(e["z0"]) + float(e["z1"])) / 2.0)
		var s := Vector3(float(e["x1"]) - float(e["x0"]), float(e["y1"]) - float(e["y0"]), float(e["z1"]) - float(e["z0"]))
		var m := 0
		for j in got.size():
			var g: Array = got[j]
			if (g[0] as Vector3).distance_to(c) <= 0.005 and (g[1] as Vector3).distance_to(s) <= 0.005 and bool(g[2]):
				m += 1
				used[j] = int(used[j]) + 1
		if m == 0:
			out.append("箱 %d：位置・寸法・回転が json と違う（中心 %s 寸法 %s）" % [i, c, s])
		elif m > 1:
			out.append("箱 %d：重複（同じ箱が %d 個）" % [i, m])
	for j in got.size():
		var g: Array = got[j]
		if int(used[j]) == 0:
			out.append("json に無い箱（中心 %s）" % (g[0] as Vector3))
		if not bool(g[5]):
			out.append("箱 %d が BoxShape3D でない" % j)
		if int(g[3]) != body_layer or int(g[4]) != body_mask:
			out.append("箱 %d の layer／mask（%d／%d）が body（%d／%d）と違う" % [j, int(g[3]), int(g[4]), body_layer, body_mask])
	return out


## 元の箱（body の CollisionShape3D）と Shell の有効状態。body_dis／shell_dis＝disabled の配列。expect：
##   "saved"＝保存された場景（腳本が走る前）／"off"＝overlay 無効：元の箱が有効・Shell は全て無効
##   "on"＝overlay 有効：元の箱が全て無効・Shell は全て有効
## どの状態でも『元の箱と Shell が同時に有効』は拒否。
static func activation_issues(body_dis: Array, shell_dis: Array, expect: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var body_on := body_dis.count(false)
	var shell_on := shell_dis.count(false)
	if body_on > 0 and shell_on > 0:
		out.append("元の箱 %d と Shell %d が同時に有効" % [body_on, shell_on])
	if expect == "on":
		if body_on > 0:
			out.append("overlay 有効なのに元の箱 %d が有効" % body_on)
		if shell_on != shell_dis.size():
			out.append("overlay 有効なのに Shell %d/%d だけ有効" % [shell_on, shell_dis.size()])
	else:
		if body_on != body_dis.size():
			out.append("%s なのに元の箱 %d/%d だけ有効" % [expect, body_on, body_dis.size()])
		if shell_on > 0:
			out.append("%s なのに Shell %d が有効" % [expect, shell_on])
	return out


## 庇 1 本の構造規則。違反の理由を返す（空＝適合）。e は generator の eaves メタ。
static func eave_issues(e: Dictionary, w: float, door_cx: float, door_w: float) -> PackedStringArray:
	var out: PackedStringArray = []
	var x0 := float(e["x0"])
	var x1 := float(e["x1"])
	var depth := float(e["depth"])
	var p := float(e["p"])
	var y := float(e["y"])
	if x0 < -w / 2.0 - 0.001 or x1 > w / 2.0 + 0.001:
		out.append("幅が建物をはみ出す（%.2f..%.2f／±%.2f）" % [x0, x1, w / 2.0])
	if p < EAVE_MIN_P:
		out.append("勾配 %.2f が緩すぎる（排水）" % p)
	var posts: Array = e.get("posts", [])
	if depth > EAVE_MAX_DEPTH and posts.size() < 2:
		out.append("深さ %.2f の庇に庇柱が %d 本" % [depth, posts.size()])
	for xp in posts:
		if float(xp) < x0 or float(xp) > x1:
			out.append("庇柱 x=%.2f が庇の外" % float(xp))
		if absf(float(xp) - door_cx) < door_w / 2.0 + 0.15:
			out.append("庇柱 x=%.2f が戸口の前" % float(xp))
	if e.get("bracket_gap") != null and float(e["bracket_gap"]) > EAVE_MAX_GAP:
		out.append("腕木の間隔 %.2f が広すぎる" % float(e["bracket_gap"]))
	var s := depth - 0.04
	var front := y - s * p - 0.30
	if front < EAVE_MIN_FRONT:
		out.append("前縁の下端 %.2f m が低い" % front)
	return out


## 屋根の収め：メタ（ridge_stack／oni／hip_caps／eave_tails／gegyo）の必要条件
static func roof_issues(r: Dictionary, tsuma: bool) -> PackedStringArray:
	var out: PackedStringArray = []
	if String(r.get("kind", "")) == "turret":
		return out
	if String(r.get("kind", "")) == "board":          # 板葺き（石置き）屋根：瓦屋根の規則（段積みの棟・鬼瓦）ではなく、押さえ竹・石・破風板（・切妻なら棟覆い）
		if int(r.get("battens", 0)) < 2:
			out.append("押さえ竹なし")
		if int(r.get("stones", 0)) < 4:
			out.append("石置きなし")
		if not bool(r.get("barge", false)):
			out.append("破風板なし")
		if bool(r.get("gable", false)) and not bool(r.get("ridge_cover", false)):
			out.append("棟覆いなし")
		return out
	if not bool(r.get("eave_tails", false)):
		out.append("軒先の垂木尻なし")
	if not bool(r.get("ridge_stack", false)):
		out.append("大棟の段積みなし")
	if not bool(r.get("oni", false)):
		out.append("棟端の鬼瓦なし")
	if String(r.get("kind", "")) == "hip" and int(r.get("hip_caps", 0)) < 4:
		out.append("隅棟の巴瓦が 4 未満")
	if tsuma and not bool(r.get("gegyo", false)):
		out.append("妻入に懸魚なし")
	return out


## 他 overlay の実体（コンパクトな物のみ）を 1 度だけ集める：[path, global_transform, local_aabb]。
## 対象外：Terrain・Districts（Kit＝大きな斜面の AABB が偽陽性になる。隣家は Kit 側面の広がりで別に検査）・自 overlay・LOD1／2。
func _collect(v: Node3D) -> Array:
	var out: Array = []
	for n in v.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.is_visible_in_tree():
			continue
		var pth := String(v.get_path_to(mi))
		var top := pth.get_slice("/", 0)
		if top == "Terrain" or top == "Districts" or top == L.NODE_NAME:
			continue
		if pth.contains("/LOD1") or pth.contains("/LOD2"):
			continue
		var g := mi.get_aabb()
		if g.size == Vector3.ZERO or g.size.length() > 12.0:
			continue
		out.append([pth, mi.global_transform, g])
	return out


## body 局部に直した、建物の前の領域にある他 overlay の AABB（接触は許し貫入を拾うため少し縮める）
static func others_for(all: Array, body: Node3D, w: float, d: float) -> Array:
	var zf := d / 2.0
	var inv := body.global_transform.affine_inverse()
	var zone := AABB(Vector3(-w / 2.0 - 1.2, -0.5, zf - 0.6), Vector3(w + 2.4, 6.0, 4.6))
	var out: Array = []
	for e: Array in all:
		var lb: AABB = inv * ((e[1] as Transform3D) * (e[2] as AABB))
		if zone.intersects(lb):
			out.append([e[0], lb.grow(-OCC_SHRINK)])
	return out


## 三角形（頂点・重心）が AABB の中にある数を数える（貫入）
static func penetrations(mesh: Mesh, boxes: Array, z_min: float = -1.0e9) -> Array:
	var hits := 0
	var who := {}
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in idx.size() / 3:
			var a := v[idx[t * 3]]
			var b := v[idx[t * 3 + 1]]
			var c := v[idx[t * 3 + 2]]
			if a.z < z_min and b.z < z_min and c.z < z_min:
				continue
			var cen := (a + b + c) / 3.0
			for bx: Array in boxes:
				var bb: AABB = bx[1]
				if (a.z > z_min and bb.has_point(a)) or (b.z > z_min and bb.has_point(b)) or (c.z > z_min and bb.has_point(c)) or (cen.z > z_min and bb.has_point(cen)):
					hits += 1
					who[String(bx[0]).substr(0, 70)] = true
					break
	return [hits, who.keys()]


## 近隣の建物（Districts 下の body）の massing 箱：[id, Transform3D（箱の global）, half_extents]
static func neighbors_of(v: Node3D, body: Node3D) -> Array:
	var out: Array = []
	for b in v.get_node("Districts").find_children("B_P_*", "Node3D", true, false):
		if b == body:
			continue
		var sh := (b as Node3D).get_node_or_null("Shape") as CollisionShape3D
		if sh == null or not (sh.shape is BoxShape3D):
			continue
		if (b as Node3D).global_position.distance_to(body.global_position) > 22.0:
			continue
		out.append([String(b.name), sh.global_transform, (sh.shape as BoxShape3D).size / 2.0 - Vector3.ONE * NEIGHBOR_SHRINK])
	return out


## 自分のメッシュ（局部）が隣棟の massing 箱（OBB）に入っている三角形の数（局部 y > y_min の屋根・庇のみ）
static func penetrations_obb(mesh: Mesh, my_xf: Transform3D, nbs: Array, y_min: float) -> Array:
	var hits := 0
	var who := {}
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in idx.size() / 3:
			var a := v[idx[t * 3]]
			var b := v[idx[t * 3 + 1]]
			var c := v[idx[t * 3 + 2]]
			if a.y < y_min and b.y < y_min and c.y < y_min:
				continue
			var pts := [a, b, c, (a + b + c) / 3.0]
			var hit := false
			for nb: Array in nbs:
				var inv: Transform3D = (nb[1] as Transform3D).affine_inverse()
				var he: Vector3 = nb[2]
				for p: Vector3 in pts:
					if p.y < y_min:
						continue
					var q := inv * (my_xf * p)
					if absf(q.x) < he.x and absf(q.y) < he.y and absf(q.z) < he.z:
						hit = true
						who[nb[0]] = true
						break
				if hit:
					break
			if hit:
				hits += 1
	return [hits, who.keys()]


func _run() -> void:
	# ---------- 反向案例（検査関数が本当に違反を拾う）----------
	var neg := _negatives()
	# ---------- 本番 ----------
	var txt := FileAccess.get_file_as_string(L.SCENE)
	var line := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"p13w9r2_arch\")]" % L.NODE_NAME
	_ok(txt.count(line) == 1, "root 直下に %s が 1 回だけ掛載（保存された village_v2.tscn）" % L.NODE_NAME)
	var order: PackedStringArray = []
	for l: String in txt.split("\n"):
		if l.begins_with("[node name=\"") and l.contains("parent=\".\""):
			order.append(l.split("\"")[1])
	_ok(order.find(L.NODE_NAME) == order.find(L.AFTER) + 1, "%s は %s の直後（順序）" % [L.NODE_NAME, L.AFTER])
	var meta := JSON.parse_string(FileAccess.get_file_as_string("res://assets/village_v2/w9r2_arch/src/modules_blender.json")) as Dictionary
	var v := (load(L.SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(v)
	for i in 4:
		await process_frame
	var ov := v.get_node_or_null(L.NODE_NAME)
	_ok(ov != null, "実行時に root/%s がある" % L.NODE_NAME)
	if ov == null:
		print("[W9R2G] 結果：%d 通過・%d 失敗（反向案例 %d/%d）" % [passed, failed, neg[0], neg[1]])
		quit(1)
		return
	_ok(ov.get_child_count() == L.SPECS.size(), "建築 %d 棟（SPECS と一致）" % L.SPECS.size())
	var tri_all := 0
	# 碰撞体は庇柱・玄関柱（<建築>/Posts）＋ 外形碰撞箱（<建築>/Shell・collision_fit.json に登録済みのものだけ）。それ以外は 0。
	# ── 規則の変更（2026-10-17 W9 FIX・使用者裁定 Decision 1）：以前は『Posts だけ』。W9R2 は正面・屋根の見た目を作り直したが
	#    body の碰撞箱（Kit の外形に合わせた 1 Shape）は据え置いた。そのため 22 棟で、新しい低い屋根の上 1.0–3.6 m に箱が出る（見えない天井）、
	#    開いた見世・前庭・庭を箱が塞ぐ（見えない壁 3.1–3.6 m）、新しい二階の壁に碰撞が無い（0.6–3.0 m）不一致が出た
	#    （work/w9_collision_fix の diag_runtime_before／probe）。body の箱は共有場景 village_v2.tscn の物なので触らず、
	#    overlay 側に見た目から導いた箱（Shell）を置き、overlay 有効の間だけ body の箱と入れ替える。よって Shell を許すが、
	#    collision_fit.json と箱ごとに完全一致すること・元の箱と同時に有効にならないことを条件にする（下の shell_issues／activation_issues）。
	var posts_meta: Dictionary = meta.get("posts", {})
	var colfit: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(L.COLFIT)) as Dictionary).get("buildings", {})
	var coll_other := 0
	var post_bodies := 0
	var shell_bodies := 0
	for cb in ov.find_children("*", "CollisionObject3D", true, false):
		var pid := String(cb.get_parent().name)
		if String(cb.name) == "Posts" and posts_meta.has(pid) and cb.get_parent().get_parent() == ov:
			post_bodies += 1
		elif String(cb.name) == "Shell" and colfit.has(pid) and cb.get_parent().get_parent() == ov and cb is StaticBody3D:
			shell_bodies += 1
		else:
			coll_other += 1
	_ok(coll_other == 0, "overlay の碰撞体は庇柱・玄関柱（Posts）と登録済みの外形碰撞箱（Shell）だけ（それ以外・未登録 %d）" % coll_other)
	_ok(post_bodies == posts_meta.size() and posts_meta.size() > 0, "柱のある %d 棟すべてに Posts 碰撞がある（実際 %d）" % [posts_meta.size(), post_bodies])
	var n_json_boxes := 0
	var ids_ok := true
	for k in colfit:
		n_json_boxes += ((colfit[k] as Dictionary)["boxes"] as Array).size()
		ids_ok = ids_ok and L.SPECS.has(k)
	_ok(shell_bodies == colfit.size() and colfit.size() > 0 and ids_ok, "collision_fit.json の %d 棟（%d 箱・全て SPECS の建物 id）すべてに Shell がある（実際 %d）" % [colfit.size(), n_json_boxes, shell_bodies])
	# 保存された状態（腳本が走る前）：元の箱が有効・Shell は全て無効（＝腳本が無くても二重にならない）
	var vs := (load(L.SCENE) as PackedScene).instantiate()
	var saved_iss: PackedStringArray = []
	for k in colfit:
		saved_iss.append_array(_act_issues_of(vs, vs.get_node(L.NODE_NAME), String(k), "saved"))
	vs.free()
	_ok(saved_iss.is_empty(), "保存された場景：%d 棟で元の箱が有効・Shell は全て無効（同時有効なし）%s" % [colfit.size(), "" if saved_iss.is_empty() else str(saved_iss.slice(0, 5))])
	# 実行時（overlay 有効）：元の箱が全て無効・Shell が全て有効
	var on_iss: PackedStringArray = []
	for k in colfit:
		on_iss.append_array(_act_issues_of(v, ov, String(k), "on"))
	_ok(on_iss.is_empty(), "実行時 enabled=true：%d 棟で元の箱が無効・Shell %d 箱が有効（同時有効なし）%s" % [colfit.size(), n_json_boxes, "" if on_iss.is_empty() else str(on_iss.slice(0, 5))])
	var before: Dictionary = {}
	var dims: Dictionary = {}
	for id: String in L.SPECS:
		var sp: Dictionary = L.SPECS[id]
		var n := ov.get_node_or_null(id) as Node3D
		_ok(n != null, "%s：overlay 子がある" % id)
		if n == null:
			continue
		var body := v.get_node_or_null(NodePath(sp["path"])) as Node3D
		_ok(body != null, "%s：body が実在（%s）" % [id, sp["path"]])
		if body == null:
			continue
		var same := n.global_transform.origin.distance_to(body.global_transform.origin) < 0.002 \
			and (n.global_transform.basis.get_euler() - body.global_transform.basis.get_euler()).length() < 0.001
		_ok(same, "%s：overlay の transform が body と同じ" % id)
		var kit := body.get_node("Kit")
		var dcx := float(kit.get_meta("door_cx", 0.0))
		var dw := float(kit.get_meta("door_w", 1.7))
		var shp := body.get_node_or_null("Shape") as CollisionShape3D
		var box := shp.shape as BoxShape3D if shp else null
		var w := box.size.x if box else 5.0
		var d := box.size.z if box else 10.0
		dims[id] = [w, d, dcx, dw]
		var pm: Array = posts_meta.get(id, [])
		var sbn := n.get_node_or_null("Posts") as StaticBody3D
		var got: Array = []
		if sbn != null:
			for cs in sbn.get_children():
				if cs is CollisionShape3D and (cs as CollisionShape3D).shape is BoxShape3D:
					got.append([(cs as CollisionShape3D).position, ((cs as CollisionShape3D).shape as BoxShape3D).size, sbn.collision_layer, sbn.collision_mask])
		if pm.size() > 0 or sbn != null:
			var piss := post_issues(pm, got, int((body as CollisionObject3D).collision_layer), int((body as CollisionObject3D).collision_mask))
			_ok(piss.is_empty(), "%s：庇柱・玄関柱 %d 本の碰撞（位置・太さ・高さ・layer／mask）%s" % [id, pm.size(), "" if piss.is_empty() else str(piss)])
		var shn := n.get_node_or_null("Shell") as CollisionObject3D
		var sexp: Array = (colfit.get(id, {}) as Dictionary).get("boxes", [])
		if shn != null or sexp.size() > 0:
			var sgot: Array = []
			if shn != null:
				for cs in shn.get_children():
					if cs is CollisionShape3D:
						var csn := cs as CollisionShape3D
						sgot.append([csn.position, (csn.shape as BoxShape3D).size if csn.shape is BoxShape3D else Vector3.ZERO, csn.basis.is_equal_approx(Basis.IDENTITY),
							shn.collision_layer, shn.collision_mask, csn.shape is BoxShape3D])
			var siss := shell_issues(sexp, sgot, int((body as CollisionObject3D).collision_layer), int((body as CollisionObject3D).collision_mask))
			_ok(siss.is_empty(), "%s：外形碰撞箱 Shell %d 箱（位置・寸法・回転・layer／mask・重複なし＝collision_fit.json）%s" % [id, sexp.size(), "" if siss.is_empty() else str(siss.slice(0, 4))])
		var l0 := n.get_node_or_null("L0") as MeshInstance3D
		var l1 := n.get_node_or_null("L1") as MeshInstance3D
		_ok(l0 != null and l1 != null, "%s：L0／L1 あり" % id)
		if l0 == null or l1 == null:
			continue
		_ok(l0.visibility_range_begin == 0.0 and l0.visibility_range_end == l1.visibility_range_begin \
			and l1.visibility_range_end >= 400.0, "%s：LOD 範囲が連続（L0→L1・遠距離まで）" % id)
		var plist: Array = []      # 柱（庇柱・玄関柱）は構造材 → 頭上帯の対象から外す（碰撞は上の Posts で検査）
		for pd: Dictionary in pm:
			plist.append([float(pd["x"]), float(pd["z"])])
		var a0 := analyze(l0.mesh, w, d, dcx, dw, plist)
		var a1 := analyze(l1.mesh, w, d, dcx, dw)
		tri_all += int(a0["tri"])
		_ok(int(a0["tri"]) <= MAX_TRI0 and int(a1["tri"]) <= MAX_TRI1, "%s：三角面 L0 %d／L1 %d（上限 %d／%d）" % [id, a0["tri"], a1["tri"], MAX_TRI0, MAX_TRI1])
		_ok(over_ok(a0["aabb"], w, d), "%s：張り出しが上限内（%s）" % [id, a0["aabb"]])
		_ok(int(a0["door"]) == 0, "%s：戸口の前（幅＋余白・壁から 1.6 m）に y 0.35–1.8 の三角形 0（%d）%s" % [id, a0["door"], a0["worst"]])
		_ok(int(a0["head"]) == 0, "%s：壁の外の頭の高さ帯（y %.1f–%.1f）に三角形 0（%d）%s" % [id, HEAD_LO, HEAD_HI, a0["head"], a0["worst"]])
		# [2.1] 庇の構造規則・屋根の収め
		var es: Array = (meta.get("eaves", {}) as Dictionary).get(id, [])
		var eiss: PackedStringArray = []
		for e: Dictionary in es:
			eiss.append_array(eave_issues(e, w, dcx, dw))
		_ok(eiss.is_empty(), "%s：庇 %d 本の構造規則（幅・勾配・腕木間隔・深い庇の庇柱・前縁高）%s" % [id, es.size(), "" if eiss.is_empty() else str(eiss)])
		var rs: Array = (meta.get("roofs", {}) as Dictionary).get(id, [])
		var riss: PackedStringArray = []
		var has_roof := false
		for r: Dictionary in rs:
			if String(r.get("kind", "")) != "turret":
				has_roof = true
			riss.append_array(roof_issues(r, TSUMA.has(id)))
		var rebuilt: bool = (sp["hide"] as Array).has("roof") or (sp["hide"] as Array).has("all")     # 屋根を作り直さない棟は収めの検査を免除
		_ok(not rebuilt or (has_roof and riss.is_empty()), "%s：屋根の収め（大棟の段積み・鬼瓦・垂木尻%s）%s" % [id, "・懸魚" if TSUMA.has(id) else "", "" if riss.is_empty() else str(riss)])
		var states: Array = []
		for lod in 3:
			var g := kit.get_node_or_null("LOD%d" % lod)
			if g:
				for mi in g.get_children():
					if mi is MeshInstance3D:
						states.append([mi, (mi as MeshInstance3D).visible])
		before[id] = states
	var max_all: int = MAX_TRI0_AVG * L.SPECS.size()
	_ok(tri_all <= max_all, "%d 棟 LOD0 合計 %d tri（上限 %d＝平均 %d × 棟数）" % [L.SPECS.size(), tri_all, max_all, MAX_TRI0_AVG])
	# [2.1] 他 overlay（P10・R1・Population など）の実体への貫入 0、隣の建物との間隔（Kit 側面の広がり＋0.25 m 以内）
	var all_others := _collect(v)
	for id: String in L.SPECS:
		if not dims.has(id):
			continue
		var body2 := v.get_node(NodePath(L.SPECS[id]["path"])) as Node3D
		var dd: Array = dims[id]
		var boxes := others_for(all_others, body2, dd[0], dd[1])
		var l0m := (ov.get_node(id).get_node("L0") as MeshInstance3D).mesh
		var pr := penetrations(l0m, boxes, dd[1] / 2.0 + WALL_FLUSH)
		_ok(int(pr[0]) == 0, "%s：他 overlay の実体（%d 件）への貫入 0（壁から 0.2 m より外・実際 %d）%s" % [id, boxes.size(), pr[0], "" if int(pr[0]) == 0 else str(pr[1])])
		var nb := neighbors_of(v, body2)
		var inv_n := penetrations_obb(l0m, body2.global_transform, nb, NEIGHBOR_Y)
		_ok(int(inv_n[0]) == 0, "%s：隣棟（%d 棟）の massing 箱への屋根・庇の貫入 0（実際 %d）%s" % [id, nb.size(), inv_n[0], "" if int(inv_n[0]) == 0 else str(inv_n[1])])
	# R1 の吊り物：この棟群に属し R1_HANG の種類のものだけが隠れる
	var expect := 0
	var r1n := v.get_node("EnrichW9P13")
	for z in r1n.get_children():
		for cl in z.get_children():
			for it in cl.get_children():
				if it is Node3D and L.SPECS.has(String(it.get_meta("w9_b", ""))) and R1_HANG.has(String(it.get_meta("w9_feature", ""))) \
						and not L.keep_r1(String(it.get_meta("w9_b", ""))).has(String(it.get_meta("w9_feature", ""))):
					expect += 1
	_ok(int(ov.get("r1_hidden")) == expect and expect > 0, "enabled=true：R1 の吊り物（%s）%d 件がこの %d 棟でだけ隠れる（実際 %d）" % ["・".join(R1_HANG), expect, L.SPECS.size(), int(ov.get("r1_hidden"))])
	var r1_off := 0
	var r1_all := 0
	for z in r1n.get_children():
		for cl in z.get_children():
			for it in cl.get_children():
				if it is Node3D:
					r1_all += 1
					if not (it as Node3D).visible:
						r1_off += 1
	_ok(r1_off == expect, "EnrichW9P13 全 %d 件のうち非表示は %d 件だけ（他の R1 内容は触れていない・実際 %d）" % [r1_all, expect, r1_off])
	var hidden_on := 0
	for id: String in before:
		for s: Array in before[id]:
			if not bool(s[1]):
				hidden_on += 1
	ov.set("enabled", false)
	await process_frame
	r1_off = 0
	for z in r1n.get_children():
		for cl in z.get_children():
			for it in cl.get_children():
				if it is Node3D and not (it as Node3D).visible:
					r1_off += 1
	_ok(r1_off == 0 and int(ov.get("r1_hidden")) == 0, "enabled=false で R1 の物は全て元の表示（非表示 %d）" % r1_off)
	var still_hidden := 0
	for id: String in before:
		for s: Array in before[id]:
			if is_instance_valid(s[0]) and not (s[0] as MeshInstance3D).visible:
				still_hidden += 1
	_ok(still_hidden == 0, "enabled=false で Kit は全て元の表示へ（非表示だったもの %d → 残り %d）" % [hidden_on, still_hidden])
	_ok(not (ov as Node3D).visible, "enabled=false で overlay は非表示")
	var off_iss: PackedStringArray = []
	for k in colfit:
		off_iss.append_array(_act_issues_of(v, ov, String(k), "off"))
	_ok(off_iss.is_empty(), "enabled=false：%d 棟で元の箱が有効に戻り Shell は全て無効（同時有効なし）%s" % [colfit.size(), "" if off_iss.is_empty() else str(off_iss.slice(0, 5))])
	ov.set("enabled", true)
	await process_frame
	var hidden_again := 0
	for id: String in before:
		for s: Array in before[id]:
			if is_instance_valid(s[0]) and not (s[0] as MeshInstance3D).visible:
				hidden_again += 1
	_ok(hidden_again == hidden_on and hidden_on > 0, "enabled=true で同じ Kit 構件が再び隠れる（%d → %d）" % [hidden_on, hidden_again])
	# 繰り返しの有効化（false→true をもう 2 回）：毎回同じ状態に戻る
	var rep_iss: PackedStringArray = []
	for r in 2:
		ov.set("enabled", false)
		await process_frame
		for k in colfit:
			rep_iss.append_array(_act_issues_of(v, ov, String(k), "off"))
		ov.set("enabled", true)
		await process_frame
		for k in colfit:
			rep_iss.append_array(_act_issues_of(v, ov, String(k), "on"))
	_ok(rep_iss.is_empty(), "enabled の繰り返し（false→true × 2 回）：毎回 off／on の状態が正しい%s" % ("" if rep_iss.is_empty() else str(rep_iss.slice(0, 5))))
	var gout := []
	OS.execute("git", ["diff", "--numstat", R2_BASE, "--", ProjectSettings.globalize_path(L.SCENE)], gout)
	var ns: PackedStringArray = String(gout[0]).strip_edges().split("\t") if gout.size() > 0 else PackedStringArray()
	# R2 の 3 行（ext_resource＋node＋空行）。Phase 3（EnrichW9P3）が掛かっていればその 3 行だけ上乗せして許す（余計な行は許さない）
	var scene_txt := FileAccess.get_file_as_string(L.SCENE)
	var p3_lines := 3 if scene_txt.contains("p13w9p3_enrich") else 0
	var p4_lines := 3 if scene_txt.contains("p13w9p4_enrich") else 0     # Phase 4（EnrichW9P4）が掛かっていればその 3 行だけ上乗せ（余計な行は許さない）
	_ok(ns.size() >= 2 and int(ns[1]) == 0 and int(ns[0]) <= 3 + p3_lines + p4_lines, "village_v2.tscn は %s から『追加のみ・≤%d 行（R2 3＋Phase 3 の EnrichW9P3 %d＋Phase 4 の EnrichW9P4 %d）』（実際 +%s −%s）" % [R2_BASE, 3 + p3_lines + p4_lines, p3_lines, p4_lines, ns[0] if ns.size() > 0 else "?", ns[1] if ns.size() > 1 else "?"])
	var shape_ok := true
	for id: String in L.SPECS:
		var body3 := v.get_node_or_null(NodePath(L.SPECS[id]["path"])) as Node3D
		if body3:
			var k := 0
			for c in body3.get_children():
				if c is CollisionShape3D:
					k += 1
			if k != 1:
				shape_ok = false
	_ok(shape_ok, "全棟とも body の碰撞は Kit 由来の 1 Shape のまま（増減なし）")
	print("[W9R2G] 結果：%d 通過・%d 失敗（反向案例 %d/%d）" % [passed, failed, neg[0], neg[1]])
	quit(0 if failed == 0 and int(neg[0]) == int(neg[1]) else 1)


## 1 棟分の元の箱と Shell の disabled を集めて activation_issues に渡す（理由に建物 id を付ける）
func _act_issues_of(vroot: Node, ovn: Node, id: String, expect: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var body := vroot.get_node_or_null(NodePath(String(L.SPECS[id]["path"])))
	var sh := ovn.get_node_or_null(id + "/Shell")
	if body == null or sh == null:
		out.append("%s：body または Shell が無い" % id)
		return out
	var bd: Array = []
	for c in body.get_children():
		if c is CollisionShape3D:
			bd.append((c as CollisionShape3D).disabled)
	var sd: Array = []
	for c in sh.get_children():
		if c is CollisionShape3D:
			sd.append((c as CollisionShape3D).disabled)
	for s in activation_issues(bd, sd, expect):
		out.append("%s：%s" % [id, s])
	return out


## 反向案例：検査関数に『違反するメッシュ・メタ』を与えて、確かに拾うこと
func _negatives() -> Array:
	var okc := 0
	var tot := 0
	var m1 := _tri_mesh(Vector3(-0.2, 0.0, 6.0), Vector3(0.2, 0.0, 6.0), Vector3(0.0, 2.0, 6.1))
	tot += 1
	okc += 1 if int(analyze(m1, 5.0, 10.0, 0.0, 1.7)["door"]) > 0 else 0
	var m2 := _tri_mesh(Vector3(2.0, 1.3, 6.4), Vector3(3.0, 1.3, 6.4), Vector3(2.5, 1.6, 6.4))
	tot += 1
	okc += 1 if int(analyze(m2, 5.0, 10.0, 0.0, 1.7)["head"]) > 0 else 0
	var m3 := _tri_mesh(Vector3(0, 3, 5), Vector3(1, 3, 9.2), Vector3(-1, 3, 9.2))
	tot += 1
	okc += 1 if not over_ok(analyze(m3, 5.0, 10.0, 0.0, 1.7)["aabb"], 5.0, 10.0) else 0
	var m4 := _tri_mesh(Vector3(-4.5, 3, 0), Vector3(0, 3, 0), Vector3(0, 3.5, 0))
	tot += 1
	okc += 1 if not over_ok(analyze(m4, 5.0, 10.0, 0.0, 1.7)["aabb"], 5.0, 10.0) else 0
	var m5 := _tri_mesh(Vector3(-2, 2.8, 5.0), Vector3(2, 2.8, 5.0), Vector3(0, 2.5, 6.5))
	var r5 := analyze(m5, 5.0, 10.0, 0.0, 1.7)
	tot += 1
	okc += 1 if int(r5["head"]) == 0 and int(r5["door"]) == 0 and over_ok(r5["aabb"], 5.0, 10.0) else 0
	var m6 := _tri_mesh(Vector3(0, 1.2, 4.0), Vector3(1, 1.2, 4.0), Vector3(0.5, 1.5, 4.0))
	var r6 := analyze(m6, 5.0, 10.0, 0.0, 1.7)
	tot += 1
	okc += 1 if int(r6["head"]) == 0 and int(r6["door"]) == 0 else 0
	# --- 庇の構造規則（2.1）---
	var good := {"x0": -2.5, "x1": 2.5, "depth": 1.4, "p": 0.28, "y": 2.95, "bracket_gap": 1.0, "posts": []}
	tot += 1
	okc += 1 if eave_issues(good, 5.2, 0.0, 1.7).is_empty() else 0
	for bad in [
			{"x0": -3.4, "x1": 2.5},                    # 建物の幅をはみ出す
			{"depth": 2.0},                             # 深いのに庇柱なし
			{"depth": 2.0, "posts": [-0.3, 2.4]},       # 庇柱が戸口の前
			{"p": 0.05},                                # 勾配が緩い（排水しない）
			{"bracket_gap": 2.1},                       # 腕木の間隔が広い
			{"y": 2.4, "depth": 1.5},                   # 前縁が低い
			{"depth": 2.0, "posts": [-2.4, 2.9]}]:      # 庇柱が庇の外
		var e: Dictionary = good.duplicate()
		e.merge(bad, true)
		tot += 1
		okc += 0 if eave_issues(e, 5.2, 0.0, 1.7).is_empty() else 1
	var deep := good.duplicate()
	deep.merge({"depth": 1.8, "posts": [-2.4, 2.4]}, true)
	tot += 1
	okc += 1 if eave_issues(deep, 5.2, 0.0, 1.7).is_empty() else 0       # 庇柱 2 本が戸口の外にあれば深い庇も適合
	# --- 屋根の収め（2.1）---
	var rgood := {"kind": "hip", "ridge_stack": true, "oni": true, "hip_caps": 4, "eave_tails": true, "gegyo": false}
	tot += 1
	okc += 1 if roof_issues(rgood, false).is_empty() else 0
	for bad2 in [{"eave_tails": false}, {"ridge_stack": false}, {"oni": false}, {"hip_caps": 2}]:
		var r: Dictionary = rgood.duplicate()
		r.merge(bad2, true)
		tot += 1
		okc += 0 if roof_issues(r, false).is_empty() else 1
	tot += 1
	okc += 0 if roof_issues(rgood, true).is_empty() else 1          # 妻入なのに懸魚なし
	# --- 板葺き屋根（Phase 2）---
	var bgood := {"kind": "board", "gable": true, "ridge_cover": true, "barge": true, "battens": 10, "stones": 40}
	tot += 1
	okc += 1 if roof_issues(bgood, false).is_empty() else 0
	for badb in [{"battens": 0}, {"stones": 0}, {"barge": false}, {"ridge_cover": false}]:
		var rb: Dictionary = bgood.duplicate()
		rb.merge(badb, true)
		tot += 1
		okc += 0 if roof_issues(rb, false).is_empty() else 1
	# --- 貫入（他 overlay の実体）---
	var pole := [["Props/StreetP10/Signs/065_st_nobori_sake/LOD0", AABB(Vector3(-2.4, -0.2, 5.9), Vector3(0.6, 4.0, 0.5))]]
	var slab := _tri_mesh(Vector3(-2.3, 2.7, 5.95), Vector3(-1.9, 2.7, 6.3), Vector3(-2.1, 2.5, 6.3))       # 幟の竿を貫く庇
	tot += 1
	okc += 1 if int(penetrations(slab, pole)[0]) > 0 else 0
	var clear := _tri_mesh(Vector3(-1.0, 2.7, 5.95), Vector3(-0.6, 2.7, 6.3), Vector3(-0.8, 2.5, 6.3))
	tot += 1
	okc += 1 if int(penetrations(clear, pole)[0]) == 0 else 0
	# --- 隣棟の massing への貫入（OBB）---
	var nbx := [["B_P_X", Transform3D(Basis.IDENTITY, Vector3(6.0, 2.0, 0.0)), Vector3(2.0, 2.0, 4.0)]]
	var over := _tri_mesh(Vector3(3.8, 3.0, 0.0), Vector3(4.2, 3.0, 0.5), Vector3(4.0, 2.8, 0.0))      # 隣の箱（x 4..8）へ庇が刺さる
	tot += 1
	okc += 1 if int(penetrations_obb(over, Transform3D.IDENTITY, nbx, 2.0)[0]) > 0 else 0
	var apart := _tri_mesh(Vector3(2.8, 3.0, 0.0), Vector3(3.2, 3.0, 0.5), Vector3(3.0, 2.8, 0.0))
	tot += 1
	okc += 1 if int(penetrations_obb(apart, Transform3D.IDENTITY, nbx, 2.0)[0]) == 0 else 0
	# --- 庇柱の碰撞（closeout）---
	var pe := [{"x": 1.0, "z": 6.0, "top": 2.3, "w": 0.14}]
	tot += 1
	okc += 1 if post_issues(pe, [[Vector3(1.0, 1.15, 6.0), Vector3(0.2, 2.3, 0.2), 1, 1]], 1, 1).is_empty() else 0
	for badp in [
			[],                                                                   # 柱があるのに碰撞なし
			[[Vector3(1.4, 1.15, 6.0), Vector3(0.2, 2.3, 0.2), 1, 1]],            # 位置がずれる
			[[Vector3(1.0, 1.15, 6.0), Vector3(0.1, 2.3, 0.1), 1, 1]],            # 柱より細い
			[[Vector3(1.0, 0.5, 6.0), Vector3(0.2, 1.0, 0.2), 1, 1]],             # 高さが届かない
			[[Vector3(1.0, 1.15, 6.0), Vector3(0.2, 2.3, 0.2), 2, 1]]]:           # layer が body と違う
		tot += 1
		okc += 0 if post_issues(pe, badp, 1, 1).is_empty() else 1
	# --- 外形碰撞箱 Shell（W9 FIX）---
	var se := [{"x0": -2.0, "x1": 2.0, "y0": -0.4, "y1": 3.0, "z0": -5.0, "z1": 1.0}, {"x0": -2.0, "x1": -1.5, "y0": -0.4, "y1": 2.6, "z0": 1.0, "z1": 5.0}]
	var sg := [[Vector3(0, 1.3, -2.0), Vector3(4, 3.4, 6), true, 1, 1, true], [Vector3(-1.75, 1.1, 3.0), Vector3(0.5, 3.0, 4.0), true, 1, 1, true]]
	tot += 1
	okc += 1 if shell_issues(se, sg, 1, 1).is_empty() else 0
	var sg_move: Array = sg.duplicate(true)
	sg_move[1][0] = Vector3(-1.45, 1.1, 3.0)
	var sg_rot: Array = sg.duplicate(true)
	sg_rot[0][2] = false
	var sg_layer: Array = sg.duplicate(true)
	sg_layer[0][3] = 2
	for bads in [
			[se, []],                                   # Shell が無い（json に登録あり）
			[se, sg_move],                              # 位置が違う
			[se, sg_rot],                               # 回転している
			[se, sg + [sg[0]]],                         # 重複（同じ箱が 2 つ）
			[se, sg + [[Vector3(5, 1, 5), Vector3(1, 1, 1), true, 1, 1, true]]],   # json に無い箱
			[[], sg],                                   # 未登録の Shell
			[se, sg_layer]]:                            # layer が body と違う
		tot += 1
		okc += 0 if shell_issues(bads[0], bads[1], 1, 1).is_empty() else 1
	# --- 元の箱と Shell の有効状態 ---
	tot += 1
	okc += 1 if activation_issues([true], [false, false], "on").is_empty() and activation_issues([false], [true, true], "saved").is_empty() else 0
	for bada in [
			[[false], [false, false], "on"],            # 同時に有効（衝突）
			[[false], [true, true], "on"],              # 有効なのに元の箱のまま
			[[true], [true, true], "on"],               # 有効なのにどちらも無効（碰撞が消える）
			[[false], [false, true], "saved"]]:         # 保存状態で Shell が有効
		tot += 1
		okc += 0 if activation_issues(bada[0], bada[1], bada[2]).is_empty() else 1
	print("[W9R2G] 反向案例 %d/%d（戸口・頭上・張り出し×2・正常軒・室内／庇構造 1+7+1／屋根の収め 1+4+1／貫入 2／隣棟 massing 2／庇柱の碰撞 1+5／板葺き屋根 1+4／外形碰撞箱 1+7／有効状態 1+4）" % [okc, tot])
	return [okc, tot]


static func _tri_mesh(a: Vector3, b: Vector3, c: Vector3) -> ArrayMesh:
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([a, b, c])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
