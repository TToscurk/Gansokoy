extends SceneTree
## 街區管線 step 4b：overlay を記憶の中で village_v2 に掛けて自動検査（village_v2.tscn は書かない）。
##   godot --headless --path godot --script res://tools/district/district_verify.gd -- --district=B8 [--manifest=<path>] [--baseline=<old manifest>] [--no-arm] [--no-tri]
## 検査（--baseline 指定時、配置判定・三角形は added／changed の item だけ＝変えた所だけ検査）：
##   M1 schema（format・space・vid 一意・登録資産・yaw のみ）       M2 bake 済み overlay の sha と manifest の一致
##   M3 往復：vid ごとに 1 節点・x/z/yaw/scale が manifest と一致・y は接地値  M4 範囲（街區 rect の中）
##   M5 AABB：Blender の world AABB と Godot 再計算の差 ≤ 5 cm（軸・原点・scale 換算）
##   M6 配置：W9.why（道・建物・戸口・水・田・封存物・NPC・Hero…）＋接地（verify_w9p8 と同じ述語）
##   M7 重なり：footprint（初篩）→ 三角形の辺×面で実貫通を確認（AABB／footprint の重なりだけでは FAIL にしない）
##   M8 碰撞箱が戸口の空け帯・NPC 巡回路に触れない   M9 keep_clear   M10 SpringArm（自分の碰撞を除いた ray と比較）
##   M11 予算・MultiMesh なし
##   M5b Runtime World AABB：bake 済み節点の LOD0 頂点を global_transform で変換した AABB ↔ Blender の頂点 AABB（aabb_v）
##       min／max／寸法を 3 軸とも（y は build の接地し直し分だけずらして比較＝y を 1 回だけ適用したことの検査）
##   M12 地形接地：足元の多点で真下へ ray（Collision/TerrainCollision だけを地形と認める）→ 浮き（支持率）・埋まり（斜面）
##   NEG 記憶の中の反向：道路上へ移動／vid 重複／y +0.5 m／AABB を 0.3 m ずらす（軸換算の誤り）／runtime 節点を 0.3 m 動かす（M5b）／
##       0.3 m 持ち上げる（M12）→ それぞれ該当検査が FAIL すること
##   --calibrate：M5b を判定せず実測の最大差だけ出す（許容値を決める制御往復用）  --out=<json>：結果を JSON で書く
## 走らないもの：玩家の実走・NPC 実歩行・TPS 画面・効能（graphical／runtime で別に行う）。
const DL := preload("res://tools/district/district_lib.gd")
const W9 := preload("res://tools/p13/w9/w9_lib.gd")
const P3 := preload("res://tools/p13/w9/w9p3_lib.gd")
const SL := preload("res://tools/village_v2_street_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")

const MAX_TRI_LOD0 := 200000
const MAX_MESH := 600
const MAX_SHAPES := 120
const OVERLAP_AREA := 0.02
const ARM_UP := 1.70
const ARM_SIN := 0.179
const ARM_MAX := 7.5
const ARM_SEV_LOSS := 2.0
const ARM_SEV_LEN := 3.0

var passed := 0
var failed := 0
var neg_ok := 0
var neg_bad := 0
var results: Array = []
var stats := {}


func _ok(cond: bool, msg: String) -> void:
	results.append({"check": msg.split(" ")[0], "ok": cond, "msg": msg})
	if cond:
		passed += 1
		print("[DVER] PASS ", msg)
	else:
		failed += 1
		print("[DVER] FAIL ", msg)


func _neg(name: String, failed_as_expected: bool, detail: String) -> void:
	results.append({"check": "NEG", "ok": failed_as_expected, "msg": "%s：%s" % [name, detail]})
	if failed_as_expected:
		neg_ok += 1
		print("[DVER] NEG  OK   %s：期待どおり FAIL（%s）" % [name, detail])
	else:
		neg_bad += 1
		print("[DVER] NEG  BAD  %s：FAIL するはずが通った（%s）" % [name, detail])


## M5b：runtime 頂点 AABB と manifest の aabb_v の差（min・max・寸法の最大成分）。dy＝build で接地し直した分
func _rt_delta(a: AABB, m: Array, dy: float) -> Dictionary:
	var emn := Vector3(float(m[0]), float(m[1]) + dy, float(m[2]))
	var emx := Vector3(float(m[3]), float(m[4]) + dy, float(m[5]))
	var dmn := (a.position - emn).abs()
	var dmx := (a.end - emx).abs()
	var dd := (a.size - (emx - emn)).abs()
	return {"min": maxf(dmn.x, maxf(dmn.y, dmn.z)), "max": maxf(dmx.x, maxf(dmx.y, dmx.z)), "dim": maxf(dd.x, maxf(dd.y, dd.z))}


## M12：足元の標本点（kit＝足跡の四隅を 10 % 内側へ＋辺の中点＋中心、植物＝根元 0.3 m の輪＋中心）
func _foot_pts(it: Dictionary) -> PackedVector2Array:
	var c: Vector2 = it["p"]
	var out := PackedVector2Array([c])
	if P3.is_plant(String(it["id"])):
		for k in 6:
			out.append(c + Vector2(cos(TAU * k / 6.0), sin(TAU * k / 6.0)) * 0.3)
		return out
	var poly := W9.foot(it)
	for k in poly.size():
		var q: Vector2 = poly[k]
		var q2: Vector2 = poly[(k + 1) % poly.size()]
		out.append(c + (q - c) * 0.9)
		out.append(c + ((q + q2) * 0.5 - c) * 0.9)
	return out


## 真下の地形（TerrainCollision だけ）。他の碰撞に当たったら除外して続ける。無ければ NAN
func _terrain_y(sp: PhysicsDirectSpaceState3D, tc: CollisionObject3D, q: Vector2, y0: float) -> float:
	var ex: Array = []
	for i in 8:
		var r := sp.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(q.x, y0 + 4.0, q.y), Vector3(q.x, y0 - 6.0, q.y), 0xFFFFFFFF, ex))
		if r.is_empty():
			return NAN
		if r["collider"] == tc:
			return float((r["position"] as Vector3).y)
		ex.append(r["rid"])
	return NAN


## 1 item の接地：gap＝基準面（y）− 地形（TerrainCollision）。gap > TOL の点は、そこに W9.top_h と同じ「碰撞の無い可視の地面」
## （店先帯 F＝P6 R4 Frontage・院子 Y＝P4 Yards／AuxYards・路面 R・田 FS）が y ± TOL にあれば、その面の上として支持に数える
## （可視面に載っている＝浮きではない。godot-asset-placement-validation「碰撞面≠可視面」）。どちらも無ければ支えなし。埋まり＝最大の −gap
const VIS_SURF := {"F": "店先帯", "Y": "院子", "R": "路面", "FS": "田"}


func _ground_eval(sp: PhysicsDirectSpaceState3D, tc: CollisionObject3D, it: Dictionary, y: float, C: Dictionary = {}) -> Dictionary:
	var pts := _foot_pts(it)
	var n := 0
	var sup := 0
	var on_f := 0
	var surf := {}
	var embed := 0.0
	var gmin := 1e9
	for q in pts:
		var ty := _terrain_y(sp, tc, q, y)
		if is_nan(ty):
			continue
		n += 1
		var gap := y - ty
		gmin = minf(gmin, gap)
		if gap <= DL.TERRAIN_FLOAT_TOL:
			sup += 1
		else:
			for k: String in VIS_SURF:
				if not C.has(k):
					continue
				var fh := (C[k] as RLib.TriSampler).h(q.x, q.y)
				if not is_nan(fh) and absf(y - fh) <= DL.TERRAIN_FLOAT_TOL:
					sup += 1
					on_f += 1
					surf[k] = int(surf.get(k, 0)) + 1
					break
		embed = maxf(embed, -gap)
	var support := float(sup) / float(n) if n > 0 else 0.0
	var verdict := "PASS"
	if n == 0 or support < 0.6:
		verdict = "FAIL"
	elif support < 0.8 or embed > DL.TERRAIN_EMBED_REVIEW:
		verdict = "REVIEW"
	return {"n": n, "support": support, "on_visible": on_f, "surf": surf, "embed": embed, "gap_min": gmin, "verdict": verdict}


func _init() -> void:
	_run.call_deferred()


func _arg(args: PackedStringArray, k: String, dflt: String) -> String:
	for s in args:
		if s.begins_with(k + "="):
			return s.trim_prefix(k + "=")
	return dflt


func _rect_poly(cs: CollisionShape3D) -> PackedVector2Array:
	var gt := cs.global_transform
	var h := Vector3(0.2, 1.0, 0.2)
	if cs.shape is BoxShape3D:
		h = (cs.shape as BoxShape3D).size * 0.5
	elif cs.shape is CylinderShape3D:
		var r := (cs.shape as CylinderShape3D).radius
		h = Vector3(r, 1.0, r)
	var pts := PackedVector2Array()
	for sg in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var q := gt * Vector3(h.x * sg.x, 0.0, h.z * sg.y)
		pts.append(Vector2(q.x, q.z))
	return pts


func _coll_bad(C: Dictionary, poly: PackedVector2Array) -> String:
	var c := Vector2.ZERO
	for q in poly:
		c += q
	c /= float(poly.size())
	for b: Dictionary in C["bld"]:
		if (b["o"] as Vector2).distance_to(c) < 14.0:
			for g: PackedVector2Array in Geometry2D.offset_polygon(SL.door_poly(b), 0.02):
				if not Geometry2D.intersect_polygons(poly, g).is_empty():
					return "door(%s)" % String(b["name"])
	for pts: PackedVector2Array in C["npc_paths"]:
		for k in range(1, pts.size()):
			for q in poly:
				if Geometry2D.get_closest_point_to_segment(q, pts[k - 1], pts[k]).distance_to(q) < 0.35:
					return "npc_path"
	return ""


func _area(polys: Array) -> float:
	var a := 0.0
	for pl: PackedVector2Array in polys:
		for k in pl.size():
			a += pl[k].cross(pl[(k + 1) % pl.size()]) * 0.5
	return absf(a)


## verify_w9p8._arm_scan と同じ（通行帯の軸 ±1.2 m・0.5 m おき・16 方位、自分の碰撞を除いた ray と比較）
func _arm_scan(v: Node3D, own: Node3D, lanes: Dictionary) -> Dictionary:
	var sp := v.get_world_3d().direct_space_state
	var ex: Array = []
	for c in own.find_children("*", "CollisionObject3D", true, false):
		ex.append((c as CollisionObject3D).get_rid())
	var cc := sqrt(1.0 - ARM_SIN * ARM_SIN)
	var res := {"n": 0, "severe": 0, "any": 0, "w_loss": 0.0, "w_pre": ARM_MAX, "w_now": ARM_MAX, "w_lane": "", "by": {}}
	for lane: String in lanes:
		var pl: Array = lanes[lane]
		for si in range(1, pl.size()):
			var a: Vector2 = pl[si - 1]
			var b: Vector2 = pl[si]
			var S := (b - a).normalized()
			var N := Vector2(-S.y, S.x)
			for k in int(a.distance_to(b) / 0.5) + 1:
				for o: float in [-1.2, -0.6, 0.0, 0.6, 1.2]:
					var pw := a + S * (0.5 * k) + N * o
					var rg := sp.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(pw.x, 60.0, pw.y), Vector3(pw.x, -20.0, pw.y), 1, ex))
					if rg.is_empty():
						continue
					var o3 := Vector3(pw.x, float((rg["position"] as Vector3).y) + ARM_UP, pw.y)
					for yi in 16:
						var yaw := TAU * float(yi) / 16.0
						var fc := Vector2(sin(yaw), -cos(yaw))
						var to := o3 + Vector3(-fc.x * cc, ARM_SIN, -fc.y * cc) * ARM_MAX
						var r1 := sp.intersect_ray(PhysicsRayQueryParameters3D.create(o3, to, 1))
						var r0 := sp.intersect_ray(PhysicsRayQueryParameters3D.create(o3, to, 1, ex))
						var now := ARM_MAX if r1.is_empty() else o3.distance_to(r1["position"] as Vector3)
						var pre := ARM_MAX if r0.is_empty() else o3.distance_to(r0["position"] as Vector3)
						var loss := pre - now
						res["n"] = int(res["n"]) + 1
						if loss >= 0.30:
							res["any"] = int(res["any"]) + 1
						if loss >= ARM_SEV_LOSS and now < ARM_SEV_LEN:
							res["severe"] = int(res["severe"]) + 1
							var who := "?"
							var co: Object = r1.get("collider")
							if co is CollisionObject3D:
								var ow := (co as CollisionObject3D).shape_find_owner(int(r1.get("shape", 0)))
								var on := (co as CollisionObject3D).shape_owner_get_owner(ow)
								who = String((on as Node).name) if on is Node else String((co as Node).name)
							var by: Dictionary = res["by"]
							by[who] = int(by.get(who, 0)) + 1
						if loss > float(res["w_loss"]):
							res["w_loss"] = loss
							res["w_pre"] = pre
							res["w_now"] = now
							res["w_lane"] = "%s(%.1f,%.1f)" % [lane, pw.x, pw.y]
	return res


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var d := _arg(args, "--district", "")
	if not DL.DISTRICTS.has(d):
		printerr("[DVER] --district=%s は DISTRICTS に無い" % d)
		quit(1)
		return
	var D: Dictionary = DL.DISTRICTS[d]
	var R: Rect2 = D["rect"]
	var mpath := _arg(args, "--manifest", DL.manifest_path(d))
	var M := DL.load_manifest(mpath)
	var ids := DL.asset_ids()
	# ── M1 schema
	var se := DL.schema_errors(M, ids) if not M.is_empty() else ["manifest が読めない " + mpath]
	for e in se.slice(0, 20):
		print("[DVER]   schema: ", e)
	_ok(se.is_empty(), "M1 schema：%s・%d 件（問題 %d）" % [mpath, (M.get("items", []) as Array).size(), se.size()])
	if not se.is_empty():
		quit(1)
		return
	var entries: Array = M["items"]
	var scope := {}
	var base_path := _arg(args, "--baseline", "")
	if base_path != "":
		var df := DL.diff(DL.load_manifest(base_path), M)
		for vid: String in (df["added"] as Array) + (df["changed"] as Array):
			scope[vid] = true
		print("[DVER] INFO baseline %s：added %d・changed %d・removed %d・same %d → 配置・三角形の検査は %d 件だけ" % [base_path, (df["added"] as Array).size(), (df["changed"] as Array).size(), (df["removed"] as Array).size(), (df["same"] as Array).size(), scope.size()])
	var in_scope := func(vid: String) -> bool: return base_path == "" or scope.has(vid)
	# ── 場景（自分の overlay を外して context を作り、bake 済みを記憶の中で掛ける）
	var v: Node3D = (load(DL.SCENE) as PackedScene).instantiate()
	var mounted := v.get_node_or_null(DL.node_name(d))
	if mounted:
		v.remove_child(mounted)
		mounted.free()
	root.add_child(v)
	for i in 3:
		await physics_frame
	P3.register_dims()
	var C := W9.context(v, PackedVector2Array())
	var txt := FileAccess.get_file_as_string(DL.SCENE)
	print("[DVER] INFO village_v2.tscn の %s 掛載：%s（本検査は書かない）" % [DL.node_name(d), "あり" if txt.contains("[node name=\"%s\"" % DL.node_name(d)) else "なし"])
	if not ResourceLoader.exists(DL.overlay_path(d)):
		_ok(false, "M2 overlay %s が無い（district_build.gd が先）" % DL.overlay_path(d))
		quit(1)
		return
	var own := (ResourceLoader.load(DL.overlay_path(d), "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as Node3D
	v.add_child(own)
	for i in 4:
		await physics_frame
	var sha := DL.file_sha256(mpath)
	_ok(String(own.get_meta("manifest_sha256", "")) == sha, "M2 overlay は現在の manifest から bake された（sha256 %s… / overlay %s…）" % [sha.substr(0, 12), String(own.get_meta("manifest_sha256", "")).substr(0, 12)])
	# ── M3 往復
	var nodes := DL.overlay_nodes(own)
	var rt_bad: Array = []
	var dy_max := 0.0
	var dy_vid := ""
	var items: Array = []
	for e: Dictionary in entries:
		var vid := String(e["vid"])
		var it := DL.item_from_entry(e, d)
		if not nodes.has(vid):
			rt_bad.append("%s 節点なし" % vid)
			continue
		var n: Node3D = nodes[vid]
		var gt := n.global_transform
		var bz := gt.basis.z
		var yaw := atan2(bz.x, bz.z)
		var dyaw := absf(wrapf(yaw - float(it["yaw"]), -PI, PI))
		var dp := Vector2(gt.origin.x, gt.origin.z).distance_to(it["p"])
		var ds := maxf(absf(gt.basis.x.length() - float(it["sx"])), maxf(absf(gt.basis.y.length() - float(it["sy"])), absf(gt.basis.z.length() - float(it["sz"]))))
		if dp > DL.XF_TOL or dyaw > 0.002 or ds > 0.002:
			rt_bad.append("%s dp %.3f dyaw %.4f ds %.4f" % [vid, dp, dyaw, ds])
		var dy := absf(gt.origin.y - float(it["y"]))
		if dy > dy_max:
			dy_max = dy
			dy_vid = vid
		it["y"] = gt.origin.y          # 以後の検査は bake 済み（接地済み）の y で
		items.append(it)
	for m in rt_bad.slice(0, 10):
		print("[DVER]   往復 ", m)
	_ok(rt_bad.is_empty() and nodes.size() == entries.size(), "M3 往復：manifest %d 件 ↔ overlay 節点 %d・x/z/yaw/scale 不一致 %d" % [entries.size(), nodes.size(), rt_bad.size()])
	_ok(dy_max <= DL.Y_BLENDER_TOL, "M3 Blender の y と Godot の接地の差 最大 %.3f m ≤ %.2f m（%s；超えたら context が古い）" % [dy_max, DL.Y_BLENDER_TOL, dy_vid])
	# ── M4 範囲
	var out_n := entries.filter(func(e: Dictionary) -> bool: return not DL.in_rect(e, R)).size()
	_ok(out_n == 0, "M4 全 item が街區 rect %s の中（外 %d）" % [R, out_n])
	# ── M5 AABB（軸換算）
	var ab_bad := 0
	var ab_worst := 0.0
	for e: Dictionary in entries:
		var dd := DL.aabb_delta(e, d)
		ab_worst = maxf(ab_worst, dd)
		if dd > DL.AABB_TOL:
			ab_bad += 1
			if ab_bad <= 5:
				print("[DVER]   AABB 差 %s %s %.3f m" % [e["vid"], e["asset"], dd])
	_ok(ab_bad == 0, "M5 Blender の world AABB と Godot 再計算（x/z）の差 最大 %.3f m ≤ %.2f m（超過 %d）" % [ab_worst, DL.AABB_TOL, ab_bad])
	# ── M5b Runtime World AABB（頂点ベース・3 軸・min／max／寸法）
	var calib := "--calibrate" in args
	var rw := {"min": 0.0, "max": 0.0, "dim": 0.0}
	var rw_vid := ""
	var rw_bad := 0
	var rw_n := 0
	var rw_missing := 0
	var rw_dy := 0.0
	for e: Dictionary in entries:
		var vid := String(e["vid"])
		if not nodes.has(vid):
			continue
		if not e.has("aabb_v"):
			rw_missing += 1
			continue
		var nd: Node3D = nodes[vid]
		var dyb := nd.global_position.y - float((e["pos"] as Array)[1])
		rw_dy = maxf(rw_dy, absf(dyb))
		var dl := _rt_delta(DL.node_rt_aabb(nd), e["aabb_v"], dyb)
		rw_n += 1
		var w := maxf(float(dl["min"]), maxf(float(dl["max"]), float(dl["dim"])))
		if w > maxf(float(rw["min"]), maxf(float(rw["max"]), float(rw["dim"]))):
			rw_vid = "%s(%s)" % [vid, e["asset"]]
		for k in ["min", "max", "dim"]:
			rw[k] = maxf(float(rw[k]), float(dl[k]))
		if w > DL.RT_AABB_TOL:
			rw_bad += 1
			if rw_bad <= 5 and not calib:
				print("[DVER]   runtime AABB 差 %s %s min %.4f max %.4f dim %.4f" % [vid, e["asset"], dl["min"], dl["max"], dl["dim"]])
	stats["rt_aabb"] = {"n": rw_n, "missing_aabb_v": rw_missing, "max_min": rw["min"], "max_max": rw["max"], "max_dim": rw["dim"], "worst": rw_vid, "max_snap_dy": rw_dy, "tol": DL.RT_AABB_TOL}
	if calib:
		var worst := maxf(float(rw["min"]), maxf(float(rw["max"]), float(rw["dim"])))
		var tol := maxf(0.001, ceilf(worst * 10.0 * 1000.0) / 1000.0)
		stats["calibration"] = {"worst": worst, "tol_rule": "max(1 mm, worst × 10) 切り上げ", "tol": tol}
		print("[DVER] CAL  M5b 実測：%d 件・min 差 %.6f・max 差 %.6f・寸法差 %.6f m（最悪 %s）・接地し直し最大 %.4f m → 規則による許容値 %.3f m" % [rw_n, rw["min"], rw["max"], rw["dim"], rw_vid, rw_dy, tol])
	else:
		_ok(rw_bad == 0 and rw_missing == 0 and rw_n == entries.size(), "M5b Runtime World AABB（頂点・3 軸）%d 件：min 差 %.4f・max 差 %.4f・寸法差 %.4f m ≤ %.3f m（超過 %d・aabb_v 欠 %d・最悪 %s）" % [rw_n, rw["min"], rw["max"], rw["dim"], DL.RT_AABB_TOL, rw_bad, rw_missing, rw_vid])
	# ── M6 配置
	var bad: Array = []
	var n_scope := 0
	for it: Dictionary in items:
		if not in_scope.call(String(it["vid"])):
			continue
		n_scope += 1
		var w := DL.check(C, it)
		if w != "":
			bad.append("%s %s@(%.1f,%.1f) %s [%s]" % [it["vid"], it["id"], (it["p"] as Vector2).x, (it["p"] as Vector2).y, w, it["cluster"]])
	for m in bad.slice(0, 25):
		print("[DVER]   不適合 ", m)
	_ok(bad.is_empty(), "M6 配置（W9.why＋接地）%d 件：道・建物・戸口・水・田・封存物・NPC・Hero に触れず接地（不適合 %d）" % [n_scope, bad.size()])
	# ── M7 重なり：footprint → 三角形
	var cand := 0
	var real := 0
	var no_tri := "--no-tri" in args
	for i in items.size():
		var a: Dictionary = items[i]
		if bool(a.get("nov", false)) or bool(a.get("hang", false)):
			continue
		for j in range(i + 1, items.size()):
			var b: Dictionary = items[j]
			if bool(b.get("nov", false)) or bool(b.get("hang", false)) or (a["p"] as Vector2).distance_to(b["p"]) > 8.0:
				continue
			if not (in_scope.call(String(a["vid"])) or in_scope.call(String(b["vid"]))):
				continue
			if _area(Geometry2D.intersect_polygons(W9.foot(a), W9.foot(b))) <= OVERLAP_AREA:
				continue
			cand += 1
			if no_tri:
				real += 1
				continue
			var h := DL.tri_hits(load(DL.lod0_path(String(a["id"]))) as Mesh, DL.item_xf(a), load(DL.lod0_path(String(b["id"]))) as Mesh, DL.item_xf(b))
			if h > 0:
				real += 1
				if real <= 8:
					print("[DVER]   貫通 %s(%s) × %s(%s) 交差 %d" % [a["vid"], a["id"], b["vid"], b["id"], h])
	_ok(real == 0, "M7 重なり：footprint 候補 %d 組 → 三角形で実貫通 %d 組%s" % [cand, real, "（--no-tri：候補をそのまま数えた）" if no_tri else ""])
	# ── M8 碰撞箱
	var shapes := own.find_children("*", "CollisionShape3D", true, false)
	var cbad := 0
	for cs in shapes:
		var r := _coll_bad(C, _rect_poly(cs as CollisionShape3D))
		if r != "":
			cbad += 1
			if cbad <= 5:
				print("[DVER]   碰撞不適合 %s %s" % [cs.name, r])
	_ok(cbad == 0, "M8 碰撞箱 %d 個が戸口の空け帯・NPC 巡回路に触れない（%d）" % [shapes.size(), cbad])
	# ── M9 keep_clear
	var kc_min := 1e9
	var kc_who := ""
	for it: Dictionary in items:
		for k: String in D.get("keep_clear", {}):
			var dist := (it["p"] as Vector2).distance_to(D["keep_clear"][k])
			if dist < kc_min:
				kc_min = dist
				kc_who = "%s↔%s" % [it["vid"], k]
	_ok(kc_min >= DL.KEEP_R, "M9 任務の出入口から最も近い item %.1f m ≥ %.1f m（%s）" % [kc_min, DL.KEEP_R, kc_who])
	# ── M10 SpringArm
	if not ("--no-arm" in args) and not (D.get("arm_lanes", {}) as Dictionary).is_empty():
		var sv := _arm_scan(v, own, D["arm_lanes"])
		for k in sv["by"]:
			print("[DVER]   重い縮みの碰撞 %s：%d 件" % [k, int(sv["by"][k])])
		_ok(int(sv["severe"]) == 0, "M10 通行帯 %d 本 %d 樣本：overlay の碰撞による SpringArm の重い縮み（≥ %.1f m かつ腕 < %.1f m）%d 件・≥ 0.30 m %d 件・最悪 %.2f → %.2f m %s" \
			% [(D["arm_lanes"] as Dictionary).size(), int(sv["n"]), ARM_SEV_LOSS, ARM_SEV_LEN, int(sv["severe"]), int(sv["any"]), float(sv["w_pre"]), float(sv["w_now"]), sv["w_lane"]])
	else:
		print("[DVER] INFO M10 SpringArm 未実施（--no-arm または通行帯なし）")
	# ── M12 地形接地（TerrainCollision だけを地形と認める多点 ray）
	var sp12 := v.get_world_3d().direct_space_state
	var tc := v.get_node_or_null("Collision/TerrainCollision") as CollisionObject3D
	var g_fail: Array = []
	var g_rev: Array = []
	var g_n := 0
	var g_rays := 0
	var g_emb := 0.0
	var g_emb_vid := ""
	var g_sup_min := 1.0
	var g_front: Array = []
	if tc == null:
		_ok(false, "M12 地形接地：Collision/TerrainCollision が無い")
	else:
		for it: Dictionary in items:
			if not in_scope.call(String(it["vid"])) or bool(it.get("hang", false)) or String(it.get("ground", "snap")) != "snap":
				continue
			var ge := _ground_eval(sp12, tc, it, float(it["y"]), C)
			g_n += 1
			g_rays += int(ge["n"])
			if int(ge["on_visible"]) > 0:
				var sn := PackedStringArray()
				for k: String in ge["surf"]:
					sn.append("%s %d 点" % [VIS_SURF[k], int(ge["surf"][k])])
				g_front.append("%s %s（碰撞の無い可視の地面の上：%s）" % [it["vid"], it["id"], "・".join(sn)])
			g_sup_min = minf(g_sup_min, float(ge["support"]))
			if float(ge["embed"]) > g_emb:
				g_emb = float(ge["embed"])
				g_emb_vid = "%s(%s)" % [it["vid"], it["id"]]
			if ge["verdict"] == "FAIL":
				g_fail.append("%s %s 支持 %.0f%% gap_min %+.3f" % [it["vid"], it["id"], float(ge["support"]) * 100.0, ge["gap_min"]])
			elif ge["verdict"] == "REVIEW":
				g_rev.append("%s %s 支持 %.0f%% 埋まり %.2f m" % [it["vid"], it["id"], float(ge["support"]) * 100.0, ge["embed"]])
		for m in g_fail.slice(0, 8):
			print("[DVER]   接地 FAIL ", m)
		for m in g_rev.slice(0, 8):
			print("[DVER]   接地 REVIEW ", m)
		for m in g_front.slice(0, 8):
			print("[DVER]   接地 INFO ", m)
		stats["terrain"] = {"items": g_n, "rays": g_rays, "fail": g_fail.size(), "review": g_rev, "on_visible_ground": g_front, "support_min": g_sup_min, "embed_max": g_emb, "embed_max_vid": g_emb_vid}
		_ok(g_fail.is_empty(), "M12 地形接地（TerrainCollision・多点 ray %d 本）%d 件：浮き FAIL %d・REVIEW %d・碰撞の無い可視の地面（店先帯・院子）の上 %d 件・最低支持率 %.0f%%・最大埋まり %.2f m（%s）" % [g_rays, g_n, g_fail.size(), g_rev.size(), g_front.size(), g_sup_min * 100.0, g_emb, g_emb_vid])
	# ── M11 予算
	var tri := 0
	var mesh := 0
	for mi in own.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		mesh += 1
		if g.visibility_range_begin <= 0.001 and g.mesh != null:
			tri += g.mesh.get_faces().size() / 3
	var mm := own.find_children("*", "MultiMeshInstance3D", true, false)
	_ok(tri <= MAX_TRI_LOD0 and mesh <= MAX_MESH and shapes.size() <= MAX_SHAPES and mm.is_empty(), "M11 予算：LOD0 三角形 %d ≤ %d・MeshInstance %d ≤ %d・碰撞 %d ≤ %d・MultiMesh %d" % [tri, MAX_TRI_LOD0, mesh, MAX_MESH, shapes.size(), MAX_SHAPES, mm.size()])
	# ── 反向（記憶の中で 1 件ずつ壊し、該当検査が FAIL すること）
	if not items.is_empty():
		# 反向の注入先は地面物（hang・wall・soft は道路の判定を受けないので、そこに注入しても検査を試せない）
		var it0: Dictionary = items[0].duplicate()
		for x: Dictionary in items:
			if not bool(x.get("hang", false)) and DL.why_mode(x) == "ground":
				it0 = x.duplicate()
				break
		var road_p := Vector2.INF
		for rn: String in C["roads"]:
			for q: Vector2 in (C["roads"][rn]["pts"] as PackedVector2Array):
				if R.has_point(q):
					road_p = q
					break
			if road_p != Vector2.INF:
				break
		if road_p != Vector2.INF:
			var itr := it0.duplicate()
			itr["p"] = road_p
			itr["y"] = W9.ground_y(C, itr)
			var w := DL.check(C, itr)
			_neg("道路の上へ移動", w != "", w)
		else:
			_neg("道路の上へ移動", false, "街區に道路の点が無く試せない")
		var Mdup := M.duplicate(true)
		(Mdup["items"] as Array).append((Mdup["items"] as Array)[0].duplicate(true))
		var de := DL.schema_errors(Mdup, ids)
		_neg("vid 重複", de.any(func(s: String) -> bool: return s.begins_with("vid 重複")), str(de.slice(0, 1)))
		var itf := it0.duplicate()
		itf["hang"] = false
		itf["y"] = W9.ground_y(C, itf) + 0.5
		var wf := DL.check(C, itf)
		_neg("y +0.5 m（浮き）", wf.begins_with("float") or wf != "", wf)
		var e0: Dictionary = (entries[0] as Dictionary).duplicate(true)
		var ab: Array = e0["aabb"]
		e0["aabb"] = [float(ab[0]), float(ab[1]), float(ab[2]) + 0.3, float(ab[3]), float(ab[4]), float(ab[5]) + 0.3]
		var dd0 := DL.aabb_delta(e0, d)
		_neg("AABB を z へ 0.3 m（軸換算の誤り）", dd0 > DL.AABB_TOL, "%.3f m" % dd0)
		# 三角形の貫通：地面物（植物・吊り物でない）を同じ位置から 0.15 m ずらして重ねる → 交差 > 0
		var solid: Array = items.filter(func(x: Dictionary) -> bool: return not P3.is_plant(String(x["id"])) and not bool(x.get("hang", false)))
		if not solid.is_empty():
			var sa: Dictionary = solid[0]
			var sb: Dictionary = sa.duplicate()
			sb["p"] = (sa["p"] as Vector2) + Vector2(0.15, 0.0)
			sb["yaw"] = float(sa["yaw"]) + 0.3
			var mesh0 := load(DL.lod0_path(String(sa["id"]))) as Mesh
			var th := DL.tri_hits(mesh0, DL.item_xf(sa), mesh0, DL.item_xf(sb))
			_neg("同じ物を 0.15 m ずらして重ねる（三角形）", th > 0, "%s 交差 %d" % [sa["id"], th])
		var Msp := M.duplicate(true)
		Msp["space"] = "blender_z_up"
		_neg("space が Blender 座標", not DL.schema_errors(Msp, ids).is_empty(), "space=blender_z_up")
		# M5b：runtime 節点を x へ 0.3 m 動かす（変換の二重適用・取り違え）→ 頂点 AABB の差が許容値を超える
		var e5: Dictionary = entries[0]
		if nodes.has(String(e5["vid"])) and e5.has("aabb_v"):
			var n5: Node3D = nodes[String(e5["vid"])]
			var keep5 := n5.global_position
			var dy5 := keep5.y - float((e5["pos"] as Array)[1])
			n5.global_position = keep5 + Vector3(0.3, 0.0, 0.0)
			var d5 := _rt_delta(DL.node_rt_aabb(n5), e5["aabb_v"], dy5)
			n5.global_position = keep5
			_neg("runtime 節点を 0.3 m 動かす（M5b）", float(d5["min"]) > DL.RT_AABB_TOL, "min 差 %.3f m" % d5["min"])
		# M12：地面物を 0.3 m 持ち上げる → 支持率 0 で FAIL
		if tc != null:
			var g12: Array = items.filter(func(x: Dictionary) -> bool: return not bool(x.get("hang", false)) and String(x.get("ground", "snap")) == "snap")
			if not g12.is_empty():
				var ge12 := _ground_eval(sp12, tc, g12[0], float((g12[0] as Dictionary)["y"]) + 0.3, C)
				_neg("0.3 m 持ち上げる（M12 浮き）", ge12["verdict"] == "FAIL", "%s 支持 %.0f%%" % [(g12[0] as Dictionary)["vid"], float(ge12["support"]) * 100.0])
	print("[DVER] 合計 PASS %d・FAIL %d・反向 OK %d／BAD %d" % [passed, failed, neg_ok, neg_bad])
	var outp := _arg(args, "--out", "")
	if outp != "":
		var fo := FileAccess.open(outp, FileAccess.WRITE)
		fo.store_string(JSON.stringify({"district": d, "manifest": mpath, "manifest_sha256": DL.file_sha256(mpath), "baseline": base_path,
			"scope": scope.size() if base_path != "" else entries.size(), "items": entries.size(), "pass": passed, "fail": failed,
			"neg_ok": neg_ok, "neg_bad": neg_bad, "results": results, "stats": stats}, "\t") + "\n")
		fo.close()
		print("[DVER] → ", outp)
	own.queue_free()
	quit(0 if failed == 0 and neg_bad == 0 else (2 if neg_bad > 0 else 1))
