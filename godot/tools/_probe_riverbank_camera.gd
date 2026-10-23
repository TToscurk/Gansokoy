extends "res://tools/verify_village_v2_riverbank_gate.gd"
## 臨時診斷：只讀鏡頭、玩家與碰撞命中；不寫 gate.json 或正式場景。
var shot_index := 0

func _setup(parent: Node, vroot: Node3D = null) -> void:
	await super._setup(parent, vroot)
	if vroot != null:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var player := root.get_node("Main/Player") as CharacterBody3D
		var adapter := player.get_node("CameraAdapter")
		adapter._target_pitch = -0.18
		adapter._current_pitch = -0.18
		print("[CAM_DIAG] fixed pitch -0.18, mouse uncaptured; official scene and gate untouched")

func _write_gate(_part: String, _keys: Array[String], _extra := {}) -> void:
	print("[CAM_DIAG] gate write suppressed")

func _img_std(img: Image) -> float:
	shot_index += 1
	var cam := root.get_viewport().get_camera_3d()
	var player := root.get_node_or_null("Main/Player") as CharacterBody3D
	if cam != null and player != null:
		var cp := cam.global_position
		var pp := player.global_position
		var ground := RLib._surf(S, RD, cp.x, cp.z)
		var ray := PhysicsRayQueryParameters3D.create(cp, cp + (-cam.global_basis.z) * 20.0)
		ray.exclude = [player.get_rid()]
		var hit := cam.get_world_3d().direct_space_state.intersect_ray(ray)
		var hit_name := str((hit.get("collider") as Node).get_path()) if hit.has("collider") else "none"
		var pivot := player.get_node("Pivot") as Node3D
		var arm := player.get_node("Pivot/SpringArm3D") as SpringArm3D
		print("[CAM_DIAG] shot=%d player=%s camera=%s ground_at_camera=%.3f camera_above_ground=%.3f pitch=%.3f arm_len=%.3f ray=%s" % [shot_index, pp, cp, ground, cp.y - ground, pivot.rotation.x, arm.get_hit_length(), hit_name])
	if shot_index == 7:
		quit(1) # Stop after three suspect south approaches; diagnostic only.
	return super._img_std(img)
