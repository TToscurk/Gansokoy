extends SceneTree
## P13 W9 Phase 3 R2：正式 TPS の相機から見た『近景の遮蔽率』を、保存済みの L0 メッシュに ray を撃って数える（headless 可・場景は書かない）。
##   godot --headless --path godot --script res://tools/p13/w9/verify_w9p3_view.gd
## 使用者（2026-10-15）：「bT3／bT4 の正常 TPS で BEFORE／AFTER の相機位置と構図に可比性があること」。
## bT3 の相機は元の場景と同じ位置（建物の前面の平面・足元から 3.48 m・高さ 2.2 m）にあり、071 の柴棚の屋根の『下』に入る（屋根は視覚だけで碰撞なし）。
## 相機の 16:9 の画面を 64×36 の ray で走査し、071 の overlay メッシュの近景（相機から d_near 以内）に当たる割合を数える。
##   相機・玩家の位置は 正式 TPS 撮影（w7_shots の <tag>_index.json）の値。メッシュ変換は arch_w9r2_p13.scn の節点 transform。
## 規則：近景（≤ 1.8 m）の遮蔽率が上限以下（柱・斜材が画面の大きな部分を塞がない）。
## 反向案例：R2 の初版（腕木＋斜材 4 本・実測 31.5 %）を modules の eaves から再現して足すと上限を超えて落ちる。
const SCN := "res://maps/village_v2/gen/arch_w9r2_p13.scn"
const MESH := "res://assets/village_v2/w9r2_arch/mesh/B_P_RSW_071_L0.res"
const BUILD := "B_P_RSW_071"
const VFOV := 75.0
const ASPECT := 16.0 / 9.0
const NX := 64
const NY := 36
const NEAR := 1.8
const META := "res://assets/village_v2/w9r2_arch/src/modules_blender.json"
## 正式 TPS 撮影の相機（RB_index.json）：cam・fwd（北＝−z）
const CAMS := {
	"bT3": {"cam": Vector3(235.168, 3.618, -84.968), "fwd": Vector3(0.2296, -0.179, -0.9567)},
	"bT4": {"cam": Vector3(244.456, 3.614, -82.643), "fwd": Vector3(0.2653, -0.179, -0.9474)},
}
## bT3 の近景遮蔽率の上限。相機は庇の下に入るので屋根裏板だけで約 2 割（R2b の実測 20.5 %）。斜材 4 本を足した R2 の初版は 31.5 %（使用者に見せる前に自分で外した）。
## bT4 は柴棚が画面に入らない
const BT3_MAX := 0.22
const BT4_MAX := 0.02

var passed := 0
var failed := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("[W9VIEW] PASS ", msg)
	else:
		failed += 1
		print("[W9VIEW] FAIL ", msg)


func _init() -> void:
	_run.call_deferred()


## 太さ (w×h) の梁 a→b を 12 三角形で（断面の向き＝梁の軸と X 軸に垂直）
static func _beam(faces: PackedVector3Array, a: Vector3, b: Vector3, w: float, h: float) -> void:
	var ax := (b - a).normalized()
	var wx := Vector3.RIGHT * (w * 0.5)
	var nn := ax.cross(Vector3.RIGHT).normalized() * (h * 0.5)
	var c: Array = []
	for end: Vector3 in [a, b]:
		for sx in [-1.0, 1.0]:
			for sn in [-1.0, 1.0]:
				c.append(end + wx * float(sx) + nn * float(sn))
	for q: Array in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		faces.append_array(PackedVector3Array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]]))


## R2 の初版の斜材（eave_roof の strut：壁の y−1.05 から前縁の ye−0.30 へ・断面 0.06×0.08・腕木と同じ間隔）を meta の eaves から再現
static func strut_faces(e: Dictionary) -> PackedVector3Array:
	var x0 := float(e["x0"])
	var x1 := float(e["x1"])
	var y := float(e["y"])
	var zf := float(e["zf"])
	var s := float(e["depth"])
	var ye := y - s * float(e["p"])
	var L := x1 - x0
	var nb := maxi(2, int(ceil(L / 1.15)))
	var faces := PackedVector3Array()
	for i in nb + 1:
		var xb := x0 + 0.15 + (L - 0.3) * float(i) / float(nb)
		_beam(faces, Vector3(xb, y - 1.05, zf - 0.02), Vector3(xb, ye - 0.30, zf + s - 0.12), 0.06, 0.08)
	return faces


static func coverage(tm: TriangleMesh, xf: Transform3D, cam: Vector3, fwd: Vector3, near: float) -> Dictionary:
	var f := fwd.normalized()
	var right := f.cross(Vector3.UP).normalized()
	var up := right.cross(f).normalized()
	var th := tan(deg_to_rad(VFOV) * 0.5)
	var tw := th * ASPECT
	var inv := xf.affine_inverse()
	var o := inv * cam
	var hit_near := 0
	var hit_any := 0
	var dmin := 1.0e9
	for iy in NY:
		for ix in NX:
			var u := (float(ix) + 0.5) / float(NX) * 2.0 - 1.0
			var v := 1.0 - (float(iy) + 0.5) / float(NY) * 2.0
			var d := (f + right * (u * tw) + up * (v * th)).normalized()
			var dl := inv.basis * d
			var r := tm.intersect_ray(o, dl)
			if r.is_empty():
				continue
			var t := o.distance_to(r["position"] as Vector3)
			hit_any += 1
			dmin = minf(dmin, t)
			if t <= near:
				hit_near += 1
	var tot := NX * NY
	return {"near": float(hit_near) / float(tot), "any": float(hit_any) / float(tot), "dmin": dmin}


func _run() -> void:
	var ps := load(SCN) as PackedScene
	var mesh := load(MESH) as Mesh
	_ok(ps != null and mesh != null, "arch_w9r2_p13.scn と %s の L0 メッシュを読めた" % BUILD)
	if ps == null or mesh == null:
		quit(1)
		return
	var root := ps.instantiate() as Node3D
	var nd := root.get_node_or_null(BUILD) as Node3D
	_ok(nd != null, "overlay に %s がある" % BUILD)
	var xf := nd.transform
	print("[W9VIEW]   %s の transform origin=%s basis.z=%s（village 直下の overlay なので建物 body と同じ）" % [BUILD, str(xf.origin), str(xf.basis.z)])
	var tm := mesh.generate_triangle_mesh()
	_ok(tm != null, "TriangleMesh を作れた（%d 面）" % (tm.get_faces().size() / 3))
	var res := {}
	for k: String in CAMS:
		var c: Dictionary = CAMS[k]
		res[k] = coverage(tm, xf, c["cam"] as Vector3, c["fwd"] as Vector3, NEAR)
		print("[W9VIEW]   %s：相機から %.1f m 以内の 071 overlay が画面の %.1f %%（全距離では %.1f %%・最近 %.2f m）" % [k, NEAR, 100.0 * float((res[k] as Dictionary)["near"]), 100.0 * float((res[k] as Dictionary)["any"]), float((res[k] as Dictionary)["dmin"])])
	_ok(float((res["bT3"] as Dictionary)["near"]) <= BT3_MAX, "bT3：近景（≤ %.1f m）の 071 overlay の遮蔽率 %.1f %% ≤ %.0f %%（正式 TPS・相機は元の場景と同じ位置）" % [NEAR, 100.0 * float((res["bT3"] as Dictionary)["near"]), 100.0 * BT3_MAX])
	_ok(float((res["bT4"] as Dictionary)["near"]) <= BT4_MAX, "bT4：近景の 071 overlay の遮蔽率 %.1f %% ≤ %.0f %%" % [100.0 * float((res["bT4"] as Dictionary)["near"]), 100.0 * BT4_MAX])
	# 反向案例：相機を柴棚の真ん中（庇の下・奥）へ 0.5 m 進めると遮蔽率は上がる＝この計測は『庇の下の相機』を区別できる
	var c3: Dictionary = CAMS["bT3"]
	var back: Vector3 = (c3["cam"] as Vector3) - ((c3["fwd"] as Vector3) * Vector3(1, 0, 1)).normalized() * 0.5
	var deeper := coverage(tm, xf, back, c3["fwd"] as Vector3, NEAR)
	_ok(float(deeper["near"]) > float((res["bT3"] as Dictionary)["near"]) + 0.02, "反向：相機を庇の奥へ 0.5 m 下げると近景遮蔽率が %.1f %% → %.1f %% に上がる（計測が相機位置に反応する）" % [100.0 * float((res["bT3"] as Dictionary)["near"]), 100.0 * float(deeper["near"])])
	var outside: Vector3 = (c3["cam"] as Vector3) + ((c3["fwd"] as Vector3) * Vector3(1, 0, 1)).normalized() * 2.0
	var out_cov := coverage(tm, xf, outside, c3["fwd"] as Vector3, NEAR)
	_ok(float(out_cov["near"]) < float((res["bT3"] as Dictionary)["near"]) * 0.5 + 0.001, "反向：相機を庇の外（2 m 前）へ出すと近景遮蔽率が %.1f %% → %.1f %% に下がる" % [100.0 * float((res["bT3"] as Dictionary)["near"]), 100.0 * float(out_cov["near"])])
	# 反向案例：R2 の初版の斜材を足す
	var mj: Variant = JSON.parse_string(FileAccess.get_file_as_string(META))
	var ev: Array = ((mj as Dictionary)["eaves"] as Dictionary).get(BUILD, [])
	_ok(ev.size() >= 1 and not bool((ev[0] as Dictionary)["strut"]), "meta：071 の庇は斜材なし（strut=false）・庇柱 %d 本" % ((ev[0] as Dictionary)["posts"] as Array).size())
	var faces := mesh.get_faces()
	faces.append_array(strut_faces(ev[0] as Dictionary))
	var tm2 := TriangleMesh.new()
	tm2.create_from_faces(faces)
	var with_struts := coverage(tm2, xf, c3["cam"] as Vector3, c3["fwd"] as Vector3, NEAR)
	_ok(float(with_struts["near"]) > BT3_MAX and float(with_struts["near"]) > float((res["bT3"] as Dictionary)["near"]) + 0.05, "反向：R2 の初版の斜材 %d 本を足すと bT3 の近景遮蔽率が %.1f %% → %.1f %% に上がり上限 %.0f %% を超えて落ちる" % [int(ev.size() > 0) * (int(ceil((float((ev[0] as Dictionary)["x1"]) - float((ev[0] as Dictionary)["x0"])) / 1.15)) + 1), 100.0 * float((res["bT3"] as Dictionary)["near"]), 100.0 * float(with_struts["near"]), 100.0 * BT3_MAX])
	root.free()
	print("[W9VIEW] PASS %d  FAIL %d" % [passed, failed])
	print("[W9VIEW] 結果：%d 項失敗" % failed)
	quit(1 if failed > 0 else 0)
