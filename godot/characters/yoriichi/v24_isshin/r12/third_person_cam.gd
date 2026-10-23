extends RefCounted
## 第三人稱自由鏡頭（與 isshin_combat_demo.gd 的 _update_cam 同一套：身後偏右肩、跟隨角色朝向帶延遲、Q／E 轉動 cam_yaw_extra）。
## R9 之後的試玩繼承鏈中間有居合試玩的左側固定鏡頭（isshin_iai_demo.gd，只有 --cam=third 才回到第三人稱），
## R12 試玩與比較錄影直接呼叫這一份，不改上游檔案。技能期間不接管鏡頭。
static func update(demo, snap: bool) -> void:
	var actor: Node3D = demo.actor
	var cam: Camera3D = demo.cam
	var pp := actor.global_position
	if snap:
		demo.cam_yaw = actor.rotation.y
	else:
		demo.cam_yaw = lerp_angle(demo.cam_yaw, actor.rotation.y, 1.0 - exp(-2.6 * demo.get_process_delta_time()))
	var yw: float = demo.cam_yaw + demo.cam_yaw_extra
	var dir := Vector3(sin(yw), 0.0, cos(yw))
	var right := dir.cross(Vector3.UP)
	var want := pp - dir * 4.4 + Vector3(0, 2.1, 0) + right * 0.9
	var look := pp + dir * 1.8 + Vector3(0, 1.05, 0)
	if snap:
		cam.global_position = want
	else:
		cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-8.0 * demo.get_process_delta_time()))
	cam.look_at(look, Vector3.UP)
