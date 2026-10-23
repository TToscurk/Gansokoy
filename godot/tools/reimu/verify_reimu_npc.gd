extends SceneTree
## 驗證 characters/reimu/reimu.tscn：袴骨鏈（SpringBoneSimulator3D）穩定度（NaN、轉角、離骨盆最遠距離）、
## 每格腳本耗時、多時間點截圖（正／側／背）。腿穿袴比例另用 probe_reimu_skirt_clip.gd（headless）。
## godot --path godot -s res://tools/reimu/verify_reimu_npc.gd -- [--out=<dir>] [--clip=idle|walk|<res 路徑>] [--sec=8] [--shots=3,5,7] [--npc=res://characters/marisa/marisa.tscn]
##   --npc：預設靈夢；魔理莎等共用 reimu_skirt.gd 的角色傳自己的 tscn（節點需有 Skirt）。
var npc: Node3D
var t := 0.0
var out := "D:/神社/shrine/docs/reimu/verify"
var npc_path := "res://characters/reimu/reimu.tscn"
var sec := 8.0
var clip := "idle"
var shots := [3.0, 5.0, 7.5]
var shot_i := 0
var phys_ms := []
var worst := {"stretch_max": 0.0, "over15_max": 0, "inside_leg_max_pct": 0.0, "far_max": 0.0, "nan": 0}
var cams := []
var vps := []
var sets := {}
var nomeasure := false
var _hooked := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--npc="): npc_path = a.substr(6)
		if a.begins_with("--sec="): sec = float(a.substr(6))
		if a.begins_with("--clip="): clip = a.substr(7)
		if a.begins_with("--shots="): shots = Array(a.substr(8).split(",")).map(func(x): return float(x))
		if a == "--nomeasure": nomeasure = true
		if a.begins_with("--set="):            # --set=屬性:值（設在 Skirt 節點上，例：springs_enabled:false、stiffness:3.0）
			var kv := a.substr(6).split(":")
			sets[kv[0]] = str_to_var(kv[1])
	DirAccess.make_dir_recursive_absolute(out)
	_setup.call_deferred()

func _setup() -> void:
	var w := Node3D.new(); get_root().add_child(w)
	var env := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.33, 0.34, 0.37); e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.82); env.environment = e; w.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 30, 0); w.add_child(sun)
	npc = (load(npc_path) as PackedScene).instantiate()
	for k in sets: npc.get_node("Skirt").set(k, sets[k])
	if clip == "idle" or clip == "walk":
		npc.set("animation", StringName(clip))
	w.add_child(npc)
	if not (clip == "idle" or clip == "walk"):
		var lib: AnimationLibrary = npc.player.get_animation_library(&"")
		var a := (load(clip) as Animation).duplicate() as Animation
		a.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(&"test", a)
		npc.play_clip(&"test", 0.0)
	var cam := Camera3D.new(); w.add_child(cam); cam.fov = 36
	cam.look_at_from_position(Vector3(0.9, 1.05, 2.9), Vector3(0, 0.75, 0)); cam.current = true   # 正面（+Z 側）
	for spec in [[Vector3(3.0, 0.95, 0.15), "side"], [Vector3(-1.2, 1.05, -2.8), "back"]]:
		var vp := SubViewport.new(); vp.size = Vector2i(800, 900); vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; w.add_child(vp)
		var c2 := Camera3D.new(); vp.add_child(c2); c2.fov = 36; c2.look_at_from_position(spec[0], Vector3(0, 0.75, 0)); c2.current = true
		vps.append([vp, spec[1]])

func _physics_process(dt: float) -> bool:
	if npc == null: return false
	t += dt
	if t > 2.0: phys_ms.append((Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
	if t > 2.0 and not nomeasure and not _hooked:
		_hooked = true
		var sk = npc.get_node("Skirt")
		(sk.skel as Skeleton3D).skeleton_updated.connect(_measure)
	if t >= sec:
		_report(); return true
	return false

func _process(_d: float) -> bool:
	if shot_i < shots.size() and t >= shots[shot_i]:
		var tag := "t%.1f" % shots[shot_i]
		shot_i += 1
		_shot(tag)
	return false

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out + "/%s_front.png" % tag)
	for v in vps: (v[0] as SubViewport).get_texture().get_image().save_png(out + "/%s_%s.png" % [tag, v[1]])

## 彈簧骨結果只在 skeleton_updated 裡讀得到：裙擺骨 NaN、相對靜止最大轉角、下襬尾端離 Hips 最遠距離
func _measure() -> void:
	var sk = npc.get_node("Skirt"); var skel: Skeleton3D = sk.skel
	var hips: Vector3 = skel.get_bone_global_pose(sk._bone("mixamorig:Hips")).origin
	for ch in sk._chains:
		for b in ch.bones:
			var q := skel.get_bone_pose_rotation(b)
			if not q.is_finite(): worst.nan += 1; continue
			worst.rot_max = maxf(worst.get("rot_max", 0.0), rad_to_deg(skel.get_bone_rest(b).basis.get_rotation_quaternion().angle_to(q)))
			worst.far_max = maxf(worst.far_max, skel.get_bone_global_pose(b).origin.distance_to(hips))

func _report() -> void:
	phys_ms.sort()
	var res := {"clip": clip, "anim": (npc.player as AnimationPlayer).current_animation, "nan": worst.nan,
		"skirt_bone_rot_from_rest_max_deg": snappedf(worst.get("rot_max", 0.0), 0.1), "skirt_joint_far_from_hips_max_m": snappedf(worst.far_max, 0.01),
		"frame_script_ms_p50_p95": [snappedf(phys_ms[phys_ms.size() / 2], 0.01), snappedf(phys_ms[int(phys_ms.size() * 0.95)], 0.01)]}
	print("VERIFY " + JSON.stringify(res))
	FileAccess.open(out + "/verify.json", FileAccess.WRITE).store_string(JSON.stringify(res, " "))
	quit(0)
