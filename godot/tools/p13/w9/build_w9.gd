extends SceneTree
## P13 W9：計画（plan）→ 烘焙（bake）→ 保存 → 掛載（attach）。生成器が source of truth（手で場景を触らない）。
##   godot --headless --path godot --script res://tools/p13/w9/build_w9.gd -- --zones=R[,M,F] [--meadow-cache=<json>] [--plan-only] [--dump=<json>] [--attach]
##   MultiMesh なし → headless build 可（MultiMesh Build Rule の対象外）。
const W9 := preload("res://tools/p13/w9/w9_lib.gd")
const HU := preload("res://tools/village_v2_human_use_lib.gd")
const MD := preload("res://tools/village_v2_meadow_lib.gd")

var fails := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--attach" in args:
		quit(_attach())
		return
	var zones: Array = ["R"]
	var cache := ""
	var dump := ""
	for s: String in args:
		if s.begins_with("--zones="):
			zones = Array(s.trim_prefix("--zones=").split(","))
		elif s.begins_with("--meadow-cache="):
			cache = s.trim_prefix("--meadow-cache=")
		elif s.begins_with("--dump="):
			dump = s.trim_prefix("--dump=")
	var v: Node3D = (load(W9.SCENE) as PackedScene).instantiate()
	var own := v.get_node_or_null(W9.NODE_NAME)
	if own:
		v.remove_child(own)
		own.free()
	root.add_child(v)
	await physics_frame
	var mp := _meadow(v, cache)
	var t0 := Time.get_ticks_msec()
	var P := W9.plan(v, mp, zones)
	print("[W9B] plan %d ms：構件 %d・cluster %d・置けなかった %d" % [Time.get_ticks_msec() - t0, (P["items"] as Array).size(), (P["clusters"] as Array).size(), (P["C"]["dropped"] as Array).size()])
	var by := {}
	var by_id := {}
	for it: Dictionary in P["items"]:
		by[String(it["zone"])] = int(by.get(String(it["zone"]), 0)) + 1
		by_id[String(it["id"])] = int(by_id.get(String(it["id"]), 0)) + 1
	print("[W9B] 区域別：", JSON.stringify(by))
	var ids := by_id.keys()
	ids.sort()
	var line := ""
	for k: String in ids:
		line += " %s×%d" % [k, by_id[k]]
	print("[W9B] 種別：", line)
	for cl: Dictionary in P["clusters"]:
		print("[W9B]   %-22s %2d  %s" % [cl["id"], cl["n"], cl["desc"]])
	for d: String in P["C"]["dropped"]:
		print("[W9B] 落ち：", d)
	if dump != "":
		var out: Array = []
		for it: Dictionary in P["items"]:
			out.append({"id": it["id"], "zone": it["zone"], "cluster": it["cluster"], "p": [snappedf((it["p"] as Vector2).x, 0.001), snappedf((it["p"] as Vector2).y, 0.001)], "y": snappedf(float(it["y"]), 0.001),
				"yaw": snappedf(float(it["yaw"]), 0.0001), "sx": float(it.get("sx", 1.0)), "kind": it.get("kind", ""), "feature": it.get("feature", ""), "b": it.get("b", ""), "who": it["who"]})
		var f := FileAccess.open(dump, FileAccess.WRITE)
		f.store_string(JSON.stringify({"items": out, "dropped": P["C"]["dropped"], "clusters": (P["clusters"] as Array).map(func(c: Dictionary) -> Dictionary: return {"id": c["id"], "zone": c["zone"], "n": c["n"], "desc": c["desc"]})}, " ", false))
		f.close()
		print("[W9B] dump → ", dump)
	if "--plan-only" in args:
		quit(0)
		return
	var rn := W9.bake(P)
	HU.own(rn, rn)
	var ps := PackedScene.new()
	if ps.pack(rn) != OK:
		printerr("[W9B] FAIL pack")
		quit(1)
		return
	if ResourceSaver.save(ps, W9.OUTPUT, ResourceSaver.FLAG_COMPRESS) != OK:
		printerr("[W9B] FAIL save")
		quit(1)
		return
	rn.free()
	var r := ResourceLoader.load(W9.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var rb := r.instantiate() as Node3D
	var mi := rb.find_children("*", "MeshInstance3D", true, false).size()
	var mm := rb.find_children("*", "MultiMeshInstance3D", true, false).size()
	print("[W9B] 存檔回讀：構件 %d（計画 %d）・MeshInstance %d・碰撞 %d・MultiMesh %d → %s" % [int(rb.get_meta("items")), (P["items"] as Array).size(), mi, int(rb.get_meta("shapes")), mm, W9.OUTPUT])
	rb.free()
	quit(0)


## MeadowP9 規劃株：R4b と同じ手順（R5-3 封存時の Props で同 seed 再計算）。cache があれば読む・無ければ計算して書く
func _meadow(v: Node3D, cache: String) -> PackedVector2Array:
	var t0 := Time.get_ticks_msec()
	if cache != "" and FileAccess.file_exists(cache):
		var raw: Array = JSON.parse_string(FileAccess.get_file_as_string(cache))
		var pc := PackedVector2Array()
		for i in range(0, raw.size(), 2):
			pc.append(Vector2(raw[i], raw[i + 1]))
		print("[W9B] MeadowP9 規劃株：キャッシュ %s（%d 株）" % [cache, pc.size()])
		return pc
	if cache == "":
		print("[W9B] MeadowP9 規劃株：未指定（meadow 検査なし）")
		return PackedVector2Array()
	var held: Array = []
	for nm in ["GroundcoverP9", "MeadowP9"]:
		var o := v.get_node_or_null("Vegetation/" + nm)
		if o:
			held.append([o, o.get_parent(), o.get_index()])
			o.get_parent().remove_child(o)
	var hid: Array = []
	for nm in ["Props/EnvironmentP9", "HumanUseP10", "HumanUseExpansionP10", W9.NODE_NAME]:
		var o := v.get_node_or_null(nm) as Node3D
		if o and o.visible:
			o.visible = false
			hid.append(o)
	var Pm: Dictionary = MD.base_plan(v)
	var MC := MD.context(Pm, v)
	var Fm := MD.fields(Pm, MC)
	var Mm := MD.plan(Pm, MC, Fm)
	for o: Node3D in hid:
		o.visible = true
	for h: Array in held:
		(h[1] as Node).add_child(h[0])
		(h[1] as Node).move_child(h[0], int(h[2]))
	var pts: PackedVector2Array = Mm["p"]
	print("[W9B] MeadowP9 規劃株を同 seed で再計算 %d ms：%d 株" % [Time.get_ticks_msec() - t0, pts.size()])
	var raw2: Array = []
	for q in pts:
		raw2.append(snappedf(q.x, 0.001))
		raw2.append(snappedf(q.y, 0.001))
	var f := FileAccess.open(cache, FileAccess.WRITE)
	f.store_string(JSON.stringify(raw2))
	f.close()
	return pts


## village_v2.tscn に root 直下（LodCalBatch1P13 の次）として掛ける（文字列編集・重複なし）
func _attach() -> int:
	var txt := FileAccess.get_file_as_string(W9.SCENE)
	if not FileAccess.file_exists(W9.OUTPUT):
		printerr("[W9B] 找不到 %s（先に build）" % W9.OUTPUT)
		return 1
	var line := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"p13w9_enrich\")]" % W9.NODE_NAME
	if txt.contains(line):
		print("[W9B] attach：已掛 root/%s（不重複、不寫場景）" % W9.NODE_NAME)
		return 0
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var after := ""
	for l: String in txt.split(nl):
		if l.begins_with("[node name=\"%s\" parent=\".\"" % W9.AFTER):
			after = l
	if after == "":
		printerr("[W9B] 找不到 root/%s" % W9.AFTER)
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
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p13w9_enrich\"]" % W9.OUTPUT)
	var f := FileAccess.open(W9.SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[W9B] attach：加 root/%s（%s の次）→ %s（+%d 行）" % [W9.NODE_NAME, W9.AFTER, W9.SCENE, out.size() - lines.size()])
	return 0
