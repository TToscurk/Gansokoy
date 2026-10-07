extends SceneTree
## 人間之里 V2 P9 FINAL SEAL（P9 CLOSED、2026-10-05 使用者裁定）。
##   Godot --headless --path godot --script res://tools/verify_village_v2_p9_final.gd
## 各 P9 子封存（R1–R5）の封存檔そのものの sha256＝P9 FINAL 時の値、P9 overlay の掛載順、P9 CLOSED 狀態、反向（竄改検出）。
## 子封存の中身（凍結檔・圖・證據）の雜湊は各 verifier の --seal が検査する（回歸總表に併入済み）。

const FINAL := "res://data/village_v2_p9_final_seal.json"
const SCENE := "res://maps/village_v2/village_v2.tscn"

var fails := 0


func check(label: String, ok: bool) -> void:
	print("[P9F] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _init() -> void:
	_run.call_deferred()


func _mismatch(fs: Dictionary) -> PackedStringArray:
	var repo := (ProjectSettings.globalize_path("res://") + "..").simplify_path() + "/"
	var bad := PackedStringArray()
	for k: String in fs["sub_seals"]:
		var e: Dictionary = fs["sub_seals"][k]
		var path: String = repo + String(e["file"])
		if not FileAccess.file_exists(path):
			bad.append("%s 不存在" % k)
		elif FileAccess.get_sha256(path) != String(e["sha256"]):
			bad.append("%s 雜湊變了" % k)
	return bad


func _run() -> void:
	var fs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FINAL))
	check("P9 狀態＝%s（使用者 %s 裁定）" % [fs["status"], fs["closed_at"]], String(fs["status"]) == "P9_CLOSED" and String(fs["closed_by"]) == "user")
	var bad := _mismatch(fs)
	check("P9 子封存 %d 檔（R1–R5）の封存檔雜湊＝FINAL 時（不符 %d：%s）" % [(fs["sub_seals"] as Dictionary).size(), bad.size(), ", ".join(bad.slice(0, 4))], bad.is_empty())
	var txt := FileAccess.get_file_as_string(SCENE)
	for grp: String in ["Vegetation", "Props"]:
		var order: Array = fs["mount_order"][grp]
		var idx: Array = []
		for nm: String in order:
			idx.append(txt.find("[node name=\"%s\" parent=\"%s\"" % [nm, grp]))
		var ok: bool = int(idx[0]) >= 0
		for k in range(1, idx.size()):
			ok = ok and int(idx[k]) > int(idx[k - 1])
		check("village_v2.tscn 掛載 %s/%s" % [grp, " → ".join(order)], ok)
	var r5: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/village_v2_p9r5_seal.json"))
	check("R5 final seal 狀態＝%s、R5-3／R5-4 子封存＝ART_APPROVED" % r5["status"], String(r5["status"]) == "ART_APPROVED_FINAL"
		and String((JSON.parse_string(FileAccess.get_file_as_string("res://data/village_v2_p9r53_seal.json")) as Dictionary)["status"]) == "ART_APPROVED"
		and String((JSON.parse_string(FileAccess.get_file_as_string("res://data/village_v2_p9r54_seal.json")) as Dictionary)["status"]) == "ART_APPROVED")
	var neg := fs.duplicate(true)
	var k0: String = (neg["sub_seals"] as Dictionary).keys()[0]
	neg["sub_seals"][k0]["sha256"] = "0".repeat(64)
	var nb := _mismatch(neg)
	check("反向：竄改 %s の封存檔雜湊 → 偵測到 1 筆不符（實際 %d）" % [k0, nb.size() - bad.size()], nb.size() == bad.size() + 1)
	print("[P9F] 結果：%d 項失敗" % fails)
	quit(fails)
