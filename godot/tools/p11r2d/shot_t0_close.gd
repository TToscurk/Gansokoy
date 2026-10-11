extends SceneTree
## P11 R2D-Fix 審圖（非 headless、只讀）：送り樋の分水口と T0 の土渠／木槽の接合・折れ点を近距離で撮る。
##   godot --path . --script res://tools/p11r2d/shot_t0_close.gd -- <outdir/> [prefix]
const VIEWS := [
	# 送り樋の南壁の開口：南西から斜め上、開口と新木槽の槽底が見える角度
	["tap_outlet", Vector3(337.2, 1.25, 6.3), Vector3(338.1, 0.5, 5.05)],
	["tap_outlet_top", Vector3(338.6, 1.9, 6.6), Vector3(338.1, 0.5, 4.95)],
	["tap_outlet_inside", Vector3(337.05, 1.15, 4.0), Vector3(338.15, 0.5, 5.6)],
	["tap_outlet_side", Vector3(339.4, 1.0, 6.1), Vector3(338.1, 0.52, 5.1)],
	# 土渠／木槽の切替（run0 s8.4、run2 s5.0／11.9／17.9／25.9）
	["j_run0_12", Vector3(336.2, 1.3, 10.4), Vector3(338.0, 0.4, 12.4)],
	["j_run2_49", Vector3(333.4, 1.3, 48.0), Vector3(331.6, 0.4, 49.8)],
	["j_run2_55", Vector3(325.4, 1.3, 53.2), Vector3(327.0, 0.4, 54.9)],
	["j_run2_60", Vector3(325.2, 1.3, 61.6), Vector3(327.0, 0.4, 60.0)],
	["j_run2_67", Vector3(330.9, 1.3, 65.6), Vector3(329.0, 0.4, 67.2)],
	# 45° 折れ点（土渠）
	["c_75", Vector3(333.0, 1.4, 73.6), Vector3(331.0, 0.35, 75.5)],
	["c_25", Vector3(333.2, 1.4, 23.6), Vector3(335.4, 0.4, 25.0)],
]

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var outdir: String = a[0]
	var prefix: String = a[1] if a.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(outdir)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		if v.has_node(nm):
			v.get_node(nm).visible = false
	await process_frame
	for c in root.get_children():
		if c.has_method("set_hour"):
			c.set_hour(10.0)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.03
	root.add_child(cam)
	cam.make_current()
	for i in 30:
		await process_frame
	for vw in VIEWS:
		cam.global_transform = Transform3D(Basis(), vw[1]).looking_at(vw[2], Vector3.UP)
		for i in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(outdir + prefix + String(vw[0]) + ".png")
	print("[T0SHOT] done")
	quit(0)
