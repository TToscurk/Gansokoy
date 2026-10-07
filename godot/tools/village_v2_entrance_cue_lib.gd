@tool
extends RefCounted
## P10 R3d r1.1 Market South Entrance Cue：市集の口（中橫街の北側、x 240–251）の両脇に、既存の承認済み market_kit の
## 「市」の幟（mk_nobori_ichi、竿 4 m・布 0.45 × 1.8 m）を 2 本立てるだけの小さな cue layer。
## R2（封存）の主街 props・R1 市集（封存）・Kit は一切変更しない（Kit の mesh を只讀で重用、新資産なし）。
## 布の面は南東（主街の南の辻）へ向ける：裏表とも字が正しく読める（2026-10-07 の字の向き修正済み mesh）。
## 出力 gen/entrance_cue_p10.tscn → Population/EntranceCueP10（ActivityCoreP10 の後）。Props の下に置かない
## （封存 Meadow／Environment の規劃は Props を occupancy として読むため）。
const PL := preload("res://tools/village_v2_population_lib.gd")

const OUTPUT := "res://maps/village_v2/gen/entrance_cue_p10.tscn"
const NODE_NAME := "EntranceCueP10"
const KIT := "res://assets/village_v2/market_kit/mesh/"
const LOD_SWITCH := 32.0
const POLE_R := 0.09
const POLE_H := 3.7
## [名前, mesh id, x, z, yaw°]：東の幟は布が口の内側（西）へ、西の幟は布が口の内側（東）へ出る。法線は南東を向く。
const ITEMS := [
	["nobori_ichi_east", "mk_nobori_ichi", 250.9, -23.4, 217.0],
	["nobori_ichi_west", "mk_nobori_ichi", 240.2, -23.6, 37.0],
]


static func plan(C: Dictionary) -> Array:
	var out := []
	for it: Array in ITEMS:
		var p2 := Vector2(float(it[2]), float(it[3]))
		out.append({"name": it[0], "mesh": it[1], "p": Vector3(p2.x, PL.top_h(C, p2), p2.y), "yaw": deg_to_rad(float(it[4]))})
	return out


static func build(items: Array) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	for it: Dictionary in items:
		var n := Node3D.new()
		n.name = String(it["name"])
		n.transform = Transform3D(Basis(Vector3.UP, float(it["yaw"])), it["p"])
		root.add_child(n)
		n.owner = root
		for lod in [0, 1]:
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % lod
			mi.mesh = load(KIT + String(it["mesh"]) + ("_l1" if lod == 1 else "") + ".res")
			mi.visibility_range_begin = 0.0 if lod == 0 else LOD_SWITCH
			mi.visibility_range_end = LOD_SWITCH if lod == 0 else 220.0
			n.add_child(mi)
			mi.owner = root
		var body := StaticBody3D.new()
		body.name = "Collision"
		n.add_child(body)
		body.owner = root
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = POLE_R
		cyl.height = POLE_H
		cs.shape = cyl
		cs.position = Vector3(0, POLE_H * 0.5, 0)
		body.add_child(cs)
		cs.owner = root
	root.set_meta("art_revision", "P10 R3d r1.1 Market South Entrance Cue ART_REVIEW")
	return root
