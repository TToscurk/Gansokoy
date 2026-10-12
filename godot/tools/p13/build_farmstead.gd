extends SceneTree
## P13 W2 農家 A1／A2 正式版の生成（gen/farmstead_p13.scn）と village_v2.tscn への掛載（root 直下の最後に 1 個）。
##   godot --headless --path . --script res://tools/p13/build_farmstead.gd -- --build
##   godot --headless --path . --script res://tools/p13/build_farmstead.gd -- --attach
const FL := preload("res://tools/village_v2_farmstead_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const EXT_ID := "p13w2_farmstead"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	if "--attach" in a:
		quit(_attach())
		return
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	var old := v.get_node_or_null(FL.NODE_NAME)
	if old:
		v.remove_child(old)
		old.free()
	root.add_child(v)
	for i in 3:
		await physics_frame
	var r := FL.bake(v)
	var ps := PackedScene.new()
	var ok := ps.pack(r) == OK and ResourceSaver.save(ps, FL.OUTPUT, ResourceSaver.FLAG_COMPRESS) == OK
	for f in r.get_children():
		if f.has_meta("dims"):
			print("[FARM] %s @%s 地形 %s %s" % [f.name, (f as Node3D).position, str(f.get_meta("ground")), f.get_meta("dims")])
	print("[FARM] 渡し板 %s" % str(r.get_meta("plank")))
	print("[FARM] save %s %s、MeshInstance %d、碰撞 %d" % [FL.OUTPUT, "OK" if ok else "FAIL", r.find_children("*", "MeshInstance3D", true, false).size(),
		r.get_node("Collision").get_child_count()])
	r.free()
	quit(0 if ok else 1)


func _attach() -> int:
	var f := FileAccess.open(SCENE, FileAccess.READ)
	var t := f.get_as_text()
	f.close()
	if t.contains("id=\"%s\"" % EXT_ID):
		print("[FARM] 既に掛載済み")
		return 0
	var nl := "\r\n" if t.contains("\r\n") else "\n"
	var ext := "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%s\"]" % [FL.OUTPUT, EXT_ID]
	var last := t.rfind("[ext_resource ")
	var eol := t.find(nl, last)
	t = t.substr(0, eol + nl.length()) + ext + nl + t.substr(eol + nl.length())
	t = t.rstrip("\r\n") + nl + nl + "[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]" % [FL.NODE_NAME, EXT_ID] + nl
	var w := FileAccess.open(SCENE, FileAccess.WRITE)
	w.store_string(t)
	w.close()
	var v: Node3D = (ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var n := v.get_node_or_null(FL.NODE_NAME)
	print("[FARM] attach：%s（root 子の最後＝%s、同名 %d）" % ["OK" if n != null else "FAIL", v.get_child(v.get_child_count() - 1).name,
		v.get_children().filter(func(c: Node) -> bool: return c.name == FL.NODE_NAME).size()])
	v.free()
	return 0 if n != null else 1
