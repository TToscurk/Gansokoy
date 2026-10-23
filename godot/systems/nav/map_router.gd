extends RefCounted
## 地圖路由：版本群組、共用室內圖的回程、生成器 meta 的傳送目標覆寫、舊→新別名（預設關）。
## 資料：res://data/map_routes.json。main.gd 持有一個實例（var router）。
##
## 原則（2026-10-23 新版地圖接管）：
##  - mode=legacy（預設）時正式流程一行不變：舊圖的傳送門照舊、別名不生效。
##  - 新版圖之間的連線靠各自 meta（或 portal_overrides），不經別名。
##  - 共用室內圖（hieda1f、kourindou）的回程 target 是 slice：同群組時改回「最後一次實際到過的成員」，
##    所以從 village_v2 進稗田邸會回 village_v2、從 slice 進去會回 slice。
##  - 所有解析結果都要驗證：目標有 data/<id>.meta.json、不是目前這張圖；不合格就退回原值。

const ROUTES_PATH := "res://data/map_routes.json"

var cfg: Dictionary = {}
var mode := "legacy"
## 群組 → 最後一次實際載入的成員 id
var group_last: Dictionary = {}
## 上一次 resolve_map() 是否把 id 換掉（讀檔相容：換掉時不沿用存檔座標）
var last_aliased := false


func _init() -> void:
	var txt := FileAccess.get_file_as_string(ROUTES_PATH)
	var parsed: Variant = JSON.parse_string(txt) if not txt.is_empty() else null
	cfg = parsed if parsed is Dictionary else {}
	mode = String(cfg.get("mode", "legacy"))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--routes="):
			mode = a.substr(9)
	if mode != "legacy" and mode != "v2":
		push_warning("[route] 未知 mode '%s'，改用 legacy" % mode)
		mode = "legacy"


func group_of(id: String) -> String:
	var groups: Dictionary = cfg.get("groups", {})
	for g in groups:
		if String(g).begins_with("_"):
			continue
		if (groups[g] as Array).has(id):
			return String(g)
	return ""


## 兩個 id 是否指同一地點（同 id 或同群組）。_place_player 找回程傳送點用。
func same_place(a: String, b: String) -> bool:
	if a == b:
		return true
	var ga := group_of(a)
	return ga != "" and ga == group_of(b)


static func map_exists(id: String) -> bool:
	return id != "" and FileAccess.file_exists("res://data/%s.meta.json" % id)


func _alias(id: String) -> String:
	if mode != "v2":
		return id
	var al: Dictionary = cfg.get("alias_v2", {})
	var to := String(al.get(id, id))
	return to if map_exists(to) else id


## 開局／讀檔／直接 load_map 用：v2 模式把舊 id 換成新 id。
func resolve_map(id: String) -> String:
	var to := _alias(id)
	last_aliased = to != id
	if last_aliased:
		print("[route] 別名 %s → %s（mode=%s）" % [id, to, mode])
	return to


## 每次載圖後呼叫：記住群組的「目前版本」。
func note_loaded(id: String) -> void:
	var g := group_of(id)
	if g != "":
		group_last[g] = id


## 生成器 meta 的傳送目標覆寫（spawn 傳送區時用）。
func portal_target(map_id: String, index: int, raw: Variant) -> String:
	var ov: Dictionary = (cfg.get("portal_overrides", {}) as Dictionary).get(map_id, {})
	var key := str(index)
	if ov.has(key) and map_exists(String(ov[key])) and String(ov[key]) != map_id:
		return String(ov[key])
	return "" if raw == null else String(raw)


## 實際傳送時用：共用室內圖回程記憶 → v2 別名 → 驗證。
## 回程記憶只在「目前這張圖不屬於任何群組」（稗田邸、香霖堂等共用室內圖）時生效：
## 舊獸道 → shrine 永遠是舊神社，新舊世界不會因為記憶而串線。
func resolve_travel(current_id: String, target: String) -> String:
	var out := target
	var g := group_of(target)
	if g != "" and group_of(current_id) == "" and group_last.has(g):
		var mem := String(group_last[g])
		if mem != target and map_exists(mem) and mem != current_id:
			out = mem
	out = _alias(out)
	if not map_exists(out) or out == current_id:
		if out != target:
			push_warning("[route] %s → %s 無效（不存在或循環），維持 %s" % [current_id, out, target])
		return target
	if out != target:
		print("[route] 傳送 %s：%s → %s" % [current_id, target, out])
	return out


## 載圖後套用暫行解鎖（open_seals）：停用指定 bp_role 的靜態碰撞。回傳停用數。
func apply_open_seals(map_id: String, map_root: Node) -> int:
	var roles: Array = (cfg.get("open_seals", {}) as Dictionary).get(map_id, [])
	if roles.is_empty() or map_root == null:
		return 0
	var n := 0
	for body in map_root.find_children("*", "CollisionObject3D", true, false):
		if roles.has(String(body.get_meta("bp_role", ""))):
			for cs in body.find_children("*", "CollisionShape3D", true, false):
				(cs as CollisionShape3D).set_deferred("disabled", true)
			n += 1
	if n > 0:
		print("[route] %s：暫行開啟出口封印 %d 處（open_seals）" % [map_id, n])
	return n
