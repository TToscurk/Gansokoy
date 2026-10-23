extends RefCounted
## 碧羅天 A/B 比較錄影（只讀，不改任何效果）：施放一次、固定鏡頭角度，逐幀記下技能時間，配合 Godot --write-movie --fixed-fps 30 錄影；
## 之後用 notes/r12/compare_vfx.py 依「同一動作階段」抽靜態畫面並並排成比較影片。
## 參數：--cap-out=FILE.json  --cap-cam=度（鏡頭相對角色後方的偏航，0＝預設正後方，65＝斜側面）
var demo
var out := ""
var cam_deg := 0.0
var t := 0.0
var phase := 0
var t_end := 0.0
var frame := 0
var rows: Array = []
var events: Array = []

func _init(d) -> void:
	demo = d
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cap-out="):
			out = a.substr(10)
		elif a.begins_with("--cap-cam="):
			cam_deg = float(a.substr(10))

func active() -> bool:
	return out != ""

func step(delta: float) -> void:
	if out == "":
		return
	frame += 1
	t += delta
	demo.cam_yaw_extra = deg_to_rad(cam_deg)
	if frame % 60 == 0 and OS.get_cmdline_user_args().has("--cap-debug"):
		print("CAPDBG f=%d cam=%s actor=%s yaw=%.3f cam_yaw=%.3f extra=%.3f" % [frame, demo.cam.global_position, demo.actor.global_position, demo.actor.rotation.y, demo.cam_yaw, demo.cam_yaw_extra])
	var on: bool = demo.combat.state == demo.combat.S.SHOT and demo.combat.shot_key == demo.cur_skill
	rows.append([frame, snappedf(t, 0.0001), snappedf(demo.combat.shot_t, 0.0001) if on else -1.0, demo.combat.hitstop_left])
	var idle: bool = demo.combat.state != demo.combat.S.SHOT and demo.combat.cooldown <= 0.0
	if phase == 0 and t > 1.2 and idle and demo.weapon == "drawn":
		demo._reset_to_dummy()
		demo.buf["skill"] = demo.now
		phase = 1
		events.append({"ev": "cast", "frame": frame, "t": t})
	elif phase == 0 and t > 0.3 and idle and demo.weapon != "drawn" and demo.combat.state != demo.combat.S.SHOT:
		demo.combat._fire("draw", 0.0)
	elif phase == 1 and on and events.size() == 1:
		events.append({"ev": "shot_start", "frame": frame, "t": t})
	elif phase == 1 and events.size() >= 2 and not on:
		events.append({"ev": "shot_end", "frame": frame, "t": t})
		phase = 2
		t_end = t
	elif phase == 2 and t > t_end + 0.8:
		finish()
	elif t > 20.0:
		finish()

func hit(info: Dictionary) -> void:
	if out != "":
		events.append({"ev": "hit", "frame": frame, "t": t, "shot_t": snappedf(float(info.get("shot_t", demo.combat.shot_t)), 0.001)})

func finish() -> void:
	if phase == 9:
		return
	phase = 9
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"cam": cam_deg, "events": events, "rows": rows, "dmg": demo.dmg_log}))
	f.close()
	demo.get_tree().quit()
