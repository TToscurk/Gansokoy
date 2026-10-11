extends RefCounted
## 人間之里 V2 P13 WAVE 1 — Architectural Diversity Pilot（主街中段 11 棟）。
##
## 根因（P13 W1 調査）：187 棟町家全部由同一個 P6 Kit 以 P4 灰盒紀錄組裝；P4 紀錄只有 3 種高さ（平屋 2.9／厨子 3.9／總二階 5.4）、
##   主街 39 棟全部「平入」（妻入 0）、店 ＝ 1F 開口＋庇 一種構成。R2／R3 變化（色・窓・勾配 0.45／0.38／0.32・小山牆・卯建）
##   都在同一個平入箱型の上で行われるため、TPS 眼高では屋根は同じ「横長の瓦の帯」に見え、差は色と細部に留まる。
## 本 Pilot：既存 Kit 構件だけで「建物の型」自体を変える——妻入（棟を街に直交＝三角の妻面を見せる）、高さ段（平屋→厨子へ上げる；
##   下げるのは P4 碰撞より低い見かけ上の屋根になるので不可）、用途（店→蔵造り住居、店→工坊）、大店（本卯建＋小山牆＋看板）。
##   P4 寬深・位置・碰撞・入口位置・門前帶（Frontage）不變。新資產・新材質なし。
## 出力：gen/arch_pilot_p13.scn（root＝ArchPilotP13、runtime script が対象棟の元 Kit を隠す；enabled=false で完全に元へ戻る）。

const KLib := preload("res://tools/village_v2_machiya_kit_lib.gd")
const GREYBOX := "res://maps/village_v2/gen/greybox.json"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const OUTPUT := "res://maps/village_v2/gen/arch_pilot_p13.scn"
const RUNTIME := "res://maps/village_v2/scripts_p13/arch_pilot.gd"
const NODE_NAME := "ArchPilotP13"
const EAVE := {"hiraya": 2.9, "zushi": 3.9, "nikai": 5.4}
const P := 0.45

## cat：建物の型（審圖用ラベル）。rec＝P4 紀錄への上書き（型・屋根向き）、pl＝Kit 風格計畫への上書き。
const PILOT := {
	"B_P_MKT_003": {"cat": "妻入りの店（角地・厨子二階）", "tsuma": true,
		"pl": {"theme": "mixed", "up": "mushi", "sign": "side", "kemuri": false}},
	"B_P_MKT_005": {"cat": "大店（本卯建・小山牆・屋根看板）",
		"pl": {"roof": "low", "udh": [-1.0, 1.0], "dormer": true, "sign": "roof", "theme": "bengara", "up": "winb", "sb": false, "fin": 1, "tone": 0}},
	"B_P_MKT_006": {"cat": "工坊（開け放し・煙出し・板庇）",
		"pl": {"theme": "open", "kemuri": true, "his_wood": true, "roof": "offb2", "sign": "side", "up": "plain", "cut": true, "rec": "none", "rec_d": 0.0, "hang": "noren_e"}},
	"B_P_MKT_007": {"cat": "妻入りの二階店", "tsuma": true,
		"pl": {"theme": "lattice", "up": "win", "sign": ""}},
	"B_P_MKT_008": {"cat": "平屋住宅（妻入・煙出し）", "tsuma": true,
		"pl": {"theme": "koshib", "kemuri": true, "kiri": true}},
	"B_P_MKT_009": {"cat": "二階セットバックの店（片卯建）",
		"pl": {"roof": "low", "sb": true, "udh": [1.0], "theme": "lattice", "up": "amado"}},
	"B_P_MKT_010": {"cat": "蔵造りの住居（閉じた正面・白壁）", "tsuma": true, "residence": true,
		"pl": {"fin": 0, "tone": 2, "theme": "amado", "up": "plain", "up_period": 0, "kiri": false, "inuyarai": true, "kemuri": false, "sign": ""}},
	"B_P_MKT_018": {"cat": "厨子二階の住宅（平屋から上げる・虫籠窓）", "type": "zushi",
		"pl": {"up": "mushi", "up_period": 0, "theme": "koshi", "kemuri": true, "roof": "std"}},
	"B_P_MKT_019": {"cat": "質素な商家（2F 退き・板庇）",
		"pl": {"roof": "offb2", "sb": true, "his_wood": true, "theme": "open", "up": "amado"}},
	"B_P_MKT_020": {"cat": "妻入りの工坊（煙出し）", "tsuma": true,
		"pl": {"theme": "open", "kemuri": true, "his_wood": true, "up": "plain"}},
	"B_P_MKT_021": {"cat": "大店（2F 退き・片卯建・袖看板）",
		"pl": {"roof": "offf", "udh": [-1.0], "sb": true, "sign": "side", "theme": "bengara", "up": "wins"}},
}


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
		assert(float(EAVE[t]) >= float(rec["eave_m"]), "P13 Pilot：簷を下げると P4 碰撞より低い屋根になる（%s）" % rec["id"])
		r["type"] = t
		r["eave_m"] = float(EAVE[t])
	if bool(o.get("residence", false)):
		r["hisashi_m"] = 0.0
		r["hisashi_depth_m"] = 0.0
	if bool(o.get("tsuma", false)):
		r["roof"] = "tsuma"
		r["ov_gable_m"] = 0.3     # 妻面（街側・背側）の螻羽出
		r["ov_eave_m"] = 0.05     # 平の軒＝隣家側：地塊線を越えない
	# std 屋根の棟高（平入＝奥行の半分、妻入＝間口の半分）
	var half := (float(r["depth_m"]) if String(r["roof"]) == "hira" else float(r["width_m"])) * 0.5
	r["ridge_m"] = float(r["eave_m"]) + P * half
	return r


## Kit 風格計畫へ Pilot 上書き（KLib の static 計畫 dict を直接書く；同プロセス内のみ）
static func apply_plan(rec: Dictionary) -> void:
	var pl := KLib.plan_for(rec)
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
	if o.has("type") and String(o["type"]) != "hiraya":
		pl["kemuri"] = bool(o["pl"].get("kemuri", false))
	for k: String in o["pl"]:
		pl[k] = o["pl"][k]


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


## v：village_v2 インスタンス（元の棟 transform を読む）。戻り値＝保存用 root
static func bake(v: Node3D) -> Node3D:
	var recs := greybox_recs()
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var embed := float(L["greybox"]["embed"])
	var lib := KLib.load_lib()
	var root := Node3D.new()
	root.name = NODE_NAME
	root.set_script(load(RUNTIME))
	var targets := PackedStringArray()
	var n := 0
	var tris := 0
	for id: String in PILOT:
		var rec: Dictionary = recs[id]
		var path := "Districts/%s/Buildings/%s" % [rec["district"], id]
		var body := v.get_node(path) as Node3D
		var r2 := pilot_rec(rec)
		apply_plan(rec)
		var holder := Node3D.new()
		holder.name = id
		holder.transform = _rel(body, v)
		holder.set_meta("p13_cat", String(PILOT[id]["cat"]))
		holder.set_meta("p13_roof", String(r2["roof"]))
		holder.set_meta("p13_type", String(r2["type"]))
		root.add_child(holder)
		var kit := KLib.build(r2, lib, embed)
		kit.set_meta("phase", "P13W1")
		holder.add_child(kit)
		tris += KLib.lod_tris(kit, 0)
		targets.append(path)
		n += 1
	root.set("targets", targets)
	root.set_meta("buildings", n)
	root.set_meta("lod0_tris", tris)
	_own(root, root)
	return root
