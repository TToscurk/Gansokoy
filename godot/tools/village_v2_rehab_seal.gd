extends RefCounted
## P10 R5–R6 Environmental Rehabilitation：ART_APPROVED 工作包の封存共通処理（使用者 2026-10-09 ROUND 3 FINAL ART DIRECTION）。
## 各工作包の既存 gate（verify_village_v2_edge_closure／road_base／albedo_pilot／prop_fix）が `--seal` でこれを呼ぶ。
##   - seal manifest（data/village_v2_p10r*_seal.json）：status ART_APPROVED（approved_by＝user）、frozen／evidence／art_review_images／child_seals の sha256
##   - 掛載：village_v2 root 直下に node 1 個、mount_after の直後
##   - 工作包固有の live 検査（Callable：v → [[ok, msg], …]）
##   - 反向：frozen 雜湊を記憶體内で竄改 → 1 件だけ検出
## refuse_write：封存中は --build／--attach を拒否（<TAG>_ALLOW_REBAKE=1＝使用者が reopen した時だけ、封存を更新すること）。

var fails := 0
var tag := ""


func _ok(c: bool, msg: String) -> void:
	print("[%s] %s %s" % [tag, "PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


static func sealed(seal_path: String) -> bool:
	if not FileAccess.file_exists(seal_path):
		return false
	var j = JSON.parse_string(FileAccess.get_file_as_string(seal_path))
	return j is Dictionary and String(j.get("status", "")) == "ART_APPROVED"


static func refuse_write(args: PackedStringArray, seal_path: String, env: String, t: String) -> bool:
	if ("--build" in args or "--attach" in args) and sealed(seal_path) and OS.get_environment(env) != "1":
		print("[%s] FAIL 封存中（%s）：--build／--attach は拒否（使用者が reopen した時だけ %s=1、封存を更新すること）" % [t, seal_path, env])
		return true
	return false


static func repo() -> String:
	return (ProjectSettings.globalize_path("res://") + "..").simplify_path() + "/"


static func mismatch(seal: Dictionary) -> Array:
	var r := repo()
	var bad: Array = []
	for grp: String in ["frozen", "evidence", "art_review_images", "child_seals"]:
		var d: Dictionary = seal.get(grp, {})
		for k: String in d:
			if not FileAccess.file_exists(r + k) or FileAccess.get_sha256(r + k) != String(d[k]):
				bad.append(k)
	return bad


func run(tree: SceneTree, seal_path: String, t: String, node_name: String, extra: Callable) -> int:
	tag = t
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(seal_path))
	if not parsed is Dictionary:
		_ok(false, "seal manifest が読める（%s）" % seal_path)
		return 2
	var seal: Dictionary = parsed
	_ok(String(seal.get("status", "")) == "ART_APPROVED" and String(seal.get("approved_by", "")) == "user",
		"status ART_APPROVED（%s；approved_by＝user、agent は美術を承認しない）" % String(seal.get("approved_date", "?")))
	var bad := mismatch(seal)
	var n := 0
	for grp: String in ["frozen", "evidence", "art_review_images", "child_seals"]:
		n += (seal.get(grp, {}) as Dictionary).size()
	_ok(bad.is_empty() and n > 0, "封存 %d 檔雜湊一致（凍結・證據・審圖・子封存；不符 %d：%s）" % [n, bad.size(), str(bad.slice(0, 4))])
	var v := (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate() as Node3D
	tree.root.add_child(v)
	for i in 4:
		await tree.process_frame
	await tree.physics_frame
	await tree.physics_frame
	var names: Array = []
	for c in v.get_children():
		names.append(String(c.name))
	var after := String(seal.get("mount_after", ""))
	var idx := names.find(node_name)
	_ok(names.count(node_name) == 1 and idx > 0 and names[idx - 1] == after and (v.get_node(node_name) as Node).scene_file_path == String(seal.get("overlay", "")),
		"掛載：root 直下 %s 1 個・%s の直後（index %d）・%s" % [node_name, after, idx, String(seal.get("overlay", ""))])
	if extra.is_valid():
		for r: Array in await extra.call(v):
			_ok(bool(r[0]), String(r[1]))
	var tam: Dictionary = seal.duplicate(true)
	var k0: String = (tam["frozen"] as Dictionary).keys()[0]
	tam["frozen"][k0] = "0".repeat(64)
	_ok(mismatch(tam).size() == bad.size() + 1, "反向：凍結雜湊 1 件を記憶體内で竄改 → 1 件だけ検出（%d）" % (mismatch(tam).size() - bad.size()))
	v.queue_free()
	print("[%s] 結果：%d 項失敗（seal）" % [tag, fails])
	return 0 if fails == 0 else 2
