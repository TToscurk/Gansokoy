extends RefCounted
## Development-only review start（開發用審圖起點）。
##
## 只在 debug 執行檔＋（編輯器 F5／MCP project_run，或命令列明示 --review）時生效；
## release 匯出永遠不生效。生效時：
##   - 直接載入人間之里（village_v2），玩家放在指定 review spawn（射線貼地、面向審圖目標）
##   - 不演獸道序章：不鎖時間、不躺下、不開獨白／對話，玩家一進場就是可操作站立狀態
##   - 時間設成審圖值（預設 10:00）並凍結
##   - 可選：隱藏規劃線／名牌等 Debug 疊層（不動遊戲節點）
## 不寫 StoryFlags、不讀寫存檔、不改序章內容——正式流程（main.gd 的 START_MAP／_play_opening）原封不動。
##
## 設定來源（後者覆蓋前者）：
##   1. res://dev/review_start.json   {"enabled": true, "spawn": "suzunaan", "hour": 10.0, "freeze_time": true, "hide_debug": true}
##   2. 命令列：--review（用設定檔的 spawn）／--review=<spawn>／--review-hour=10.5／--no-review（強制正式流程）
## 設定檔 enabled=true 只在編輯器執行（OS.has_feature("editor")）時採用；匯出的 debug 版要用命令列 --review。
## spawn 一覽：main_street, hieda, shrine, school, waterwheel, fire_lookout, suzunaan, dragon, geidontei, kirisame。

const CONFIG := "res://dev/review_start.json"
const MAP := "village_v2"
## 站位（x, z）→ 面向（x, z）；全部在路面或開闊地（不在屋頂上），y 由射線決定；預設 SpringArm 長度下相機不進建物（主街 4 m 寬，正對門面會被對街建物擋，故鈴奈庵從北角斜看）。
const SPAWNS := {
	"main_street": {"label": "主街（北望）", "at": Vector2(241.0, 44.0), "look": Vector2(262.0, -20.0)},
	"hieda": {"label": "稗田邸（大宅門前）", "at": Vector2(398.0, 3.0), "look": Vector2(400.0, -30.0)},
	"shrine": {"label": "神社參道（參道鳥居前）", "at": Vector2(296.5, -142.0), "look": Vector2(289.6, -166.0)},
	"school": {"label": "寺子屋（西巷→玄關）", "at": Vector2(213.0, 24.0), "look": Vector2(188.0, 24.0)},
	"waterwheel": {"label": "水車（一號水車，西岸看輪面）", "at": Vector2(327.8, -52.6), "look": Vector2(334.8, -52.0)},
	"fire_lookout": {"label": "火見櫓（主街側）", "at": Vector2(240.6, 54.6), "look": Vector2(250.0, 66.0)},
	"suzunaan": {"label": "鈴奈庵（北の角から門前・置き看板）", "at": Vector2(257.0, -11.0), "look": Vector2(250.6, -3.8)},
	"dragon": {"label": "龍神像（參拝道）", "at": Vector2(375.2, -188.0), "look": Vector2(388.0, -188.0)},
	"geidontei": {"label": "鯢吞亭（主街南西から門前・外の席）", "at": Vector2(274.2, -56.8), "look": Vector2(280.5, -62.2)},
	"kirisame": {"label": "霧雨店（主街の南から店先・南側の出し）", "at": Vector2(237.1, 71.7), "look": Vector2(229.9, 64.3)},
}
const DEBUG_NODES := ["Debug", "QuestAnchors", "Districts/LandmarkParcelLines", "Districts/AuxParcelLines"]


## 回傳空字典＝不生效（走正式流程）。tool_args＝已被其他工具模式（--shot／--playtest／--map／--continue）佔用時傳 true。
static func resolve(tool_args: bool) -> Dictionary:
	if not OS.is_debug_build():
		return {}
	var args := OS.get_cmdline_user_args()
	if "--no-review" in args:
		return {}
	var cfg := {"enabled": false, "spawn": "suzunaan", "hour": 10.0, "freeze_time": true, "hide_debug": true}
	if FileAccess.file_exists(CONFIG):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		if j is Dictionary:
			cfg.merge(j, true)
	var explicit := false
	for a: String in args:
		if a == "--review":
			explicit = true
		elif a.begins_with("--review="):
			explicit = true
			cfg["spawn"] = a.trim_prefix("--review=")
		elif a.begins_with("--review-hour="):
			cfg["hour"] = a.trim_prefix("--review-hour=").to_float()
	var active := explicit or (bool(cfg["enabled"]) and OS.has_feature("editor") and not tool_args)
	if not active:
		return {}
	var sp := String(cfg["spawn"])
	if not SPAWNS.has(sp):
		push_warning("[review] 未知 spawn '%s'，改用 suzunaan（可用：%s）" % [sp, ", ".join(SPAWNS.keys())])
		sp = "suzunaan"
	cfg["spawn"] = sp
	cfg["map"] = MAP
	return cfg


## load_map(MAP) 之後呼叫（main.gd 用 call_deferred）：等碰撞註冊 → 射線貼地 → 面向 → 時間 → 疊層。
static func apply(main: Node, cfg: Dictionary) -> void:
	var tree := main.get_tree()
	await tree.physics_frame
	await tree.physics_frame
	var player: CharacterBody3D = main.get("player")
	var sp: Dictionary = SPAWNS[String(cfg["spawn"])]
	var at: Vector2 = sp["at"]
	var look: Vector2 = sp["look"]
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, 60.0, at.y), Vector3(at.x, -20.0, at.y))
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	var y: float = (hit["position"] as Vector3).y + 0.05 if not hit.is_empty() else 40.0
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(at.x, y, at.y)
	var yaw := atan2(-(look.x - at.x), -(look.y - at.y))
	if player.has_method("snap_yaw"):
		player.snap_yaw(yaw)
	else:
		player.rotation.y = yaw
	if "input_locked" in player:
		player.set("input_locked", false)
	var dn: Node = main.get_node_or_null("/root/DayNight")
	if dn != null:
		if dn.has_method("set_hour"):
			dn.set_hour(float(cfg["hour"]))
		if bool(cfg.get("freeze_time", true)):
			dn.set("flowing", false)
	var mr: Node = main.get("map_root")
	if bool(cfg.get("hide_debug", true)) and mr != null:
		for nm: String in DEBUG_NODES:
			var n: Node = mr.get_node_or_null(nm)
			if n is Node3D:
				(n as Node3D).visible = false
		var d: Node = mr.get_node_or_null("Districts")
		if d != null:
			for n in d.find_children("*ParcelLines*", "", true, false):
				if n is Node3D:
					(n as Node3D).visible = false
	if "portal_cooldown" in main:
		main.set("portal_cooldown", 2.0)
	print("[review] dev review start：%s %s（%.2f, %.2f, %.2f）時刻 %.2f%s" % [cfg["spawn"], sp["label"], at.x, y, at.y,
		float(cfg["hour"]), "（凍結）" if bool(cfg.get("freeze_time", true)) else ""])
