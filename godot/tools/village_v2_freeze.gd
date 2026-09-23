extends RefCounted
## 人間之里 V2：Macro Layout 凍結（LAYOUT_APPROVED 2026-09-24：v2-layout-0.3，主街 W80 全寬 7.20 m）。
##
## 凍結範圍（任何改動都要先回報使用者重審）：
##   frame、hill、relief、districts、water、roads、landmarks、quest_anchors、portals、spawn、
##   review_shots、variants，forests 只凍結各林帶 poly，heights 只凍結水位四鍵（WATER_HEIGHT_KEYS）。
## 不凍結（P1 起可改）：heights 的其他鍵（建成區基準面、feather…）、terrain（P1 新增）、
##   forests 的 canopy_h／canopy_var／cell（臨時林冠，P9 Vegetation 會換掉）、version／status／approval／註記。
## 主街只准用 variants.main_street_width.selected（W80）；W100／W65 是 ART_REVIEW 比較紀錄，凍結後產生器拒用。
## 所有以 "_" 開頭的鍵（_note 等註記）在計算前遞迴剝除：改註記不會觸發凍結。
##
## 做法：凍結子集 → JSON.stringify(sort_keys=true) → sha256_text()，與 layout 的 approval.freeze.sha256 比。
## JSON.parse_string 會把數字都轉成 float，所以 234 與 234.0 同值；key 順序不影響雜湊。
##
## 用法：const Freeze := preload("res://tools/village_v2_freeze.gd")
##       var err: String = Freeze.check(L)   # "" ＝通過；沒有 approval.freeze 的 layout 一律通過

const FROZEN_KEYS := ["frame", "hill", "relief", "districts", "forests", "water", "roads",
	"landmarks", "quest_anchors", "portals", "spawn", "review_shots", "variants"]
const WATER_HEIGHT_KEYS := ["river_water", "river_bed", "canal_max_water", "canal_water_depth"]


static func _strip(v: Variant) -> Variant:
	if typeof(v) == TYPE_DICTIONARY:
		var out := {}
		for k in v:
			if not String(k).begins_with("_"):
				out[k] = _strip(v[k])
		return out
	if typeof(v) == TYPE_ARRAY:
		var arr := []
		for e in v:
			arr.append(_strip(e))
		return arr
	return v


static func frozen_subset(L: Dictionary) -> Dictionary:
	var sub := {}
	for k in FROZEN_KEYS:
		if not L.has(k):
			continue
		if k == "forests":
			var f := {}
			for name in L[k]:
				if typeof(L[k][name]) == TYPE_DICTIONARY and L[k][name].has("poly"):
					f[name] = L[k][name]["poly"]
			sub[k] = f
		else:
			sub[k] = L[k]
	var wh := {}
	var H: Dictionary = L.get("heights", {})
	for k in WATER_HEIGHT_KEYS:
		if H.has(k):
			wh[k] = H[k]
	sub["heights_water"] = wh
	return _strip(sub)


static func frozen_sha256(L: Dictionary) -> String:
	return JSON.stringify(frozen_subset(L), "", true).sha256_text()


static func check(L: Dictionary) -> String:
	var fr: Dictionary = L.get("approval", {}).get("freeze", {})
	if fr.is_empty():
		return ""
	var want := String(fr.get("sha256", ""))
	var got := frozen_sha256(L)
	if got == want:
		return ""
	return "凍結的 Macro Layout 被改動：sha256 %s… ≠ 核可值 %s…（凍結範圍 %s＋heights 水位）。要改必須先回報使用者重新審核。" % [
		got.substr(0, 12), want.substr(0, 12), ", ".join(FROZEN_KEYS)]



## 凍結後只准產生核可的主街 Variant；variant 空字串＝用 selected。回傳 "" ＝允許。
static func check_variant(L: Dictionary, variant: String) -> String:
	if L.get("approval", {}).get("freeze", {}).is_empty() or variant == "":
		return ""
	var sel := String(L["variants"]["main_street_width"]["selected"])
	if variant == sel:
		return ""
	return "Macro Layout 已凍結：主街只准用核可的 %s，不能產生 --variant=%s（W100／W65 只是 ART_REVIEW 比較紀錄）。" % [sel, variant]
