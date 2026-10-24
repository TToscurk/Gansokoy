extends RefCounted
## 日之呼吸：唯一正式技能清單的讀取接口（資料＝sun_breathing_registry.json，ART_REVIEW）。
## 清單＝十二式（kind＝form，01～12）＋衍生技（kind＝derived，13 起，例如 13 圓舞一閃）。
## 道場與正式技能選擇介面都只透過這裡取得排序、名稱、技能 key、動畫、特效 profile，不另外維護清單。
## 使用：const SunRegistry = preload("res://characters/yoriichi/sun_breathing_registry.gd")
##   SunRegistry.skill_keys()          → 選單順序的全部技能 key（01～12 十二式＋13 衍生技）
##   SunRegistry.step(key, +1 / -1)    → 選單的下一個／上一個（13 之後回到 01、01 之前是 13）
##   SunRegistry.forms()               → 只有十二式（衍生技不算）
##   SunRegistry.form13()              → 第十三型（十二式連續施展、炎舞接回圓舞；不含衍生技）的預留資料；目前 enabled＝false，沒有自動連段
## 正式 Player（yoriichi_character.gd＋sun_breathing.gd）目前沒有接這套 R16 技能，也沒有選招介面；這裡是給它日後接的獨立接口。
## 資料由 D:/research/sekiro_r8_p0/notes/r16/build_sun12_registry.py 產生（選版在產生器，數值從各技能 JSON 讀出）。

const PATH := "res://characters/yoriichi/sun_breathing_registry.json"
const FORM_COUNT := 12      # 十二式
const MENU_COUNT := 13      # 選單總數＝十二式＋衍生技（13 圓舞一閃）
const COUNT := MENU_COUNT   # 舊名稱（＝選單總數）

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = d if d is Dictionary else {}
	return _data

## 選單順序的全部條目（十二式＋衍生技）
static func entries() -> Array:
	var es: Array = (data().get("entries", []) as Array).duplicate()
	es.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
	return es

static func is_derived(e: Dictionary) -> bool:
	return str(e.get("kind", "form")) == "derived"

## 只有十二式
static func forms() -> Array:
	return entries().filter(func(e: Dictionary) -> bool: return not is_derived(e))

## 只有衍生技
static func derived() -> Array:
	return entries().filter(func(e: Dictionary) -> bool: return is_derived(e))

static func skill_keys() -> Array:
	return entries().map(func(e: Dictionary) -> String: return str(e["skill_key"]))

static func entry_by_skill(key: String) -> Dictionary:
	for e: Dictionary in entries():
		if str(e["skill_key"]) == key:
			return e
	return {}

static func entry_by_id(id: String) -> Dictionary:
	for e: Dictionary in entries():
		if str(e["id"]) == id:
			return e
	return {}

## 選單上顯示的名稱：「01 圓舞」、「13 圓舞一閃（衍生技）」（編號只是選單順序，不加「壹之型」）
static func label(e: Dictionary) -> String:
	return "%s %s%s" % [str(e.get("menu", "")), str(e.get("name_zh", "")), str(e.get("label_suffix", ""))]

## dir＝+1 下一個、−1 上一個（選單全部條目循環）；不在清單裡的 key 回到第一式
static func step(key: String, dir: int) -> String:
	var keys := skill_keys()
	if keys.is_empty():
		return key
	var i := keys.find(key)
	if i < 0:
		return str(keys[0])
	return str(keys[posmod(i + dir, keys.size())])

static func form13() -> Dictionary:
	return data().get("form13", {})

## 清單自我檢查：數量、編號、ID／技能／動畫／特效不重複，資源存在，且與各技能 JSON 的動畫／命中窗／傷害一致；
## 十二式在前、衍生技在後；第十三型只含十二式（不含衍生技）。回傳問題清單（空＝通過）。
static func validate() -> Array:
	var bad: Array = []
	var es := entries()
	if es.size() != MENU_COUNT:
		bad.append("選單數量 %d（應為 %d）" % [es.size(), MENU_COUNT])
	var fs := forms()
	if fs.size() != FORM_COUNT:
		bad.append("十二式數量 %d（應為 %d）" % [fs.size(), FORM_COUNT])
	var seen := {}
	for i in es.size():
		var e: Dictionary = es[i]
		if int(e["order"]) != i + 1:
			bad.append("第 %d 筆的 order＝%s" % [i + 1, str(e["order"])])
		if is_derived(e) != (i >= FORM_COUNT):
			bad.append("%s 的位置不對（十二式＝01～12、衍生技在 12 之後）" % label(e))
		for f in ["id", "skill_key", "anim", "vfx_profile", "name_zh", "name_ja"]:
			var tag := "%s=%s" % [f, str(e.get(f, ""))]
			if str(e.get(f, "")) == "":
				bad.append("%s 缺 %s" % [label(e), f])
			elif seen.has(tag):
				bad.append("%s 與 %s 重複 %s" % [label(e), str(seen[tag]), f])
			seen[tag] = label(e)
		if not ResourceLoader.exists(str(e["anim_res"])):
			bad.append("%s 動畫資源不存在 %s" % [label(e), str(e["anim_res"])])
		var sj := str(e["skill_json"])
		if not FileAccess.file_exists(sj):
			bad.append("%s 技能 JSON 不存在 %s" % [label(e), sj])
			continue
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(sj))
		if str(e.get("skill_json_key", "")) != "":
			d = (d as Dictionary)["skills"][str(e["skill_json_key"])]
		var sh: Dictionary = (d as Dictionary)["shot"]
		var base_anim := str(e.get("anim_base", e["anim"]))   # 收勢挺直版：清單用 *_up 動畫，技能 JSON 仍是原動畫（回退用）
		if str(sh["anim"]) != base_anim:
			bad.append("%s 原動畫 %s ≠ 技能 JSON %s" % [label(e), base_anim, str(sh["anim"])])
		if JSON.stringify(sh.get("strikes", [])) != JSON.stringify(e["hit"].get("strikes", [])):
			bad.append("%s 命中窗與技能 JSON 不一致" % label(e))
		if int((d as Dictionary).get("damage", 3)) != int(e["damage"]["per_strike"]):
			bad.append("%s 傷害與技能 JSON 不一致" % label(e))
	var f13 := form13()
	if bool(f13.get("enabled", false)):
		bad.append("第十三型被開啟（目前只保留資料入口）")
	var seq: Array = f13.get("sequence", [])
	if seq != fs.map(func(e: Dictionary) -> String: return str(e["id"])):
		bad.append("第十三型的順序不是十二式（或混入衍生技）：%s" % JSON.stringify(seq))
	return bad
