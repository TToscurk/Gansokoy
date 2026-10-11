extends SceneTree
## P13 W1 Architecture Pilot 生成／掛載。
##   build：godot --headless --path . --script res://tools/p13/build_arch_pilot.gd -- --build   → gen/arch_pilot_p13.scn（MeshInstance のみ、MultiMesh なし）
##   attach：... -- --attach   → village_v2.tscn の root 末尾に ArchPilotP13（1 個）
const AL := preload("res://tools/village_v2_arch_pilot_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const EXT_ID := "p13w1_arch_pilot"

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	if "--attach" in a:
		quit(_attach())
		return
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	var r := AL.bake(v)
	var ps := PackedScene.new()
	var ok := ps.pack(r) == OK and ResourceSaver.save(ps, AL.OUTPUT, ResourceSaver.FLAG_COMPRESS) == OK
	print("[ARCH] save %s %s：%d 棟、LOD0 %d 三角面" % [AL.OUTPUT, "OK" if ok else "FAIL", int(r.get_meta("buildings")), int(r.get_meta("lod0_tris"))])
	r.free()
	# 回讀
	var back := (ResourceLoader.load(AL.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var mi := back.find_children("*", "MeshInstance3D", true, false).size()
	var tg: PackedStringArray = back.get("targets")
	var miss := 0
	for p in tg:
		miss += 0 if v.get_node_or_null(NodePath(p)) != null else 1
	print("[ARCH] 回讀：棟 %d、MeshInstance %d、targets %d（場景に無い %d）" % [back.get_child_count(), mi, tg.size(), miss])
	back.free()
	v.free()
	quit(0 if ok and miss == 0 else 1)

func _attach() -> int:
	var f := FileAccess.open(SCENE, FileAccess.READ)
	var t := f.get_as_text()
	f.close()
	if t.contains("id=\"%s\"" % EXT_ID):
		print("[ARCH] 既に掛載済み")
		return 0
	var nl := "\r\n" if t.contains("\r\n") else "\n"
	var ext := "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%s\"]" % [AL.OUTPUT, EXT_ID]
	var last := t.rfind("[ext_resource ")
	var eol := t.find(nl, last)
	t = t.substr(0, eol + nl.length()) + ext + nl + t.substr(eol + nl.length())
	t = t.rstrip("\r\n") + nl + nl + "[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]" % [AL.NODE_NAME, EXT_ID] + nl
	var w := FileAccess.open(SCENE, FileAccess.WRITE)
	w.store_string(t)
	w.close()
	var v: Node3D = (ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var n := v.get_node_or_null(AL.NODE_NAME)
	print("[ARCH] attach：%s（root 子の最後＝%s）" % ["OK" if n != null else "FAIL", v.get_child(v.get_child_count() - 1).name])
	v.free()
	return 0 if n != null else 1
