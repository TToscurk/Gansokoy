extends SceneTree
## 丘腳社寺 E2：境內環境 overlay（HillfootPrecinctE2）の烘焙。生成器が source of truth（手で場景を触らない）。
##   godot --headless --path godot --script res://tools/p13/w9/e2/build_hf_precinct.gd
## 出力：res://maps/village_v2/gen/hillfoot_precinct_e2.scn（Ground＋抑制リストのメタ＋ hillfoot_precinct_e2.gd）。
## MultiMesh を含まない → headless build 可（MultiMesh Build Rule の対象外）。village_v2.tscn には書かない（掛載は mount_hf_precinct.py）。
const L := preload("res://tools/p13/w9/e2/hf_precinct_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v: Node3D = (load(L.SCENE) as PackedScene).instantiate()
	for nm: String in [L.NODE_NAME, L.DISTRICT_NODE]:
		var own := v.get_node_or_null(nm)
		if own:
			v.remove_child(own)
			own.free()
	root.add_child(v)
	for i in 3:
		await physics_frame
	var t0 := Time.get_ticks_msec()
	var S := RLib.terrain_sampler(v)
	var G := L.ground_mesh(S)
	print("[HFB] ground：頂点 %d・三角形 %d・持ち上げた頂点 %d（最大 %.3f m）・被覆を落とした頂点 %d・%d ms" % [G["verts"], G["tris"], G["raised"], G["max_raise"], G["faded"], Time.get_ticks_msec() - t0])
	var D := L.design()
	var rn := Node3D.new()
	rn.name = L.NODE_NAME
	rn.set_script(load(L.SCRIPT))
	var gi := MeshInstance3D.new()
	gi.name = "Ground"
	gi.mesh = G["mesh"]
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rn.add_child(gi)
	var j: Dictionary = D["raw"]
	rn.set_meta("suppress_groups", PackedStringArray(j["suppress"]["groups"]))
	rn.set_meta("mm_polys", D["mm_polys"])
	rn.set_meta("mm_margin", D["mm_margin"])
	rn.set_meta("mm_roots", PackedStringArray(j["suppress"]["mm_roots"]))
	rn.set_meta("design_sha256", FileAccess.get_sha256(L.DESIGN))
	rn.set_meta("art_revision", L.ART_REVISION)
	rn.set_meta("ground_tris", int(G["tris"]))
	rn.set_meta("ground_lift", float(D["lift"]))
	for n in rn.find_children("*", "", true, false):
		n.owner = rn
	var ps := PackedScene.new()
	if ps.pack(rn) != OK or ResourceSaver.save(ps, L.OUTPUT, ResourceSaver.FLAG_COMPRESS) != OK:
		printerr("[HFB] FAIL 保存 ", L.OUTPUT)
		quit(1)
		return
	rn.free()
	var rb := (ResourceLoader.load(L.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as Node3D
	var mi := rb.find_children("*", "MeshInstance3D", true, false)
	var mm := rb.find_children("*", "MultiMeshInstance3D", true, false)
	print("[HFB] 存檔回読：MeshInstance %d・MultiMesh %d・script %s・suppress_groups %s・mm_polys %d → %s" % [mi.size(), mm.size(),
		rb.get_script() != null, str(rb.get_meta("suppress_groups")), (rb.get_meta("mm_polys") as Array).size(), L.OUTPUT])
	var ok: bool = mi.size() == 1 and mm.size() == 0 and rb.get_script() != null
	rb.free()
	quit(0 if ok else 1)
