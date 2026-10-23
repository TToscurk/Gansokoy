extends "res://tools/beast_path/s01_ground.gd"
## 獸道 S02／S03 森林地表（Beast Path 全區美術完成指令，2026-10-17）。
## 沿用 S01 R3 的地表系統（同一個 shader bp_ground_s01.gdshader、同一套 13 通道），讓 S01 → S02 → S03 的林床是同一種語言，
## 而不是 V0.1 白模的平塗頂點色。S02／S03 是「S01 的深處」：u 固定在 1（vil＝0、forest_k＝deep＝1），差異由 layout.zone_ground 的 r3 參數決定。
##   · 兩區共用同一個實例與同一組場（範圍 z −344…−96）→ S02／S03 的接縫列逐點相同；
##   · 與 S01 的接縫：z −112 → −100 之間逐步改用 S01 自己的通道（z −100 那一列＝S01 的值）；
##   · 與 S04 的接縫：z −324 → −340 之間逐步改用 S04 的 bp_lib.ground_channels（S04 V1.3 不動）；
##   · 只動頂點通道與材質，不動高度（地形碰撞網格的頂點位置不變）。
## 樹（凍結的 V0.1 位置）照舊；舊的 V0.1 林下 prefab（kind＝under）在候選中不載入，林床改由 zone_dress（Blender kit）負責。

const SELF := "res://tools/beast_path/zone_ground.gd"
const ZBOUNDS := Rect2(-114.0, -344.0, 228.0, 248.0)
const MAT_PATH := "res://assets/beast_path/materials/bp_ground_zone.tres"

var s01g = null
var s01ctx := {}
var s04ctx := {}
var seam_s01 := Vector2(-112.0, -100.0)
var seam_s04 := Vector2(-340.0, -324.0)


func setup(lib_: BP) -> void:
	super.setup(lib_)
	var zc: Dictionary = lib.L.get("zone_ground", {})
	var c2: Dictionary = cfg.duplicate(true)
	c2["features"] = zc.get("features", [])
	var r3b: Dictionary = (cfg.get("r3", {}) as Dictionary).duplicate(true)
	for k: String in (zc.get("r3", {}) as Dictionary):
		r3b[k] = zc["r3"][k]
	c2["r3"] = r3b
	if zc.has("road_vis_k"):
		c2["road_vis_k"] = zc["road_vis_k"]               # 荒野化 R3：S02／S03 的視覺路寬
	if zc.has("shoulder_k"):
		c2["shoulder_k"] = zc["shoulder_k"]
	cfg = c2
	r3 = r3b
	r3_on = true
	# u≡1：S02／S03 全區都是 S01 最深處的延伸（村緣帶、草地段的規則不適用）
	s0 = lib.st_s("s01_s02") - 5000.0
	s_len = 5000.0
	_build_features()


func channels(ix: int, iz: int, ctx: Dictionary) -> PackedFloat32Array:
	var z := lib.lz0 + float(iz) * lib.cell
	var out: PackedFloat32Array = super.channels(ix, iz, ctx)
	if s01g != null and z > seam_s01.x:
		out = _mix(out, s01g.channels(ix, iz, s01ctx), smoothstep(seam_s01.x, seam_s01.y, z))
	if not s04ctx.is_empty() and z < seam_s04.y:
		out = _mix(out, lib.ground_channels(ix, iz, s04ctx), 1.0 - smoothstep(seam_s04.x, seam_s04.y, z))
	return out


static func _mix(a: PackedFloat32Array, b: PackedFloat32Array, w: float) -> PackedFloat32Array:
	if w <= 0.0:
		return a
	var n := maxi(a.size(), b.size())
	var o := PackedFloat32Array()
	o.resize(n)
	for k in n:
		var va := a[k] if k < a.size() else 0.0
		var vb := b[k] if k < b.size() else (0.0 if k != 8 else 0.0)
		o[k] = vb if w >= 1.0 else lerpf(va, vb, w)
	return o


## 回傳給 terrain_generator.build_tile 的 ctx（S02、S03 共用一份）
static func build_ctx_zone(lib_: BP, trees: Array, kit: Dictionary, feet: Array, s01ctx: Dictionary, s04ctx: Dictionary) -> Dictionary:
	var B := ZBOUNDS
	var crowns: Array = []
	for t: Dictionary in trees:
		var z := float(t["z"])
		if z < B.position.y - 10.0 or z > B.end.y + 10.0:
			continue
		var kind := String(t["kind"])
		if kind == "bamboo":
			# 竹林：竹稈細、樹冠窄但成林後整片遮蔭（林床＝落葉、苔、笹；不是草地）
			crowns.append({"x": float(t["x"]), "z": z, "reach": 2.2, "w": 0.55})
			continue
		if kind != "tree" and kind != "pin" and kind != "landmark":
			continue
		var hh := float((kit[String(t["id"])] as Dictionary)["h"]) * float(t["s"])
		crowns.append({"x": float(t["x"]), "z": z, "reach": clampf(hh * 0.30, 2.0, 8.0), "w": clampf(hh / 20.0, 0.4, 1.3)})
	var rocks: Array = []
	for f: Dictionary in feet:
		var id := String(f["id"])
		var q: Vector2 = f["p"]
		if q.y < B.position.y - 4.0 or q.y > B.end.y + 4.0:
			continue
		if id.contains("rock") or id.contains("stone") or id.contains("boulder") or id.contains("roots"):
			rocks.append({"p": q, "r": float(f["r"])})
	var inst = load(SELF).new(lib_)
	var ctx := {"s01": inst, "canopy": lib_.build_canopy_field(crowns), "rock_d": lib_.build_rockprox_field(rocks),
		"n_crowns": crowns.size(), "n_rocks": rocks.size(), "mat_path": MAT_PATH}
	var r3c: Dictionary = inst.r3
	ctx.merge(_r3_fields(lib_, trees, kit, r3c, {}, B, "Z"))
	if not s01ctx.is_empty():
		inst.s01g = s01ctx["s01"]
		inst.s01ctx = s01ctx
	inst.s04ctx = s04ctx
	return ctx
