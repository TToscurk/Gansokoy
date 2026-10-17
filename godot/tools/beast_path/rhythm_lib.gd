extends RefCounted
## 岩壁節奏量測（V1.2 B）：玩家站在戰場裡，往四周看，岩石佔多少視野、有沒有連成一整圈、缺口在哪。
## 做法：從戰場中央與周圍 8 點（r=12 m），水平射線（眼高 1.6 m）每 2° 一根、射程 60 m；
##       看「第一個撞到的」是：岩壁岩（設計高度 ≥ 4 m，讀成牆／崖）／矮石（< 4 m，掩體、碎石、腳邊石）／樹／地形（土坡）／什麼都沒有。
##       只有「岩壁岩」算牆——矮石、土坡、樹林就是使用者要用來取代高牆視覺的東西。
## 北崖扇區（方位 325°→45°）不計：那邊的「牆」是瀑布崖本身，要保留。
## 與 verify_beast_path.gd 的 arena.rock_rhythm 共用（同一份實作，量測腳本 probe_rock_rhythm.gd 也用它）。

const AZ_STEP := 2.0
const RANGE_M := 60.0
const EYE := 1.6
const NORTH_FROM := 325.0
const NORTH_TO := 45.0
const WALL_M := 4.0           # 岩壁岩的最小高度
const TALL_M := 8.0           # 高岩（讀成峭壁）
const GAP_RAYS := 4           # 缺口至少 4 根＝8°


static func _in_north(az: float) -> bool:
	return az >= NORTH_FROM or az < NORTH_TO


## 往上找父節點，判斷撞到的是什麼；回傳 {"k": "rock"|"tree"|"terrain"|"other", "h": 岩石設計高度}
static func _rock_h(n: Node) -> float:
	for c in n.get_children():
		var mi := c as MeshInstance3D
		if mi != null and mi.mesh != null:
			return mi.mesh.get_aabb().size.y - 0.9          # 網格含 0.9 m 的埋地部分
	return 0.0


static func classify(col: Node) -> Dictionary:
	var n := col
	while n != null:
		if n.has_meta("bp_slab") or n.has_meta("bp_rock_r"):
			return {"k": "rock", "h": _rock_h(n)}
		if String(n.name) == "Forest":
			return {"k": "tree", "h": 0.0}
		if String(n.name) == "TerrainBody":
			return {"k": "terrain", "h": 0.0}
		n = n.get_parent()
	return {"k": "other", "h": 0.0}


static func view(space: PhysicsDirectSpaceState3D, lib, vp: Vector2) -> Dictionary:
	var gy: float = lib.h_at(vp.x, vp.y)
	var from := Vector3(vp.x, gy + EYE, vp.y)
	var n_az := int(round(360.0 / AZ_STEP))
	var cls: Array = []          # 每根射線：R／T／G／N／X(排除)
	var tall: Array = []
	var n_rock := 0
	var n_tall := 0
	var n_cnt := 0
	for i in n_az:
		var az := float(i) * AZ_STEP
		if _in_north(az):
			cls.append("X")
			tall.append(false)
			continue
		n_cnt += 1
		var dir := Vector3(sin(deg_to_rad(az)), 0.0, -cos(deg_to_rad(az)))
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * RANGE_M)
		var r := space.intersect_ray(q)
		var k := "N"
		var is_tall := false
		if not r.is_empty():
			var c := classify(r["collider"] as Node)
			match String(c["k"]):
				"rock":
					if float(c["h"]) >= WALL_M:
						k = "R"
						is_tall = float(c["h"]) >= TALL_M
					else:
						k = "L"
				"tree": k = "T"
				"terrain": k = "G"
				_: k = "T"
		cls.append(k)
		tall.append(is_tall)
		if k == "R":
			n_rock += 1
			if is_tall:
				n_tall += 1
	# 連續岩壁弧（循環；X 當斷點）與缺口數（連續非岩壁 ≥ GAP_RAYS 根）
	var max_run := 0
	var run := 0
	for pass_i in 2:
		for i in n_az:
			if String(cls[i]) == "R":
				run += 1
				max_run = maxi(max_run, run)
			else:
				run = 0
	max_run = mini(max_run, n_az)
	var gaps := 0
	var gap_arcs: Array = []
	var start := -1
	for i in range(n_az + 1):
		var non: bool = i < n_az and String(cls[i]) != "R" and String(cls[i]) != "X"
		if non and start < 0:
			start = i
		elif not non and start >= 0:
			if i - start >= GAP_RAYS:
				gaps += 1
				gap_arcs.append([start * AZ_STEP, (i - 1) * AZ_STEP])
			start = -1
	return {"rock_frac": float(n_rock) / float(maxi(n_cnt, 1)), "tall_frac": float(n_tall) / float(maxi(n_cnt, 1)),
		"max_arc_deg": float(max_run) * AZ_STEP, "gaps": gaps, "gap_arcs": gap_arcs, "cls": "".join(cls)}


## 中央一點＋周圍 8 點（r=12）
static func measure(space: PhysicsDirectSpaceState3D, lib) -> Dictionary:
	var c0: Vector2 = lib.arena_c()
	var views: Array = [view(space, lib, c0)]
	for k in 8:
		var a := TAU * float(k) / 8.0
		views.append(view(space, lib, c0 + Vector2(sin(a), -cos(a)) * 12.0))
	var mean_rock := 0.0
	var mean_tall := 0.0
	var worst_arc := 0.0
	for v: Dictionary in views:
		mean_rock += float(v["rock_frac"])
		mean_tall += float(v["tall_frac"])
		worst_arc = maxf(worst_arc, float(v["max_arc_deg"]))
	return {"center": views[0], "rock_frac_mean": mean_rock / float(views.size()), "tall_frac_mean": mean_tall / float(views.size()),
		"max_arc_worst": worst_arc, "views": views}
