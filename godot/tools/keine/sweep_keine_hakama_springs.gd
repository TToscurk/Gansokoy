extends SceneTree
## 慧音袴彈簧參數掃描（headless 可，只讀骨姿）：idle 靜態下垂、走路末端位移，彈簧開 vs 關。
## godot --headless --path . --fixed-fps 60 --script res://tools/keine/sweep_keine_hakama_springs.gd
var vis: Node3D
var sk: Skeleton3D
var spr: Node
var sim: SpringBoneSimulator3D
var frame := 0
var want := {}
var got := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	vis = (load("res://characters/keine/keine.tscn") as PackedScene).instantiate()
	vis.set("start_time", 0.0)
	root.add_child(vis)
	for i in 3: await process_frame
	sk = vis.find_child("GeneralSkeleton", true, false) as Skeleton3D
	spr = vis.get_node("HakamaSprings")
	sim = sk.get_node("Spring_Hakama")
	sk.skeleton_updated.connect(func():
		frame += 1
		if want.has(frame):
			var a: Array = []
			for b in sk.get_bone_count(): a.append(sk.get_bone_global_pose(b))
			got[frame] = a)
	var idle_off := await _case(&"idle", false, [120, 240])
	var walk_off := await _case(&"walk", false, range(120, 240, 4))
	var combos := [[2.0, 0.6, true], [2.0, 0.0, true], [2.0, 0.6, false], [4.0, 0.3, true], [6.0, 0.3, true], [4.0, 0.15, true], [8.0, 0.2, true]]
	for cb in combos:
		for i in sim.setting_count:
			sim.set_stiffness(i, cb[0]); sim.set_gravity(i, cb[1])
			sim.set_collision_count(i, 5 if cb[2] else 0)
			if cb[2]:
				var k := 0
				for n in sim.get_children():
					sim.set_collision_path(i, k, NodePath(n.name)); k += 1
		var io := await _case(&"idle", true, [120, 240])
		var wo := await _case(&"walk", true, range(120, 240, 4))
		var s := "stiff %.1f grav %.2f col %s | idle@2s %s idle@4s %s | walk max %.3f mean %.3f" % [cb[0], cb[1], str(cb[2]), _dev(io[120], idle_off[120]), _dev(io[240], idle_off[240]), _wmax(wo, walk_off), _wmean(wo, walk_off)]
		print("SWEEP ", s)
	quit()


func _tip(p: Array, c: Dictionary) -> Vector3:
	return (p[sk.find_bone(c.bones[2])] as Transform3D) * Vector3(0, float(c.lengths[2]), 0)


func _dev(a: Array, b: Array) -> String:
	var o := []
	for c in spr.get("_data").chains:
		o.append("%s %.0f" % [c.dir, _tip(a, c).distance_to(_tip(b, c)) * 100.0])
	return "[" + ", ".join(o) + "] cm"


func _wmax(a: Dictionary, b: Dictionary) -> float:
	var m := 0.0
	for f in a:
		for c in spr.get("_data").chains:
			m = maxf(m, _tip(a[f], c).distance_to(_tip(b[f], c)))
	return m


func _wmean(a: Dictionary, b: Dictionary) -> float:
	var s := 0.0; var n := 0
	for f in a:
		for c in spr.get("_data").chains:
			s += _tip(a[f], c).distance_to(_tip(b[f], c)); n += 1
	return s / n


func _case(clip: StringName, on: bool, frames: Array) -> Dictionary:
	spr.set("springs_enabled", on)
	vis.call("play_clip", clip, 0.0)
	sim.reset()
	frame = 0
	want.clear(); got.clear()
	for f in frames: want[f] = true
	var last: int = frames.max()
	while frame < last:
		await process_frame
	return got.duplicate()
