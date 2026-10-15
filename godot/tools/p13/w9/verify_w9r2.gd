extends SceneTree
## P13 W9 Round 2／2.1 gate：ArchW9R2P13（建築外形サンプル）を「保存された場景」から独立に検査する ＋ 反向案例。
##   godot --headless --path godot --script res://tools/p13/w9/verify_w9r2.gd
## 見るもの：掛載（1 回・順序）／各棟の id・body 追従／LOD 範囲・三角面予算／張り出し上限／戸口前の淨空／通行の頭上淨空／
##   enabled の往復（Kit の visible が完全に元へ戻る）／碰撞は庇柱・玄関柱（Posts）だけ（柱ごとに位置・太さ・高さ・layer／mask を meta と突き合わせ）／R1 の吊り物を隠す件数（R1 の中身は他に触れない）／
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
const TSUMA := ["B_P_MKT_009", "B_P_MKT_010", "B_P_RSW_062", "B_P_MKT_020", "B_P_RSW_014", "B_P_RSW_075"]   # 妻入（懸魚が要る）
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
	# 碰撞体は庇柱・玄関柱（<建築>/Posts）だけ。それ以外（壁・屋根・小物）の碰撞体は 0（footprint・入口・body の碰撞は Kit のまま）
	var posts_meta: Dictionary = meta.get("posts", {})
	var coll_other := 0
	var post_bodies := 0
	for cb in ov.find_children("*", "CollisionObject3D", true, false):
		if String(cb.name) == "Posts" and posts_meta.has(String(cb.get_parent().name)):
			post_bodies += 1
		else:
			coll_other += 1
	_ok(coll_other == 0, "overlay の碰撞体は庇柱・玄関柱（Posts）だけ（それ以外 %d）" % coll_other)
	_ok(post_bodies == posts_meta.size() and posts_meta.size() > 0, "柱のある %d 棟すべてに Posts 碰撞がある（実際 %d）" % [posts_meta.size(), post_bodies])
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
				if it is Node3D and L.SPECS.has(String(it.get_meta("w9_b", ""))) and R1_HANG.has(String(it.get_meta("w9_feature", ""))):
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
	ov.set("enabled", true)
	await process_frame
	var hidden_again := 0
	for id: String in before:
		for s: Array in before[id]:
			if is_instance_valid(s[0]) and not (s[0] as MeshInstance3D).visible:
				hidden_again += 1
	_ok(hidden_again == hidden_on and hidden_on > 0, "enabled=true で同じ Kit 構件が再び隠れる（%d → %d）" % [hidden_on, hidden_again])
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
	print("[W9R2G] 反向案例 %d/%d（戸口・頭上・張り出し×2・正常軒・室内／庇構造 1+7+1／屋根の収め 1+4+1／貫入 2／隣棟 massing 2／庇柱の碰撞 1+5／板葺き屋根 1+4）" % [okc, tot])
	return [okc, tot]


static func _tri_mesh(a: Vector3, b: Vector3, c: Vector3) -> ArrayMesh:
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([a, b, c])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
