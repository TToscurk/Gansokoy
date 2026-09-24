extends SceneTree
## 人間之里 V2：橋與路×水交叉回歸（P1 起每次改產生器都要跑）。
##   Godot --headless --path godot --script res://tools/verify_village_v2_bridges.gd
## 1) Roads/Bridges 底下正好 EXPECTED_BRIDGES 座橋。
## 2) layout 裡每條路與每條水（主河、水渠、支流）的交叉點（去重）都落在某座橋的 AABB（±1 m）內。
## 橋端與地面高差、橋長 ±10 % 由 verify_village_v2_terrain.gd／產生器負責，這裡不重複。
## 每項印一行 [BRIDGE] PASS/FAIL；結尾 quit(失敗項數)。

const SCN := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const EXPECTED_BRIDGES := 5

var fails := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v: Node3D = (load(SCN) as PackedScene).instantiate()
	root.add_child(v)
	await process_frame
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var br := v.get_node_or_null("Roads/Bridges")
	var bl: Array = []   # [name, AABB]
	if br != null:
		for b in br.get_children():
			if b is Node3D:
				var ab := _aabb(b)
				bl.append([String(b.name), ab])
				print("[BRIDGE]   %-34s 中心 (%.1f, %.1f) 尺寸 %.1f×%.1f×%.1f 橋面頂 %.2f m" % [
					b.name, ab.get_center().x, ab.get_center().z, ab.size.x, ab.size.y, ab.size.z, ab.end.y])
	_check(bl.size() == EXPECTED_BRIDGES, "Roads/Bridges 共 %d 座（應為 %d）" % [bl.size(), EXPECTED_BRIDGES])
	var W: Dictionary = L["water"]
	var waters := [["MainRiver", W["MainRiver"]["pts"]], ["Canal", W["Canal"]["pts"]]]
	for s in W["Streams"]:
		waters.append([s["name"], s["pts"]])
	var seen := {}
	for r in L["roads"]:
		var rp: Array = r["pts"]
		for w in waters:
			var wp: Array = w[1]
			for i in rp.size() - 1:
				for j in wp.size() - 1:
					var x = Geometry2D.segment_intersects_segment(
						Vector2(rp[i][0], rp[i][1]), Vector2(rp[i + 1][0], rp[i + 1][1]),
						Vector2(wp[j][0], wp[j][1]), Vector2(wp[j + 1][0], wp[j + 1][1]))
					if x == null:
						continue
					# 交叉點剛好落在折線頂點時，相鄰兩段都會算到：以路名×水名×0.1 m 座標去重
					var key := "%s|%s|%d|%d" % [r["name"], w[0], roundi(x.x * 10.0), roundi(x.y * 10.0)]
					if seen.has(key):
						continue
					seen[key] = true
					var hit := ""
					for e in bl:
						var ab: AABB = e[1]
						if x.x >= ab.position.x - 1 and x.x <= ab.end.x + 1 and x.y >= ab.position.z - 1 and x.y <= ab.end.z + 1:
							hit = e[0]
					_check(hit != "", "交叉 %s × %s @ (%.1f, %.1f) → %s" % [r["name"], w[0], x.x, x.y, hit if hit != "" else "無橋覆蓋"])
	_check(seen.size() == EXPECTED_BRIDGES, "路×水交叉 %d 處（應為 %d）" % [seen.size(), EXPECTED_BRIDGES])
	print("[BRIDGE] 結果：%d 項失敗" % fails)
	quit(fails)


func _check(ok: bool, msg: String) -> void:
	print("[BRIDGE] %s %s" % ["PASS" if ok else "FAIL", msg])
	if not ok:
		fails += 1


func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [n]
	while stack.size():
		var c = stack.pop_back()
		if c is VisualInstance3D:
			var ab: AABB = c.global_transform * c.get_aabb()
			out = ab if first else out.merge(ab)
			first = false
		for k in c.get_children():
			stack.append(k)
	return out
