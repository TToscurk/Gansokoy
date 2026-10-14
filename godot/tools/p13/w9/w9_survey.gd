extends SceneTree
## P13 W9 現場測繪（唯読・headless）：既存の R4 context（HU.context）で「置ける所／置けない理由」を ASCII 地図にし、範囲内の建物 OBB を列挙する。
##   godot --headless --path . --script res://tools/p13/w9/w9_survey.gd -- x,z,w,h[,step] [--blds]
##   凡例：. 空き  R 道路  F 店先帯  B 建物  D 戸口  d 背戸  W 水  w P7  A P8  S 封存  T 幹  H Hero  E Env  P P10  N NPC  / 傾斜  g 草(meadow は無視)
const HU := preload("res://tools/village_v2_human_use_lib.gd")
const SL := preload("res://tools/village_v2_street_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var r: PackedStringArray = args[0].split(",")
	var rect := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var step := float(r[4]) if r.size() > 4 else 1.0
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await process_frame
	var C := HU.context(v, PackedVector2Array())
	print("[SRV] context %d ms・建物 %d" % [int(C["ms"]), (C["bld"] as Array).size()])
	if "--blds" in args:
		for b: Dictionary in C["bld"]:
			var o: Vector2 = b["o"]
			if rect.grow(6.0).has_point(o):
				print("[SRV] %-12s o=(%.1f,%.1f) w=%.2f d=%.2f road=%-12s type=%-8s ax=(%.3f,%.3f) az=(%.3f,%.3f) door_cx=%.2f" % [b["name"], o.x, o.y, b["w"], b["d"], b["road"], b["type"], (b["ax"] as Vector2).x, (b["ax"] as Vector2).y, (b["az"] as Vector2).x, (b["az"] as Vector2).y, b["door_cx"]])
	var rows := HU.survey(C, rect, step)
	print("[SRV] 地図 x=%.0f..%.0f（左→右 step %.1f m）、z 行 %.0f..%.0f" % [rect.position.x, rect.end.x, step, rect.position.y, rect.end.y])
	for l in rows:
		print("[SRV]" + l)
	quit(0)
