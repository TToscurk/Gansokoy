@tool
extends RefCounted
## P10 R3d Village Core Population Expansion：R3b（16 人、封存）に核心區の住人を足して計 30–40 人にする。
## 範囲＝主市集・Market West 裏通り・主街（市の口〜中ほど）・鯢吞亭（居酒屋）の門前・寺子屋の前庭。農田／河岸／森林へは広げない。
## 密度：市集が最も濃く、主街が次、裏通り・居酒屋・寺子屋はまばら。等間隔に撒かない（二人組・三人組＋単独の店主／停留者＋留白）。
## R3b の baseline（generator・actor・Population scene・snapshot）は一切変更しない：別 overlay Population/CoreP10。
##   立ち位置・高さ・patrol の高さ焼き・walk 速度・RenderIndex は封存 R3b lib の関数を只讀で呼ぶ（同じ規則）。
## 動作＝R3c／R3c.1 で承認・封存された Activity vocabulary だけ（Talk／Drink／Sit／Carry／YouthShortStep、各モデルの承認済み clip）。
##   新しい clip・新しい種類は作らない。割り当ては scripts/npc_activity_core.gd（封存 overlay を継承、封存ファイルは不変）。
## 南側から「市」が読みにくい件（R2 non-blocking）はここで人の流れで補う：市の口へ向かう買い物客の往復、口の呼び込み、荷を抱える運び手。
const PL := preload("res://tools/village_v2_population_lib.gd")

const OUTPUT := "res://maps/village_v2/gen/population_core_p10.tscn"
const NODE_NAME := "CoreP10"
const ACT_NODE := "ActivityCoreP10"
const ACT_SCRIPT := "res://scripts/npc_activity_core.gd"
const PARENT := "Population"
const ART_REVISION := "P10 R3d Village Core Population r1 ART_REVIEW"
const ZONE_NODE := {"market": "Market", "market_west": "MarketWest", "main_street": "MainStreet", "izakaya": "Izakaya", "terakoya": "Terakoya"}
## R3b の職業対位＋R3d の追加（居酒屋の客、寺子屋の子・付き添い）
const ROLE_OK := {
	"yaoya_m01": ["yasai", "tenbin", "porter"],
	"sakanaya_m01": ["sakana", "passer", "customer", "guest"],
	"nunoya_f01": ["gofuku", "barker", "parent"],
	"chaya_f01": ["chaya", "guest", "dango", "customer"],
	"takigi_m01": ["zakka", "porter", "takigi"],
	"shufu_f01": ["customer", "parent"],
	"yakusou_f01": ["kanbutsu", "kusuri", "customer", "parent"],
	"setomono_f01": ["seto", "zakka", "dango", "meshi"],
	"kozo_m01": ["errand", "pupil"],
	"chonin_m01": ["customer", "clerk", "porter", "passer", "guest"],
}
const NO_WALK := ["yakusou_f01", "setomono_f01"]

## 追加 23 人（モデルは同モデルが 8 m 以内に並ばないよう選ぶ）。anchor＝封存 overlay の activity anchor（只讀）、at＝[x, z, yaw°]（anchor の無い居酒屋・寺子屋）。
const CAST := [
	# ── 主市集 +9（R3b 7 → 16）：市集の真ん中の立ち話、団子の屋台（売り子＋客の会話）、反物の棚（布屋＋客の会話）、荷車の運び手、魚の屋台の客、市の口で木箱を抱える八百屋
	{"id": "C1", "zone": "market", "model": "chaya_f01", "trade": "dango", "anchor": "MarketP10/vendor_yatai_dango", "off": [0.75, 0.0], "face": "partner:C2", "group": "g_dango"},
	{"id": "C2", "zone": "market", "model": "shufu_f01", "trade": "customer", "anchor": "MarketP10/customer_yatai_dango_b", "face": "partner:C1", "group": "g_dango"},
	{"id": "C3", "zone": "market", "model": "takigi_m01", "trade": "porter", "anchor": "MarketP10/porter", "face": "anchor"},
	{"id": "C4", "zone": "market", "model": "nunoya_f01", "trade": "gofuku", "anchor": "MarketP10/vendor_tana_nuno", "off": [0.0, -0.6], "face": "partner:C5", "group": "g_nuno"},
	{"id": "C5", "zone": "market", "model": "shufu_f01", "trade": "customer", "anchor": "MarketP10/customer_tana_nuno_a", "face": "partner:C4", "group": "g_nuno"},
	{"id": "C7", "zone": "market", "model": "sakanaya_m01", "trade": "customer", "anchor": "MarketP10/customer_yatai_meshi_a", "face": "anchor"},
	{"id": "C12", "zone": "market", "model": "yaoya_m01", "trade": "porter", "anchor": "MarketP10/peddler", "face": "anchor", "group": "g_mouth"},
	# 市集の真ん中で立ち話する二人（通りの中央に人の溜まりを作る；R3b の M7 往復路から ≥ 0.6 m）
	{"id": "C23", "zone": "market", "model": "yakusou_f01", "trade": "customer", "anchor": "MarketP10/walker_b", "face": "partner:C24", "group": "g_square"},
	{"id": "C24", "zone": "market", "model": "chaya_f01", "trade": "customer", "at": [246.1, -43.0, 0.0], "face": "partner:C23", "group": "g_square"},
	# ── Market West 裏通り +3（5 → 8）：一膳飯の下屋の婆、乾物棚の客、クランクの運び手
	{"id": "C8", "zone": "market_west", "model": "setomono_f01", "trade": "meshi", "anchor": "MarketWestP10/mw_meshi_vendor", "off": [0.15, 0.0], "face": "anchor"},
	{"id": "C9", "zone": "market_west", "model": "sakanaya_m01", "trade": "customer", "anchor": "MarketWestP10/mw_n3_customer", "face": "anchor"},
	{"id": "C10", "zone": "market_west", "model": "chonin_m01", "trade": "porter", "anchor": "MarketWestP10/mw_porter_crank", "face": "anchor"},
	# ── 主街 +6（4 → 10）：市の口の呼び込み、市へ向かう買い物客の往復、甕の店（売り手＋客の会話）、荒物の店、薬の看板の客
	{"id": "C6", "zone": "main_street", "model": "sakanaya_m01", "trade": "customer", "mode": "patrol", "group": "g_mouth",
		"path": [[259.0, -19.0], [253.5, -20.6], [249.5, -21.0]], "wait": [2.0, 4.5]},
	{"id": "C11", "zone": "main_street", "model": "nunoya_f01", "trade": "barker", "anchor": "StreetP10/st_barker_ichi", "face": "anchor", "group": "g_mouth"},
	{"id": "C13", "zone": "main_street", "model": "shufu_f01", "trade": "customer", "anchor": "StreetP10/st_customer_MKT_024", "face": "partner:C14", "group": "g_kame"},
	{"id": "C14", "zone": "main_street", "model": "setomono_f01", "trade": "seto", "anchor": "StreetP10/st_vendor_MKT_024", "off": [0.0, 0.25], "face": "partner:C13", "group": "g_kame"},
	{"id": "C16", "zone": "main_street", "model": "takigi_m01", "trade": "zakka", "anchor": "StreetP10/st_vendor_MKT_011", "off": [-0.08, -0.12], "face": "anchor"},
	{"id": "C19", "zone": "main_street", "model": "chonin_m01", "trade": "customer", "anchor": "StreetP10/st_customer_MKT_013", "face": "anchor"},
	# ── 鯢吞亭の門前 +2：外の席の手前で一服する二人
	{"id": "C17", "zone": "izakaya", "model": "chaya_f01", "trade": "guest", "at": [276.4, -59.0, 135.0], "face": "partner:C18", "group": "g_izakaya"},
	{"id": "C18", "zone": "izakaya", "model": "sakanaya_m01", "trade": "guest", "at": [277.6, -60.8, -45.0], "face": "partner:C17", "group": "g_izakaya"},
	# ── 寺子屋の前庭 +3：迎えの婆（縁台に座って話す）と迎えの母（立って話す）、往復する子
	{"id": "C20", "zone": "terakoya", "model": "kozo_m01", "trade": "pupil", "mode": "patrol", "path": [[202.0, 20.4], [205.0, 24.0], [206.4, 25.6]], "wait": [1.5, 3.5], "group": "g_terakoya"},
	{"id": "C21", "zone": "terakoya", "model": "nunoya_f01", "trade": "parent", "at": [207.8, 27.6, -90.0], "face": "partner:C22", "group": "g_terakoya"},
	{"id": "C22", "zone": "terakoya", "model": "yakusou_f01", "trade": "parent", "at": [206.0, 28.9, 90.0], "face": "partner:C21", "group": "g_terakoya"},
]

## R3c／R3c.1 で承認・封存された vocabulary の割り当て（clip は各モデルの承認済み grounded clip、options も承認値）。
const ASSIGN := {
	"Market/C2_shufu_f01": ["Talk", "shufu_f01", "talk_general_a030", "idle"],
	"Market/C5_shufu_f01": ["Talk", "shufu_f01", "talk_general_a030", "idle"],
	"Market/C23_yakusou_f01": ["Talk", "yakusou_f01", "talk_funny_a030", "idle"],
	"Market/C12_yaoya_m01": ["Carry", "yaoya_m01", "box_idle_a030", "idle", {"crate": ["res://assets/village_v2/suzu_kit/mesh/sz_hako.res", 0.30, 0.20], "crate_forward": 0.14, "crate_up": 0.09, "crate_inset": 0.09}],
	"MainStreet/C11_nunoya_f01": ["Talk", "nunoya_f01", "talk_general_a040", "idle"],
	"MainStreet/C13_shufu_f01": ["Talk", "shufu_f01", "talk_general_a030", "idle"],
	"Izakaya/C17_chaya_f01": ["Drink", "chaya_f01", "drinking_im1_a030", "idle"],
	"Terakoya/C20_kozo_m01": ["YouthShortStep", "kozo_m01", "light_walk_s100_a030", "walk"],
	"Terakoya/C21_nunoya_f01": ["Talk", "nunoya_f01", "talk_general_a040", "idle"],
	"Terakoya/C22_yakusou_f01": ["Sit", "yakusou_f01", "sit_talk_a_a030", "idle", {"seat": "res://assets/village_v2/mise_kit/mesh/ms_endai_mousen.res", "seat_drop": 0.22, "seat_back": -0.09, "seat_depth": 0.34, "seat_len": 1.2, "seat_shift": -0.1}],
}


static func plan(v: Node3D, cast: Array = CAST) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var C := PL.context(v)
	var RO := PL.roster()
	var speeds := {}
	var actors: Array = []
	var byid := {}
	var k := 0
	for e: Dictionary in cast:
		var a := {"id": e["id"], "zone": e["zone"], "model": e["model"], "trade": e["trade"], "mode": e.get("mode", "idle"),
			"group": e.get("group", ""), "anchor": e.get("anchor", ""), "seed": 104729 * (k + 5)}
		var rng := RandomNumberGenerator.new()
		rng.seed = a["seed"]
		a["height"] = float(RO.get(e["model"], {}).get("height", 1.68))
		a["idle_t"] = snappedf(rng.randf_range(0.0, 6.0), 0.01)
		a["speed_scale"] = snappedf(rng.randf_range(0.93, 1.07), 0.01) if a["mode"] == "idle" else 1.0
		if a["mode"] == "patrol":
			if not speeds.has(e["model"]):
				speeds[e["model"]] = PL.walk_speed(v, e["model"])
			a["walk"] = speeds[e["model"]]
			a["walk_speed"] = snappedf(float(speeds[e["model"]]["speed"]), 0.001)
			var pts := PackedVector2Array()
			for q: Array in e["path"]:
				pts.append(Vector2(float(q[0]), float(q[1])))
			var L := 0.0
			for i in range(1, pts.size()):
				L += pts[i].distance_to(pts[i - 1])
			var ys := PackedFloat32Array()
			var n := int(ceil(L / 0.25)) + 1
			for j in n:
				ys.append(PL.top_h(C, PL._along(pts, minf(j * 0.25, L))))
			a["path_xz"] = pts
			a["path_y"] = ys
			a["path_len"] = L
			a["wait"] = e.get("wait", [2.0, 5.0])
			a["start_u"] = snappedf(rng.randf_range(0.15, 0.85), 0.01)
			a["p"] = Vector3(pts[0].x, ys[0], pts[0].y)
			a["yaw"] = PL.yaw_to(pts[1] - pts[0])
		elif e.has("at"):
			var at: Array = e["at"]
			var p2 := Vector2(float(at[0]), float(at[1]))
			a["p"] = Vector3(p2.x, PL.top_h(C, p2), p2.y)
			a["yaw"] = deg_to_rad(float(at[2]))
		else:
			var an: Dictionary = C["anchors"].get(e["anchor"], {})
			if an.is_empty():
				a["error"] = "anchor %s が無い" % e["anchor"]
				actors.append(a)
				k += 1
				continue
			var p3: Vector3 = an["p"]
			var off: Array = e.get("off", [0.0, 0.0])
			var p2 := Vector2(p3.x + float(off[0]), p3.z + float(off[1]))
			a["p"] = Vector3(p2.x, PL.top_h(C, p2), p2.y)
			a["yaw"] = float(an["yaw"])
			a["anchor_act"] = an["act"]
		a["face"] = e.get("face", "anchor")
		actors.append(a)
		byid[a["id"]] = a
		k += 1
	for a: Dictionary in actors:
		var f := String(a.get("face", ""))
		if f.begins_with("partner:") and byid.has(f.trim_prefix("partner:")):
			var b: Dictionary = byid[f.trim_prefix("partner:")]
			a["yaw"] = PL.yaw_to(Vector2((b["p"] as Vector3).x - (a["p"] as Vector3).x, (b["p"] as Vector3).z - (a["p"] as Vector3).z))
	return {"actors": actors, "C": C, "speeds": speeds, "ms": Time.get_ticks_msec() - t0}


## Population/CoreP10/<Zone>/<id>_<model>（R3b と同じ actor script・同じ capsule・封存 NPC wrapper の instance）
static func build(P: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	var zones := {}
	var script := load(PL.ACTOR) as Script
	for a: Dictionary in P["actors"]:
		if a.has("error"):
			continue
		var z := String(a["zone"])
		if not zones.has(z):
			var zn := Node3D.new()
			zn.name = ZONE_NODE[z]
			root.add_child(zn)
			zn.owner = root
			zones[z] = zn
		var body := AnimatableBody3D.new()
		body.name = "%s_%s" % [a["id"], a["model"]]
		body.set_script(script)
		body.sync_to_physics = false
		body.transform = Transform3D(Basis(Vector3.UP, float(a["yaw"])), a["p"])
		body.set("mode", a["mode"])
		body.set("seed_i", int(a["seed"]))
		if a["mode"] == "patrol":
			body.set("path_xz", a["path_xz"])
			body.set("path_y", a["path_y"])
			body.set("walk_speed", float(a["walk_speed"]))
			body.set("wait_min", float(a["wait"][0]))
			body.set("wait_max", float(a["wait"][1]))
			body.set("start_u", float(a["start_u"]))
		for mk in ["model", "trade", "zone", "group", "anchor"]:
			body.set_meta(mk, a[mk])
		(zones[z] as Node).add_child(body)
		body.owner = root
		var cs := CollisionShape3D.new()
		cs.name = "Body"
		var cap := CapsuleShape3D.new()
		cap.radius = PL.CAP_R
		cap.height = float(a["height"]) - 0.06
		cs.shape = cap
		cs.position = Vector3(0, cap.height * 0.5 + 0.04, 0)
		body.add_child(cs)
		cs.owner = root
		var npc: Node3D = (load(PL.npc_scene(a["model"])) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		npc.name = "NPC"
		npc.set("animation", &"idle" if a["mode"] == "idle" or float(a.get("start_u", -1.0)) < 0.0 else &"walk")
		npc.set("start_time", float(a["idle_t"]))
		npc.set("speed_scale", float(a["speed_scale"]))
		body.add_child(npc)
		npc.owner = root
	root.set_meta("art_revision", ART_REVISION)
	root.set_meta("actors", (P["actors"] as Array).size())
	return root
