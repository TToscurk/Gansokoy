extends SceneTree
## R6 唯讀檢查：候選場景每個 R6 匯出資源，在執行期 AnimationPlayer 同名動畫是否真的是它（同名 GLB 內建動畫會擋掉 _add_animation_resource）。
func _initialize() -> void:
	var p: Node = (load("res://characters/yoriichi/player_yoriichi_r6.tscn") as PackedScene).instantiate()
	root.add_child(p)
	await process_frame
	var ap: AnimationPlayer = p.get("_anim")
	var pairs := {"idle_anim": "idle_grounded_resource", "jump_anim": "jump_anim_resource", "fall_anim": "fall_resource", "land_anim": "land_resource",
		"attack_spin_jump_anim": "attack_spin_jump_resource", "attack_thrust_anim": "attack_thrust_resource", "attack_form05_anim": "attack_form05_resource",
		"attack_form06_anim": "attack_form06_resource", "attack_form12_anim": "attack_form12_resource", "attack_spin_anim": "attack_spin_resource",
		"iai_stance_anim": "iai_stance_resource", "iai_slash_anim": "iai_slash_resource", "guard_anim": "guard_anim_resource", "block_anim": "block_anim_resource",
		"deflect_anim": "deflect_anim_resource"}
	for k in pairs:
		var nm: String = str(p.get(k))
		var res: Animation = p.get(pairs[k])
		var cur: Animation = ap.get_animation(nm) if ap.has_animation(nm) else null
		print("RES ", k, "=", nm, " R6=", res.resource_path.get_file() if res else "null", " playing=", (cur.resource_path.get_file() if cur and cur.resource_path != "" else ("<builtin>" if cur else "none")), " OK=", cur == res)
	for nm in ["Heavy_Cut", "D_Grip", "D_Idle", "D_StrafeL", "D_StrafeR", "D_WalkBack", "D_StrafeLRun", "D_StrafeRRun", "D_RunBack", "R5_QuickDraw"]:
		var cur2: Animation = ap.get_animation(nm) if ap.has_animation(nm) else null
		print("ANIM ", nm, " -> ", (cur2.resource_path.get_file() if cur2 else "none"))
	print("LIBS ", ap.get_animation_library_list())
	quit()
