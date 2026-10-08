## P10 人口：scope 別の身元検査（R3d／R3e の scene gate が共用）。
##   2026-10-08 使用者承認の scope-aware count fix：R3d は自分の 39 人（R3b PopulationP10 16＋R3d CoreP10 23、R3d snapshot の身元）だけを
##   検査し、場景全体の NPC 総数では判定しない——R3e 外圍が掛かっても外れても R3d の判定は変わらない。
##   R3e は外圍 12 人（R3e snapshot）を検査し、最終の村人口 51＝核心 39＋外圍 12 は別の項目で検査する（Population 全体の身元＝両 snapshot の和、scope 外の NPC・重複なし）。
##   身元＝NPC body の名前 "<id>_<model>" の id（snapshot の id）と meta model。人数だけでなく、欠け・余分・重複・model 違いを全部見る。
const CORE_SNAP := "res://data/village_v2_p10r3d_snapshot.json"
const OUTER_SNAP := "res://data/village_v2_p10r3e_snapshot.json"
const CORE_LAYERS := ["PopulationP10", "CoreP10"]
const OUTER_LAYERS := ["OuterP10"]


## Population/<layer> の下の NPC body（AnimatableBody3D）
static func bodies(v: Node, layers: Array) -> Array:
	var out: Array = []
	for nm in layers:
		var n := v.get_node_or_null("Population/" + String(nm))
		if n:
			out.append_array(n.find_children("*", "AnimatableBody3D", true, false))
	return out


## 期待される身元 {id: model}：scope＝"core"（39）・"outer"（12）・"village"（51）
static func want(scope: String) -> Dictionary:
	var w := {}
	if scope in ["core", "village"]:
		var s: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CORE_SNAP))
		for k in ["r3b_baseline", "r3d_added"]:
			for r: Dictionary in s[k]:
				w[String(r["id"])] = String(r["model"])
	if scope in ["outer", "village"]:
		var s2: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUTER_SNAP))
		for r: Dictionary in s2["outer"]:
			w[String(r["id"])] = String(r["model"])
	return w


static func id_of(b: Node) -> String:
	return String(b.name).split("_")[0]


## 不符の一覧（空＝一致）：人数・欠け・余分・重複・model 違い
static func mismatch(bs: Array, w: Dictionary) -> Array:
	var bad: Array = []
	var seen := {}
	for b: Node in bs:
		var id := id_of(b)
		seen[id] = int(seen.get(id, 0)) + 1
		if not w.has(id):
			bad.append("余分 " + String(b.name))
		elif b.has_meta("model") and String(b.get_meta("model")) != String(w[id]):
			bad.append("model 違い " + String(b.name))
	for id in seen:
		if int(seen[id]) > 1:
			bad.append("重複 %s×%d" % [id, seen[id]])
	for id in w:
		if not seen.has(id):
			bad.append("欠け " + String(id))
	if bs.size() != w.size():
		bad.append("人数 %d≠%d" % [bs.size(), w.size()])
	return bad


## 反向（記憶體内だけ・場景は変えない）：多一人／少一人／身元重複（人数そのまま＝一人を別の人の身元に差し替え）
static func negatives(bs: Array, w: Dictionary) -> Dictionary:
	var extra := AnimatableBody3D.new()
	extra.name = "X99_extra"
	var dup := AnimatableBody3D.new()
	dup.name = id_of(bs[0]) + "_dup"
	if (bs[0] as Node).has_meta("model"):
		dup.set_meta("model", (bs[0] as Node).get_meta("model"))
	var plus := bs.duplicate()
	plus.append(extra)
	var minus := bs.duplicate()
	minus.remove_at(0)
	var same := bs.duplicate()
	same[1] = dup
	var r := {"plus1": mismatch(plus, w), "minus1": mismatch(minus, w), "dup": mismatch(same, w)}
	extra.free()
	dup.free()
	return r


static func neg_ok(r: Dictionary) -> bool:
	return not (r["plus1"] as Array).is_empty() and not (r["minus1"] as Array).is_empty() \
		and (r["dup"] as Array).any(func(s: String) -> bool: return s.begins_with("重複"))


static func neg_txt(r: Dictionary) -> String:
	return "多一人 %s／少一人 %s／身元重複 %s" % [str((r["plus1"] as Array).slice(0, 2)), str((r["minus1"] as Array).slice(0, 2)), str((r["dup"] as Array).slice(0, 2))]
