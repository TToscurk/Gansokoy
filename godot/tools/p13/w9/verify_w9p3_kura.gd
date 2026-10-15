extends SceneTree
## P13 W9 Phase 3 R2 局所 gate：B_P_MXC_005（質屋）の白い蔵の比例。
##   godot --headless --path godot --script res://tools/p13/w9/verify_w9p3_kura.gd
## 使用者（2026-10-15 ART_REVIEW ACCEPTED）：「白蔵が高く細く、TPS で塔に読める。倉庫の量体にせよ」。
## 保存された L0 メッシュ（B_P_MXC_005_L0.res・局部座標＝建物 body の原点）から実測する：
##   店＝x ≤ −0.05（左）／蔵＝x ≥ +0.05（右）。棟＝各側の最高点。蔵の幅・奥行＝足元（y ≤ 0.5 m＝石の土台と壁の下端）の頂点の範囲
##   （屋根・庇の出は含めない）。
## 規則（R1 の数値＝幅 3.0・棟 7.1・奥行 6.8・店の棟 6.7 が全部落ちる）：
##   (a) 蔵の棟は店の棟より 1.0 m 以上低い（付属の倉）　 (b) 蔵の棟 ≤ 5.2 m　 (c) 蔵の壁の幅 ≥ 3.3 m
##   (d) 棟高 ÷ 壁幅 ≤ 1.6（塔の細長さを避ける）　 (e) 蔵の奥行 ≥ 壁幅 × 2.5（横に長い量体）
## 数値の変化の根拠は設計書（build_w9r2_arch.py の build_mxc005 の docstring）。このスクリプトは場景を書かない。
const MESH := "res://assets/village_v2/w9r2_arch/mesh/B_P_MXC_005_L0.res"
const KURA_X0 := 0.05
const FOOT_Y := 0.5
const RIDGE_BELOW_SHOP := 1.0
const RIDGE_MAX := 5.2
const WIDTH_MIN := 3.3
const RATIO_MAX := 1.6
const DEPTH_FACTOR := 2.5

var passed := 0
var failed := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("[W9KURA] PASS ", msg)
	else:
		failed += 1
		print("[W9KURA] FAIL ", msg)


func _init() -> void:
	_run.call_deferred()


## 蔵の実測値 → 違反の理由（空＝適合）。k＝{ridge, shop_ridge, width, depth}
static func issues(k: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var ridge := float(k["ridge"])
	var width := float(k["width"])
	if ridge > float(k["shop_ridge"]) - RIDGE_BELOW_SHOP:
		out.append("蔵の棟 %.2f が店の棟 %.2f より %.1f m 以上低くない" % [ridge, float(k["shop_ridge"]), RIDGE_BELOW_SHOP])
	if ridge > RIDGE_MAX:
		out.append("蔵の棟 %.2f > %.1f m" % [ridge, RIDGE_MAX])
	if width < WIDTH_MIN:
		out.append("蔵の壁の幅 %.2f < %.1f m" % [width, WIDTH_MIN])
	if ridge / maxf(width, 0.01) > RATIO_MAX:
		out.append("棟高÷幅 %.2f > %.1f（塔の比）" % [ridge / maxf(width, 0.01), RATIO_MAX])
	if float(k["depth"]) < width * DEPTH_FACTOR:
		out.append("奥行 %.2f < 幅×%.1f＝%.2f（横に長くない）" % [float(k["depth"]), DEPTH_FACTOR, width * DEPTH_FACTOR])
	return out


static func measure(mesh: Mesh) -> Dictionary:
	var ridge := -1.0e9
	var shop_ridge := -1.0e9
	var wx0 := 1.0e9
	var wx1 := -1.0e9
	var wz0 := 1.0e9
	var wz1 := -1.0e9
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for p in v:
			if p.x >= KURA_X0:
				ridge = maxf(ridge, p.y)
				if p.y <= FOOT_Y:
					wx0 = minf(wx0, p.x)
					wx1 = maxf(wx1, p.x)
					wz0 = minf(wz0, p.z)
					wz1 = maxf(wz1, p.z)
			elif p.x <= -KURA_X0:
				shop_ridge = maxf(shop_ridge, p.y)
	return {"ridge": ridge, "shop_ridge": shop_ridge, "width": wx1 - maxf(wx0, 0.0), "depth": wz1 - wz0}


func _run() -> void:
	var mesh := load(MESH) as Mesh
	_ok(mesh != null, "MXC_005 の L0 メッシュを読めた（%s）" % MESH)
	if mesh == null:
		quit(1)
		return
	var k := measure(mesh)
	print("[W9KURA]   実測：蔵の棟 %.2f m・店の棟 %.2f m・蔵の壁の幅 %.2f m・奥行 %.2f m・棟高÷幅 %.2f" % [float(k["ridge"]), float(k["shop_ridge"]), float(k["width"]), float(k["depth"]), float(k["ridge"]) / float(k["width"])])
	var iss := issues(k)
	_ok(iss.is_empty(), "蔵は付属の低い倉庫の量体（a 店より 1.0 m 低い・b 棟 ≤ 5.2 m・c 幅 ≥ 3.3 m・d 棟高÷幅 ≤ 1.6・e 奥行 ≥ 幅×2.5）%s" % str(iss))
	# 反向案例
	var r1 := {"ridge": 7.1, "shop_ridge": 6.7, "width": 3.0, "depth": 6.8}                     # R1（0fdea17）の蔵＝塔に読めた
	var n1 := issues(r1)
	_ok(not n1.is_empty() and n1.size() >= 4, "反向：R1 の蔵（幅 3.0・棟 7.1・奥行 6.8）は %d 項で落ちる（%s）" % [n1.size(), str(n1)])
	var slim := {"ridge": 4.9, "shop_ridge": 6.7, "width": 2.2, "depth": 10.0}                  # 低くても細い（幅 2.2）
	_ok(not issues(slim).is_empty(), "反向：低くても細い蔵（幅 2.2）は落ちる（%s）" % str(issues(slim)))
	var tall := {"ridge": 6.0, "shop_ridge": 6.7, "width": 3.5, "depth": 10.0}                  # 店とほぼ同じ高さ
	_ok(not issues(tall).is_empty(), "反向：店とほぼ同じ高さの蔵（棟 6.0）は落ちる（%s）" % str(issues(tall)))
	var stubby := {"ridge": 4.9, "shop_ridge": 6.7, "width": 3.5, "depth": 6.0}                 # 奥行が足りない（立方体に近い）
	_ok(not issues(stubby).is_empty(), "反向：奥行 6.0 m の立方体に近い蔵は落ちる（%s）" % str(issues(stubby)))
	print("[W9KURA] PASS %d  FAIL %d" % [passed, failed])
	print("[W9KURA] 結果：%d 項失敗" % failed)
	quit(1 if failed > 0 else 0)
