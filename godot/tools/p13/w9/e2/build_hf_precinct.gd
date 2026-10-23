extends SceneTree
## 丘腳林地（TASK E FINAL，使用者 2026-10-18：丘腳社寺取消→自然林）：抑制 overlay（節點名沿用 HillfootPrecinctE2）の烘焙。
##   godot --headless --path godot --script res://tools/p13/w9/e2/build_hf_precinct.gd
## 出力：res://maps/village_v2/gen/hillfoot_precinct_e2.scn（hillfoot_precinct_e2.gd ＋抑制リストのメタのみ）。
## E2 の境內地面（Ground・sg_ground）と草株抑制は廃止：設計 HF_design.json に "ground" が無ければ Ground を作らない・mm_polys は空。
## 残すのは EnvironmentP9 E082 四目垣斷片の可逆抑制だけ（林の中に旧社寺の垣を戻さない）。樹木は DistrictHF（街區管線）。
## MultiMesh を含まない → headless build 可。village_v2.tscn には書かない。
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
	var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(L.DESIGN))
	var rn := Node3D.new()
	rn.name = L.NODE_NAME
	rn.set_script(load(L.SCRIPT))
	var n_tris := 0
	if j.has("ground"):
		var G := L.ground_mesh(RLib.terrain_sampler(v))
		var gi := MeshInstance3D.new()
		gi.name = "Ground"
		gi.mesh = G["mesh"]
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rn.add_child(gi)
		n_tris = int(G["tris"])
	var polys: Array = []
	for poly: Array in j["suppress"].get("mm_polys", []):
		var pv := PackedVector2Array()
		for q: Array in poly:
			pv.append(Vector2(float(q[0]), float(q[1])))
		polys.append(pv)
	rn.set_meta("suppress_groups", PackedStringArray(j["suppress"]["groups"]))
	rn.set_meta("mm_polys", polys)
	rn.set_meta("mm_margin", float(j["suppress"].get("mm_margin", 0.4)))
	rn.set_meta("mm_roots", PackedStringArray(j["suppress"].get("mm_roots", [])))
	rn.set_meta("design_sha256", FileAccess.get_sha256(L.DESIGN))
	rn.set_meta("art_revision", L.ART_REVISION)
	rn.set_meta("ground_tris", n_tris)
	print("[HFB] design %s：Ground %s・suppress_groups %s・mm_polys %d" % [j.get("format", "?"), j.has("ground"), str(j["suppress"]["groups"]), polys.size()])
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
	var ok: bool = mi.size() == (1 if j.has("ground") else 0) and mm.size() == 0 and rb.get_script() != null
	rb.free()
	quit(0 if ok else 1)
