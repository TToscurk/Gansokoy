extends SceneTree
## 人間之里 V2：Macro Layout 凍結檢查（headless，不寫任何檔）。
##
##   Godot --headless --path godot --script res://tools/verify_village_v2_freeze.gd
##
## 每項印一行 [FREEZE] PASS/FAIL；結尾 quit(失敗項數)。
## 前半驗 layout_v2.json 真的是使用者核可的 v2-layout-0.3（W80）；後半驗凍結模組擋得住 Macro 改動、放得過非 Macro 改動。

const Freeze := preload("res://tools/village_v2_freeze.gd")
const LAYOUT := "res://maps/village_v2/layout_v2.json"

var fails := 0


func check(label: String, ok: bool) -> void:
	print("[FREEZE] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _init() -> void:
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var h: String = Freeze.frozen_sha256(L)
	print("[FREEZE] 現值 frozen sha256 = ", h)
	# ── layout 本身：核可版本、已凍結、雜湊一致
	var fr: Dictionary = L.get("approval", {}).get("freeze", {})
	check("layout 有 approval.freeze", not fr.is_empty())
	check("version = v2-layout-0.3（實際 %s）" % L.get("version", ""), String(L.get("version", "")) == "v2-layout-0.3")
	check("status = LAYOUT_FREEZE（實際 %s）" % L.get("status", ""), String(L.get("status", "")) == "LAYOUT_FREEZE")
	check("approval.freeze.sha256 = 現值", String(fr.get("sha256", "")) == h)
	var sel := String(L["variants"]["main_street_width"]["selected"])
	var ms_hw := 0.0
	for r in L["roads"]:
		if r["name"] == "MainStreet":
			ms_hw = float(r["half_w"])
	check("主街 selected = W80（實際 %s）" % sel, sel == "W80")
	check("主街全寬 7.20 m（實際 %.2f m）" % (ms_hw * 2.0), is_equal_approx(ms_hw * 2.0, 7.2))
	# ── 凍結模組行為（在 layout 副本上改，不動原檔）
	var A := L.duplicate(true)
	A["approval"] = {"freeze": {"sha256": h}}
	check("核可值＝現值 → 通過", Freeze.check(A) == "")
	var m1 := A.duplicate(true)
	for r in m1["roads"]:
		if r["name"] == "MainStreet":
			r["half_w"] = 4.5
	check("主街半寬 3.6→4.5 → 擋下", Freeze.check(m1) != "")
	var m2 := A.duplicate(true)
	m2["hill"]["height"] = float(m2["hill"]["height"]) + 0.3
	check("北丘高 +0.3 m → 擋下", Freeze.check(m2) != "")
	var m3 := A.duplicate(true)
	m3["water"]["MainRiver"]["half_w"][0] = float(m3["water"]["MainRiver"]["half_w"][0]) + 1.0
	check("主河半寬改 → 擋下", Freeze.check(m3) != "")
	var m4 := A.duplicate(true)
	m4["heights"]["river_water"] = float(m4["heights"]["river_water"]) - 0.2
	check("主河水位改 → 擋下", Freeze.check(m4) != "")
	var m5 := A.duplicate(true)
	m5["landmarks"][0]["at"][0] = float(m5["landmarks"][0]["at"][0]) + 1.0
	check("地標位置移 1 m → 擋下", Freeze.check(m5) != "")
	var ok := A.duplicate(true)
	ok["heights"]["built"] = float(ok["heights"]["built"]) + 0.2
	for f in ok["forests"]:
		if typeof(ok["forests"][f]) == TYPE_DICTIONARY:
			ok["forests"][f]["canopy_h"] = 99.0
	ok["terrain"] = {"retaining_walls": []}
	ok["hill"]["_note"] = "改註記"
	ok["version"] = "v2-layout-0.3-p1"
	check("建成區基準面／林冠高／terrain／註記／版本改 → 仍通過", Freeze.check(ok) == "")
	var reorder := {}
	var keys := A.keys()
	keys.reverse()
	for k in keys:
		reorder[k] = A[k]
	check("key 順序顛倒 → 雜湊不變", Freeze.frozen_sha256(reorder) == h)
	var none := A.duplicate(true)
	none.erase("approval")
	check("沒有 approval.freeze → 通過（未核可的 layout 不擋）", Freeze.check(none) == "")
	check("凍結後 --variant=W100 → 拒絕", Freeze.check_variant(A, "W100") != "")
	check("凍結後 --variant=W80／空白 → 允許", Freeze.check_variant(A, "W80") == "" and Freeze.check_variant(A, "") == "")
	print("[FREEZE] 結果：%d 項失敗" % fails)
	quit(fails)
