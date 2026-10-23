extends SceneTree
## 暫用探針：判定護岸面板埋入地形的成因。
## A 部：用 mesh 內存的 ARRAY_NORMAL（權威）判可見面朝向，避免 winding 正負號誤判。
## B 部：把面板當剛體，沿「沿岸方向 u」分成 5 段，量每段的地形侵入量（>0＝地形跑到面板外側，遮住石面）。
##   若侵入量集中在兩端 → 面板只依單一斷面定平面，沿岸（2.4 m 寬）起伏沒被納入。
## 用法：godot --headless --path . --script res://tools/_probe_panel_fit.gd

const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"

const U_BINS := 5


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_part_a()
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	var lib := RLib.load_lib()
	var P: Dictionary = RLib.plan(v, L)
	await physics_frame
	await physics_frame
	_part_b(v, lib, P)
	v.free()
	quit()


## A 部：ARRAY_NORMAL 為準
func _part_a() -> void:
	var lib := RLib.load_lib()
	print("── A 部：以 ARRAY_NORMAL 判可見面（mesh 區域座標）")
	for n: String in ["rb_rev_a", "rb_rev_e", "rb_revb_a", "rb_bld_a", "rb_cap_a", "rb_flag_a"]:
		var m: Mesh = lib.get(n)
		if m == null:
			continue
		var a: Array = m.surface_get_arrays(0)
		var V: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var N: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var I: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var pa := 0.0
		var na := 0.0
		var ua := 0.0
		for t in range(0, I.size(), 3):
			var p0 := V[I[t]]
			var p1 := V[I[t + 1]]
			var p2 := V[I[t + 2]]
			var ar := (p1 - p0).cross(p2 - p0).length() * 0.5
			if ar < 1e-9:
				continue
			var nn := (N[I[t]] + N[I[t + 1]] + N[I[t + 2]]).normalized()
			if nn.z > 0.7:
				pa += ar
			elif nn.z < -0.7:
				na += ar
			else:
				ua += ar
		var az := m.get_aabb()
		print("  %-11s z∈[%+.3f,%+.3f]｜法線朝 +Z 面積 %.3f、−Z %.3f、側面 %.3f → 可見＝%s" % [
			n, az.position.z, az.end.z, pa, na, ua, "+Z" if pa > na else "−Z"])


## B 部：面板剛體侵入量，沿岸分 5 段
func _part_b(v: Node3D, lib: Dictionary, P: Dictionary) -> void:
	var space := root.get_world_3d().direct_space_state
	var terrain_rid := (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	var items: Array = P["items"]
	var per_bin := []
	var tot := []
	for i in U_BINS:
		per_bin.append(0.0)
		tot.append(0)
	var worst := {}
	var n_panel := 0
	var n_bury_end := 0
	var n_clear := 0
	var need_off := []
	for it: Dictionary in items:
		if not String(it["k"]) in ["rev", "revb"]:
			continue
		var xf: Transform3D = it["xf"]
		var m: Mesh = lib[String(it["m"])]
		if m == null:
			continue
		var az := m.get_aabb()
		var x3 := xf.basis.x.normalized()
		var y3 := xf.basis.y.normalized()
		var n3 := xf.basis.z.normalized()
		var hw := az.size.x * 0.5
		var hh := az.size.y * 0.5
		n_panel += 1
		var bin_intr := []
		for b in U_BINS:
			bin_intr.append(0.0)
		var mx := 0.0
		for bi in U_BINS:
			var u := -1.0 + 2.0 * (float(bi) + 0.5) / float(U_BINS)
			var acc := 0.0
			var cnt := 0
			for vv: float in [-0.75, 0.0, 0.75]:
				var p: Vector3 = xf * (Vector3(az.position.x + az.size.x * (u * 0.5 + 0.5), az.get_center().y + vv * hh, 0.0))
				# 從面板「內側 0.6 m」往 +n3 打：地形若在外側 → 侵入量 = 0.6 − 命中距離
				var q := PhysicsRayQueryParameters3D.new()
				q.from = p - n3 * 0.6
				q.to = p + n3 * 2.0
				var h := space.intersect_ray(q)
				if h.is_empty():
					acc += -0.6
					cnt += 1
					continue
				var col := h["collider"] as CollisionObject3D
				if col == null or col.get_rid() != terrain_rid:
					acc += -0.6
					cnt += 1
					continue
				var d := (p - n3 * 0.6).distance_to(h["position"] as Vector3)
				var intr := 0.6 - d
				acc += intr
				cnt += 1
				mx = maxf(mx, intr)
			bin_intr[bi] += acc / maxf(float(cnt), 1.0)
		for bi in U_BINS:
			per_bin[bi] += bin_intr[bi]
			tot[bi] += 1
		need_off.append(mx)
		# 兩端（u=±0.9）侵入 > 0.05 但中央（u=0）乾淨 → 沿岸傾斜造成
		var end_i: float = maxf(float(bin_intr[0]) / 3.0, float(bin_intr[U_BINS - 1]) / 3.0)
		var mid_i: float = float(bin_intr[U_BINS / 2]) / 3.0
		if end_i > 0.05 and mid_i < 0.02:
			n_bury_end += 1
		if mx < 0.02:
			n_clear += 1
		var key := String(it["tag"])
		if not worst.has(key) or mx > float(worst[key]):
			worst[key] = mx
	print("── B 部：%d 片護岸面板，沿岸 5 段平均地形侵入量（>0＝地形在面板外側、擋住石面）" % n_panel)
	var labels := ["最左(u=-1)", "左(u=-0.6)", "中(u=0)", "右(u=+0.6)", "最右(u=+1)"]
	for bi in U_BINS:
		print("  %-12s 平均侵入 %+.3f m（%d 片）" % [labels[bi], per_bin[bi] / maxf(float(tot[bi]), 1), tot[bi]])
	print("  完全乾淨（最大侵入 < 0.02 m）：%d／%d（%.0f%%）" % [n_clear, n_panel, 100.0 * n_clear / maxf(float(n_panel), 1)])
	print("  兩端埋、中央乾淨（沿岸傾斜）：%d／%d" % [n_bury_end, n_panel])
	need_off.sort()
	if not need_off.is_empty():
		print("  修平所需額外外推：中位 %.3f、p90 %.3f、最大 %.3f m" % [
			float(need_off[need_off.size() / 2]), float(need_off[mini(need_off.size() - 1, int(need_off.size() * 0.9))]),
			float(need_off[need_off.size() - 1])])
	var ks: Array = worst.keys()
	ks.sort()
	var show: Array = []
	for k: String in ks:
		show.append("%s=%.2f" % [k, float(worst[k])])
	print("  每站最差（前 12）：%s" % ", ".join(show.slice(0, 12)))
