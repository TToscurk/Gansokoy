extends SceneTree
## 獸道 V1.3：把 V1.2 的 S04 森林凍結成 frozen/forest_plan_v12_s04.json（一次性；在重生 V1.3 之前跑）。
##   godot --headless --path godot --script res://tools/beast_path/freeze_s04_v12.gd
## 來源＝目前磁碟上的 V1.2 產物：maps/beast_path/gen/forest_plan.json（S04 那幾筆的順序）＋
##       maps/beast_path/s04_boss_clearing.tscn 的 Forest 子節點（場景裡實際存檔的 transform；節點名 <id>_<序號>）。
## 格式同 forest_plan_v01_s01_s03.json（每筆多一個 xf＝列優先 3×3＋原點）。寫完印 sha256，填進 layout.forest.freeze_s04。

const PLAN := "res://maps/beast_path/gen/forest_plan.json"
const SCN := "res://maps/beast_path/s04_boss_clearing.tscn"
const OUT := "res://tools/beast_path/frozen/forest_plan_v12_s04.json"


func _initialize() -> void:
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLAN))
	if not (plan is Dictionary):
		push_error("讀不到 %s" % PLAN)
		quit(2)
		return
	var s04: Array = []
	for t: Dictionary in (plan as Dictionary)["trees"]:
		if String(t["scene"]) == "S04":
			s04.append(t)
	var ps := ResourceLoader.load(SCN, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var root := ps.instantiate()
	var forest := root.get_node_or_null("Forest")
	if forest == null:
		push_error("%s 沒有 Forest" % SCN)
		quit(2)
		return
	var by_idx := {}
	for c in forest.get_children():
		var nm := String(c.name)
		var cut := nm.rfind("_")
		by_idx[int(nm.substr(cut + 1))] = c
	if by_idx.size() != s04.size():
		push_error("數量對不上：plan S04 %d 筆、場景 Forest %d 個" % [s04.size(), by_idx.size()])
		quit(2)
		return
	var out: Array = []
	var bad := 0
	for i in s04.size():
		var t: Dictionary = s04[i]
		var n := by_idx.get(i) as Node3D
		if n == null or not String(n.name).begins_with(String(t["id"]) + "_"):
			bad += 1
			continue
		var b := n.transform.basis
		var o := n.transform.origin
		var e := t.duplicate()
		e["xf"] = [b.x.x, b.y.x, b.z.x, b.x.y, b.y.y, b.z.y, b.x.z, b.y.z, b.z.z, o.x, o.y, o.z]
		if absf(o.x - float(t["x"])) > 0.011 or absf(o.z - float(t["z"])) > 0.011:
			bad += 1
		out.append(e)
	root.free()
	if bad > 0:
		push_error("配對失敗 %d 筆（plan 與場景順序不一致）" % bad)
		quit(2)
		return
	var doc := {"_note": "V1.3：S04 森林凍結＝V1.2 ART_REVIEW 版（使用者：V1.2 的整體地形與場景配置保留）。來源＝V1.2 forest_plan.json＋s04_boss_clearing.tscn 裡實際存檔的 transform。勿手改；改了 layout.forest.freeze_s04.sha256 對不上，產生器會拒絕。",
		"source": "V1.2（2026-10-15 產物）", "seed": (plan as Dictionary)["seed"], "scenes": {"S04": out}}
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	print("[freeze] S04 %d 筆 → %s  sha256=%s" % [out.size(), OUT, FileAccess.get_sha256(OUT)])
	quit(0)
