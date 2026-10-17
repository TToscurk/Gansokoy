extends SceneTree
## 街區管線 step 4a：manifest（source of truth）→ overlay を bake して保存＋隔離テスト場景を書く。
##   godot --headless --path godot --script res://tools/district/district_build.gd -- --district=B8 [--manifest=<path>]
## 出力：res://maps/village_v2/gen/district_<id>.scn（MultiMesh なし → headless build 可）
##       res://tests/district/district_<id>_test.tscn（village_v2.tscn をインスタンスして overlay を子に足すだけ）
## village_v2.tscn には書かない（掛載は共有編輯器の所有を確認し、使用者の同意を得てから別途）。
## ground=snap の item は W9.ground_y（見えている最上面の最小値）で y を決め直す；Blender の y との差は INFO と verify で報告。
const DL := preload("res://tools/district/district_lib.gd")
const W9 := preload("res://tools/p13/w9/w9_lib.gd")
const P3 := preload("res://tools/p13/w9/w9p3_lib.gd")


func _init() -> void:
	_run.call_deferred()


func _arg(args: PackedStringArray, k: String, dflt: String) -> String:
	for s in args:
		if s.begins_with(k + "="):
			return s.trim_prefix(k + "=")
	return dflt


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var d := _arg(args, "--district", "")
	if not DL.DISTRICTS.has(d):
		printerr("[DBLD] --district=%s は DISTRICTS に無い" % d)
		quit(1)
		return
	var mpath := _arg(args, "--manifest", DL.manifest_path(d))
	var M := DL.load_manifest(mpath)
	if M.is_empty():
		printerr("[DBLD] manifest が読めない：%s（Blender の export_manifest が先）" % mpath)
		quit(1)
		return
	var errs := DL.schema_errors(M, DL.asset_ids())
	if String(M.get("district", "")) != d:
		errs.append("manifest の district=%s ≠ --district=%s" % [M.get("district", ""), d])
	if not errs.is_empty():
		for e in errs.slice(0, 30):
			printerr("[DBLD] schema: ", e)
		printerr("[DBLD] FAIL schema %d 件 → build しない" % errs.size())
		quit(1)
		return
	var sha := DL.file_sha256(mpath)
	# 同じ manifest・同じ bake 規則で作られた overlay があれば書き直さない（--force で強制）
	if not ("--force" in args) and ResourceLoader.exists(DL.overlay_path(d)):
		var old := (ResourceLoader.load(DL.overlay_path(d), "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		var same := String(old.get_meta("manifest_sha256", "")) == sha and String(old.get_meta("bake_version", "")) == DL.BAKE_VERSION
		old.free()
		if same:
			print("[DBLD] 変更なし：%s は manifest（sha256 %s…）と bake 規則 %s から作られている → 書き直さない（--force で強制）" % [DL.overlay_path(d), sha.substr(0, 12), DL.BAKE_VERSION])
			_write_test_scene(d)
			quit(0)
			return
	var v: Node3D = (load(DL.SCENE) as PackedScene).instantiate()
	var own := v.get_node_or_null(DL.node_name(d))
	if own:
		v.remove_child(own)
		own.free()
	root.add_child(v)
	for i in 3:
		await physics_frame
	var n_supp := DL.prepare_scene(v, d)
	if n_supp > 0:
		print("[DBLD] 街區表 suppress：既存 %d 組を記憶内で取り除いて判定（場景ファイルは書かない）" % n_supp)
	P3.register_dims()
	var C := W9.context(v, PackedVector2Array())
	var n_surf := DL.attach_surface(C, v, d)
	if n_surf > 0:
		print("[%s] 街區表 surface：%d 三角形を W9.top_h に併入（掛載済みの境內地面）" % ["DBLD", n_surf])
	var items: Array = []
	var dy_max := 0.0
	var dy_vid := ""
	for e: Dictionary in M["items"]:
		var it := DL.item_from_entry(e, d)
		if String(it["ground"]) == "snap" and not bool(it.get("hang", false)):
			var gy := DL.ground_y(C, it)
			var dy := absf(gy - float(it["y"]))
			if dy > dy_max:
				dy_max = dy
				dy_vid = String(it["vid"])
			it["y"] = gy
		items.append(it)
	print("[DBLD] manifest %s（sha256 %s…）%d 件・接地し直し：Blender の y との差 最大 %.3f m（%s）" % [mpath, sha.substr(0, 12), items.size(), dy_max, dy_vid])
	var rn := DL.bake(d, items, sha)
	for n in rn.find_children("*", "", true, false):
		n.owner = rn
	var ps := PackedScene.new()
	if ps.pack(rn) != OK or ResourceSaver.save(ps, DL.overlay_path(d), ResourceSaver.FLAG_COMPRESS) != OK:
		printerr("[DBLD] FAIL 保存 %s" % DL.overlay_path(d))
		quit(1)
		return
	rn.free()
	var rb := (ResourceLoader.load(DL.overlay_path(d), "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as Node3D
	var nodes := DL.overlay_nodes(rb)
	var mi := rb.find_children("*", "MeshInstance3D", true, false).size()
	var mm := rb.find_children("*", "MultiMeshInstance3D", true, false).size()
	print("[DBLD] 存檔回読：item %d（manifest %d）・MeshInstance %d・碰撞 %d・MultiMesh %d → %s" % [nodes.size(), items.size(), mi, int(rb.get_meta("shapes")), mm, DL.overlay_path(d)])
	rb.free()
	_write_test_scene(d)
	quit(0 if nodes.size() == items.size() and mm == 0 else 1)


## 隔離テスト場景（village_v2.tscn は instance で読むだけ）。F6 で開けば overlay 付きの村を見られる。
func _write_test_scene(d: String) -> void:
	var path := DL.test_scene_path(d)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var txt := "\n".join(PackedStringArray([
		"[gd_scene load_steps=3 format=3]",
		"",
		"[ext_resource type=\"PackedScene\" path=\"%s\" id=\"1_village\"]" % DL.SCENE,
		"[ext_resource type=\"PackedScene\" path=\"%s\" id=\"2_district\"]" % DL.overlay_path(d),
		"",
		"[node name=\"DistrictTest%s\" type=\"Node3D\"]" % d,
		"",
		"[node name=\"Village\" parent=\".\" instance=ExtResource(\"1_village\")]",
		"",
		"[node name=\"%s\" parent=\"Village\" instance=ExtResource(\"2_district\")]" % DL.node_name(d),
		""]))
	if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == txt:
		print("[DBLD] テスト場景 %s（変更なし）" % path)
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(txt)
	f.close()
	print("[DBLD] テスト場景 → %s" % path)
