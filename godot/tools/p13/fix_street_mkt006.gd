extends SceneTree
## P13 W2：StreetP10（P10 R2 封存）の MKT_006 だけの limited correction（使用者 2026-10-12 授權）。
## 竹籠製作兼販売の工房：販売＝既存の荒物平台（054_st_hiradai_zakka：笊の重ね・籠）を残し、
##   左の手桶（055_sk_teoke）を「編み作業の筵座」st_wara（筵・材料束・編みかけ・腰掛け）へ差し替え、入口左の 1F 前に置く。
## 他の店・他の節點・anchors は一切変更しない（実行後に MKT_006 以外の全節點の transform／meta 不変を自己検査）。
##   godot --headless --path . --script res://tools/p13/fix_street_mkt006.gd
const OUT := "res://maps/village_v2/gen/street_p10.scn"
const ST := "res://assets/village_v2/street_kit/mesh/"
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const LX := -1.70     # 建物局部 x（入口 0±0.87 の左、開間 0–1 の前）
const FWD := 0.62     # 正面壁から前へ（筵の奥 0.45 → 壁から 0.17–1.07）


func _init() -> void:
	_run.call_deferred()


func _sig(r: Node) -> Dictionary:
	var d := {}
	for n in r.find_children("*", "Node3D", true, false):
		var s := "%s|%s" % [(n as Node3D).transform, str(n.get_meta_list().map(func(k: StringName) -> String: return "%s=%s" % [k, n.get_meta(k)]))]
		d[String(r.get_path_to(n))] = s
	return d


func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	await physics_frame
	var body := v.get_node("Districts/Market/Buildings/B_P_MKT_006") as Node3D
	var R := RLib.road_sampler(v)
	var S := RLib.terrain_sampler(v)
	var d := float(body.get_meta("depth_m"))
	var bx := body.global_transform
	var wp := bx * Vector3(LX, 0.0, d * 0.5 + FWD)
	var hy := S.h(wp.x, wp.z)
	var hr := R.h(wp.x, wp.z)
	var y := maxf(hy if not is_nan(hy) else -INF, hr if not is_nan(hr) else -INF)
	var r := (ResourceLoader.load(OUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var before := _sig(r)
	var old := r.get_node("Shopfront/055_sk_teoke") as Node3D
	assert(String(old.get_meta("building")) == "B_P_MKT_006")
	var col := r.get_node("Collision") as StaticBody3D
	var oc := col.get_node("055_sk_teoke_c") as CollisionShape3D
	var yaw := old.rotation.y
	old.name = "055_st_wara"
	old.position = Vector3(wp.x, y, wp.z)
	old.set_meta("st_id", "st_wara")
	old.set_meta("st_tag", "shop:zakka")
	old.set_meta("p13", "P13 W2 limited correction：竹籠工房の編み作業（元 sk_teoke）")
	(old.get_node("LOD0") as MeshInstance3D).mesh = load(ST + "st_wara.res")
	(old.get_node("LOD1") as MeshInstance3D).mesh = load(ST + "st_wara_l1.res")
	# street_lib BOX["st_wara"] = [0.7, 0.45, 1.4, 0, 0]
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.4, 1.4, 0.9)
	oc.name = "055_st_wara_c"
	oc.shape = sh
	var ba := Basis(Vector3.UP, yaw)
	oc.transform = Transform3D(ba, old.position + ba * Vector3(0.0, 0.7, 0.0))
	var after := _sig(r)
	var changed: Array = []
	for k: String in before:
		if not after.has(k) or after[k] != before[k]:
			changed.append(k)
	for k: String in after:
		if not before.has(k):
			changed.append(k)
	var ok := changed.all(func(k: String) -> bool: return k.contains("055_s"))
	var ps := PackedScene.new()
	var e := ps.pack(r)
	var e2 := ResourceSaver.save(ps, OUT, ResourceSaver.FLAG_COMPRESS) if e == OK and ok else ERR_INVALID_DATA
	print("[FIX006] 位置 (%.2f, %.3f, %.2f) yaw %.1f°、変化した節點 %s（MKT_006 以外 %d）、save %d" % [wp.x, y, wp.z, rad_to_deg(yaw), str(changed), changed.filter(func(k: String) -> bool: return not k.contains("055_s")).size(), e2])
	r.free()
	quit(0 if e2 == OK else 1)
