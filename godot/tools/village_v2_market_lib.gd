extends RefCounted
## 人間之里 V2 P10 R1：市集廣場（Market Square）——主街西側の町家列（MKT_023–027）の裏手、鈴奈庵北の空地（x 230–257, z −60–−24）、
##   中橫街から 12 m の口（x 240–252）で入る「裏の広場の市」。
##   ART 基準：同じ TPS 鏡位が「人が住み・売り買いし・働いている村」へ明らかに変わること（「何か変わった」ではない）。
##   構圖（r2：密度）：中橫街の口を入口に、東（町家の背面）に屋台 3、西に布棚 2、北の突き当たりに布棚＋屋台、
##         中に背中合わせの低い列（筵 3＋縁台）——通り 2 本（西・東、幅 3–4 m）と中の切れ目で歩く。輪郭を変えるのは 屋台の板屋根・布棚の日除け・幟（3.7 m）・番傘（2.4 m）。
##         裏手（西・北）は荷車・荷積み・甕・干し竿＝商いの裏側。NPC activity anchors は売り手・客・座る客・運び手・行き交う人。
##   Generator＝source of truth：配置はここだけで決める（Editor で動かさない）。overlay＝Props/MarketP10（gen/market_p10.scn）。

const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const ML := preload("res://tools/village_v2_groundcover_macro.gd")
const OUTPUT := "res://maps/village_v2/gen/market_p10.scn"
const NODE_NAME := "MarketP10"
const PARENT := "Props"
const LOD_SWITCH := 32.0
const DIRS := {"mk_": "res://assets/village_v2/market_kit/mesh/", "gd_": "res://assets/village_v2/geidon_kit/mesh/",
	"sz_": "res://assets/village_v2/suzu_kit/mesh/", "sk_": "res://assets/village_v2/school_kit/mesh/",
	"kr_": "res://assets/village_v2/kiri_kit/mesh/", "wk_": "res://assets/village_v2/waterside_kit/mesh/"}
## 局部の足元（半幅 x、半奥 z、高さ、奥の中心ずれ z、横の中心ずれ x）——碰撞・擺放檢查の共通定義
const BOX := {
	"mk_yatai_yasai": [1.25, 0.7, 2.45, 0.0, 0.0], "mk_yatai_dango": [1.25, 0.7, 2.45, 0.0, 0.0], "mk_yatai_meshi": [1.25, 0.7, 2.45, 0.0, 0.0],
	"mk_tana_nuno": [1.55, 1.15, 2.45, 0.0, 0.0], "mk_tana_seto": [1.55, 1.2, 2.45, 0.0, 0.0],
	"mk_mushiro_yasai": [1.02, 0.95, 0.55, -0.22, 0.0], "mk_mushiro_kago": [0.92, 0.66, 0.5, 0.0, 0.0],
	"mk_bangasa": [0.16, 0.16, 2.4, 0.0, 0.0],
	"mk_nobori_yasai": [0.1, 0.1, 3.7, 0.0, 0.0], "mk_nobori_cha": [0.1, 0.1, 3.7, 0.0, 0.0], "mk_nobori_seto": [0.1, 0.1, 3.7, 0.0, 0.0],
	"mk_nobori_tanmono": [0.1, 0.1, 3.7, 0.0, 0.0], "mk_nobori_ichi": [0.1, 0.1, 3.7, 0.0, 0.0],
	"mk_kanban_yasai": [0.27, 0.31, 1.15, 0.0, 0.0], "mk_kanban_dango": [0.27, 0.31, 1.15, 0.0, 0.0],
	"mk_kanban_seto": [0.27, 0.31, 1.15, 0.0, 0.0], "mk_kanban_furugi": [0.27, 0.31, 1.15, 0.0, 0.0],
	"mk_kuruma_ni": [0.56, 1.46, 1.21, 0.56, 0.0], "mk_tenbin": [0.86, 0.22, 0.62, 0.0, 0.0],
	"mk_yatai_sakana": [1.25, 0.7, 2.5, 0.0, 0.0], "mk_tana_zakka": [1.55, 1.15, 2.5, 0.0, 0.0],
	"mk_mushiro_tsuke": [0.97, 0.95, 0.6, -0.22, 0.0], "mk_endai_uri": [0.9, 0.3, 0.85, 0.0, 0.0],
	"mk_yatai_cha": [1.25, 0.7, 2.5, 0.0, 0.0], "mk_yatai_ame": [1.25, 0.7, 2.5, 0.0, 0.0],
	"mk_tana_kasa": [1.55, 1.15, 2.5, 0.0, 0.0], "mk_tana_omocha": [1.55, 1.15, 2.5, 0.0, 0.0],
	"mk_chochin_line": [2.55, 0.1, 3.3, 0.0, 0.0],
	"mk_tsumini": [1.08, 0.59, 0.83, -0.21, 0.03], "mk_kame": [0.6, 0.5, 1.06, -0.09, 0.25], "mk_hoshimono": [1.72, 0.14, 1.95, 0.0, 0.0],
	"gd_shogi": [0.8, 0.29, 0.42, 0.0, 0.0], "gd_taru": [0.24, 0.24, 0.64, 0.0, 0.0], "sz_stool": [0.21, 0.13, 0.4, 0.0, 0.0],
	"sk_tensui": [0.31, 0.31, 0.74, 0.0, 0.0], "sk_bench": [0.9, 0.24, 0.42, 0.0, 0.0], "kr_okeyama": [0.47, 0.31, 0.88, 0.0, 0.0],
	"wk_tawara3": [0.41, 0.46, 0.84, 0.0, 0.0], "sk_teoke": [0.27, 0.15, 0.46, 0.0, 0.13],
}
## 形式（構圖の検査用）
const STALL := ["mk_yatai_yasai", "mk_yatai_dango", "mk_yatai_meshi", "mk_yatai_sakana", "mk_yatai_cha", "mk_yatai_ame",
	"mk_tana_nuno", "mk_tana_seto", "mk_tana_zakka", "mk_tana_kasa", "mk_tana_omocha",
	"mk_mushiro_yasai", "mk_mushiro_kago", "mk_mushiro_tsuke", "mk_endai_uri"]
const TALL := 2.2
const NO_COLLIDE := ["mk_hoshimono"]
## 足元が線状のもの（提灯の吊り綱）：足元＝竿 2 本だけ（局部 x ±2.5）
const LINE := ["mk_chochin_line"]
## 廣場の範圍（中央の歩く空き地＝OPEN は何も置かない）
const PLAZA := Rect2(226.0, -64.0, 34.0, 42.0)
## 歩く通り：西の通り（布棚の前〜中の列）・東の通り（中の列〜屋台の前）・中の列の切れ目・入口の口——ここには何も置かない（幟・置き看板も）
const LANES := {"west_lane": Rect2(237.3, -53.0, 2.3, 20.0), "east_lane": Rect2(246.3, -53.0, 2.2, 17.4),
	"cross_gap": Rect2(240.0, -46.6, 6.0, 9.6), "mouth": Rect2(244.0, -31.0, 4.0, 6.5)}
const SEED := 10010


static func yaw_to(d: Vector2) -> float:
	var n := d.normalized()
	return atan2(n.x, n.y)


static func local_to_world(it: Dictionary, l: Vector2) -> Vector2:
	var yaw: float = it["yaw"]
	var ax := Vector2(cos(yaw), -sin(yaw))
	var az := Vector2(sin(yaw), cos(yaw))
	return (it["p"] as Vector2) + ax * l.x + az * l.y


## 足元の 4 隅（世界）
static func corners(it: Dictionary) -> PackedVector2Array:
	var b: Array = BOX[String(it["id"])]
	var out := PackedVector2Array()
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		out.append(local_to_world(it, Vector2(float(b[4]) + s.x * float(b[0]), float(b[3]) + s.y * float(b[1]))))
	return out


static func top_h(S: RLib.TriSampler, R: RLib.TriSampler, Y: RLib.TriSampler, p: Vector2) -> float:
	var h := S.h(p.x, p.y)
	for s: RLib.TriSampler in [R, Y]:
		var v := s.h(p.x, p.y)
		if not is_nan(v):
			h = maxf(h, v)
	return h


static func item(C: Dictionary, id: String, p: Vector2, face: Vector2, tag: String, extra := {}) -> Dictionary:
	var it := {"id": id, "p": p, "yaw": yaw_to(face), "sc": Vector3.ONE, "tag": tag, "y": 0.0}
	it.merge(extra, true)
	# 接地：足元の中心と 4 隅の最低（浮かせない；坂の上側が少し沈むのは gate で上限を見る）
	var hs: Array = [top_h(C["S"], C["R"], C["Y"], p)]
	for q: Vector2 in corners(it):
		hs.append(top_h(C["S"], C["R"], C["Y"], q))
	it["y"] = hs.min()
	return it


## 主街の西縁（廣場側）：z に応じて x（P3 路面の實測：z −30→260.5、−40→263.5、−48→265.5）
static func ms_edge(z: float) -> float:
	return 260.5 + maxf(0.0, -30.0 - z) * 0.3


## 主街西側の町家列（MKT_023–027）の背面（廣場の東縁）：z に応じて x（OBB 實測：z −29.8→249.25、傾き −0.3）
static func back_x(z: float) -> float:
	return 249.25 + (-29.8 - z) * 0.3


static func plan(v: Node3D) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var C := {"S": RLib.terrain_sampler(v), "R": RLib.road_sampler(v), "Y": ML.yard_sampler(v)}
	var items: Array = []
	var anchors: Array = []
	var w_in := Vector2(-0.958, -0.287)                  # 町家の背面 → 廣場（西）
	var along := Vector2(0.287, -0.958)                   # 町家列（北行き）
	var row_e := func(z: float) -> Vector2:              # 東の列の線（町家の背面から 1.75 m）
		return Vector2(back_x(z), z) + w_in * 1.75
	# ── 東の列（町家の背面に背を寄せた屋台 5、西向き、4.6 m 間隔）：八百屋・茶店・一膳飯・飴屋・団子屋
	var east := []
	for e: Array in [["mk_yatai_yasai", -33.4], ["mk_yatai_cha", -38.0], ["mk_yatai_meshi", -42.6], ["mk_yatai_ame", -47.2], ["mk_yatai_dango", -51.8]]:
		var it := item(C, e[0], row_e.call(e[1]), w_in, "east")
		items.append(it)
		east.append(it)
	items.append(item(C, "mk_nobori_yasai", row_e.call(-35.7) + w_in * 0.2, w_in, "east"))
	items.append(item(C, "wk_tawara3", row_e.call(-35.7) - w_in * 0.55, w_in, "east_side"))
	items.append(item(C, "sk_bench", row_e.call(-40.3), w_in, "east_seat"))
	items.append(item(C, "mk_kanban_dango", row_e.call(-44.9) + w_in * 0.15, w_in, "east"))
	items.append(item(C, "kr_okeyama", row_e.call(-49.5) - w_in * 0.2, w_in, "east_side"))
	items.append(item(C, "mk_nobori_cha", row_e.call(-54.0) + w_in * 0.2, w_in, "east"))
	items.append(item(C, "sk_tensui", row_e.call(-54.0) - w_in * 0.6, w_in, "east_side"))
	# ── 北東の角：番傘と床几（茶店・団子屋の客の休み場）
	items.append(item(C, "mk_bangasa", Vector2(253.4, -56.6), Vector2(0, 1), "tea"))
	items.append(item(C, "gd_shogi", Vector2(251.9, -55.6), Vector2(1, 0.3), "tea"))
	items.append(item(C, "gd_shogi", Vector2(254.7, -58.0), Vector2(-0.3, 1), "tea"))
	# ── 西の列（布棚 4、東向き、3.9 m 間隔）：反物・笠と傘・瀬戸物・玩具
	var west := []
	for e: Array in [["mk_tana_nuno", -36.4], ["mk_tana_kasa", -40.3], ["mk_tana_seto", -44.2], ["mk_tana_omocha", -48.1]]:
		var it := item(C, e[0], Vector2(235.2, e[1]), Vector2(1, 0), "west")
		items.append(it)
		west.append(it)
	items.append(item(C, "mk_nobori_tanmono", Vector2(236.65, -34.95), Vector2(1, 0), "west"))
	items.append(item(C, "mk_kanban_furugi", Vector2(236.6, -38.35), Vector2(1, 0), "west"))
	items.append(item(C, "mk_kanban_seto", Vector2(236.6, -46.15), Vector2(1, 0), "west"))
	items.append(item(C, "mk_nobori_seto", Vector2(236.2, -50.1), Vector2(1, 0), "west"))
	# ── 北の突き当たり：荒物屋の布棚・魚屋の屋台（南向き）
	var zakka := item(C, "mk_tana_zakka", Vector2(241.4, -57.4), Vector2(0, 1), "north")
	items.append(zakka)
	var sakana := item(C, "mk_yatai_sakana", Vector2(248.4, -57.3), Vector2(0, 1), "north")
	items.append(sakana)
	# ── 中の列（背中合わせ、真ん中に切れ目）
	var mush1 := item(C, "mk_mushiro_yasai", Vector2(241.0, -35.3), Vector2(-1, 0), "center")
	items.append(mush1)
	var tsuke := item(C, "mk_mushiro_tsuke", Vector2(241.0, -49.5), Vector2(-1, 0), "center")
	items.append(tsuke)
	var mush2 := item(C, "mk_mushiro_kago", Vector2(245.2, -35.6), Vector2(1, 0), "center")
	items.append(mush2)
	var endai := item(C, "mk_endai_uri", Vector2(245.3, -49.4), Vector2(1, 0), "center")
	items.append(endai)
	items.append(item(C, "sz_stool", local_to_world(mush1, Vector2(0.75, -1.5)), Vector2(-1, 0), "center_seat"))
	items.append(item(C, "sz_stool", local_to_world(mush2, Vector2(-0.6, -1.0)), Vector2(1, 0), "center_seat"))
	items.append(item(C, "sz_stool", local_to_world(endai, Vector2(0.3, -0.75)), Vector2(1, 0), "center_seat"))
	# ── 提灯の吊り綱 3（西の通り・東の通り・入口の口の上）
	items.append(item(C, "mk_chochin_line", Vector2(238.6, -38.35), Vector2(0, 1), "lantern"))
	items.append(item(C, "mk_chochin_line", Vector2(248.0, -45.4), Vector2(0, 1), "lantern"))
	items.append(item(C, "mk_chochin_line", Vector2(246.1, -30.8), Vector2(0, 1), "lantern"))
	# ── 入口：天秤の振り売り、「市」の幟
	var tenbin := item(C, "mk_tenbin", Vector2(241.6, -26.4), Vector2(0.3, 1), "south")
	items.append(tenbin)
	items.append(item(C, "mk_nobori_ichi", Vector2(240.4, -24.9), Vector2(0.6, 1), "gate"))
	# ── 裏手（北・西）
	items.append(item(C, "mk_hoshimono", Vector2(231.6, -55.4), Vector2(1, 0), "back"))
	items.append(item(C, "mk_kame", Vector2(236.7, -60.6), Vector2(0.3, 1), "back"))
	items.append(item(C, "mk_tsumini", Vector2(252.2, -61.0), Vector2(0, 1), "back"))
	var kuruma := item(C, "mk_kuruma_ni", Vector2(230.4, -44.0), Vector2(0.1, 1), "back")
	items.append(kuruma)
	items.append(item(C, "sk_teoke", Vector2(239.2, -59.8), Vector2(0, 1), "back"))
	# ── NPC activity anchors
	var A := func(id: String, act: String, p: Vector2, face: Vector2, ref := "") -> void:
		anchors.append({"id": id, "activity": act, "p": p, "yaw": yaw_to(face), "ref": ref})
	for s: Dictionary in east + [sakana]:
		var fz := local_to_world(s, Vector2(0, 1)) - (s["p"] as Vector2)
		var nm := String(s["id"]).trim_prefix("mk_")
		A.call("vendor_" + nm, "vendor_stand", local_to_world(s, Vector2(0.0, -0.3)), fz, s["id"])
		A.call("customer_" + nm + "_a", "customer_browse", local_to_world(s, Vector2(-0.6, 1.25)), -fz, s["id"])
		A.call("customer_" + nm + "_b", "customer_buy", local_to_world(s, Vector2(0.65, 1.2)), -fz, s["id"])
	for s: Dictionary in west + [zakka]:
		var fz := local_to_world(s, Vector2(0, 1)) - (s["p"] as Vector2)
		var nm := String(s["id"]).trim_prefix("mk_")
		A.call("vendor_" + nm, "vendor_sit", local_to_world(s, Vector2(1.2, -0.75)), fz, s["id"])
		A.call("customer_" + nm + "_a", "customer_browse", local_to_world(s, Vector2(-0.5, 1.45)), -fz, s["id"])
		A.call("customer_" + nm + "_b", "customer_browse", local_to_world(s, Vector2(0.7, 1.55)), -fz, s["id"])
	for s: Dictionary in [mush1, mush2, tsuke, endai]:
		var fz := local_to_world(s, Vector2(0, 1)) - (s["p"] as Vector2)
		var nm := String(s["id"]).trim_prefix("mk_")
		var vp: Vector2 = {mush1: Vector2(0.75, -1.5), mush2: Vector2(-0.6, -1.0), tsuke: Vector2(-0.6, -1.45), endai: Vector2(0.3, -0.75)}[s]
		A.call("seller_" + nm, "vendor_sit", local_to_world(s, vp), fz, s["id"])
		A.call("customer_" + nm, "customer_crouch" if String(s["id"]).begins_with("mk_mushiro") else "customer_browse", local_to_world(s, Vector2(0.2, 1.25)), -fz, s["id"])
	A.call("tea_guest_a", "sit_tea", Vector2(251.9, -55.6) + Vector2(0.3, 0.2), Vector2(1, 0.3), "gd_shogi")
	A.call("tea_guest_b", "sit_tea", Vector2(254.7, -58.0) + Vector2(-0.4, 0.1), Vector2(-0.3, 1), "gd_shogi")
	A.call("meshi_guest", "sit_eat", row_e.call(-40.3) + along * 0.3, w_in, "sk_bench")
	A.call("peddler", "peddler_rest", local_to_world(tenbin, Vector2(-0.3, 0.75)), Vector2(0.3, 1), "mk_tenbin")
	A.call("porter", "porter_unload", local_to_world(kuruma, Vector2(0.95, 0.3)), Vector2(-1, 0), "mk_kuruma_ni")
	A.call("walker_a", "walk", Vector2(238.5, -44.0), Vector2(0.05, -1))
	A.call("walker_b", "walk", Vector2(247.4, -42.0), Vector2(-0.1, 1))
	A.call("walker_c", "walk", Vector2(246.0, -27.5), Vector2(-0.2, -1))
	A.call("walker_d", "walk", Vector2(243.1, -42.6), Vector2(1, 0.1))
	return {"items": items, "anchors": anchors, "C": C, "ms": Time.get_ticks_msec() - t0}


static func mesh_dir(id: String) -> String:
	return DIRS[id.substr(0, 3)]


static func bake(P: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	var groups := {}
	for nm: String in ["Stalls", "Goods", "Signs", "Back", "Anchors"]:
		var n := Node3D.new()
		n.name = nm
		root.add_child(n)
		groups[nm] = n
	var col := StaticBody3D.new()
	col.name = "Collision"
	root.add_child(col)
	var meshes := {}
	var n_i := 0
	var ns := 0
	for it: Dictionary in P["items"]:
		var id := String(it["id"])
		var node := Node3D.new()
		node.name = "%03d_%s" % [n_i, id]
		node.transform = Transform3D(Basis(Vector3.UP, float(it["yaw"])), Vector3((it["p"] as Vector2).x, float(it["y"]), (it["p"] as Vector2).y))
		node.set_meta("mk_id", id)
		node.set_meta("mk_tag", String(it["tag"]))
		var grp := "Stalls" if id in STALL else ("Signs" if id.begins_with("mk_nobori") or id.begins_with("mk_kanban") or id == "mk_bangasa" or id in LINE else
			("Back" if String(it["tag"]) == "back" or String(it["tag"]).ends_with("_side") or String(it["tag"]) == "east_back" else "Goods"))
		(groups[grp] as Node).add_child(node)
		for lod in 2:
			var key := id + ("_l1" if lod == 1 else "")
			if not meshes.has(key):
				meshes[key] = load(mesh_dir(id) + key + ".res")
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % lod
			mi.mesh = meshes[key]
			mi.visibility_range_begin = 0.0 if lod == 0 else LOD_SWITCH
			mi.visibility_range_end = LOD_SWITCH if lod == 0 else 220.0
			if lod == 1:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
		if id in LINE:
			for sx in [-2.5, 2.5]:
				var pb := BoxShape3D.new()
				pb.size = Vector3(0.12, 3.3, 0.12)
				var pcs := CollisionShape3D.new()
				pcs.name = "%s_c%d" % [node.name, 0 if sx < 0 else 1]
				pcs.shape = pb
				var pba := Basis(Vector3.UP, float(it["yaw"]))
				pcs.transform = Transform3D(pba, node.transform.origin + pba * Vector3(sx, 1.65, 0.0))
				col.add_child(pcs)
				ns += 1
		elif not (id in NO_COLLIDE):
			var b: Array = BOX[id]
			var bx := BoxShape3D.new()
			bx.size = Vector3(float(b[0]) * 2.0, float(b[2]), float(b[1]) * 2.0)
			var cs := CollisionShape3D.new()
			cs.name = "%s_c" % node.name
			cs.shape = bx
			var ba := Basis(Vector3.UP, float(it["yaw"]))
			cs.transform = Transform3D(ba, node.transform.origin + ba * Vector3(float(b[4]), float(b[2]) * 0.5, float(b[3])))
			col.add_child(cs)
			ns += 1
		n_i += 1
	var C: Dictionary = P["C"]
	for a: Dictionary in P["anchors"]:
		var mk := Marker3D.new()
		mk.name = String(a["id"])
		var p: Vector2 = a["p"]
		mk.transform = Transform3D(Basis(Vector3.UP, float(a["yaw"])), Vector3(p.x, top_h(C["S"], C["R"], C["Y"], p), p.y))
		mk.set_meta("activity", String(a["activity"]))
		mk.set_meta("ref", String(a["ref"]))
		mk.add_to_group("npc_activity_anchor", true)
		(groups["Anchors"] as Node).add_child(mk)
	root.set_meta("items", (P["items"] as Array).size())
	root.set_meta("anchors", (P["anchors"] as Array).size())
	root.set_meta("shapes", ns)
	root.set_meta("art_revision", "P10 R1 市集廣場 r3（ART_REVIEW 前）")
	return root


static func own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		if c.scene_file_path == "":
			own(c, owner)
