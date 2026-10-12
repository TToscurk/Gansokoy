extends RefCounted
## 人間之里 V2 P13 W2 — 主街 39 棟の正式造型（使用者 2026-10-12：妻入＋平入差異化＋高度段差＋用途型、主街 39 棟のみ）。
##
## 来源：data/village_v2_p13_mainstreet.json（tools/p13/design_mainstreet.py 生成）。P4 灰盒紀錄 greybox.json は変更しない。
## ここが「P4 紀錄への上書き（妻入・型・庇）」と「Kit 風格計畫への上書き」の唯一の実装で、
##   gen_village_v2.gd（_kits／_gb_building の碰撞）・verify_village_v2_machiya_kit_gate.gd・tools/p13/integrate_mainstreet.gd が共用する。
## 空白壁の対策（全 39 棟）：上層は白壁週期なし（全開間に窓）／見える側壁（隣家が 0.8 m 内に無い側）は開口のある側壁 sdo＋懸魚／
##   妻入の街側妻面に懸魚。住居化（role residence・旧店）：庇を外し、入口以外の 1F 開口を壁／小窓へ。
## 計畫 dict（KLib._plan）は build の間だけ書き換え、直後に元へ戻す（他の 148 棟の生成に影響しない）。

const KLib := preload("res://tools/village_v2_machiya_kit_lib.gd")
const DESIGN := "res://data/village_v2_p13_mainstreet.json"
const EAVE := {"hiraya": 2.9, "zushi": 3.9, "nikai": 5.4}
const P := 0.45

static var _d: Dictionary = {}


static func design() -> Dictionary:
	if _d.is_empty():
		var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DESIGN))
		for e: Dictionary in j["buildings"]:
			_d[String(e["id"])] = e
	return _d


static func has(id: String) -> bool:
	return design().has(id)


## P4 紀錄の実効版（元 rec は変更しない）。対象外はそのまま返す。
static func effective_rec(rec: Dictionary) -> Dictionary:
	var id := String(rec["id"])
	if not has(id):
		return rec
	var e: Dictionary = design()[id]
	var r := rec.duplicate(true)
	if e.has("type"):
		var t := String(e["type"])
		assert(float(EAVE[t]) >= float(rec["eave_m"]), "P13 W2：簷を下げない（%s）" % id)
		r["type"] = t
		r["eave_m"] = float(EAVE[t])
		r["eave_edge_m"] = float(EAVE[t]) - 0.2
	if String(e["role"]) == "residence" and float(rec.get("hisashi_m", 0.0)) > 0.0:
		r["hisashi_m"] = 0.0
		r["hisashi_depth_m"] = 0.0
	if bool(e["tsuma"]):
		r["roof"] = "tsuma"
		r["ov_gable_m"] = 0.3
		r["ov_eave_m"] = 0.05
	var half := (float(r["depth_m"]) if String(r["roof"]) == "hira" else float(r["width_m"])) * 0.5
	if bool(e["tsuma"]) or e.has("type"):
		r["ridge_m"] = float(r["eave_m"]) + P * half
	return r


static func _plan_over(rec: Dictionary, pl: Dictionary) -> void:
	var e: Dictionary = design()[String(rec["id"])]
	var vis: Array = e["visible_sides"]
	if bool(e["tsuma"]):
		pl["roof"] = "std"
		pl["udh"] = []
		pl["dormer"] = false
		pl["sb"] = false
		pl["udatsu"] = -1
	if String(e["role"]) == "residence":
		pl["sb"] = false
		pl["his_wood"] = false
		pl["udatsu"] = -1
		pl["rec"] = "none"
		pl["rec_d"] = 0.0
		pl["sign"] = ""
	for k: String in e["pl"]:
		pl[k] = e["pl"][k]
	# 空白壁：見える側壁は開口側壁＋懸魚、妻入は街側妻面にも懸魚、上層は全開間に窓
	pl["corner"] = vis.duplicate()
	var gyo: Array = []
	if bool(e["tsuma"]):
		gyo.append(1.0)
	else:
		for s in vis:
			if not (pl.get("udh", []) as Array).has(s):
				gyo.append(s)
	pl["gyo"] = gyo
	pl["up_period"] = 0
	if String(pl.get("up", "")) == "plain":
		pl["up"] = "mushi" if String(rec["type"]) == "zushi" else "win"


## Kit を組む（対象外は従来どおり KLib.build）
static func build(rec: Dictionary, lib: Dictionary, embed: float) -> Node3D:
	var id := String(rec["id"])
	if not has(id):
		return KLib.build(rec, lib, embed)
	var r2 := effective_rec(rec)
	var pl := KLib.plan_for(rec)
	var keep := pl.duplicate(true)
	_plan_over(r2, pl)
	var kit := KLib.build(r2, lib, embed)
	pl.clear()
	pl.merge(keep)
	var e: Dictionary = design()[id]
	if String(e["role"]) == "residence":
		_residential_front(kit, lib)
	if bool(e.get("no_noren", false)):
		for mi: MeshInstance3D in kit.get_node("LOD0").get_children():
			if String(mi.name).begins_with("nr_"):
				mi.get_parent().remove_child(mi)
				mi.free()
	kit.set_meta("phase", "P6+P13W2")
	kit.set_meta("p13_role", String(e["role"]))
	kit.set_meta("p13_cat", String(e["cat"]))
	kit.set_meta("p13_tsuma", bool(e["tsuma"]))
	return kit


## 灰盒 → Kit（KLib.apply と同じ契約：灰盒網格は隠す、碰撞・節點は保留）
static func apply(body: Node3D, rec: Dictionary, lib: Dictionary, embed: float) -> Node3D:
	var old := body.get_node_or_null("Kit")
	if old != null:
		return old as Node3D
	for nm: String in KLib.GB_MESHES:
		var m := body.get_node_or_null(nm) as MeshInstance3D
		if m != null:
			m.visible = false
	var kit := build(rec, lib, embed)
	body.add_child(kit)
	body.set_meta("kit_asset", "machiya_kit")
	return kit


## 住居化：入口以外の 1F 開口を壁／小窓に（LOD0）、LOD1 の正面貼片も住宅型。bay_kind も実際に合わせる。
static func _residential_front(kit: Node3D, lib: Dictionary) -> void:
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
			mi.name = "%s_%s" % [nm, m.get_string(5)]
	for mi: MeshInstance3D in kit.get_node("LOD1").get_children():
		var s := String(mi.name)
		if s.begins_with("l_f1_") and not s.begins_with("l_f1_res"):
			var h := "h27" if s.contains("h27") else "h29"
			if lib.has("l_f1_res_" + h):
				mi.mesh = lib["l_f1_res_" + h]
	var kinds: Array = (kit.get_meta("bay_kind") as Array).duplicate()
	var door := int(kit.get_meta("door_i"))
	var a2 := 0
	for i in kinds.size():
		if i == door:
			kinds[i] = "door"
		else:
			kinds[i] = "mado" if a2 % 2 == 1 else "plain"
			a2 += 1
	kit.set_meta("bay_kind", kinds)
