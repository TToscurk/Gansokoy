@tool
extends RefCounted
## P10 R3e Outer Village Population Pilot：核心（市集・主街・裏通り・居酒屋・寺子屋＝R3d 封存 39 人）の外側に、刻意的に稀な住人を置く。
## 原則：市場の核心から離れるほど人が少ない。核心の密度を地図全体に複製しない。森林・山腳・偏僻な路段は無人でよい。
## 区域（第一輪 12 人）：農田 4（稲架の脇で作業・収穫の木箱・畦の短い往復・丘の畑の婆）、水車 2（一號水車の西岸で眺める二人）、
##   水渠／橋 2（南の橋のたもとで縁台に座る婆・中の橋のたもとで一服する娘）、住宅後巷 3（中巷の井戸端の二人・大工の作業場）、神社の外 1（參道鳥居の婆）。
## 動作＝R3c／R3c.1 封存 vocabulary だけ（Carry／Talk／Sit／Drink、他は Idle／Walk）。農田に城市の動作を無理に当てない（立つ・短く歩く・運ぶ）。
## R3b／R3d（封存）は不変：別 overlay Population/OuterP10＋ActivityOuterP10。配置計算は封存 R3d lib の plan()（R3b の context・接地）を只讀で呼ぶ。
const CL := preload("res://tools/village_v2_population_core_lib.gd")
const PL := preload("res://tools/village_v2_population_lib.gd")

const OUTPUT := "res://maps/village_v2/gen/population_outer_p10.tscn"
const NODE_NAME := "OuterP10"
const ACT_NODE := "ActivityOuterP10"
const ACT_SCRIPT := "res://scripts/npc_activity_outer.gd"
const PARENT := "Population"
const ART_REVISION := "P10 R3e Outer Village Population Pilot r1 ART_REVIEW"
const ZONE_NODE := {"farm": "Farm", "waterwheel": "Waterwheel", "canal": "Canal", "alley": "BackAlley", "shrine": "ShrineOutskirts"}
const ROLE_OK := {
	"yaoya_m01": ["farmer", "porter"],
	"sakanaya_m01": ["passer", "fisher"],
	"nunoya_f01": ["neighbor"],
	"chaya_f01": ["passer"],
	"takigi_m01": ["farmer", "carpenter"],
	"shufu_f01": ["neighbor", "passer"],
	"yakusou_f01": ["pilgrim", "resting"],
	"setomono_f01": ["farmer", "pilgrim"],
	"kozo_m01": ["errand"],
	"chonin_m01": ["farmer", "passer"],
}
const NO_WALK := ["yakusou_f01", "setomono_f01"]

const CAST := [
	# ── 農田 4：村側の稲架（R2 の農田交界）と丘の畑
	{"id": "O1", "zone": "farm", "model": "takigi_m01", "trade": "farmer", "anchor": "StreetP10/st_farmer_farm_mid", "face": "anchor"},
	{"id": "O2", "zone": "farm", "model": "yaoya_m01", "trade": "farmer", "anchor": "StreetP10/st_farmer_farm_east", "face": "anchor"},
	{"id": "O3", "zone": "farm", "model": "chonin_m01", "trade": "farmer", "mode": "patrol", "path": [[306.5, 13.0], [306.5, 18.5], [307.0, 24.0]], "wait": [3.0, 6.0]},
	{"id": "O4", "zone": "farm", "model": "setomono_f01", "trade": "farmer", "anchor": "StreetP10/st_farmer_farm_hill", "face": "anchor"},
	# ── 水車 2：一號水車の西岸で輪を眺める二人
	{"id": "O5", "zone": "waterwheel", "model": "sakanaya_m01", "trade": "fisher", "at": [328.6, -50.8, 90.0], "face": "partner:O6", "group": "g_wheel"},
	{"id": "O6", "zone": "waterwheel", "model": "shufu_f01", "trade": "neighbor", "at": [327.6, -48.9, 90.0], "face": "partner:O5", "group": "g_wheel"},
	# ── 水渠／橋 2：南の橋（Bridge_04）と中の橋（Bridge_03）の村側のたもと
	{"id": "O7", "zone": "canal", "model": "yakusou_f01", "trade": "resting", "at": [311.0, 37.8, 90.0]},
	{"id": "O8", "zone": "canal", "model": "chaya_f01", "trade": "passer", "at": [330.5, -31.5, 120.0]},
	# ── 住宅後巷 3：中巷の井戸端の二人、大工の作業場
	{"id": "O9", "zone": "alley", "model": "shufu_f01", "trade": "neighbor", "anchor": "StreetP10/st_well_ido_midlane", "face": "partner:O10", "group": "g_well"},
	{"id": "O10", "zone": "alley", "model": "nunoya_f01", "trade": "neighbor", "at": [269.4, -86.6, 0.0], "face": "partner:O9", "group": "g_well"},
	{"id": "O11", "zone": "alley", "model": "takigi_m01", "trade": "carpenter", "anchor": "StreetP10/st_worker_105", "face": "anchor"},
	# ── 神社の外 1：參道鳥居の手前の婆
	{"id": "O12", "zone": "shrine", "model": "yakusou_f01", "trade": "pilgrim", "at": [292.0, -152.0, -160.0]},
]

## 封存 vocabulary（R3c seal の (type, model, clip, slot, options) と一致すること）
const ASSIGN := {
	"Farm/O2_yaoya_m01": ["Carry", "yaoya_m01", "box_idle_a030", "idle", {"crate": ["res://assets/village_v2/suzu_kit/mesh/sz_hako.res", 0.30, 0.20], "crate_forward": 0.14, "crate_up": 0.09, "crate_inset": 0.09}],
	"Waterwheel/O6_shufu_f01": ["Talk", "shufu_f01", "talk_general_a030", "idle"],
	"Canal/O7_yakusou_f01": ["Sit", "yakusou_f01", "sit_talk_a_a030", "idle", {"seat": "res://assets/village_v2/mise_kit/mesh/ms_endai_mousen.res", "seat_drop": 0.22, "seat_back": -0.09, "seat_depth": 0.34, "seat_len": 1.2, "seat_shift": -0.1}],
	# O8 茶屋少女の Drink は 2026-10-16 使用者指示で削除（基線 Idle）
	"BackAlley/O10_nunoya_f01": ["Talk", "nunoya_f01", "talk_general_a040", "idle"],
}


static func plan(v: Node3D, cast: Array = CAST) -> Dictionary:
	return CL.plan(v, cast)


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
		body.set("seed_i", int(a["seed"]) + 7)
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
		npc.set("start_time", fmod(float(a["idle_t"]) + 2.7, 6.0))
		npc.set("speed_scale", float(a["speed_scale"]))
		body.add_child(npc)
		npc.owner = root
	root.set_meta("art_revision", ART_REVISION)
	root.set_meta("actors", (P["actors"] as Array).size())
	return root
