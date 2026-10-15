extends SceneTree
## P13 W9 Phase 4：計画（plan）→ 烘焙（bake）→ 保存 → 掛載（attach）。生成器が source of truth（手で場景を触らない）。
##   godot --headless --path godot --script res://tools/p13/w9/build_w9p4.gd -- --meadow-cache=<json> [--zones=B4,C4] [--plan-only] [--dump=<json>]
##   godot --headless --path godot --script res://tools/p13/w9/build_w9p4.gd -- --attach
##   MultiMesh なし → headless build 可（MultiMesh Build Rule の対象外）。
const P4 := preload("res://tools/p13/w9/w9p4_lib.gd")
const W9 := preload("res://tools/p13/w9/w9_lib.gd")
const HU := preload("res://tools/village_v2_human_use_lib.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--attach" in args:
		quit(_attach())
		return
	var zones: Array = ["B4", "C4"]
	var cache := ""
	var dump := ""
	for s: String in args:
		if s.begins_with("--zones="):
			zones = Array(s.trim_prefix("--zones=").split(","))
		elif s.begins_with("--meadow-cache="):
			cache = s.trim_prefix("--meadow-cache=")
		elif s.begins_with("--dump="):
			dump = s.trim_prefix("--dump=")
	var v: Node3D = (load(P4.SCENE) as PackedScene).instantiate()
	var own := v.get_node_or_null(P4.NODE_NAME)
	if own:
		v.remove_child(own)
		own.free()
	root.add_child(v)
	await physics_frame
	var mp := PackedVector2Array()
	if cache != "" and FileAccess.file_exists(cache):
		var raw: Array = JSON.parse_string(FileAccess.get_file_as_string(cache))
		for i in range(0, raw.size(), 2):
			mp.append(Vector2(raw[i], raw[i + 1]))
		print("[W9P4B] MeadowP9 規劃株：キャッシュ %s（%d 株）" % [cache, mp.size()])
	else:
		print("[W9P4B] MeadowP9 規劃株：未指定（meadow 検査なし）")
	var t0 := Time.get_ticks_msec()
	var P := P4.plan(v, mp, zones)
	print("[W9P4B] plan %d ms：構件 %d・cluster %d・置けなかった %d（占有 %d 件）" % [Time.get_ticks_msec() - t0, (P["items"] as Array).size(), (P["clusters"] as Array).size(), (P["C"]["dropped"] as Array).size(), int(P["C"]["n_r1"])])
	var by := {}
	var by_id := {}
	for it: Dictionary in P["items"]:
		by[String(it["zone"])] = int(by.get(String(it["zone"]), 0)) + 1
		by_id[String(it["id"])] = int(by_id.get(String(it["id"]), 0)) + 1
	print("[W9P4B] 区域別：", JSON.stringify(by))
	var ids := by_id.keys()
	ids.sort()
	var line := ""
	for k: String in ids:
		line += " %s×%d" % [k, by_id[k]]
	print("[W9P4B] 種別：", line)
	for cl: Dictionary in P["clusters"]:
		print("[W9P4B]   %-26s %2d  %s" % [cl["id"], cl["n"], cl["desc"]])
	for d: String in P["C"]["dropped"]:
		print("[W9P4B] 落ち：", d)
	if dump != "":
		var out: Array = []
		for it: Dictionary in P["items"]:
			out.append({"id": it["id"], "zone": it["zone"], "cluster": it["cluster"], "p": [snappedf((it["p"] as Vector2).x, 0.001), snappedf((it["p"] as Vector2).y, 0.001)], "y": snappedf(float(it["y"]), 0.001),
				"yaw": snappedf(float(it["yaw"]), 0.0001), "sx": snappedf(float(it.get("sx", 1.0)), 0.001), "sy": snappedf(float(it.get("sy", 1.0)), 0.001), "kind": it.get("kind", ""), "who": it["who"]})
		var f := FileAccess.open(dump, FileAccess.WRITE)
		f.store_string(JSON.stringify({"items": out, "dropped": P["C"]["dropped"], "clusters": (P["clusters"] as Array).map(func(c: Dictionary) -> Dictionary: return {"id": c["id"], "zone": c["zone"], "n": c["n"], "desc": c["desc"]})}, " ", false))
		f.close()
		print("[W9P4B] dump → ", dump)
	if "--plan-only" in args:
		quit(0)
		return
	var rn := P4.bake(P)
	HU.own(rn, rn)
	var ps := PackedScene.new()
	if ps.pack(rn) != OK:
		printerr("[W9P4B] FAIL pack")
		quit(1)
		return
	if ResourceSaver.save(ps, P4.OUTPUT, ResourceSaver.FLAG_COMPRESS) != OK:
		printerr("[W9P4B] FAIL save")
		quit(1)
		return
	rn.free()
	var r := ResourceLoader.load(P4.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var rb := r.instantiate() as Node3D
	var mi := rb.find_children("*", "MeshInstance3D", true, false).size()
	var mm := rb.find_children("*", "MultiMeshInstance3D", true, false).size()
	print("[W9P4B] 存檔回読：構件 %d（計画 %d）・MeshInstance %d・碰撞 %d・MultiMesh %d → %s" % [int(rb.get_meta("items")), (P["items"] as Array).size(), mi, int(rb.get_meta("shapes")), mm, P4.OUTPUT])
	rb.free()
	quit(0)


## village_v2.tscn に root 直下（EnrichW9P3 の次）として掛ける（文字列編集・重複なし）
func _attach() -> int:
	var txt := FileAccess.get_file_as_string(P4.SCENE)
	if not FileAccess.file_exists(P4.OUTPUT):
		printerr("[W9P4B] 找不到 %s（先に build）" % P4.OUTPUT)
		return 1
	var line := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"p13w9p4_enrich\")]" % P4.NODE_NAME
	if txt.contains(line):
		print("[W9P4B] attach：已掛 root/%s（不重複、不寫場景）" % P4.NODE_NAME)
		return 0
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var after := ""
	for l: String in txt.split(nl):
		if l.begins_with("[node name=\"%s\" parent=\".\"" % P4.AFTER):
			after = l
	if after == "":
		printerr("[W9P4B] 找不到 root/%s" % P4.AFTER)
		return 1
	var lines := txt.split(nl)
	var out := PackedStringArray(Array(lines))
	var at := out.find(after)
	out.insert(at + 1, "")
	out.insert(at + 2, line)
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p13w9p4_enrich\"]" % P4.OUTPUT)
	var f := FileAccess.open(P4.SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[W9P4B] attach：加 root/%s（%s の次）→ %s（+%d 行）" % [P4.NODE_NAME, P4.AFTER, P4.SCENE, out.size() - lines.size()])
	return 0
