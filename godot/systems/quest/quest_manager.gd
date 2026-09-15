extends Node
## QuestManager —— 任務進度（autoload）。
##
## 定義 = res://data/quests/<id>.tres（QuestData）；進度只存在這裡：
##   _progress[quest_id] = { "objective_index": int, "current": int, "state": State }
## 事件入口只有 report_event()；沒有對應的 active quest 就安靜忽略。
## 不 get_node 世界物件；只往下呼叫 StoryFlags。
##
## quest_id 一律經 _norm() 正規化（大寫、去空白）後才當 key。
## ⚠ 舊版檔名用 to_lower()、字典用原字串：start_quest("MQ00") 與 start_quest("mq00")
##   會各建一份 active 進度，同一個事件同時推進兩份、完成兩次、連鎖兩次。

signal quest_started(quest_id: String)
signal objective_updated(quest_id: String, objective_index: int, current: int, required: int)
signal quest_completed(quest_id: String)
signal tracked_quest_changed(quest_id: String)

enum State { INACTIVE, ACTIVE, COMPLETED }

const QUEST_DIR := "res://data/quests/"

var _progress: Dictionary = {}
var _tracked: String = ""
var _defs: Dictionary = {}       # id → QuestData（快取）
## 早到的事件："<type_int>|<target_id>" → 累積 amount。
## 世界事件只演一次，任務還沒推進到時先存著，等目標對上再補算。
var _pending: Dictionary = {}
## "<type_int>|<target_id>" → [[quest_id, objective_index], …]，掃 data/quests/ 建立。
## 用途：判斷一個早到事件**將來還有沒有任務會用到**。
var _event_index: Dictionary = {}
var _index_built := false


func _norm(quest_id: String) -> String:
	return quest_id.strip_edges().to_upper()


func load_definition(quest_id: String) -> QuestData:
	var id := _norm(quest_id)
	if _defs.has(id):
		return _defs[id]
	var path := QUEST_DIR + id.to_lower() + ".tres"
	if not ResourceLoader.exists(path):
		push_warning("[Quest] 找不到任務定義 %s" % path)
		return null
	var q := load(path) as QuestData
	if q != null:
		_defs[id] = q
	return q


func start_quest(quest_id: String) -> bool:
	var id := _norm(quest_id)
	if is_active(id) or is_completed(id):
		return false
	var q := load_definition(id)
	if q == null:
		return false
	_progress[id] = {"objective_index": 0, "current": 0, "state": State.ACTIVE}
	quest_started.emit(id)
	if _tracked.is_empty() or not is_active(_tracked):
		_set_tracked(id)
	var obj := get_current_objective(id)
	if obj != null:
		objective_updated.emit(id, 0, 0, obj.required_amount)
	# 這個任務的第一個目標，玩家可能在接到任務前就已經達成了
	_flush_pending()
	return true


## 統一事件入口。type 用 QuestObjective.Type 的名字（"REACH"/"TALK"…）或列舉值。
##
## 事件若現在沒有對應的 active 目標，**且將來還有任務可能用到它**，會存進 _pending，
## 等到該目標成為當前目標時自動補算。理由：世界事件只演一次（受傷妖怪的 once_flag
## 一立就再也不會重播），若那一刻任務還沒推進到該目標，玩家就永久失去完成任務的機會。
##
## ⚠ 但不能無條件存。舊版任何事件都往 _pending 丟，於是：
##   回頭走過已完成的 REACH 區、重複找靈夢說話、傳了個不存在的列舉值，
##   全都在字典裡永久累積（實測回頭走一趟就殘留 3 筆、重訪靈夢 3 次累積到 amount=3）。
##   這些存貨會把未來用到同一 target_id 的任務瞬間沖完。
##   現在只存「_event_index 裡還有任務沒走到這一格」的事件。
func report_event(event_type: Variant, target_id: String, amount: int = 1) -> void:
	var t := _to_type(event_type)
	if t < 0:
		return
	# 0 或負數沒有意義：舊版 amount=-3 會把 current 倒扣成負的，
	# amount=0 則被當成「已處理」既不推進也不存起來。
	if amount <= 0:
		if amount < 0:
			push_warning("[Quest] report_event 收到負的 amount=%d（%s）" % [amount, target_id])
		return
	if _apply_event(t, target_id, amount):
		return
	var cap := _future_required(t, target_id)
	if cap <= 0:
		return          # 將來沒有任務會用到這個事件 —— 不留存貨
	var key := "%d|%s" % [t, target_id]
	_pending[key] = mini(int(_pending.get(key, 0)) + amount, cap)


## 把事件套用到目前 active 的任務上。有任何一個任務吃下就回傳 true。
func _apply_event(t: int, target_id: String, amount: int) -> bool:
	var applied := false
	# 先複製 key 清單：完成任務會連鎖 start_quest() 動到 _progress，
	# 直接迭代原字典會在迴圈中被修改。
	for quest_id in _progress.keys().duplicate():
		if not _progress.has(quest_id) or _progress[quest_id]["state"] != State.ACTIVE:
			continue
		var obj := get_current_objective(quest_id)
		if obj == null or obj.type != t or obj.target_id != target_id:
			continue
		var p: Dictionary = _progress[quest_id]
		if p["current"] >= obj.required_amount:
			continue          # 已滿，不重複計
		p["current"] = mini(p["current"] + amount, obj.required_amount)
		applied = true
		objective_updated.emit(quest_id, p["objective_index"], p["current"], obj.required_amount)
		if p["current"] >= obj.required_amount:
			advance_objective(quest_id)
	return applied


## 目標切換後：把先前存起來、對得上新目標的事件補算掉。
func _flush_pending() -> void:
	if _pending.is_empty():
		return
	for key in _pending.keys().duplicate():
		if not _pending.has(key):
			continue
		var parts := String(key).split("|", true, 1)
		if parts.size() != 2:
			_pending.erase(key)
			continue
		var t := int(parts[0])
		var target := String(parts[1])
		var amount := int(_pending[key])
		# 先移除再套用：_apply_event 可能連鎖推進任務並再次呼叫本函式。
		_pending.erase(key)
		if _apply_event(t, target, amount):
			continue
		# 沒人要：只有「將來還用得到」才留著，否則就此丟棄（避免永久殘留）。
		var cap := _future_required(t, target)
		if cap > 0:
			_pending[key] = mini(amount, cap)


## 這個事件將來還有任務可能用到嗎？回傳「還用得到的最大 required_amount」，
## 0 = 沒有任何任務會再吃它。同時當成 _pending 的累積上限。
func _future_required(t: int, target_id: String) -> int:
	_build_index()
	var key := "%d|%s" % [t, target_id]
	var best := 0
	for entry in _event_index.get(key, []):
		var qid: String = entry[0]
		var oi: int = entry[1]
		if is_completed(qid):
			continue                      # 這個任務已經結束
		if is_active(qid) and int(_progress[qid]["objective_index"]) > oi:
			continue                      # 已經走過這一格，不會再回頭
		var q := load_definition(qid)
		if q == null or oi >= q.objectives.size():
			continue
		best = maxi(best, q.objectives[oi].required_amount)
	return best


## 掃描 data/quests/，建立 (type|target) → [[quest_id, objective_index], …]。
func _build_index() -> void:
	if _index_built:
		return
	_index_built = true
	var dir := DirAccess.open(QUEST_DIR)
	if dir == null:
		push_warning("[Quest] 開不了 %s" % QUEST_DIR)
		return
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var q := load(QUEST_DIR + f) as QuestData
		if q == null:
			continue
		var qid := _norm(q.id) if not q.id.is_empty() else _norm(f.get_basename())
		_defs[qid] = q
		for i in q.objectives.size():
			var o: QuestObjective = q.objectives[i]
			if o == null:
				continue
			var key := "%d|%s" % [o.type, o.target_id]
			if not _event_index.has(key):
				_event_index[key] = []
			_event_index[key].append([qid, i])


func advance_objective(quest_id: String) -> void:
	var id := _norm(quest_id)
	if not is_active(id):
		return
	var q := load_definition(id)
	if q == null:
		return
	var p: Dictionary = _progress[id]
	p["objective_index"] += 1
	p["current"] = 0
	if p["objective_index"] >= q.objectives.size():
		complete_quest(id)
	else:
		var obj: QuestObjective = q.objectives[p["objective_index"]]
		objective_updated.emit(id, p["objective_index"], 0, obj.required_amount)
		# 新目標可能早就被玩家達成過（例：先撞到受傷妖怪、才回頭看逃跑妖怪）
		_flush_pending()


func complete_quest(quest_id: String) -> void:
	var id := _norm(quest_id)
	if not is_active(id):
		return
	var q := load_definition(id)
	_progress[id]["state"] = State.COMPLETED
	if q != null:
		for f in q.complete_flags:
			StoryFlags.set_flag(String(f), true)
	quest_completed.emit(id)
	var chained := false
	if q != null and not q.next_quest_id.is_empty():
		chained = start_quest(q.next_quest_id)
	# ⚠ 鏈斷了（沒有下一關／下一關已完成／定義不存在）時，追蹤指標不得留在
	#   剛完成的任務上 —— 舊版的 elif 只在 next_quest_id 為空時才清，
	#   下一關已完成的情況下 _tracked 會永久卡著一個 COMPLETED 的 id，
	#   tracked_quest_changed 也不再發，追蹤 UI 只能靠字典順序 fallback 撐著。
	if _tracked == id and not chained:
		_set_tracked(_first_active())


func is_active(quest_id: String) -> bool:
	var id := _norm(quest_id)
	return _progress.has(id) and _progress[id]["state"] == State.ACTIVE


func is_completed(quest_id: String) -> bool:
	var id := _norm(quest_id)
	return _progress.has(id) and _progress[id]["state"] == State.COMPLETED


func get_active_quest() -> String:
	if is_active(_tracked):
		return _tracked
	return _first_active()


func _first_active() -> String:
	for id in _progress.keys():
		if is_active(id):
			return id
	return ""


func get_current_objective(quest_id: String) -> QuestObjective:
	var id := _norm(quest_id)
	if not is_active(id):
		return null
	var q := load_definition(id)
	var i: int = _progress[id]["objective_index"]
	if q == null or i >= q.objectives.size():
		return null
	return q.objectives[i]


func get_objective_progress(quest_id: String) -> int:
	return int(_progress.get(_norm(quest_id), {}).get("current", 0))


func _set_tracked(quest_id: String) -> void:
	_tracked = quest_id
	tracked_quest_changed.emit(quest_id)


func _to_type(v: Variant) -> int:
	if v is int:
		var i := int(v)
		# ⚠ 一定要驗範圍。舊版原封不動回傳，report_event(99, …) 照樣被接受，
		#   在 _pending 裡留下一筆永遠對不上任何目標的殘骸。
		if QuestObjective.Type.values().has(i):
			return i
		push_warning("[Quest] 事件型別超出範圍 %d" % i)
		return -1
	var s := String(v).to_upper()
	if QuestObjective.Type.has(s):
		return QuestObjective.Type[s]
	push_warning("[Quest] 未知事件型別 %s" % s)
	return -1


## ── 存檔 ──
## 只吐純資料：進度字典、追蹤中的任務、未消化的早到事件。
## **不存 QuestData 本身** —— 定義在 res:// 裡，跟著版本走，存進檔案只會讓
## 改任務內容時舊檔全爆。存 id 與索引，載入時重新對照定義。
func serialize() -> Dictionary:
	var prog := {}
	for id in _progress:
		var p: Dictionary = _progress[id]
		prog[String(id)] = {
			"objective_index": int(p["objective_index"]),
			"current": int(p["current"]),
			"state": int(p["state"]),
		}
	return {"progress": prog, "tracked": _tracked, "pending": _pending.duplicate()}


## 從存檔還原。**不發任何 signal** —— UI 會在載入完成後統一 refresh，
## 逐筆重放 quest_started／objective_updated 會讓追蹤器連跳好幾格、
## 甚至讓 WorldInteraction 的前置閘在場景重建到一半時誤觸發。
##
## 每一筆都對照現行定義驗證：任務被刪掉、目標數量變少（改版）時直接丟棄該筆，
## 不讓壞資料進到 _progress —— 存檔是使用者可編輯的檔案。
func deserialize(data: Dictionary) -> void:
	_progress.clear()
	_pending.clear()
	_tracked = ""
	var prog: Dictionary = data.get("progress", {})
	for raw_id in prog:
		var id := _norm(String(raw_id))
		var q := load_definition(id)
		if q == null:
			push_warning("[Quest] 存檔含已不存在的任務 %s，略過" % id)
			continue
		var e: Dictionary = prog[raw_id]
		var state := int(e.get("state", State.INACTIVE))
		if state != State.ACTIVE and state != State.COMPLETED:
			continue
		var oi := clampi(int(e.get("objective_index", 0)), 0, maxi(q.objectives.size(), 1))
		# ACTIVE 但索引已越界 = 定義改短了；當成已完成處理，不留一個推不動的任務。
		if state == State.ACTIVE and oi >= q.objectives.size():
			state = State.COMPLETED
			oi = q.objectives.size()
		var cur := 0
		if state == State.ACTIVE and oi < q.objectives.size():
			cur = clampi(int(e.get("current", 0)), 0, q.objectives[oi].required_amount)
		_progress[id] = {"objective_index": oi, "current": cur, "state": state}
	var t := _norm(String(data.get("tracked", "")))
	_tracked = t if is_active(t) else _first_active()
	# pending 照樣驗：型別與 target 對不上現行任務就不收（避免舊檔的殘骸復活）。
	for key in data.get("pending", {}):
		var parts := String(key).split("|", true, 1)
		if parts.size() != 2:
			continue
		var cap := _future_required(int(parts[0]), String(parts[1]))
		if cap <= 0:
			continue
		_pending[String(key)] = clampi(int(data["pending"][key]), 1, cap)


## 測試用
func reset() -> void:
	_progress.clear()
	_pending.clear()
	_tracked = ""
