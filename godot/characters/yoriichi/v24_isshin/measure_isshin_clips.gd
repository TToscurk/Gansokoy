extends SceneTree
## 實測：每支一心動作在 Godot 的真 AnimationPlayer + Skeleton3D 上播放。
##  1) 與 Blender 評估的骨頭位置逐格比對（blender_probe_<tag>.json，Blender Z-up -> Godot: x, z, -y）
##  2) 站立腳的接觸速度向量（走路速度＝不滑步的速度；方向＝角色相對移動方向，+前／+右）
##  3) 離地（最低腳趾）、循環接縫
## godot --headless --path godot -s res://characters/yoriichi/v24_isshin/measure_isshin_clips.gd
const PROBE_DIR := "D:/research/sekiro_r8_p0/retarget/"
const CLIPS := {
	"isshin_walk": "a000_405000", "isshin_idle": "a000_400000", "isshin_back": "a000_405001",
	"isshin_strafe_l": "a000_405002", "isshin_strafe_r": "a000_405003", "isshin_run": "a000_405010",
}
var ap: AnimationPlayer
var sk: Skeleton3D

func _init() -> void:
	var root: Node = (load("res://characters/yoriichi/v24_r62/yoriichi_v24_r62.glb") as PackedScene).instantiate()
	get_root().add_child(root)
	ap = root.find_child("AnimationPlayer", true, false)
	sk = root.find_child("Skeleton3D", true, false)
	var lib := ap.get_animation_library("")
	for n in CLIPS:
		var path := "res://characters/yoriichi/v24_isshin/anims/%s.res" % n
		if ResourceLoader.exists(path):
			lib.add_animation(n, load(path))
	_run()

func _pos(b: String) -> Vector3:
	return sk.get_bone_global_pose(sk.find_bone("mixamorig_" + b)).origin

func _at(t: float) -> void:
	ap.seek(t, true)
	await process_frame
	await process_frame

func _run() -> void:
	for n in CLIPS:
		if not ap.has_animation(n):
			print("MISSING ", n)
			continue
		await _clip(n, CLIPS[n])
	quit()

func _clip(n: String, tag: String) -> void:
	ap.play(n)
	ap.pause()
	var a := ap.get_animation(n)
	var N := int(round(a.length * 30.0))
	# 1) Blender vs Godot
	var pf := PROBE_DIR + "blender_probe_%s.json" % tag
	var worst := -1.0
	if FileAccess.file_exists(pf):
		var pr: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pf))
		worst = 0.0
		for fk in pr:
			if int(fk) >= N:
				continue
			await _at(int(fk) / 30.0)
			for b in pr[fk]:
				var v: Array = pr[fk][b]
				worst = maxf(worst, _pos(b).distance_to(Vector3(v[0], v[2], -v[1])))
	# 2) stance-foot velocity (skeleton space: +Z forward, -X = character right)
	var P := {"LeftFoot": [], "RightFoot": []}
	var toe_y := []
	for i in N:
		await _at(i / 30.0)
		for b in P:
			P[b].append(_pos(b))
		toe_y.append(minf(_pos("LeftToeBase").y, _pos("RightToeBase").y))
	var vf := []
	var vr := []
	var feet_txt := ""
	for b in P:
		var ymin := 9.0
		for p in P[b]:
			ymin = minf(ymin, p.y)
		var sf := []
		var sr := []
		for i in range(1, N - 1):
			if P[b][i].y < ymin + 0.02:
				var v: Vector3 = (P[b][i + 1] - P[b][i - 1]) / (2.0 / 30.0)
				sf.append(-v.z)       # body moves forward when a planted foot slides backward
				sr.append(v.x)        # body moves to its right (-X) when a planted foot slides toward +X
		var cnt := sf.size()
		if cnt > 0:
			sf.sort()
			sr.sort()
			vf.append(sf[cnt / 2])      # 中位數：排除落地／離地瞬間
			vr.append(sr[cnt / 2])
		# 站立相位：站立幀的圓周平均（佔整個循環的比例），用來對齊不同動作的左右腳節奏
		var cx := 0.0
		var cy := 0.0
		for i in N:
			if P[b][i].y < ymin + 0.02:
				cx += cos(TAU * i / N)
				cy += sin(TAU * i / N)
		var ph := fposmod(atan2(cy, cx) / TAU, 1.0)
		feet_txt += " %s stance=%d phase=%.3f" % [b, cnt, ph]
	var mvf: float = (vf[0] + vf[1]) / 2.0 if vf.size() == 2 else NAN
	var mvr: float = (vr[0] + vr[1]) / 2.0 if vr.size() == 2 else NAN
	await _at(0.0)
	var p0 := _pos("RightHand")
	await _at(a.length - 0.0001)
	var seam := p0.distance_to(_pos("RightHand"))
	print("CLIP %-16s len=%.3fs frames=%d | blender_err=%s m | body_vel fwd=%.3f right=%.3f speed=%.3f m/s |%s | lowest_toe_y=%.3f | seam=%.4f m" % [
		n, a.length, N, ("%.5f" % worst) if worst >= 0 else "n/a", mvf, mvr, Vector2(mvf, mvr).length(), feet_txt, toe_y.min(), seam])
