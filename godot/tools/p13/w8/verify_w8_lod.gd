extends SceneTree
## P13 Wave 8 gate：LodGuardP13（TASK A・LOD 可視遲滯の状態初期化）＋ LodCalBatch1P13（TASK B・第一批 50 棟の LOD1／LOD2 材質）。
##   godot --headless --path . --script res://tools/p13/w8/verify_w8_lod.gd [-- --negatives]
## 区塊：
##   A guard   ：LodGuardP13 の掛載（root 直下 1 つ・子 0・script・既定値）／実行時の不変条件：ノードの visibility_range_* を一切書き換えない（対象全件の雜湊が前後で同じ）・
##               primes が動く・enabled=false で動かない。（描画結果＝gap／double の実測は tools/p13/w8/w8_lod_sweep.gd。headless では描画できないのでここでは見ない）
##   B registry：lod_cal_p13/ の登記表・shader・21 変体 .tres：sha256・shader・既定引数が K 版と同じ・乗数が範囲内・種別ごとの引数・余計なファイルなし。
##   C manifest：data/village_v2_p13w8_lod.json＝W7 の第一批 50 棟と同一・割り当ての材質が登記済みで種別が合う・死んだ材質なし・overlay scene と名簿が一致。
##   D runtime ：50 棟の LOD1／LOD2 の V2_MachiyaKit 表面が全部、期待の種別（l1／l2／roof）の登記材質に覆寫されている・LOD0 と範囲外の建物に W8 材質 0・
##               enabled=false で W7 の状態（K 版／屋根は覆寫なし）に完全還原・再度 true で同数に戻る・幾何（mesh）と碰撞は不変。
##   N negatives：in-memory の壊れたデータで各検査が必ず FAIL する。
const SCENE := "res://maps/village_v2/village_v2.tscn"
const W7_MAN := "res://data/village_v2_p13w7_batch1.json"
const W8_MAN := "res://data/village_v2_p13w8_lod.json"
const W8_REG := "res://maps/village_v2/lod_cal_p13/lod_material_variants.json"
const W8_DIR := "res://maps/village_v2/lod_cal_p13/"
const SHADER := "res://maps/village_v2/lod_cal_p13/kit_cal_lod.gdshader"
const ATLAS_BASE := "res://assets/village_v2/machiya_kit/V2_MachiyaKit.tres"
const ATLAS_TEX := "res://assets/village_v2/machiya_kit/machiya_kit_atlas.png"
const EMIT_TEX := "res://assets/village_v2/machiya_kit/machiya_kit_emit.png"
const K_FILE := "res://maps/village_v2/kit_cal_p10/V2_MachiyaKit_K.tres"
const ROOF_PREFIX := "l_rh_"
const MUL_LO := 0.15
const MUL_HI := 3.0
const ROOF_K0 := 0.1413
const MAX_MATS := 30
## 独立抄写（lod_guard.gd と builder の既定値を別に持つ）
const GUARD := {"jump_threshold": 6.0, "turn_threshold_deg": 35.0, "accum_turn_deg": 45.0, "minimum_interval": 1.0}

var v: Node3D
var fails := 0
var passes := 0
var quiet := false
var reg: Dictionary
var man: Dictionary
var w7_man: Dictionary
var by_id := {}          # 変体 id → 登記 entry
var by_file := {}        # 変体 file → 登記 entry
var batch_paths := {}    # 名簿の建物 path → W8 割り当て
var all_b: Array = []    # Kit 持ちの建物 Node3D
var guard_snapshot_before := 0   # scene を tree に入れる前の『margin 付き fade-disabled』全件の雜湊
var guard_count_before := 0


func _init() -> void:
	_run.call_deferred()


func ok(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		if not quiet:
			print("[W8G] PASS ", msg)
	else:
		fails += 1
		if not quiet:
			print("[W8G] FAIL ", msg)


func _ranges_hash(root_node: Node) -> Array:
	var h := PackedInt64Array()
	var n := 0
	for g in root_node.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if gi.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED and (gi.visibility_range_begin_margin > 0.0 or gi.visibility_range_end_margin > 0.0):
			n += 1
			var s := "%s|%.3f|%.3f|%.3f|%.3f" % [root_node.get_path_to(gi), gi.visibility_range_begin, gi.visibility_range_end, gi.visibility_range_begin_margin, gi.visibility_range_end_margin]
			h.append(s.hash())
	var acc := 0
	for x in h:
		acc = (acc * 1000003 + x) & 0x7FFFFFFFFFFFFFFF
	return [acc, n]


func _run() -> void:
	var neg := OS.get_cmdline_user_args().has("--negatives")
	v = (load(SCENE) as PackedScene).instantiate()
	# TASK A の不変条件：tree に入れる前（guard が動く前）の状態を記録する
	var snap := _ranges_hash(v)
	guard_snapshot_before = snap[0]
	guard_count_before = snap[1]
	root.add_child(v)
	# LodGuardP13 は『現在の Camera3D』の位置・向きで動く → 診断用の相機を 1 つ置く（描画はしない・位置は村内）
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = Vector3(226.4, 8.0, 157.0)
	cam.current = true
	for i in 12:
		await process_frame
	_load_data()
	_collect()
	_a_guard()
	_b_registry(reg)
	_c_manifest()
	_d_runtime()
	await _a_guard_runtime()
	if neg:
		await _negatives()
	print("[W8G] ", "PASS %d" % passes, "  FAIL %d" % fails)
	print("[W8G] 結果：%d 項失敗" % fails)
	quit(1 if fails > 0 else 0)


func _load_data() -> void:
	reg = JSON.parse_string(FileAccess.get_file_as_string(W8_REG))
	man = JSON.parse_string(FileAccess.get_file_as_string(W8_MAN))
	w7_man = JSON.parse_string(FileAccess.get_file_as_string(W7_MAN))
	for e: Dictionary in reg["variants"]:
		by_id[String(e["id"])] = e
		by_file[String(e["file"])] = e
	for b: Dictionary in man["buildings"]:
		batch_paths[String(b["path"])] = b


func _collect() -> void:
	for n in v.get_node("Districts").find_children("B_*", "Node3D", true, false):
		if n.get_node_or_null("Kit") != null:
			all_b.append(n)


# ─────────────────────────── A guard ───────────────────────────
func _a_guard() -> void:
	var g := v.find_children("LodGuardP13", "", false, false)
	ok(g.size() == 1, "root/LodGuardP13 掛載 1 個（実得 %d）" % g.size())
	if g.size() != 1:
		return
	var n: Node = g[0]
	ok(n.get_child_count() == 0, "LodGuardP13 は子ノード 0（資源を持たない）")
	ok(String(n.get_script().resource_path) == "res://maps/village_v2/scripts_p13/lod_guard.gd", "script＝scripts_p13/lod_guard.gd")
	for k: String in GUARD:
		ok(is_equal_approx(float(n.get(k)), float(GUARD[k])), "LodGuardP13.%s＝%s（期待 %s）" % [k, str(n.get(k)), str(GUARD[k])])
	ok(bool(n.get("enabled")), "LodGuardP13.enabled")
	var cal := v.get_node_or_null("LodCalBatch1P13")
	ok(cal != null and cal.get_index() > v.get_node("AlbedoBatch1P13").get_index(), "LodCalBatch1P13 は AlbedoBatch1P13 より後に掛かる（W7 の K 版の上から差し替えるため）")


func _a_guard_runtime() -> void:
	## headless は描画ループを回さない（frame_pre_draw／frame_post_draw が発行されない）→ ここでは処理関数を直接呼んで論理を検証する。
	## 描画結果（gap／double）の実測は tools/p13/w8/w8_lod_sweep.gd（非 headless）と check_sweep.py。
	var n := v.get_node("LodGuardP13")
	var cam := root.get_viewport().get_camera_3d()
	ok(cam != null, "実行時：診断用の相機が current")
	n.set("minimum_interval", 0.0)
	n.call("_on_pre_draw")           # 最初の 1 幀（first）
	ok(int(n.get("primes")) == 1 and String(n.get("last_reason")) == "first", "実行時：最初の 1 幀で初期化（first）が走る（primes＝%d・reason＝%s）" % [int(n.get("primes")), String(n.get("last_reason"))])
	var tracked := int(n.get("tracked"))
	ok(tracked == guard_count_before and tracked > 10000, "対象インスタンス＝margin 付き fade-disabled 全件（走査 %d／事前計数 %d）" % [tracked, guard_count_before])
	ok(bool(n.get("_priming")), "初期化中＝その 1 幀だけ margin 0（_priming＝true）")
	n.call("_on_post_draw")
	ok(not bool(n.get("_priming")), "描画後に margin を戻している（_priming＝false）")
	# 不変条件：ノードのプロパティは 1 つも書き換わらない（RenderingServer だけを叩く）
	var after := _ranges_hash(v)
	ok(after[0] == guard_snapshot_before and after[1] == guard_count_before, "不変条件：初期化と復元の後も visibility_range_*（%d 件）が 1 つも変わらない（雜湊 %s）" % [after[1], "一致" if after[0] == guard_snapshot_before else "不一致"])
	var p := int(n.get("primes"))
	# 小さな移動・小さな回転では走らない
	cam.global_position += Vector3(1.0, 0, 0)
	n.call("_on_pre_draw")
	n.call("_on_post_draw")
	ok(int(n.get("primes")) == p, "実行時：1 m の移動では初期化しない（primes＝%d のまま）" % p)
	# テレポート
	cam.global_position += Vector3(80.0, 0, 0)
	n.call("_on_pre_draw")
	n.call("_on_post_draw")
	ok(int(n.get("primes")) == p + 1 and String(n.get("last_reason")) == "jump", "実行時：80 m のテレポートで初期化（jump）")
	# 1 幀で 60° 振り向く
	cam.rotate_y(deg_to_rad(60.0))
	n.call("_on_pre_draw")
	n.call("_on_post_draw")
	ok(int(n.get("primes")) == p + 2 and String(n.get("last_reason")) == "flick", "実行時：1 幀 60° の振り向きで初期化（flick）")
	# ゆっくりした振り向き（10°／幀）→ 累積 45° を超えた幀で初期化
	var before_accum := int(n.get("primes"))
	var hit := ""
	for i in 7:
		cam.rotate_y(deg_to_rad(10.0))
		n.call("_on_pre_draw")
		n.call("_on_post_draw")
		if int(n.get("primes")) > before_accum and hit == "":
			hit = "%d 幀目（累積 %d°）" % [i + 1, (i + 1) * 10]
			ok(String(n.get("last_reason")) == "accum" and i == 4, "実行時：10°/幀 の振り向きは累積 45° を超えた 5 幀目で初期化（accum）（%s）" % hit)
	ok(hit != "", "実行時：ゆっくりした振り向きでも初期化が走る")
	# 間引き（minimum_interval）：直後に再度 45° 以上回しても、間隔内なら走らない
	n.set("minimum_interval", 5.0)
	n.set("_since_prime", 0.0)
	var p2 := int(n.get("primes"))
	for i in 7:
		cam.rotate_y(deg_to_rad(10.0))
		n.call("_on_pre_draw")
		n.call("_on_post_draw")
	ok(int(n.get("primes")) == p2, "実行時：minimum_interval 内の累積振り向きでは初期化しない（間引き）")
	# 無効化
	n.set("enabled", false)
	n.call("prime_next_frame")
	cam.global_position += Vector3(200.0, 0, 0)
	n.call("_on_pre_draw")
	n.call("_on_post_draw")
	ok(int(n.get("primes")) == p2, "実行時：enabled=false ならテレポートでも初期化しない")
	n.set("enabled", true)
	n.set("minimum_interval", float(GUARD["minimum_interval"]))
	var after2 := _ranges_hash(v)
	ok(after2[0] == guard_snapshot_before, "不変条件：一連の操作の後も visibility_range_* は不変")


# ─────────────────────────── B registry ───────────────────────────
func _vec3_ok(a: Variant, lo: float, hi: float) -> bool:
	if not (a is Array) or (a as Array).size() != 3:
		return false
	for x in a:
		if float(x) < lo - 1e-6 or float(x) > hi + 1e-6:
			return false
	return true


## 登記表 r を検査して問題数を返す（negatives からも使う）
func _check_registry(r: Dictionary, tag := "") -> int:
	var bad := 0
	var sh: Dictionary = r.get("shader", {})
	if String(sh.get("file", "")) != SHADER or FileAccess.get_sha256(SHADER) != String(sh.get("sha256", "")):
		bad += 1
	var vs: Array = r.get("variants", [])
	if vs.size() == 0 or vs.size() > MAX_MATS:
		bad += 1
	var seen := {}
	for e: Dictionary in vs:
		var id := String(e.get("id", ""))
		if seen.has(id):
			bad += 1
		seen[id] = true
		var f := String(e.get("file", ""))
		if not FileAccess.file_exists(f) or FileAccess.get_sha256(f) != String(e.get("sha256", "")):
			bad += 1
			continue
		if String(e.get("base", "")) != ATLAS_BASE:
			bad += 1
		var kind := String(e.get("kind", ""))
		var p: Dictionary = e.get("params", {})
		if kind == "roof":
			if not bool(p.get("roof_mode", false)) or not _vec3_ok(p.get("roof_k"), ROOF_K0 * MUL_LO, ROOF_K0 * MUL_HI):
				bad += 1
		elif kind == "l1" or kind == "l2":
			if bool(p.get("roof_mode", false)) or not _vec3_ok(p.get("box_mul"), MUL_LO, MUL_HI) or not _vec3_ok(p.get("face_mul"), MUL_LO, MUL_HI):
				bad += 1
			if kind == "l2" and p.get("face_mul") != [1.0, 1.0, 1.0]:
				bad += 1
		else:
			bad += 1
		# 材質ファイルそのもの
		var m := load(f) as ShaderMaterial
		if m == null or m.shader == null or m.shader.resource_path != SHADER:
			bad += 1
			continue
		var kmat := load(K_FILE) as ShaderMaterial
		for k in ["k_dark", "k_mid", "k_light", "band_dark", "band_light", "roughness_v", "emission_energy"]:
			if m.get_shader_parameter(k) != kmat.get_shader_parameter(k):
				bad += 1
		if m.get_shader_parameter("albedo_tex") == null or m.get_shader_parameter("albedo_tex").resource_path != ATLAS_TEX:
			bad += 1
		if m.get_shader_parameter("emit_tex") == null or m.get_shader_parameter("emit_tex").resource_path != EMIT_TEX:
			bad += 1
		if kind == "roof":
			var rk: Vector3 = m.get_shader_parameter("roof_k")
			var want: Array = p["roof_k"]
			if not ((m.get_shader_parameter("roof_mode") == true) and absf(rk.x - float(want[0])) < 2e-4 and absf(rk.y - float(want[1])) < 2e-4 and absf(rk.z - float(want[2])) < 2e-4):
				bad += 1
		else:
			var bm: Vector3 = m.get_shader_parameter("box_mul")
			var fm: Vector3 = m.get_shader_parameter("face_mul")
			var wb: Array = p["box_mul"]
			var wf: Array = p["face_mul"]
			if (m.get_shader_parameter("roof_mode") == true) or absf(bm.x - float(wb[0])) > 2e-4 or absf(bm.y - float(wb[1])) > 2e-4 or absf(bm.z - float(wb[2])) > 2e-4 \
					or absf(fm.x - float(wf[0])) > 2e-4 or absf(fm.y - float(wf[1])) > 2e-4 or absf(fm.z - float(wf[2])) > 2e-4:
				bad += 1
	if tag == "":
		# 余計なファイルなし（.uid／.import は許す）
		var want_files := {"kit_cal_lod.gdshader": true, "lod_material_variants.json": true}
		for e2: Dictionary in vs:
			want_files[String(e2["file"]).get_file()] = true
		for fn in DirAccess.get_files_at(W8_DIR):
			if fn.ends_with(".uid") or fn.ends_with(".import"):
				continue
			if not want_files.has(fn):
				bad += 1
	return bad


func _b_registry(r: Dictionary) -> void:
	var bad := _check_registry(r)
	ok(bad == 0, "B 登記：shader sha・%d 変体の sha／種別／引数範囲／K 版と同じ既定引数／roof_mode・余計なファイルなし（問題 %d）" % [(r["variants"] as Array).size(), bad])
	var kinds := {"l1": 0, "l2": 0, "roof": 0}
	for e: Dictionary in r["variants"]:
		kinds[String(e["kind"])] += 1
	ok(kinds["l1"] >= 1 and kinds["l2"] >= 1 and kinds["roof"] >= 1 and (r["variants"] as Array).size() <= MAX_MATS, "B 調色盤の数＝少量（l1 %d・l2 %d・roof %d・計 %d ≤ %d）" % [kinds["l1"], kinds["l2"], kinds["roof"], (r["variants"] as Array).size(), MAX_MATS])


# ─────────────────────────── C manifest ───────────────────────────
func _c_manifest() -> void:
	var w7_ids := {}
	for b: Dictionary in w7_man["buildings"]:
		w7_ids[String(b["id"])] = String(b["path"])
	var rows: Array = man["buildings"]
	ok(rows.size() == 50 and int(man["count"]) == 50, "C 名簿 50 棟（%d）" % rows.size())
	var same := rows.size() == w7_ids.size()
	var bad := 0
	var used := {}
	for b: Dictionary in rows:
		if not w7_ids.has(String(b["id"])) or w7_ids[String(b["id"])] != String(b["path"]):
			same = false
		for kind in ["l1", "l2", "roof"]:
			var e: Dictionary = by_id.get(String(b[kind]), {})
			if e.is_empty() or String(e["kind"]) != kind:
				bad += 1
			used[String(b[kind])] = true
	ok(same, "C 名簿＝W7 第一批 50 棟と同一（id・path）")
	ok(bad == 0, "C 割り当ての材質はすべて登記済みで種別が合う（l1／l2／roof）（不一致 %d）" % bad)
	var dead := []
	for id: String in by_id:
		if not used.has(id):
			dead.append(id)
	ok(dead.is_empty(), "C 死んだ材質なし（未使用 %s）" % str(dead))
	var cal := v.get_node("LodCalBatch1P13")
	var tg: PackedStringArray = cal.get("targets")
	var asg: Array = cal.get("assign")
	var mats: Array = cal.get("mats")
	var okc := tg.size() == rows.size() and asg.size() == rows.size() and mats.size() == (reg["variants"] as Array).size()
	if okc:
		for i in rows.size():
			if tg[i] != String(rows[i]["path"]):
				okc = false
			for kind in ["l1", "l2", "roof"]:
				var mf := String((mats[int(asg[i][kind])] as Material).resource_path)
				if mf != String(by_id[String(rows[i][kind])]["file"]):
					okc = false
	ok(okc, "C overlay scene の targets／assign／mats が名簿・登記表と一致")


# ─────────────────────────── D runtime ───────────────────────────
func _lod_of(m: Node) -> int:
	var n := m.get_parent()
	while n != null and n != v:
		var nm := String(n.name)
		if nm == "LOD0":
			return 0
		if nm == "LOD1":
			return 1
		if nm == "LOD2":
			return 2
		n = n.get_parent()
	return -1


## 全建物の全 MeshInstance3D を数えて期待と照合する。返り値 {bad, applied, roof, w8_elsewhere, detail}
func _scan_runtime(expect_on: bool) -> Dictionary:
	var bad := 0
	var applied := 0
	var roof := 0
	var elsewhere := 0
	var detail: Array = []
	for b in all_b:
		var path := String(v.get_path_to(b))
		var asg: Dictionary = batch_paths.get(path, {})
		for mi in b.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var lod := _lod_of(m)
			for si in m.mesh.get_surface_count():
				var ov := m.get_surface_override_material(si)
				var is_w8 := ov != null and by_file.has(ov.resource_path)
				var base := m.mesh.surface_get_material(si)
				var bp := base.resource_path if base != null else ""
				if m.material_override != null and by_file.has(m.material_override.resource_path):
					bad += 1
					detail.append("%s/%s: material_override に W8 材質" % [b.name, m.name])
				if asg.is_empty() or lod == 0 or lod < 0:
					if is_w8:
						elsewhere += 1
						bad += 1
						if detail.size() < 8:
							detail.append("%s/%s LOD%d: 範囲外に W8 材質" % [b.name, m.name, lod])
					continue
				# 名簿の建物の LOD1／LOD2
				if bp != ATLAS_BASE:
					if is_w8:
						bad += 1
						detail.append("%s/%s: 基底 %s に W8 材質" % [b.name, m.name, bp.get_file()])
					continue
				var is_roof := String(m.name).begins_with(ROOF_PREFIX)
				var kind := "roof" if is_roof else ("l1" if lod == 1 else "l2")
				if expect_on:
					var want := String(by_id[String(asg[kind])]["file"])
					if ov == null or ov.resource_path != want:
						bad += 1
						if detail.size() < 8:
							detail.append("%s/%s LOD%d: 期待 %s／実 %s" % [b.name, m.name, lod, want.get_file(), ov.resource_path.get_file() if ov != null else "なし"])
					else:
						applied += 1
						if is_roof:
							roof += 1
				else:
					# 還原後＝W7 の状態：本体は K 版、屋根は覆寫なし
					var good := (ov == null) if is_roof else (ov != null and ov.resource_path == K_FILE)
					if not good:
						bad += 1
						if detail.size() < 8:
							detail.append("%s/%s LOD%d: 還原後の状態が W7 と違う（%s）" % [b.name, m.name, lod, ov.resource_path.get_file() if ov != null else "なし"])
	return {"bad": bad, "applied": applied, "roof": roof, "elsewhere": elsewhere, "detail": detail}


func _d_runtime() -> void:
	var cal := v.get_node("LodCalBatch1P13")
	ok(bool(cal.get("enabled")) and cal.get_child_count() == 0, "D LodCalBatch1P13 enabled・子ノード 0（雙份 geometry なし）")
	var s := _scan_runtime(true)
	ok(int(s["bad"]) == 0, "D 50 棟の LOD1／LOD2 の V2_MachiyaKit 表面＝期待の種別の登記材質（不一致 %d%s）" % [s["bad"], "" if (s["detail"] as Array).is_empty() else " " + str((s["detail"] as Array).slice(0, 3))])
	ok(int(s["applied"]) == int(cal.get("applied_surfaces")) and int(s["applied"]) > 500, "D 覆寫面数＝overlay の記録＝独立計数（%d／%d）" % [s["applied"], int(cal.get("applied_surfaces"))])
	ok(int(s["roof"]) == int(cal.get("roof_surfaces")) and int(s["roof"]) > 100, "D 屋根（l_rh_*）の覆寫面＝roof 材質（%d／%d）" % [s["roof"], int(cal.get("roof_surfaces"))])
	ok(int(s["elsewhere"]) == 0, "D LOD0 と名簿外の建物に W8 材質 0")
	# 幾何：overlay は mesh を差し替えない（surface override だけ）
	var changed := 0
	for b in all_b:
		for mi in b.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).mesh == null:
				changed += 1
	ok(changed == 0, "D 幾何不変：mesh を持たない MeshInstance3D なし（surface override だけ）")
	# 開閉
	cal.set("enabled", false)
	var s0 := _scan_runtime(false)
	ok(int(s0["bad"]) == 0, "D enabled=false → W7 の状態へ完全還原（K 版／屋根は覆寫なし・W8 材質 0）（不一致 %d%s）" % [s0["bad"], "" if (s0["detail"] as Array).is_empty() else " " + str((s0["detail"] as Array).slice(0, 3))])
	ok(int(cal.get("applied_surfaces")) == 0, "D 還原後 applied_surfaces＝0")
	cal.set("enabled", true)
	var s1 := _scan_runtime(true)
	ok(int(s1["bad"]) == 0 and int(s1["applied"]) == int(s["applied"]), "D enabled=true で同数（%d）に戻る" % int(s1["applied"]))


# ─────────────────────────── N negatives ───────────────────────────
func _first_batch_surface(lod_want: int, roof_want: bool) -> Array:
	for b in all_b:
		if not batch_paths.has(String(v.get_path_to(b))):
			continue
		for mi in b.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null or _lod_of(m) != lod_want:
				continue
			if String(m.name).begins_with(ROOF_PREFIX) != roof_want:
				continue
			for si in m.mesh.get_surface_count():
				var base := m.mesh.surface_get_material(si)
				if base != null and base.resource_path == ATLAS_BASE:
					return [m, si, b]
	return []


func _negatives() -> void:
	print("[W8G] 永久反向（每案必須讓 gate 失敗）")
	var cases_ok := 0
	var total := 0
	quiet = true
	# N1 登記表の shader sha 改竄
	var r1: Dictionary = reg.duplicate(true)
	r1["shader"]["sha256"] = "0".repeat(64)
	total += 1
	var b1 := _check_registry(r1, "n")
	cases_ok += 1 if b1 > 0 else 0
	print("[W8G]   N1 shader sha 改竄：", "PASS（gate 正確失敗）" if b1 > 0 else "FAIL（検出されない）")
	# N2 変体の乗数が範囲外
	var r2: Dictionary = reg.duplicate(true)
	for e: Dictionary in r2["variants"]:
		if String(e["kind"]) == "l1":
			e["params"]["box_mul"] = [3.5, 1.0, 1.0]
			break
	total += 1
	var b2 := _check_registry(r2, "n")
	cases_ok += 1 if b2 > 0 else 0
	print("[W8G]   N2 乗数が範囲外（3.5）：", "PASS（gate 正確失敗）" if b2 > 0 else "FAIL（検出されない）")
	# N3 変体 sha 改竄
	var r3: Dictionary = reg.duplicate(true)
	(r3["variants"] as Array)[0]["sha256"] = "f".repeat(64)
	total += 1
	var b3 := _check_registry(r3, "n")
	cases_ok += 1 if b3 > 0 else 0
	print("[W8G]   N3 変体 sha 改竄：", "PASS（gate 正確失敗）" if b3 > 0 else "FAIL（検出されない）")
	# N4 登記外の材質を LOD1 表面に
	var tgt := _first_batch_surface(1, false)
	var prev: Material = (tgt[0] as MeshInstance3D).get_surface_override_material(int(tgt[1]))
	var rogue := ShaderMaterial.new()
	rogue.shader = load(SHADER)
	(tgt[0] as MeshInstance3D).set_surface_override_material(int(tgt[1]), rogue)
	var s4 := _scan_runtime(true)
	(tgt[0] as MeshInstance3D).set_surface_override_material(int(tgt[1]), prev)
	total += 1
	cases_ok += 1 if int(s4["bad"]) > 0 else 0
	print("[W8G]   N4 登記外の材質を LOD1 表面に：", "PASS（gate 正確失敗）" if int(s4["bad"]) > 0 else "FAIL（検出されない）")
	# N5 LOD0 の atlas 表面に W8 材質
	var f0 := []
	for b in all_b:
		if batch_paths.has(String(v.get_path_to(b))):
			for mi in b.find_children("*", "MeshInstance3D", true, false):
				if _lod_of(mi) == 0 and (mi as MeshInstance3D).mesh != null:
					f0 = [mi, 0]
					break
		if not f0.is_empty():
			break
	var prev0: Material = (f0[0] as MeshInstance3D).get_surface_override_material(0)
	(f0[0] as MeshInstance3D).set_surface_override_material(0, load(String(by_id[String((man["buildings"] as Array)[0]["l1"])]["file"])))
	var s5 := _scan_runtime(true)
	(f0[0] as MeshInstance3D).set_surface_override_material(0, prev0)
	total += 1
	cases_ok += 1 if int(s5["bad"]) > 0 else 0
	print("[W8G]   N5 LOD0 に W8 材質：", "PASS（gate 正確失敗）" if int(s5["bad"]) > 0 else "FAIL（検出されない）")
	# N6 名簿外の建物の LOD1 に W8 材質
	var outsider: MeshInstance3D = null
	for b in all_b:
		if not batch_paths.has(String(v.get_path_to(b))):
			for mi in b.find_children("*", "MeshInstance3D", true, false):
				var mm := mi as MeshInstance3D
				if mm.mesh != null and _lod_of(mm) == 1:
					var bs := mm.mesh.surface_get_material(0)
					if bs != null and bs.resource_path == ATLAS_BASE:
						outsider = mm
						break
		if outsider != null:
			break
	var prevo: Material = outsider.get_surface_override_material(0)
	outsider.set_surface_override_material(0, load(String(by_id[String((man["buildings"] as Array)[0]["l1"])]["file"])))
	var s6 := _scan_runtime(true)
	outsider.set_surface_override_material(0, prevo)
	total += 1
	cases_ok += 1 if int(s6["bad"]) > 0 else 0
	print("[W8G]   N6 名簿外の建物に W8 材質：", "PASS（gate 正確失敗）" if int(s6["bad"]) > 0 else "FAIL（検出されない）")
	# N7 屋根に壁用（l2）材質
	var rt := _first_batch_surface(1, true)
	var prevr: Material = (rt[0] as MeshInstance3D).get_surface_override_material(int(rt[1]))
	(rt[0] as MeshInstance3D).set_surface_override_material(int(rt[1]), load(String(by_id[String((man["buildings"] as Array)[0]["l2"])]["file"])))
	var s7 := _scan_runtime(true)
	(rt[0] as MeshInstance3D).set_surface_override_material(int(rt[1]), prevr)
	total += 1
	cases_ok += 1 if int(s7["bad"]) > 0 else 0
	print("[W8G]   N7 屋根に壁用の材質：", "PASS（gate 正確失敗）" if int(s7["bad"]) > 0 else "FAIL（検出されない）")
	# N8 guard がノードの margin を書き換えた
	var drift := false
	for g in v.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if gi.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED and gi.visibility_range_end_margin > 0.0:
			var old := gi.visibility_range_end_margin
			gi.visibility_range_end_margin = 0.0
			var h := _ranges_hash(v)
			gi.visibility_range_end_margin = old
			drift = h[0] != guard_snapshot_before or h[1] != guard_count_before
			break
	total += 1
	cases_ok += 1 if drift else 0
	print("[W8G]   N8 ノードの margin が書き換わった：", "PASS（gate 正確失敗）" if drift else "FAIL（検出されない）")
	# N9 掛載順：LodCal が AlbedoBatch より前
	var ab := v.get_node("AlbedoBatch1P13")
	var cal := v.get_node("LodCalBatch1P13")
	var ix_ok := cal.get_index() > ab.get_index()
	v.move_child(cal, ab.get_index())
	var wrong := not (cal.get_index() > ab.get_index())
	v.move_child(cal, v.get_child_count() - 1)
	total += 1
	cases_ok += 1 if (ix_ok and wrong) else 0
	print("[W8G]   N9 掛載順が逆（LodCal が AlbedoBatch より前）：", "PASS（gate 正確失敗）" if (ix_ok and wrong) else "FAIL（検出されない）")
	quiet = false
	ok(cases_ok == total, "N 永久反向 %d／%d 案が正しく FAIL" % [cases_ok, total])
