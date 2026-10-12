extends SceneTree
## P13 W3：CanalSampleP13 を village_v2.tscn の root 末尾へ掛け（--attach）、読み込み後に適用されたかを確認（--check）。
##   godot --headless --path . --script res://tools/p13/attach_canal_sample.gd -- --attach
##   godot --headless --path . --script res://tools/p13/attach_canal_sample.gd -- --check
const SCENE := "res://maps/village_v2/village_v2.tscn"
const SCRIPT := "res://maps/village_v2/scripts_p13/canal_sample.gd"
const EXT_ID := "p13w3_canal_sample"
const NAME := "CanalSampleP13"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	if "--attach" in OS.get_cmdline_user_args():
		var f := FileAccess.open(SCENE, FileAccess.READ)
		var t := f.get_as_text()
		f.close()
		if not t.contains("id=\"%s\"" % EXT_ID):
			var nl := "\r\n" if t.contains("\r\n") else "\n"
			var last := t.rfind("[ext_resource ")
			var eol := t.find(nl, last)
			t = t.substr(0, eol + nl.length()) + "[ext_resource type=\"Script\" path=\"%s\" id=\"%s\"]" % [SCRIPT, EXT_ID] + nl + t.substr(eol + nl.length())
			t = t.rstrip("\r\n") + nl + nl + "[node name=\"%s\" type=\"Node3D\" parent=\".\"]" % NAME + nl + "script = ExtResource(\"%s\")" % EXT_ID + nl
			var w := FileAccess.open(SCENE, FileAccess.WRITE)
			w.store_string(t)
			w.close()
	var v: Node3D = (ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await process_frame
	var n := v.get_node_or_null(NAME)
	var cnt := v.get_children().filter(func(c: Node) -> bool: return c.name == NAME).size()
	var ok := n != null and cnt == 1 and int(n.get_meta("applied_earth_verts", 0)) > 0 and int(n.get_meta("applied_water_tris", 0)) > 0
	print("[CANAL] 掛載 %s（同名 %d、root 末尾＝%s）適用：土渠頂点 %s・樣本水面三角形 %s" % ["OK" if ok else "FAIL", cnt,
		v.get_child(v.get_child_count() - 1).name, n.get_meta("applied_earth_verts", 0) if n else "-", n.get_meta("applied_water_tris", 0) if n else "-"])
	# OFF で元へ戻る
	if n:
		n.set("enabled", false)
		var em := preload("res://tools/village_v2_canal_sample_lib.gd")._find(v, "earth")
		var cs: PackedColorArray = em.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var distinct := {}
		for c in cs:
			distinct[str(c)] = true
		print("[CANAL] OFF 後の土渠重み種類 %d（元＝1）、樣本水面ノード %s" % [distinct.size(), em.get_parent().get_node_or_null("P13W3_WaterSample") != null])
		ok = ok and distinct.size() == 1 and em.get_parent().get_node_or_null("P13W3_WaterSample") == null
	quit(0 if ok else 1)
