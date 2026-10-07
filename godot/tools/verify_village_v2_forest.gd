extends SceneTree
## 人間之里 V2 P9 R2 Forest Belts：規劃＋local gate＋烘焙＋掛進場景。
##   規劃＋gate（唯讀）：Godot --headless --path godot --script res://tools/verify_village_v2_forest.gd
##   烘焙 overlay：     Godot --path godot --script res://tools/verify_village_v2_forest.gd -- --build
##                     （MultiMesh 實例資料在 headless dummy RenderingServer 存不下來 → 非 headless）
##   掛進場景：         Godot --headless --path godot --script res://tools/verify_village_v2_forest.gd -- --attach
##                     （village_v2.tscn 文字層級替換：移除 6 塊 Forest_* placeholder 與其網格引用，加 ForestP9 instance；
##                       先確認沒有 Godot 編輯器開著這個場景）
##   反向：             -- --neg=hinoki|uniform|float|road|sightline（各自瞄準一項，必須讓那一項 FAIL）
##   封存：             -- --seal（data/village_v2_p9r2_seal.json：規劃器／gate／overlay／掛載場景／ART_REVIEW 總表／證據 sha256＋記憶體竄改反向）
## 每項一行 [FOREST] PASS/FAIL；INFO 不計失敗；結尾 quit(失敗項數)。

const FLib := preload("res://tools/village_v2_forest_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const REPORT := "res://data/village_v2_p9r2_forest.json"
const SEAL := "res://data/village_v2_p9r2_seal.json"

## 天際線量測機位（主要村道／入口／農田／河岸各一）：[名稱, cam, look]
const SKY_CAMS := [
	["村道 主街北望", Vector3(241, 2.91, 44), Vector3(276, 4.32, -70)],
	["入口 南大鳥居北望", Vector3(229, 2.7, 132), Vector3(240, 3.66, 40)],
	["農田 望北丘", Vector3(420, 2.1, 70), Vector3(300, 9.8, -150)],
	["河岸 主河北岸望北丘", Vector3(430, 1.8, -128), Vector3(262, 20.0, -226)],
]

var fails := 0
var neg := ""
var failed_labels: Array = []
var quiet := false


func check(label: String, ok: bool) -> void:
	if not quiet:
		print("[FOREST] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
		failed_labels.append(label)


func info(label: String) -> void:
	if not quiet:
		print("[FOREST] INFO " + label)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for a: String in args:
		if a.begins_with("--neg="):
			neg = a.trim_prefix("--neg=")
	if "--attach" in args:
		quit(_attach())
		return
	if "--seal" in args:
		quit(_seal())
		return
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	# 場景已掛 ForestP9 時先拿掉（規劃只看地形／地標；不拿掉的話 --build 會同時存在新舊兩份 overlay，instance uniform 緩衝爆掉）
	var old := v.get_node_or_null("Vegetation/" + FLib.NODE_NAME)
	if old:
		old.get_parent().remove_child(old)
		old.free()
	var opts := _sight_opts(v, L)
	var P: Dictionary = FLib.plan(v, L, opts)
	var items: Array = P["items"]
	var C: FLib.Ctx = P["ctx"]
	if "--negatives" in args:
		# 永久反向（回歸用）：同一份規劃，5 案各自注入，瞄準項必須 FAIL；全部如預期＝exit 0
		var target := {"hinoki": "檜 secondary", "uniform": "非均勻", "float": "接地", "road": "禁區", "sightline": "視線"}
		var bad := 0
		for nm: String in target:
			var cp: Array = []
			for it: Dictionary in items:
				cp.append(it.duplicate())
			neg = nm
			fails = 0
			failed_labels.clear()
			quiet = true
			_inject(cp, C, opts)
			_checks(cp, C, opts)
			quiet = false
			var hit := failed_labels.any(func(l: String) -> bool: return l.begins_with(String(target[nm])))
			print("[FOREST] %s 反向 %-9s → 瞄準「%s」%s（本案共 %d 項 FAIL）" % ["OK" if hit else "NG", nm, target[nm], "FAIL" if hit else "未 FAIL", fails])
			if not hit:
				bad += 1
		v.free()
		print("[FOREST] 結果：反向 %d 案不符預期" % bad)
		quit(bad)
		return
	info("規劃 %d ms（遮罩 %d ms）：林冠層 %d 棵、次林層 %d、林帶外坡地 喬木 %d／灌木 %d（視線：降級 %d／移除 %d、林內草地 %d、層級上限 %d、坡度 %d、無地面 %d），總計 %d 件" % [
		P["ms"], P["mask_ms"], P["n_canopy"], P["n_sub"], P["n_slope"], P["n_slope_shrub"], int(P["dropped"].get("sight_lowered", 0)), P["dropped"]["sightline"], P["dropped"]["meadow"],
		P["dropped"]["sky"], P["dropped"]["slope"], P["dropped"]["ground"], items.size()])
	_inject(items, C, opts)
	var rep := _checks(items, C, opts)
	if neg != "":
		print("[FOREST] negative=%s 失敗 %d 項" % [neg, fails])
		v.free()
		quit(fails)
		return
	if "--build" in args and fails == 0:
		if DisplayServer.get_name() == "headless":
			check("--build 需要非 headless（MultiMesh 實例資料）", false)
		else:
			var root := FLib.bake(items)
			FLib.own(root, root)
			var ps := PackedScene.new()
			check("pack overlay", ps.pack(root) == OK)
			var e := ResourceSaver.save(ps, FLib.OUTPUT, ResourceSaver.FLAG_COMPRESS)
			check("save %s" % FLib.OUTPUT, e == OK)
			rep["overlay"] = {"path": FLib.OUTPUT, "mb": FileAccess.get_file_as_bytes(FLib.OUTPUT).size() / 1048576.0,
				"near_mesh_nodes": root.get_meta("near_mesh_nodes"), "multimesh_nodes": root.get_meta("multimesh_nodes"),
				"trunk_shapes": root.get_meta("trunk_shapes")}
			info("overlay %.1f MB、近級逐棵 MeshInstance %d、遠級 MultiMesh 節點 %d、樹幹碰撞 %d" % [rep["overlay"]["mb"],
				rep["overlay"]["near_mesh_nodes"], rep["overlay"]["multimesh_nodes"], rep["overlay"]["trunk_shapes"]])
			root.free()
			var f := FileAccess.open(REPORT, FileAccess.WRITE)
			f.store_string(JSON.stringify(rep, "  ", false))
			f.close()
	v.free()
	print("[FOREST] 結果：%d 項失敗" % fails)
	quit(fails)


## 視線目標（山頂社殿頂、參道鳥居笠木）與視點（主街／入口道／丘腳街每 8 m，眼高 1.7 m）
func _sight_opts(v: Node3D, L: Dictionary) -> Dictionary:
	var S := RLib.terrain_sampler(v)
	var targets: Array = []
	for pair: Array in [["山頂社殿", "Landmarks/LANDMARK_NORTH_HILL"], ["參道鳥居", "Landmarks/LANDMARK_HILL_TORII"]]:
		var n := v.get_node_or_null(String(pair[1]))
		if n == null:
			continue
		var box := AABB()
		var first := true
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).mesh == null:
				continue
			var ab: AABB = RLib.rel_xf(mi, v) * (mi as MeshInstance3D).mesh.get_aabb()
			if ab.size.y < 0.3:
				continue
			box = ab if first else box.merge(ab)
			first = false
		if not first:
			targets.append([pair[0], Vector3(box.get_center().x, box.end.y - 0.3, box.get_center().z)])
			if pair[0] == "山頂社殿":
				# 社殿屋身（簷口高度）：參道上看社殿不能只露屋脊尖（plan 對 approach 視點檢查 targets[0]，這裡另加一條到屋身）
				targets.append(["山頂社殿屋身", Vector3(box.get_center().x, box.end.y - 4.0, box.get_center().z)])
	var st := PackedVector3Array()
	var ap := PackedVector3Array()
	for r: Dictionary in L["roads"]:
		if String(r["name"]) == "HillApproach":
			# 參道（丘腳→山頂）：每 6 m 一個 1.7 m 眼高視點，只檢查望山頂社殿
			var pa: Array = r["pts"]
			for i in pa.size() - 1:
				var a := Vector2(float(pa[i][0]), float(pa[i][1]))
				var b := Vector2(float(pa[i + 1][0]), float(pa[i + 1][1]))
				var n := maxi(1, int(a.distance_to(b) / 6.0))
				for k in n:
					var q := a.lerp(b, float(k) / n)
					var h := S.h(q.x, q.y)
					if not is_nan(h):
						ap.append(Vector3(q.x, h + 1.7, q.y))
		if not String(r["name"]) in ["MainStreet", "EntranceRoad", "HillFootStreet"]:
			continue
		var pts: Array = r["pts"]
		for i in pts.size() - 1:
			var a := Vector2(float(pts[i][0]), float(pts[i][1]))
			var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
			var n := maxi(1, int(a.distance_to(b) / 8.0))
			for k in n:
				var p := a.lerp(b, float(k) / n)
				var h := S.h(p.x, p.y)
				if not is_nan(h):
					st.append(Vector3(p.x, h + 1.7, p.y))
	return {"targets": targets, "stations": st, "approach": ap}


## 反向案例（只改記憶體裡的規劃結果）
func _inject(items: Array, C: FLib.Ctx, opts: Dictionary) -> void:
	match neg:
		"hinoki":
			for it: Dictionary in items:
				if String(it["id"]).begins_with("sugi") and String(it["layer"]) == "canopy":
					it["id"] = "hinoki_a"
		"uniform":
			# 林冠位置改成林地內的規則格（每 8 m 一棵、等距植樹）＝均勻 scatter
			var grid_p: Array = []
			for j in range(0, C.nz, 4):
				for i in range(0, C.nx, 4):
					if C.belt_of[j * C.nx + i] >= 0:
						grid_p.append(FLib.cell_p(C, i, j))
			var cn: Array = items.filter(func(it: Dictionary) -> bool: return String(it["layer"]) in ["canopy", "edge"])
			for k in mini(cn.size(), grid_p.size()):
				(cn[k] as Dictionary)["p"] = grid_p[k]
				(cn[k] as Dictionary)["y"] = C.S.h(grid_p[k].x, grid_p[k].y) - FLib.EMBED
			for k in range(grid_p.size(), cn.size()):
				items.erase(cn[k])
		"float":
			items[items.size() / 2]["y"] = float(items[items.size() / 2]["y"]) + 0.5
		"road":
			for r: Dictionary in C.L["roads"]:
				if String(r["name"]) == "HillApproach":
					items[0]["p"] = Vector2(float(r["pts"][1][0]), float(r["pts"][1][1]))
		"sightline":
			# 在「山頂社殿」視線上、離社殿 25 m 的丘坡（林帶內）種一棵杉
			var t: Vector3 = opts["targets"][0][1]
			var s: Vector3 = opts["stations"][0]
			var dir := (Vector2(s.x, s.z) - Vector2(t.x, t.z)).normalized()
			var p := Vector2(t.x, t.z) + dir * 25.0
			items.append({"id": "sugi_a", "p": p, "y": C.S.h(p.x, p.y) - FLib.EMBED, "yaw": 0.0, "sc": 1.0, "lean": 0.0, "lean_dir": 0.0,
				"layer": "canopy", "belt": "Forest_HillCrown", "de": 30.0, "rad": 3.0, "tone": 0.5, "preset": "mature"})


func _checks(items: Array, C: FLib.Ctx, opts: Dictionary) -> Dictionary:
	var M := FLib.modules()
	var rep := {"date": Time.get_datetime_string_from_system(), "trees": items.size()}
	# ── 1 禁區（樹幹落點重驗）
	var bad := {}
	for it: Dictionary in items:
		var why := FLib.blocked(C, it["p"])
		if why != "":
			bad[why] = int(bad.get(why, 0)) + 1
	check("禁區：%d 件樹幹落點全在林地內（建成區 +%.0f／農田 +%.0f／道路半寬 +%.0f／主河 +%.0f／水渠溪 +%.0f／整平區 +%.0f／鳥居龍神像 %.0f m）；違規 %s" % [
		items.size(), FLib.M_BUILT, FLib.M_FARM, FLib.M_ROAD, FLib.M_RIVER, FLib.M_CHANNEL, FLib.M_PAD, FLib.M_MARK, str(bad)], bad.is_empty())
	# ── 2 接地：根盤環 8 點＋中心；不得浮空（y ≤ 環上最低地面）、中心埋深 ≤ 1.3 m
	var floating := 0
	var deep := 0
	var worst_f := 0.0
	var worst_d := 0.0
	for it: Dictionary in items:
		var p: Vector2 = it["p"]
		var rr := clampf(float(M[it["id"]]["dbh_m"]) * float(it["sc"]) * 0.7, 0.15, 1.0)
		var lo := INF
		for k in 8:
			var h := C.S.h(p.x + cos(k * TAU / 8.0) * rr, p.y + sin(k * TAU / 8.0) * rr)
			if not is_nan(h):
				lo = minf(lo, h)
		var hc := C.S.h(p.x, p.y)
		lo = minf(lo, hc)
		var y := float(it["y"])
		if y > lo + 0.01:
			floating += 1
			worst_f = maxf(worst_f, y - lo)
		if hc - y > 1.3:
			deep += 1
		worst_d = maxf(worst_d, hc - y)
	check("接地：浮空 %d 件（最大 %.2f m）、中心埋深 > 1.3 m %d 件（最大 %.2f m）" % [floating, worst_f, deep, worst_d],
		floating == 0 and deep == 0)
	# ── 3 檜＝secondary：各林帶 檜／針葉 ≤ 15 %、全區 3–15 %；林緣 ≥ 18 m；不在林緣層
	var conif := {}
	var hin := {}
	var hin_edge := 0
	for it: Dictionary in items:
		var tid := String(it["id"])
		if not tid in FLib.CONIFERS:
			continue
		var b := String(it["belt"])
		conif[b] = int(conif.get(b, 0)) + 1
		if tid in FLib.HINOKI:
			hin[b] = int(hin.get(b, 0)) + 1
			if float(it["de"]) < FLib.HINOKI_MIN_EDGE or String(it["layer"]) != "canopy":
				hin_edge += 1
	var tot_c := 0
	var tot_h := 0
	var per := []
	var per_ok := true
	for b: String in conif:
		tot_c += int(conif[b])
		tot_h += int(hin.get(b, 0))
		var r := float(hin.get(b, 0)) / maxf(1.0, float(conif[b]))
		per.append("%s %.0f%%/%d" % [b.trim_prefix("Forest_"), r * 100.0, conif[b]])
		if int(conif[b]) >= 40:
			per_ok = per_ok and r <= 0.15
	var share := float(tot_h) / maxf(1.0, float(tot_c))
	check("檜 secondary：檜／針葉 全區 %.1f %%（5–15 %%）、各林帶 ≤ 15 %%（%s；針葉 ≥ 40 棵才計）、林緣 < %.0f m 或非林冠層 %d 棵" % [
		share * 100.0, ", ".join(per), FLib.HINOKI_MIN_EDGE, hin_edge], per_ok and share >= 0.05 and share <= 0.15 and hin_edge == 0)
	rep["hinoki_share"] = share
	# ── 4 非均勻散佈＋不是杉綠牆
	var cn: Array = items.filter(func(it: Dictionary) -> bool: return String(it["layer"]) in ["canopy", "edge"])
	var ce := _clark_evans(cn, C)
	var cv := _density_cv(cn, 24.0, C)
	var sugi := 0
	var sugi_edge := 0
	var n_edge := 0
	var species := {}
	for it: Dictionary in cn:
		var tid := String(it["id"])
		species[tid] = int(species.get(tid, 0)) + 1
		if tid.begins_with("sugi"):
			sugi += 1
		if String(it["layer"]) == "edge":
			n_edge += 1
			if tid.begins_with("sugi"):
				sugi_edge += 1
	var sugi_r := float(sugi) / maxf(1.0, float(cn.size()))
	var sugi_er := float(sugi_edge) / maxf(1.0, float(n_edge))
	check("非均勻：林冠 Clark–Evans R = %.2f（規則格 ≈ 2.1；需 ≤ 1.45）、24 m 格密度變異係數 %.2f（需 ≥ 0.30）" % [ce, cv],
		ce <= 1.45 and cv >= 0.30)
	check("不是杉綠牆：林冠杉佔 %.0f %%（≤ 45 %%）、林緣層杉佔 %.0f %%（≤ 15 %%）" % [sugi_r * 100.0, sugi_er * 100.0],
		sugi_r <= 0.45 and sugi_er <= 0.15)
	rep["species_canopy"] = species
	rep["clark_evans"] = ce
	rep["density_cv"] = cv
	# ── 5 視線：主街／入口道／丘腳街（眼高 1.7 m）望山頂社殿頂、參道鳥居，林冠擋住的站數＝0
	var blk := 0
	var who := {}
	for it: Dictionary in items:
		if String(it["layer"]) in ["under", "dead"]:
			continue
		for t: Array in opts["targets"]:
			if FLib._blocks(it, M, [t], opts["stations"]):
				blk += 1
				who[t[0]] = int(who.get(t[0], 0)) + 1
		if not (opts["approach"] as PackedVector3Array).is_empty() and FLib._blocks(it, M, [opts["targets"][0], opts["targets"][1]], opts["approach"]):
			blk += 1
			who["參道→社殿"] = int(who.get("參道→社殿", 0)) + 1
	check("視線：村道 %d 視點 × %d 目標（%s）＋參道 %d 視點 → 社殿，擋住視線的樹 %d 棵 %s" % [(opts["stations"] as PackedVector3Array).size(),
		(opts["targets"] as Array).size(), ", ".join((opts["targets"] as Array).map(func(t: Array) -> String: return String(t[0]))),
		(opts["approach"] as PackedVector3Array).size(), blk, str(who)], blk == 0 and (opts["targets"] as Array).size() == 3)
	# ── 6 天際線（INFO：東次峰約主峰 70–80 %，75 % 只是構圖 reference）
	var sky := []
	for cam: Array in SKY_CAMS:
		var prof := FLib.skyline(C, items, cam[1], cam[2])
		var rt := FLib.hill_ratios(C, prof, cam[1], "terrain")
		var ra := FLib.hill_ratios(C, prof, cam[1], "all")
		sky.append({"cam": cam[0], "terrain": rt["ratio"], "with_forest": ra["ratio"], "deg": ra["deg"]})
		info("天際線 %s：純地形 西肩 %.0f%%／東次峰 %.0f%%（主峰 %.1f°）；含林冠 西肩 %.0f%%／東次峰 %.0f%%（主峰 %.1f°）" % [cam[0],
			float(rt["ratio"].get("西肩", 0)) * 100, float(rt["ratio"].get("東次峰", 0)) * 100, float(rt["deg"]["主峰"]),
			float(ra["ratio"].get("西肩", 0)) * 100, float(ra["ratio"].get("東次峰", 0)) * 100, float(ra["deg"]["主峰"])])
		# 林冠不能把丘頭補平（村內兩個由南望機位）：含林冠後主峰最高、西肩 ≤ 88 %、東次峰 65–85 %
		# （概念圖由南望 西肩 56 %／東次峰 75 %；林冠在每個丘頭都加同樣的十幾公尺，比例必然往 100 % 壓縮，所以門檻不是概念值本身）
		if String(cam[0]).begins_with("村道") or String(cam[0]).begins_with("入口"):
			var rw := float(ra["ratio"].get("西肩", 0))
			var re := float(ra["ratio"].get("東次峰", 0))
			check("天際線層級（%s）：主峰最高、西肩 %.0f %%（≤ 88）、東次峰 %.0f %%（65–85）" % [cam[0], rw * 100, re * 100],
				rw <= 0.88 and re >= 0.65 and re <= 0.85)
	rep["skyline"] = sky
	# ── 7 統計（INFO）
	var layers := {}
	var tris0 := 0
	for it: Dictionary in items:
		layers[it["layer"]] = int(layers.get(it["layer"], 0)) + 1
		tris0 += int(M[it["id"]]["lods"][0]["tris"]) if M[it["id"]].has("lods") else 0
	var belts := {}
	for it: Dictionary in items:
		belts[it["belt"]] = int(belts.get(it["belt"], 0)) + 1
	info("層：%s；林帶：%s；全部 LOD0 三角面總和 %d（只是規模參考，實際只有 30 m 內畫 LOD0）" % [str(layers), str(belts), tris0])
	var sp := species.keys()
	sp.sort_custom(func(a: String, b: String) -> bool: return int(species[a]) > int(species[b]))
	info("林冠樹種：%s" % ", ".join(sp.map(func(k: String) -> String: return "%s %d" % [k, species[k]])))
	rep["layers"] = layers
	rep["belts"] = belts
	var nn := FLib.node_count(items)
	var buf := int(ProjectSettings.get_setting("rendering/limits/global_shader_variables/buffer_size", 65536))
	check("instance uniform 節點：%d 個（近級逐棵＋遠級分組；≤ %d，且 × 16 ≤ project buffer_size %d 的 80 %%）" % [nn, FLib.MAX_NODES, buf],
		nn <= FLib.MAX_NODES and nn * 16 <= buf * 0.8)
	rep["instance_uniform_nodes"] = nn
	return rep


## Clark–Evans 最近鄰比（只算距林地邊 > 10 m 的點，避開邊界效應）
func _clark_evans(pts: Array, C: FLib.Ctx) -> float:
	var grid := {}
	for k in pts.size():
		var p: Vector2 = pts[k]["p"]
		var c := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
		if not grid.has(c):
			grid[c] = []
		(grid[c] as Array).append(k)
	var sum := 0.0
	var n := 0
	for k in pts.size():
		var p: Vector2 = pts[k]["p"]
		if FLib.edge_at(C, p) < 10.0:
			continue
		var c := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
		var best := INF
		for dj in range(-2, 3):
			for di in range(-2, 3):
				for j: int in grid.get(c + Vector2i(di, dj), []):
					if j != k:
						best = minf(best, p.distance_to(pts[j]["p"]))
		if best < INF:
			sum += best
			n += 1
	if n == 0:
		return 0.0
	# 林地面積（遮罩格數 × 格面積）
	var area := 0.0
	for k in C.nx * C.nz:
		if C.belt_of[k] >= 0:
			area += FLib.CELL * FLib.CELL
	var dens := float(pts.size()) / maxf(area, 1.0)
	return (sum / n) / (0.5 / sqrt(dens))


func _density_cv(pts: Array, cell: float, C: FLib.Ctx) -> float:
	var cnt := {}
	for it: Dictionary in pts:
		var p: Vector2 = it["p"]
		var c := Vector2i(floori(p.x / cell), floori(p.y / cell))
		cnt[c] = int(cnt.get(c, 0)) + 1
	# 只算林地覆蓋 ≥ 80 % 的格
	var vals: Array = []
	for c: Vector2i in cnt:
		var inside := 0
		var tot := 0
		var x := c.x * cell + 1.0
		while x < (c.x + 1) * cell:
			var z := c.y * cell + 1.0
			while z < (c.y + 1) * cell:
				tot += 1
				if FLib.belt_at(C, Vector2(x, z)) >= 0:
					inside += 1
				z += 2.0
			x += 2.0
		if tot > 0 and float(inside) / tot >= 0.8:
			vals.append(float(cnt[c]))
	if vals.size() < 2:
		return 0.0
	var m := 0.0
	for x: float in vals:
		m += x
	m /= vals.size()
	var s := 0.0
	for x: float in vals:
		s += (x - m) * (x - m)
	return sqrt(s / (vals.size() - 1)) / maxf(m, 1e-6)


## village_v2.tscn 文字層級替換（最小差異）：移除 6 塊 Forest_* placeholder 節點、其 canopy 網格 ext_resource 與只被它們用的材質；
## 加一個 ForestP9 instance（Vegetation 底下）。
func _attach() -> int:
	var path := ProjectSettings.globalize_path(SCENE)
	var txt := FileAccess.get_file_as_string(SCENE)
	if txt.is_empty():
		push_error("讀不到 " + SCENE)
		return 1
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	var out := PackedStringArray()
	var drop_ids := {}
	var mat_ids := {}
	# 先找 placeholder 節點用到的 ext／sub resource id
	var i := 0
	while i < lines.size():
		var ln := lines[i]
		if ln.begins_with("[node name=\"Forest_") and ln.contains("parent=\"Vegetation\""):
			var j := i + 1
			while j < lines.size() and not lines[j].begins_with("["):
				var m := RegEx.create_from_string("ExtResource\\(\"([^\"]+)\"\\)").search(lines[j])
				if m != null:
					drop_ids[m.get_string(1)] = true
				var s := RegEx.create_from_string("SubResource\\(\"([^\"]+)\"\\)").search(lines[j])
				if s != null:
					mat_ids[s.get_string(1)] = true
				j += 1
		i += 1
	# 材質只在 placeholder 用才移除
	# （6 塊 placeholder 各引用 1 次；別處還有引用就保留）
	for sid: String in mat_ids.keys():
		if txt.count("SubResource(\"%s\")" % sid) > 6:
			mat_ids.erase(sid)
	if txt.contains("gen/forest_p9.scn"):
		push_error("已經掛過 ForestP9")
		return 1
	var n_removed := 0
	i = 0
	var veg_done := false
	while i < lines.size():
		var ln := lines[i]
		var skip_block := false
		if ln.begins_with("[node name=\"Forest_") and ln.contains("parent=\"Vegetation\""):
			skip_block = true
			n_removed += 1
		elif ln.begins_with("[ext_resource"):
			var m := RegEx.create_from_string(" id=\"([^\"]+)\"\\]").search(ln)
			if m != null and drop_ids.has(m.get_string(1)):
				i += 1
				continue
		elif ln.begins_with("[sub_resource"):
			var m := RegEx.create_from_string(" id=\"([^\"]+)\"\\]").search(ln)
			if m != null and mat_ids.has(m.get_string(1)):
				skip_block = true
		if skip_block:
			i += 1
			while i < lines.size() and not lines[i].begins_with("["):
				i += 1
			continue
		out.append(ln)
		if ln.begins_with("[node name=\"Vegetation\"") and not veg_done:
			# 節點區塊之後插入
			i += 1
			while i < lines.size() and not lines[i].begins_with("["):
				out.append(lines[i])
				i += 1
			out.append("[node name=\"ForestP9\" parent=\"Vegetation\" instance=ExtResource(\"p9r2_forest\")]")
			out.append("")
			veg_done = true
			continue
		i += 1
	# ext_resource 插在最後一個 ext_resource 之後
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p9r2_forest\"]" % FLib.OUTPUT)
	# load_steps 不存在於 format=3 header（本檔 header 沒有）；直接寫回
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[FOREST] attach：移除 placeholder 節點 %d、ext_resource %d、sub_resource %d；加 ForestP9 → %s" % [
		n_removed, drop_ids.size(), mat_ids.size(), path])
	return 0 if n_removed == 6 and veg_done else 1


# ─────────────────────────── 封存（--seal，P9 R2 ART_APPROVED 2026-10-02） ───────────────────────────

func _seal_mismatch(seal: Dictionary) -> PackedStringArray:
	var repo := (ProjectSettings.globalize_path("res://") + "..").simplify_path() + "/"
	var docs := repo + "docs/art_review/village_v2_p9_vegetation/"
	var bad := PackedStringArray()
	for grp: String in ["frozen", "art_review_images", "evidence"]:
		var d: Dictionary = seal[grp]
		for k: String in d:
			var path: String = (repo + k) if grp == "frozen" else (docs + k)
			if not FileAccess.file_exists(path):
				bad.append("%s 不存在" % k)
			elif FileAccess.get_sha256(path) != String(d[k]):
				bad.append("%s 雜湊變了" % k)
	return bad


func _seal() -> int:
	var seal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SEAL))
	var bad := _seal_mismatch(seal)
	var n: int = seal["frozen"].size() + seal["art_review_images"].size() + seal["evidence"].size()
	check("P9 R2 封存 %d 檔雜湊一致（凍結 %d、ART_REVIEW 總表 %d、證據 %d；不符 %d：%s）" % [n, seal["frozen"].size(),
		seal["art_review_images"].size(), seal["evidence"].size(), bad.size(), ", ".join(bad.slice(0, 4))], bad.is_empty())
	var neg_seal := seal.duplicate(true)
	var k0: String = neg_seal["frozen"].keys()[0]
	neg_seal["frozen"][k0] = "0".repeat(64)
	var nb := _seal_mismatch(neg_seal)
	check("反向：竄改 %s 期望雜湊 → 偵測到 1 筆不符（實際 %d）" % [k0, nb.size() - bad.size()], nb.size() == bad.size() + 1)
	print("[FOREST] 結果：%d 項失敗（seal）" % fails)
	return fails
