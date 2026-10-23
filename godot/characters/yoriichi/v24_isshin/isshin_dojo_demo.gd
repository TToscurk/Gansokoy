extends "res://characters/yoriichi/v24_isshin/isshin_pairx_demo.gd"
## 緣一劍術動作展示／試玩場景（候選；不改正式 Player／跑酷／共用資產；各招獨立 demo 與既有候選設定不動）。
## 招式表：dojo_moves.json（notes/gen_batch_moves.py 產生：既有招式＋本批新招）。
## 操作：1–9、0 選招（Tab／Shift+Tab 換頁）；J／K／滑鼠左鍵＝出選中的招；G＝拔刀／收刀；W/S/A/D 移動；Space 閃避；
##       其餘同戰鬥步行 demo（Q/E 轉鏡頭、O 繞敵、F 布料、H 說明）。
## 武器狀態（場景內的簡單狀態機）：drawn＝刀在手上（一般架勢、可移動）；sheathed＝居合構（刀在鞘）。
##   需要「刀在鞘」的招（居合系）在刀在手上時：先收刀再出招；需要「刀在手上」的招在居合構時：先拔刀再出招。
##   居合斬／二連斬斬完、納刀前按移動或閃避＝取消、刀留在手上；不取消就完整納刀。居合構時按移動＝自動拔刀。
## 自動導覽（錄影／測試）：-- --tour --tourfile=PATH.json [--cam=third|side]；每段：{d,label,select,weapon,attack,dodge,hold,side,mv,enemy}
const MOVES_JSON := "res://characters/yoriichi/v24_isshin/dojo_moves.json"
var moves: Array = []
var move_ix := {}
var sel := 0
var weapon := "drawn"
var pending_key := ""
var tracks := {}
var _prev_state := -1
var _prev_key := ""
var _tour_file := ""
## R10（選用，預設維持舊行為）：居合構按移動不再自動拔刀；切換武器狀態後不自動補出選中的招
var auto_draw_on_move := true
var auto_pending_after_switch := true

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tourfile="):
			_tour_file = a.substr(11)
	super._ready()
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MOVES_JSON))
	moves = d["moves"]
	for i in moves.size():
		move_ix[moves[i]["key"]] = i
	for k in d.get("overrides", {}):
		combat.shot_override[k] = d["overrides"][k]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ovr="):          # 調參用：--ovr='{"key": {"min_dist": 1.3}}'
			var o: Dictionary = JSON.parse_string(a.substr(6))
			for k in o:
				combat.shot_override[k] = (combat.shot_override.get(k, {}) as Dictionary).merged(o[k], true)
	for k in move_ix.keys() + ["draw", "noto"]:
		var anim: String = combat.shots[k]["anim"]
		var p := "res://characters/yoriichi/v24_isshin/anims/" + anim + "_sword.json"
		if FileAccess.file_exists(p):
			tracks[k] = JSON.parse_string(FileAccess.get_file_as_string(p))
	combat.shot_finished.connect(_on_shot_finished)
	_set_weapon("drawn")
	sel = 0

var weapon_log: Array = []

func _set_weapon(w: String) -> void:
	if w != weapon or weapon_log.is_empty():
		weapon_log.append({"t": snappedf(tour_t - TOUR_START_DELAY, 0.001), "weapon": w, "after": combat.shot_key if combat else ""})
	weapon = w
	combat.set_iai_mode(w == "sheathed")

func _finish_tour() -> void:
	if slashlog_path != "":
		var f := FileAccess.open(slashlog_path.get_basename() + "_weapon.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(weapon_log))
		f.close()
	super._finish_tour()

func _sel_key() -> String:
	return moves[sel]["key"]

func _req(key: String) -> String:
	return str(moves[move_ix[key]].get("req", "drawn")) if move_ix.has(key) else "drawn"

## 每幀出招前：依選中的招與武器狀態決定攻擊鍵出哪一支（不符時先出拔刀／收刀，之後自動接選中的招）
func _route() -> void:
	var k := _sel_key()
	combat.iai_key = k if _req(k) == "sheathed" else "draw"      # 居合構時出的招
	combat.attack_key = k if _req(k) == "drawn" else "noto"     # 刀在手上時出的招（收招段攻擊取消後武器狀態可能剛切換，兩個都先設好）

func _on_shot_finished(key: String, t: float, cancelled: bool) -> void:
	if key == "draw":
		_set_weapon("drawn")
	elif key == "noto":
		_set_weapon("sheathed")
	elif move_ix.has(key):
		var m: Dictionary = moves[move_ix[key]]
		if str(m.get("req", "drawn")) == "sheathed":
			if bool(m.get("ends_drawn", false)) or (cancelled and t < float(m.get("noto_t", 99.0))):
				_set_weapon("drawn")
			else:
				_set_weapon("sheathed")
	if (key == "draw" or key == "noto") and pending_key != "" and not cancelled:
		call_deferred("_fire_pending")

func _fire_pending() -> void:
	var k := pending_key
	pending_key = ""
	if k != "" and combat.state != combat.S.SHOT:
		var to := enemy_pos - actor.global_position
		combat._fire(k, wrapf(atan2(to.x, to.z) - actor.rotation.y, -PI, PI))

var _chase := 0.0
var _chase_until := 99.0

func _process(delta: float) -> void:
	# 導覽段的 chase（m/s）：出招期間木樁朝角色追（停在 0.9 m；停格中不動）——退步系招式要有追擊中的敵人才打得到
	if tour and _chase > 0.0 and combat.state == combat.S.SHOT and combat.hitstop_left == 0 and combat.shot_t < _chase_until:
		var to := actor.global_position - enemy_pos
		to.y = 0.0
		if to.length() > 0.9:
			enemy_pos += to.normalized() * minf(_chase * delta, to.length() - 0.9)
	_route()
	if auto_draw_on_move and weapon == "sheathed" and combat.state != combat.S.SHOT and _move_input().length() > 0.1:
		pending_key = ""
		combat._fire("draw", 0.0)       # 居合構時按移動＝自動拔刀
	super._process(delta)
	if combat.state == combat.S.SHOT and (combat.shot_key != _prev_key or _prev_state != combat.S.SHOT):
		var k := _sel_key()
		if auto_pending_after_switch and ((combat.shot_key == "draw" and _req(k) == "drawn") or (combat.shot_key == "noto" and _req(k) == "sheathed")):
			if tour or _move_input().length() <= 0.1:
				pending_key = k
	_prev_state = combat.state
	_prev_key = combat.shot_key
	if hud and not tour:
		hud.text = _hud_text()

func _hud_text() -> String:
	var lines := ["緣一劍術動作展示（候選 ART_REVIEW）  武器：%s   G 拔刀／收刀  1–0 選招  Tab 換頁" % ("刀在手上" if weapon == "drawn" else "居合構（刀在鞘）")]
	var page := sel / 10
	for i in range(page * 10, mini(moves.size(), page * 10 + 10)):
		var m: Dictionary = moves[i]
		lines.append("%s %d  %s%s" % ["▶" if i == sel else "  ", (i % 10 + 1) % 10, m["label"], "（鞘）" if str(m.get("req", "drawn")) == "sheathed" else ""])
	lines.append("出招中：%s  t=%.2f" % [combat.shot_key if combat.state == combat.S.SHOT else "—", combat.shot_t])
	return "\n".join(lines)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo:
		var ke := e as InputEventKey
		if ke.keycode >= KEY_0 and ke.keycode <= KEY_9:
			var n := (int(ke.keycode - KEY_0) + 9) % 10
			sel = clampi((sel / 10) * 10 + n, 0, moves.size() - 1)
			return
		if ke.keycode == KEY_TAB:
			var pages := (moves.size() + 9) / 10
			var pg := posmod(sel / 10 + (-1 if ke.shift_pressed else 1), pages)
			sel = clampi(pg * 10, 0, moves.size() - 1)
			return
		if ke.keycode == KEY_G and combat.state != combat.S.SHOT:
			pending_key = ""
			combat._fire("draw" if weapon == "sheathed" else "noto", 0.0)
			return
	super._unhandled_input(e)

## 受擊擊退：招式表有 knock（每刀擊退 m）就用它，否則沿用基底（依第幾刀 0／0.6／0.45 m）
func _on_hit(info: Dictionary) -> void:
	super._on_hit(info)
	var key := str(info.get("key", ""))
	if move_ix.has(key) and moves[move_ix[key]].has("knock"):
		var kl: Array = moves[move_ix[key]]["knock"]
		var km := float(kl[mini(int(info.get("strike", 0)), kl.size() - 1)])
		var kd := enemy_pos - actor.global_position
		kd.y = 0.0
		if km > 0.0 and kd.length() > 0.01:
			knock_from = enemy_pos
			knock_to = enemy_pos + kd.normalized() * km
			knock_t = 0.0
		else:
			knock_t = -1.0

## 判定：同 pairx 候選（刀身 u ≥ 0.25、木樁實際半徑、切入 5 cm、整把刀變換插值掃掠），另外掃掠只取「判定窗打開之後」的那一段
## （上一幀若還在窗外，就不檢查窗開之前的中間位置；否則窗一打開就會把開窗前刀已經在木樁裡的位置算成命中）。
func _hit_test() -> Dictionary:
	if sword == null:
		return {}
	var cfg: Dictionary = combat._cfg(combat.shot_key)
	var t1: float = combat.shot_t
	var dt := get_process_delta_time()
	var t0 := t1 - dt
	var wmin := 0.0
	for w in cfg.get("strikes", []):
		if t1 >= float(w[0]) and t1 <= float(w[1]) and t0 < float(w[0]) and dt > 0.0:
			wmin = clampf((float(w[0]) - t0) / dt, 0.0, 1.0)
	var cur := sword.global_transform
	var prev := _xf_prev if _xf_prev != Transform3D() else cur
	for k in range(1, 5):
		var w2 := float(k) / 4.0
		if w2 < wmin - 1e-4:
			continue
		var xf := prev.interpolate_with(cur, w2)
		var a := xf * GUARD_LOCAL
		var b := xf * TIP_LOCAL
		var best := 0.0
		var hit := {}
		for i in range(4, 17):
			var u := float(i) / 16.0
			var p := a.lerp(b, u)
			var hv := Vector2(p.x - enemy_pos.x, p.z - enemy_pos.z)
			var r := _dummy_r(p.y)
			var depth := r - hv.length()
			if p.y > 0.05 and p.y < 1.95 and depth > maxf(best, HIT_MIN_DEPTH):
				best = depth
				var n := hv.normalized() if hv.length() > 1e-3 else Vector2(0, -1)
				var dv := tip_v.normalized() if tip_v.length() > 0.5 else Vector3.DOWN
				hit = {"pos": Vector3(enemy_pos.x + n.x * r, p.y, enemy_pos.z + n.y * r), "dir": dv, "tip_speed": tip_speed, "blade_u": u, "depth": depth, "sub": w2}
		if not hit.is_empty():
			return hit
	return {}

## 刀的顯示：有逐格刀可見度資料的招（居合系、拔刀、收刀）照資料；其餘依武器狀態
func _apply_sword_vis() -> void:
	var mode := "hand" if weapon == "drawn" else "sheathed"
	var clip := 10.0
	var key: String = combat.shot_key
	if combat.state == combat.S.SHOT and tracks.has(key):
		var tr: Dictionary = tracks[key]
		var frames: Array = tr["frames"]
		var f := clampi(int(round(combat.shot_t * float(tr["fps"]))), 0, frames.size() - 1)
		mode = str(frames[f]["mode"])
		clip = float(frames[f]["clip_y"])
	sword.visible = mode == "hand"
	sword_sheathed.visible = mode == "sheathed"
	for sm in hand_mats:
		(sm as ShaderMaterial).set_shader_parameter("clip_y", clip if mode == "hand" else 10.0)
	if tour and tour_t >= TOUR_START_DELAY and combat.state == combat.S.SHOT and combat.shots[key].get("attack", false):
		vis_log.append({"t": snappedf(tour_t - TOUR_START_DELAY, 0.0001), "shot_t": snappedf(combat.shot_t, 0.0001), "key": key, "mode": mode,
			"hitstop": combat.hitstop_left, "label": cur_label, "weapon": weapon, "probe": _contact_probe()})

## 側面相機：每次出招時定一次、整招固定（垂直於角色→木樁連線、站在右手側再往正面轉 20°）
var _dj_side_set := false
var _dj_side_locked := false

func _update_cam(snap: bool) -> void:
	if not OS.get_cmdline_user_args().has("--cam=side"):
		super._update_cam(snap)
		return
	var firing: bool = combat.state == combat.S.SHOT and bool(combat.shots[combat.shot_key].get("attack", false))
	if not _dj_side_set or (firing and not _dj_side_locked):
		_dj_side_set = true
		_dj_side_locked = firing
		var to := enemy_pos - actor.global_position
		to.y = 0.0
		var yaw := atan2(to.x, to.z)
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		var right := Vector3(-cos(yaw), 0, sin(yaw))
		var midp := actor.global_position + dir * (to.length() * 0.5) + Vector3(0, 1.0, 0)
		var cdir := right.rotated(Vector3.UP, -deg_to_rad(20.0))
		cam.global_position = midp + cdir * maxf(5.0, to.length() * 1.4) + Vector3(0, 0.6, 0)
		cam.look_at(midp, Vector3.UP)
	if not firing:
		_dj_side_locked = false

## 導覽：讀 --tourfile；每段開頭可指定 select（招式 key）與 weapon（直接設定武器狀態）
func _build_tour() -> void:
	if _tour_file == "":
		_s(1.0, "（沒有 --tourfile）")
		return
	var segs: Array = JSON.parse_string(FileAccess.get_file_as_string(_tour_file))
	for sg in segs:
		var st: Dictionary = sg
		var mv := Vector2.ZERO
		if st.has("mv"):
			mv = Vector2(float(st["mv"][0]), float(st["mv"][1]))
		var extra := st.duplicate()
		extra.erase("d")
		extra.erase("label")
		extra.erase("mv")
		_s(float(st["d"]), str(st.get("label", "")), mv, extra)

func _tour_step(delta: float) -> void:
	var prev := tour_ix
	super._tour_step(delta)
	if tour_ix != prev and tour_ix >= 0 and tour_ix < tour_steps.size():
		var st: Dictionary = tour_steps[tour_ix]
		if st.has("select") and move_ix.has(str(st["select"])):
			sel = int(move_ix[str(st["select"])])
		_chase = float(st.get("chase", 0.0))
		_chase_until = float(st.get("chase_until", 99.0))
		if st.has("weapon") and combat.state != combat.S.SHOT:
			_set_weapon(str(st["weapon"]))
			pending_key = ""
