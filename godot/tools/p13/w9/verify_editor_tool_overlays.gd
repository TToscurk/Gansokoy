extends SceneTree
## 編輯器 @tool overlay の存檔安全 gate（2026-10-17）：ArchW9R2P13（arch_w9r2.gd）・DevLayerGate（dev_layer_gate.gd）。
##   godot --headless --path godot --script res://tools/p13/w9/verify_editor_tool_overlays.gd
## 編輯器と同じ条件を作る：@tool でない腳本を全部外してから village_v2 を木に入れる（編輯器では @tool しか走らない）。
## 見るもの：
##   1. ArchW9R2P13 が Kit を隠す（hidden_count>0）・hide_extra0 の前角柱 5 本も隠れる
##   2. DevLayerGate（遊戲路徑）が Districts 下の *ParcelLines* 全部と Debug／QuestAnchors／Portals を隠す
##   3. DevLayerGate（編輯器路徑 _hide_all(true)）が上記＋地形碰撞 Collision/TerrainCollision/Shape を隠す
##   4. NOTIFICATION_EDITOR_PRE_SAVE を流すと、visible／材質覆寫が『保存ファイルを読んだだけの状態』と完全一致（＝存檔に何も書き込まれない）
##   5. NOTIFICATION_EDITOR_POST_SAVE で ArchW9R2P13 が同じ件数を隠し直す
##   6.（W9 FIX）外形碰撞箱：有効中は Shell を持つ棟の body の元の箱が無効・Shell が有効。PRE_SAVE で両方とも保存時の disabled に戻る
##     （署名に CollisionShape3D.disabled を含む）。POST_SAVE で入れ替え直す。
##   反向：PRE_SAVE 後に 1 件だけ隠す → 比較器が 1 件の差を拾う。Shell の箱を 1 つ有効にする → 1 件の差を拾う
const SCENE := "res://maps/village_v2/village_v2.tscn"
const W9R2 := preload("res://tools/p13/w9/w9r2_lib.gd")

var passed := 0
var failed := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("[EDTOOL] PASS ", msg)
	else:
		failed += 1
		print("[EDTOOL] FAIL ", msg)


func _init() -> void:
	_run.call_deferred()


## 署名：Node3D の visible と MeshInstance3D の材質覆寫と CollisionShape3D の disabled
## 対象は 2 つの overlay が触る範囲だけ（Lighting の天象系統など他の @tool が時刻で切り替える物は含めない）
const SIG_ROOTS := ["Districts", "EnrichW9P13", "ArchW9R2P13", "Debug", "QuestAnchors", "Portals", "Collision"]


static func sig(v: Node) -> Dictionary:
	var out := {}
	for r: String in SIG_ROOTS:
		var rn := v.get_node_or_null(r)
		if rn == null:
			continue
		for n in [rn] + rn.find_children("*", "", true, false):
			if not (n is Node3D):
				continue
			var p := String(v.get_path_to(n))
			var s := "v=%s" % (n as Node3D).visible
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var mi := n as MeshInstance3D
				for i in mi.get_surface_override_material_count():
					var m := mi.get_surface_override_material(i)
					s += "|%d:%s" % [i, ("null" if m == null else (m.resource_path if m.resource_path != "" else m.get_class() + ":" + m.resource_name))]
			if n is CollisionShape3D:
				s += "|d=%s" % (n as CollisionShape3D).disabled
			out[p] = s
	return out


static func diff(a: Dictionary, b: Dictionary) -> Array:
	var d: Array = []
	for k in a:
		if b.has(k) and a[k] != b[k]:
			d.append("%s：%s → %s" % [k, a[k], b[k]])
	return d


## [Shell を持つ棟, そのうち body の箱が全部無効, Shell の箱の数, そのうち有効]
static func _swap_state(v: Node, ov: Node) -> Array:
	var nb := 0
	var nb_off := 0
	var ns := 0
	var ns_on := 0
	for b in ov.get_children():
		var sh := b.get_node_or_null("Shell")
		if sh == null:
			continue
		nb += 1
		var body := v.get_node(NodePath(String(b.get_meta("body_path"))))
		var all_off := true
		for cs in body.get_children():
			if cs is CollisionShape3D and not (cs as CollisionShape3D).disabled:
				all_off = false
		if all_off:
			nb_off += 1
		for cs in sh.get_children():
			if cs is CollisionShape3D:
				ns += 1
				if not (cs as CollisionShape3D).disabled:
					ns_on += 1
	return [nb, nb_off, ns, ns_on]


func _run() -> void:
	var ps := load(SCENE) as PackedScene
	var fresh := ps.instantiate()
	var s0 := sig(fresh)
	fresh.free()
	var v := ps.instantiate()
	var stripped := 0
	for n in [v] + v.find_children("*", "", true, false):
		var sc: Script = n.get_script()
		if sc != null and not sc.is_tool():
			n.set_script(null)
			stripped += 1
	var ov := v.get_node("ArchW9R2P13")
	var gate := v.get_node("DevLayerGate")
	_ok(ov.get_script() != null and (ov.get_script() as Script).is_tool(), "ArchW9R2P13 の腳本は @tool（編輯器でも走る）")
	_ok(gate.get_script() != null and (gate.get_script() as Script).is_tool(), "DevLayerGate の腳本は @tool")
	print("[EDTOOL] 非 @tool 腳本を外した節點 %d" % stripped)
	root.add_child(v)
	for i in 6:
		await process_frame
	# 1. Arch
	var hc := int(ov.get("hidden_count"))
	_ok(hc > 0, "ArchW9R2P13 が Kit 構件を隠す（%d）" % hc)
	var extra_ok := 0
	var extra_n := 0
	for id: String in W9R2.SPECS:
		for nm: String in W9R2.SPECS[id].get("hide_extra0", []):
			extra_n += 1
			var k := v.get_node_or_null(NodePath(String(W9R2.SPECS[id]["path"]) + "/Kit/LOD0/" + nm)) as Node3D
			if k != null and not k.visible:
				extra_ok += 1
	_ok(extra_n == 5 and extra_ok == extra_n, "hide_extra0 の前角柱 %d/%d 本が隠れる" % [extra_ok, extra_n])
	# 1b. W9 FIX 外形碰撞箱の入れ替え
	var sw := _swap_state(v, ov)
	var cf: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(W9R2.COLFIT)) as Dictionary)["buildings"]
	var n_boxes := 0
	for k in cf:
		n_boxes += ((cf[k] as Dictionary)["boxes"] as Array).size()
	_ok(sw[0] == cf.size() and sw[0] > 0 and sw[1] == sw[0] and sw[2] == n_boxes and sw[3] == sw[2],
		"外形碰撞箱：Shell %d 棟（collision_fit.json %d 棟）の body の元の箱が無効 %d・Shell の箱 %d 個（json %d）が有効 %d" % [sw[0], cf.size(), sw[1], sw[2], n_boxes, sw[3]])
	# 2. Gate（遊戲路徑）
	var devs: Array = gate.dev_nodes(v)
	var parcels := v.get_node("Districts").find_children("*ParcelLines*", "", true, false)
	var vis_dev := 0
	for n: Node3D in devs:
		if n.visible:
			vis_dev += 1
	_ok(parcels.size() == 7 and devs.size() == 3 + parcels.size() and vis_dev == 0,
		"遊戲路徑：ParcelLines %d 個＋Debug／QuestAnchors／Portals＝%d 個すべて非表示（可見 %d）" % [parcels.size(), devs.size(), vis_dev])
	# 3. Gate（編輯器路徑）：遊戲路徑で隠した分を保存状態に戻してから _hide_all(true)
	for n: Node3D in devs:
		var key := String(v.get_path_to(n))
		n.visible = String(s0[key]).begins_with("v=true")
	gate.call("_hide_all", true)
	var shape := v.get_node("Collision/TerrainCollision/Shape") as Node3D
	vis_dev = 0
	for n: Node3D in devs:
		if n.visible:
			vis_dev += 1
	_ok(not shape.visible and vis_dev == 0, "編輯器路徑：地形碰撞 Shape と開發疊層 %d 個が非表示" % devs.size())
	# 4. PRE_SAVE → 保存ファイルの状態と完全一致
	v.propagate_notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	var d := diff(s0, sig(v))
	_ok(d.is_empty(), "PRE_SAVE 後の visible／材質覆寫が保存ファイルと一致（差 %d）%s" % [d.size(), "" if d.is_empty() else str(d.slice(0, 5))])
	_ok(int(ov.get("hidden_count")) == 0, "PRE_SAVE で ArchW9R2P13 の隠し件数 0")
	# 反向：1 件だけ隠すと比較器が拾う
	var probe := v.get_node(NodePath(String(W9R2.SPECS["B_P_MKT_012"]["path"]) + "/Kit/LOD0/post_e54_c2_21")) as Node3D
	probe.visible = false
	var dn := diff(s0, sig(v))
	probe.visible = true
	_ok(dn.size() == 1, "反向：PRE_SAVE 後に 1 件隠すと差 1 を拾う（%d）" % dn.size())
	var sw0 := _swap_state(v, ov)
	_ok(sw0[1] == 0 and sw0[3] == 0, "PRE_SAVE で外形碰撞箱の入れ替えが戻る（body 無効 %d・Shell 有効 %d）" % [sw0[1], sw0[3]])
	var sbox := v.get_node("ArchW9R2P13/B_P_MXC_007/Shell").get_child(0) as CollisionShape3D
	sbox.disabled = false
	var dc := diff(s0, sig(v))
	sbox.disabled = true
	_ok(dc.size() == 1, "反向：PRE_SAVE 後に Shell の箱を 1 つ有効にすると差 1 を拾う（%d）" % dc.size())
	# 5. POST_SAVE → 隠し直す
	v.propagate_notification(Node.NOTIFICATION_EDITOR_POST_SAVE)
	_ok(int(ov.get("hidden_count")) == hc, "POST_SAVE で ArchW9R2P13 が同じ %d 件を隠し直す（%d）" % [hc, int(ov.get("hidden_count"))])
	var sw2 := _swap_state(v, ov)
	_ok(sw2 == sw, "POST_SAVE で外形碰撞箱を入れ替え直す（%s）" % str(sw2))
	# 6. 2 回目の保存サイクルも同じ（冪等）
	v.propagate_notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	var d2 := diff(s0, sig(v))
	v.propagate_notification(Node.NOTIFICATION_EDITOR_POST_SAVE)
	_ok(d2.is_empty() and _swap_state(v, ov) == sw and int(ov.get("hidden_count")) == hc, "2 回目の PRE_SAVE／POST_SAVE も同じ結果（差 %d）" % d2.size())
	print("[EDTOOL] 結果：%d 通過・%d 失敗" % [passed, failed])
	quit(0 if failed == 0 else 1)
