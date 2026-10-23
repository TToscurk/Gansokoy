extends Node
## 錄製用外殼（候選測試工具；不改被測場景的任何檔案或行為）：
##   godot --path godot --write-movie OUT/video.avi --fixed-fps 60 res://tools/motion_capture/record_harness.tscn --
##         --mc-target=res://…/isshin_slash_demo.tscn --mc-out=OUT [--mc-proj-check] [--mc-no-marker] [--mc-cam-sweep=度每秒,開始秒,結束秒]
##         （其餘參數照常傳給被測場景，例如 --tour --no-audio --slashlog=…）
## 做的事：實例化被測場景→掛 MotionRecorder→（選用）放投影驗證小球、在指定時段旋轉被測場景的相機（只寫 cam_yaw_extra，不碰角色／戰鬥）。
const Recorder = preload("res://tools/motion_capture/motion_recorder.gd")
const SwordGeo = preload("res://tools/motion_capture/sword_geometry.gd")
const PROJ_POINTS := [Vector3(-1.0, 0.05, 2.4), Vector3(1.0, 0.05, 2.4), Vector3(-0.8, 1.8, 4.0), Vector3(0.8, 1.8, 4.0)]

var target: Node
var rec: Node
var cam_sweep := Vector3.ZERO      # x＝度／秒，y＝開始秒，z＝結束秒（相對錄製開始）
var _t := 0.0

func _ready() -> void:
	var tpath := ""
	var out := ""
	var proj := false
	var marker := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mc-target="):
			tpath = a.substr(12)
		elif a.begins_with("--mc-out="):
			out = a.substr(9)
		elif a == "--mc-proj-check":
			proj = true
		elif a == "--mc-no-marker":
			marker = false
		elif a.begins_with("--mc-cam-sweep="):
			var p := a.substr(15).split(",")
			cam_sweep = Vector3(float(p[0]), float(p[1]) if p.size() > 1 else 0.0, float(p[2]) if p.size() > 2 else 1e9)
	if tpath == "" or out == "":
		push_error("record_harness: need --mc-target= and --mc-out=")
		get_tree().quit(2)
		return
	var ps := load(tpath) as PackedScene
	if ps == null:
		push_error("record_harness: cannot load " + tpath)
		get_tree().quit(2)
		return
	target = ps.instantiate()
	add_child(target)
	rec = Recorder.new()
	rec.name = "MotionRecorder"
	rec.configure(target, out)
	rec.marker_enabled = marker
	rec.extra_meta = {"harness": {"target": tpath, "proj_check": proj, "cam_sweep_deg_s_start_end": [cam_sweep.x, cam_sweep.y, cam_sweep.z],
		"cam_sweep_writes": "target.cam_yaw_extra (camera only)" if cam_sweep.x != 0.0 else ""}}
	if proj:
		rec.proj_points = PROJ_POINTS
		rec.proj_tip_marker = true
		for p in PROJ_POINTS:
			_add_ball(self, p, 0.03, Color(1, 0, 1))
		var sword := target.find_child("Sword_Hand", true, false) as Node3D
		if sword:
			var mi := SwordGeo.find_mesh(sword)
			var geo := SwordGeo.analyze(sword)
			if mi and geo.get("ok", false):
				# 掛在刀網格底下＝與刀同一格繪製；半徑換算成世界 2.5 cm
				var s := mi.global_transform.basis.get_scale().x
				_add_ball(mi, geo["tip_local"], 0.025 / maxf(s, 1e-4), Color(0, 1, 0))
	add_child(rec)

func _add_ball(parent: Node, pos: Vector3, r: float, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.no_depth_test = true
	m.render_priority = 100
	m.disable_receive_shadows = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "MC_ProjBall"
	parent.add_child(mi)
	mi.position = pos

func _process(delta: float) -> void:
	# 外殼是被測場景的父節點：同優先權下比子節點先跑，所以這裡寫的相機角度在被測場景本格 _update_cam 前生效
	if rec:
		rec.note_harness_process()
	_t += delta
	if cam_sweep.x != 0.0 and target and "cam_yaw_extra" in target and _t >= cam_sweep.y and _t <= cam_sweep.z:
		target.set("cam_yaw_extra", float(target.get("cam_yaw_extra")) + deg_to_rad(cam_sweep.x) * delta)
