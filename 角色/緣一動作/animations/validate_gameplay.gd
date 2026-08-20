extends SceneTree
# Headless runtime validation: loads yoriichi_test.tscn, drives the real
# controller through roll / jump / draw / 3-hit combo and measures the
# CharacterBody3D artifact (positions, timings, playback speed).

class Driver extends Node:
	var chr: CharacterBody3D
	var phase := "settle"
	var t := 0.0
	var p0 := Vector3.ZERO
	var p_roll_end := Vector3.ZERO
	var y_max := -1e9
	var action_t0 := 0.0
	var combo_max := 0
	var speed_seen := 0.0
	var clicks_sent := 0
	var results := PackedStringArray()

	func check(label: String, ok: bool, detail: String) -> void:
		results.append("%s %s: %s" % ["PASS" if ok else "FAIL", label, detail])

	func _physics_process(delta: float) -> void:
		t += delta
		match phase:
			"settle":
				if t > 0.5:
					p0 = chr.global_position
					chr.request_dodge(Vector3(0, 0, -1))
					action_t0 = t
					phase = "roll"
			"roll":
				if chr.action_state == chr.ActionState.FREE:
					p_roll_end = chr.global_position
					action_t0 = t
					phase = "roll_hold"
			"roll_hold":
				if t - action_t0 > 0.4:
					var p2 := chr.global_position
					var snap := Vector2(p2.x - p_roll_end.x, p2.z - p_roll_end.z).length()
					var disp := p0 - p_roll_end
					check("roll_displacement", absf(disp.z - chr.roll_distance) < 0.6 and absf(disp.x) < 0.3,
						"moved %.2f m in -Z (target %.1f), x drift %.2f" % [p_roll_end.z - p0.z, chr.roll_distance, disp.x])
					check("roll_no_snapback", snap < 0.05, "post-roll horizontal drift %.3f m" % snap)
					check("roll_floor", chr.is_on_floor() and absf(p2.y - p0.y) < 0.05, "y0=%.3f y_end=%.3f on_floor=%s" % [p0.y, p2.y, chr.is_on_floor()])
					p0 = chr.global_position
					y_max = -1e9
					chr.request_jump()
					action_t0 = t
					phase = "jump"
			"jump":
				y_max = maxf(y_max, chr.global_position.y)
				if chr.action_state == chr.ActionState.FREE:
					var dur := t - action_t0
					check("jump_height", y_max - p0.y > 0.4 and y_max - p0.y < 1.1, "peak +%.2f m (physics target ~0.71)" % (y_max - p0.y))
					check("jump_lands_back", chr.is_on_floor() and absf(chr.global_position.y - p0.y) < 0.05,
						"y back to %.3f (start %.3f), duration %.2f s (clip 1.90)" % [chr.global_position.y, p0.y, dur])
					chr.request_draw()
					action_t0 = t
					phase = "draw"
			"draw":
				if chr.sword_state == chr.SwordState.DRAWN:
					check("draw", true, "DRAWN after %.2f s" % (t - action_t0))
					chr.request_primary_attack()
					action_t0 = t
					clicks_sent = 1
					combo_max = 0
					speed_seen = 0.0
					phase = "combo"
				elif t - action_t0 > 3.0:
					check("draw", false, "still not DRAWN after 3 s")
					phase = "done"
			"combo":
				combo_max = maxi(combo_max, chr.combo_stage)
				if chr.action_state == chr.ActionState.ATTACKING:
					speed_seen = maxf(speed_seen, chr._anim.get_playing_speed())
				# Rapid re-clicks 0.12 s apart, well inside the 0.30 s buffer.
				if clicks_sent < 3 and t - action_t0 > 0.12 * clicks_sent:
					chr.request_primary_attack()
					clicks_sent += 1
				if clicks_sent >= 3 and chr.action_state == chr.ActionState.FREE:
					var dur := t - action_t0
					check("combo_reaches_3", combo_max >= 3, "max combo_stage=%d from 3 rapid clicks" % combo_max)
					check("attack_speed_5x", absf(speed_seen - chr.attack_speed_scale) < 0.01, "playing speed %.2f (target %.1f)" % [speed_seen, chr.attack_speed_scale])
					check("combo_fast_finish", dur < 2.0, "3-hit combo total %.2f s" % dur)
					check("attack_returns_free", true, "back to FREE, on_floor=%s" % chr.is_on_floor())
					phase = "done"
				elif t - action_t0 > 6.0:
					check("combo", false, "stuck: state=%d stage=%d after 6 s" % [chr.action_state, chr.combo_stage])
					phase = "done"
			"done":
				print("=== VALIDATION RESULTS ===")
				for r in results:
					print(r)
				get_tree().quit()

func _initialize():
	var level = (load("res://yoriichi_test.tscn") as PackedScene).instantiate()
	root.add_child(level)
	var chr: CharacterBody3D = level.get_node("Yoriichi")
	var d := Driver.new()
	d.chr = chr
	root.add_child(d)
