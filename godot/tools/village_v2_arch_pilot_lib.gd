extends RefCounted
## 人間之里 V2 P13 WAVE 1／1B — Architectural Diversity Pilot（主街中段 11 棟）＋ 農家 A1／A2 預覽。
##
## 根因（W1 調査）：187 棟町家は同一 P6 Kit が P4 灰盒紀錄から組立；P4 は高さ 3 種、主街 39 棟は全て平入。
## W1B（使用者裁定 2026-10-12）：妻入は 11 棟中 3 棟（角地店 003・蔵造住居 010・工坊 020）に絞る。平入 8 棟は屋根勾配・
##   棟偏り・本卯建・小山牆・2F 退縮・庇の種類・正面の開口構成で差をつける（色替えだけにしない）。
##   MKT_010：住居化——入口以外の 1F 開口を壁＋小窓へ差し替え、門前帶の店前踏段（fr_dan、MeshInstance のみ・碰撞なし）を預覽中だけ隠す。
##   MKT_006：竹籠工房——暖簾を外し、開いた店先の奥に作業台・桶（既存 street_kit）を置く（建物碰撞箱の内側）。
## 既存 Kit 構件・材質のみ（農家の茅葺だけ預覽用の手続き材質）。P4 寬深・位置・碰撞・入口・StreetP10・NPC は不変。
## KLib の共用計畫 dict は build の間だけ書き換え、直後に元へ戻す（同一プロセスの他生成を汚さない）。
## 出力：gen/arch_pilot_p13.scn（root＝ArchPilotP13；runtime が元の可視状態を記録して切替、OFF で元へ戻す）。

const KLib := preload("res://tools/village_v2_machiya_kit_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const GREYBOX := "res://maps/village_v2/gen/greybox.json"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const OUTPUT := "res://maps/village_v2/gen/arch_pilot_p13.scn"
const RUNTIME := "res://maps/village_v2/scripts_p13/arch_pilot.gd"
const NODE_NAME := "ArchPilotP13"
const ST_MESH := "res://assets/village_v2/street_kit/mesh/"
const MAT := "res://assets/village_v2/_matlib/"
const EAVE := {"hiraya": 2.9, "zushi": 3.9, "nikai": 5.4}
const P := 0.45

const PILOT := {
	"B_P_MKT_003": {"cat": "妻入りの店（角地・厨子）", "tsuma": true,
		"pl": {"theme": "mixed", "up": "mushi", "sign": "side", "kemuri": false}},
	"B_P_MKT_005": {"cat": "大店（両端本卯建・小山牆・屋根看板）",
		"pl": {"roof": "low", "udh": [-1.0, 1.0], "dormer": true, "sign": "roof", "theme": "bengara", "up": "winb", "sb": false, "fin": 1, "tone": 0}},
	"B_P_MKT_006": {"cat": "竹籠工房（開け放し・煙出し・板庇・作業台）", "workshop": true,
		"pl": {"theme": "open", "kemuri": true, "his_wood": true, "roof": "offb2", "sign": "", "up": "plain", "cut": true, "rec": "none", "rec_d": 0.0}},
	"B_P_MKT_007": {"cat": "二階店（棟偏後・板庇・袖看板）",
		"pl": {"roof": "offb", "sb": false, "his_wood": true, "theme": "lattice", "up": "win", "sign": "side", "udh": [], "dormer": false}},
	"B_P_MKT_008": {"cat": "平屋住宅（緩勾配・出簷浅・煙出し）",
		"pl": {"roof": "flat", "kemuri": true, "kiri": true, "theme": "koshib", "cut": true, "udh": [], "dormer": false}},
	"B_P_MKT_009": {"cat": "二階退縮の店（片卯建）",
		"pl": {"roof": "low", "sb": true, "udh": [1.0], "theme": "lattice", "up": "amado"}},
	"B_P_MKT_010": {"cat": "蔵造りの住居（妻入・閉じた正面）", "tsuma": true, "residence": true,
		"pl": {"fin": 0, "tone": 2, "theme": "amado", "up": "plain", "up_period": 0, "kiri": true, "inuyarai": true, "kemuri": false, "sign": ""}},
	"B_P_MKT_018": {"cat": "厨子二階の住宅（平屋から上げる・虫籠窓）", "type": "zushi",
		"pl": {"up": "mushi", "up_period": 0, "theme": "koshi", "kemuri": true, "roof": "std"}},
	"B_P_MKT_019": {"cat": "質素な商家（2F 退縮・板庇・棟偏後）",
		"pl": {"roof": "offb2", "sb": true, "his_wood": true, "theme": "open", "up": "amado"}},
	"B_P_MKT_020": {"cat": "妻入りの工坊（煙出し）", "tsuma": true,
		"pl": {"theme": "open", "kemuri": true, "his_wood": true, "up": "plain"}},
	"B_P_MKT_021": {"cat": "大店（2F 退縮・片卯建・袖看板）",
		"pl": {"roof": "offf", "udh": [-1.0], "sb": true, "sign": "side", "theme": "bengara", "up": "wins"}},
}

## 農家（W1B 再選址；tools/p13/farm_sites_v2.py で幾何判定、probe_farm_sites_v2.gd で実景確認）：
## [名, 中心 x, z, 本体 x 幅, z 奥]。棟は z 沿い、正面＝+x（東の T0 田・FarmPath_5 側）。
const FARM := [["A1_noka", 318.0, 82.0, 6.4, 9.1], ["A2_naya", 323.0, 71.0, 3.6, 5.5]]


static func greybox_recs() -> Dictionary:
	var G: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GREYBOX))
	var by := {}
	for b: Dictionary in G["buildings"]:
		by[String(b["id"])] = b
	return by


## P4 紀錄の Pilot 版（元 rec は変更しない）
static func pilot_rec(rec: Dictionary) -> Dictionary:
	var o: Dictionary = PILOT[String(rec["id"])]
	var r := rec.duplicate(true)
	if o.has("type"):
		var t := String(o["type"])
		assert(float(EAVE[t]) >= float(rec["eave_m"]), "P13 Pilot：簷を下げない（%s）" % rec["id"])
		r["type"] = t
		r["eave_m"] = float(EAVE[t])
	if bool(o.get("residence", false)):
		r["hisashi_m"] = 0.0
		r["hisashi_depth_m"] = 0.0
	if bool(o.get("tsuma", false)):
		r["roof"] = "tsuma"
		r["ov_gable_m"] = 0.3
		r["ov_eave_m"] = 0.05
	var half := (float(r["depth_m"]) if String(r["roof"]) == "hira" else float(r["width_m"])) * 0.5
	r["ridge_m"] = float(r["eave_m"]) + P * half
	return r


## KLib の共用計畫 dict を build の間だけ書き換え、元へ戻す
static func _with_plan(rec: Dictionary, f: Callable) -> Variant:
	var pl := KLib.plan_for(rec)
	var keep := pl.duplicate(true)
	var o: Dictionary = PILOT[String(rec["id"])]
	if bool(o.get("tsuma", false)):
		pl["roof"] = "std"
		pl["udh"] = []
		pl["dormer"] = false
		pl["sb"] = false
		pl["udatsu"] = -1
		pl["gyo"] = [1.0]
	if bool(o.get("residence", false)):
		pl["sb"] = false
		pl["his_wood"] = false
		pl["udatsu"] = -1
		pl["rec"] = "none"
		pl["rec_d"] = 0.0
	for k: String in o["pl"]:
		pl[k] = o["pl"][k]
	var out: Variant = f.call()
	pl.clear()
	pl.merge(keep)
	return out


## 1F 正面構件の差し替え（住居化）：入口以外の開間 → 壁／小窓を交互。LOD1 外殻も住宅型へ。
static func _residential_front(kit: Node3D, lib: Dictionary) -> int:
	var n := 0
	var re := RegEx.create_from_string("^f1_([a-z_]+?)_(\\d+)_(h\\d+)(_c\\d)?_(\\d+)$")
	var alt := 0
	for mi: MeshInstance3D in kit.get_node("LOD0").get_children():
		var m := re.search(String(mi.name))
		if m == null or m.get_string(1) == "door":
			continue
		var kind := "mado" if alt % 2 == 1 else "plain"
		alt += 1
		var nm := "f1_%s_%s_%s%s" % [kind, m.get_string(2), m.get_string(3), m.get_string(4)]
		if lib.has(nm):
			mi.mesh = lib[nm]
			n += 1
	for mi: MeshInstance3D in kit.get_node("LOD1").get_children():
		var s := String(mi.name)
		if s.begins_with("l_f1_") and not s.begins_with("l_f1_res"):
			var h := "h27" if s.contains("h27") else "h29"
			if lib.has("l_f1_res_" + h):
				mi.mesh = lib["l_f1_res_" + h]
				n += 1
	return n


## 工房：暖簾を外し、開いた店先の奥に作業台・桶（street_kit 既存）を置く。建物碰撞箱の内側。
static func _workshop(kit: Node3D, rec: Dictionary) -> int:
	var n := 0
	for mi: MeshInstance3D in kit.get_node("LOD0").get_children():
		if String(mi.name).begins_with("nr_"):
			mi.visible = false
			n += 1
	var xs: Array = kit.get_meta("bay_x")
	var kinds: Array = kit.get_meta("bay_kind")
	var zf := float(rec["depth_m"]) * 0.5 - 0.95
	var props := ["st_daiku", "st_okeya"]
	var pi := 0
	for i in kinds.size():
		if pi >= props.size():
			break
		if String(kinds[i]).begins_with("shop"):
			var cx := (float(xs[i]) + float(xs[i + 1])) * 0.5
			var mi := MeshInstance3D.new()
			mi.name = "p13_work_%s" % props[pi]
			mi.mesh = load(ST_MESH + props[pi] + ".res")
			mi.transform = Transform3D(Basis.IDENTITY, Vector3(cx, KLib.FL, zf))
			mi.visibility_range_end = 40.0
			kit.get_node("LOD0").add_child(mi)
			pi += 1
			n += 1
	return n


static func _rel(n: Node3D, top: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != top:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


static func _own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		_own(c, owner)


static func _aabb(k: Node3D) -> AABB:
	var ab := AABB()
	var first := true
	for mi: MeshInstance3D in k.get_node("LOD0").get_children():
		if mi.mesh == null or not mi.visible:
			continue
		var a := mi.transform * mi.mesh.get_aabb()
		ab = a if first else ab.merge(a)
		first = false
	return ab


static func bake(v: Node3D) -> Node3D:
	var recs := greybox_recs()
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var embed := float(L["greybox"]["embed"])
	var lib := KLib.load_lib()
	var root := Node3D.new()
	root.name = NODE_NAME
	root.set_script(load(RUNTIME))
	var targets := PackedStringArray()
	var hide := PackedStringArray()
	var report: Array = []
	var tris := 0
	for id: String in PILOT:
		var rec: Dictionary = recs[id]
		var path := "Districts/%s/Buildings/%s" % [rec["district"], id]
		var body := v.get_node(path) as Node3D
		var r2 := pilot_rec(rec)
		var kit: Node3D = _with_plan(rec, func() -> Node3D: return KLib.build(r2, lib, embed))
		var o: Dictionary = PILOT[id]
		var extra := 0
		if bool(o.get("residence", false)):
			extra += _residential_front(kit, lib)
			var fr := body.get_node_or_null("Frontage/LOD0")
			if fr:
				for c in fr.get_children():
					if String(c.name).begins_with("fr_dan"):
						hide.append(String(v.get_path_to(c)))
		if bool(o.get("workshop", false)):
			extra += _workshop(kit, rec)
		kit.set_meta("phase", "P13W1B")
		var holder := Node3D.new()
		holder.name = id
		holder.transform = _rel(body, v)
		holder.set_meta("p13_cat", String(o["cat"]))
		holder.set_meta("p13_roof", String(r2["roof"]))
		holder.set_meta("p13_type", String(r2["type"]))
		root.add_child(holder)
		holder.add_child(kit)
		tris += KLib.lod_tris(kit, 0)
		targets.append(path)
		# 見た目 vs P4 碰撞箱（頂・水平）
		var cs := body.get_node("Shape") as CollisionShape3D
		var bs := (cs.shape as BoxShape3D).size
		var a1 := _aabb(kit)
		var a0 := _aabb(body.get_node("Kit") as Node3D)
		report.append({"id": id, "cat": o["cat"], "roof": r2["roof"], "type": r2["type"], "top0": snappedf(a0.end.y, 0.01),
			"top1": snappedf(a1.end.y, 0.01), "col_top": snappedf(cs.position.y + bs.y * 0.5, 0.01),
			"x1": [snappedf(a1.position.x, 0.01), snappedf(a1.end.x, 0.01)], "z1": [snappedf(a1.position.z, 0.01), snappedf(a1.end.z, 0.01)],
			"col_half": [snappedf(bs.x * 0.5, 0.01), snappedf(bs.z * 0.5, 0.01)], "swaps": extra})
	root.add_child(farm_preview(v))
	root.set("targets", targets)
	root.set("hide_nodes", hide)
	root.set_meta("buildings", targets.size())
	root.set_meta("lod0_tris", tris)
	root.set_meta("report", report)
	_own(root, root)
	return root


# ─────────────────────────── 農家 A1／A2 預覽（碰撞なし・預覽専用） ───────────────────────────

static func _thatch() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "P13_ThatchPreview"
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_CELLULAR
	nz.frequency = 0.09
	var tx := NoiseTexture2D.new()
	tx.width = 256
	tx.height = 256
	tx.noise = nz
	tx.seamless = true
	var gr := Gradient.new()
	gr.set_color(0, Color(0.36, 0.30, 0.19))
	gr.set_color(1, Color(0.70, 0.60, 0.40))
	tx.color_ramp = gr
	m.albedo_texture = tx
	m.uv1_scale = Vector3(1.5, 14.0, 1.0)
	m.roughness = 1.0
	return m


static func _tint(path: String, c: Color) -> Material:
	var m := (load(path) as Material).duplicate() as StandardMaterial3D
	m.albedo_color = m.albedo_color * c
	return m


static func _box(p: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.transform = Transform3D(rot, pos)
	p.add_child(mi)
	return mi


## 妻壁三角（x 平面、z 方向に底辺 2·half、頂 rise）。両面。
static func _gable(p: Node3D, x: float, y0: float, half: float, rise: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v3 in [Vector3(x, y0, -half), Vector3(x, y0 + rise, 0), Vector3(x, y0, half), Vector3(x, y0, half), Vector3(x, y0 + rise, 0), Vector3(x, y0, -half)]:
		st.set_uv(Vector2(v3.z, v3.y))
		st.add_vertex(v3)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	p.add_child(mi)


## 切妻屋根：棟は局所 x 沿い、±z へ下る。half＝棟→軒先の水平、rise、y_eave＝軒先高
static func _roof(p: Node3D, len_x: float, half: float, rise: float, y_eave: float, th: float, mat: Material) -> void:
	var ang := atan2(rise, half)
	var sl := sqrt(half * half + rise * rise)
	for sg in [1.0, -1.0]:
		var b := Basis(Vector3.RIGHT, sg * ang)
		_box(p, Vector3(len_x, th, sl), Vector3(0, y_eave + rise * 0.5 + th * 0.5 / cos(ang), sg * half * 0.5), mat, b)


static func farm_preview(v: Node3D) -> Node3D:
	var S := RLib.terrain_sampler(v)   # 地形三角形のみ（牆頂・樹冠・屋根は拾わない）
	var g := Node3D.new()
	g.name = "FarmPreview"
	g.set_meta("note", "P13 W1B 農家 A1／A2 預覽（碰撞なし・正式施工前）")
	var plaster := _tint(MAT + "V2_Plaster.tres", Color(0.78, 0.66, 0.50))
	var wood: Material = load(MAT + "V2_Wood.tres")
	var dark := _tint(MAT + "V2_Wood.tres", Color(0.45, 0.42, 0.40))
	var board := _tint(MAT + "V2_Wood.tres", Color(0.62, 0.55, 0.48))
	var stone: Material = load(MAT + "V2_Stone.tres")
	var thatch := _thatch()
	for s: Array in FARM:
		var c := Vector2(s[1], s[2])
		var w: float = s[3]
		var d: float = s[4]
		var hs: Array = []
		for ix in 5:
			for iz in 5:
				var h := S.h(c.x + lerpf(-w, w, ix / 4.0) * 0.5, c.y + lerpf(-d, d, iz / 4.0) * 0.5)
				if not is_nan(h):
					hs.append(h)
		var lo: float = hs.min()
		var hi: float = hs.max()
		var n := Node3D.new()
		n.name = String(s[0])
		n.position = Vector3(c.x, hi, c.y)
		n.set_meta("ground", [snappedf(lo, 0.01), snappedf(hi, 0.01)])
		g.add_child(n)
		var body := Node3D.new()
		body.rotation.y = PI * 0.5        # 局所 x（棟）＝世界 z、局所 +z（正面）＝世界 +x
		n.add_child(body)
		var Lx := d
		var D := w
		var fnd := 0.25
		_box(body, Vector3(Lx + 0.2, fnd + (hi - lo) + 0.3, D + 0.2), Vector3(0, (fnd - (hi - lo) - 0.3) * 0.5, 0), stone)
		if String(s[0]).ends_with("noka"):
			var e := 2.3
			_box(body, Vector3(Lx, e, D), Vector3(0, fnd + e * 0.5, 0), plaster)
			var nb := int(round(Lx / 1.82))
			for i in nb + 1:
				var x := -Lx * 0.5 + i * Lx / nb
				for zz in [-D * 0.5, D * 0.5]:
					_box(body, Vector3(0.16, e, 0.16), Vector3(x, fnd + e * 0.5, zz), wood)
			_box(body, Vector3(Lx + 0.1, 0.22, 0.2), Vector3(0, fnd + e - 0.11, D * 0.5), wood)
			_box(body, Vector3(Lx + 0.1, 0.22, 0.2), Vector3(0, fnd + e - 0.11, -D * 0.5), wood)
			_box(body, Vector3(1.8, 1.9, 0.12), Vector3(-Lx * 0.25, fnd + 0.95, D * 0.5 + 0.02), dark)       # 土間の大戸
			_box(body, Vector3(2.6, 1.2, 0.1), Vector3(Lx * 0.2, fnd + 1.3, D * 0.5 + 0.02), dark)         # 窓
			_box(body, Vector3(Lx * 0.55, 0.12, 0.9), Vector3(Lx * 0.2, fnd + 0.45, D * 0.5 + 0.45), wood) # 縁
			var half := D * 0.5 + 0.9
			_gable(body, -Lx * 0.5, fnd + e, D * 0.5, D * 0.5, plaster)
			_gable(body, Lx * 0.5, fnd + e, D * 0.5, D * 0.5, plaster)
			_roof(body, Lx + 1.2, half, half, fnd + e - 0.9, 0.55, thatch)                                  # 茅葺 45°
			_box(body, Vector3(Lx + 1.4, 0.35, 0.5), Vector3(0, fnd + e - 0.9 + half + 0.45, 0), dark)       # 棟押さえ
			n.set_meta("dims", "主屋 %.1f×%.1f m、簷 %.1f、棟 %.1f、茅葺 45°" % [w, d, fnd + e, fnd + e + D * 0.5])
		else:
			var e2 := 2.1
			_box(body, Vector3(Lx, e2, D), Vector3(0, fnd + e2 * 0.5, 0), board)
			for x in [-Lx * 0.5, -Lx * 0.17, Lx * 0.17, Lx * 0.5]:
				_box(body, Vector3(0.14, e2, 0.14), Vector3(x, fnd + e2 * 0.5, D * 0.5), wood)
			_box(body, Vector3(Lx * 0.33 - 0.14, e2 - 0.15, 0.1), Vector3(0, fnd + (e2 - 0.15) * 0.5, D * 0.5 + 0.03), dark)  # 開いた戸口
			var half2 := D * 0.5 + 0.45
			_gable(body, -Lx * 0.5, fnd + e2, D * 0.5, D * 0.5 * 0.4, board)
			_gable(body, Lx * 0.5, fnd + e2, D * 0.5, D * 0.5 * 0.4, board)
			_roof(body, Lx + 0.6, half2, half2 * 0.4, fnd + e2 - 0.18, 0.1, wood)                              # 板葺
			n.set_meta("dims", "納屋 %.1f×%.1f m、簷 %.1f、板葺 4 寸勾配" % [w, d, fnd + e2])
	return g
