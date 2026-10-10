extends RefCounted
## P11 R2：候補スクリプトの差し替え（**メモリ上のみ・ファイル不変**）。
## main.tscn を instantiate() した直後（add_child＝_ready 前）に呼ぶ。対象ノードのスクリプトを
## tools/p11r2/ の「元スクリプトを extends した候補」に差し替え、シーン由来のスクリプト変数を復元する。
##   A＝Player（yoriichi_character.gd → yoriichi_character_p11r2.gd：_try_step_up）
##   B＝Player/CameraAdapter（player_camera_adapter.gd → player_camera_adapter_p11r2.gd：_process）
##   C＝Main（main.gd → main_p11r2.gd：_place_player）
## 使い方：P11R2Swap.apply(main, "ABC")  → 差し替えたものの一覧を返す
## --patched=A|B|C：候補（override）ではなく、patches/*.patch を当てた「元ファイルの全体コピー」（tools/p11r2/_patched/、git 管理外）に
##   差し替える＝所有者へ渡す patch が候補と同じ挙動になることの確認用。

const SUB := {
	"A": ["Player", "res://tools/p11r2/yoriichi_character_p11r2.gd", 0.35],
	"B": ["Player/CameraAdapter", "res://tools/p11r2/player_camera_adapter_p11r2.gd", null],
	"C": [".", "res://tools/p11r2/main_p11r2.gd", null],
}


const PATCHED := {
	"A": "res://tools/p11r2/_patched/yoriichi_character.gd",
	"B": "res://tools/p11r2/_patched/player_camera_adapter.gd",
	"C": "res://tools/p11r2/_patched/main.gd",
}


static func parse(args: PackedStringArray) -> String:
	for a: String in args:
		if a.begins_with("--candidate="):
			return a.trim_prefix("--candidate=").to_upper()
		if a.begins_with("--patched="):
			return "P" + a.trim_prefix("--patched=").to_upper()
	return ""


static func apply(main: Node, which: String) -> Array:
	var done: Array = []
	var patched := which.begins_with("P")
	for k: String in ["A", "B", "C"]:
		if not which.trim_prefix("P").contains(k):
			continue
		var spec: Array = (SUB[k] as Array).duplicate()
		if patched:
			spec[1] = PATCHED[k]
		var n: Node = main if spec[0] == "." else main.get_node_or_null(spec[0])
		if n == null:
			push_error("P11R2Swap: node %s not found" % spec[0])
			continue
		var keep := {}
		for p: Dictionary in n.get_property_list():
			if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				keep[p["name"]] = n.get(p["name"])
		n.set_script(load(spec[1]))
		for nm: String in keep:
			n.set(nm, keep[nm])
		if k == "A" and spec[2] != null:
			n.set("step_height", float(spec[2]))
		done.append("%s:%s→%s" % [k, spec[0], spec[1].get_file()])
	return done
