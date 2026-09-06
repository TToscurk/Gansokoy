extends SceneTree
## Replay Asset Placer's "Sync Assets" pass against the generated library.
##
## Why: the library now deliberately omits the stone props, but sync is a
## separate code path — Synchronize.add_assets_from_folder() re-scans the folder
## and re-adds anything a registered folder's rules accept. If those rules are
## too loose the stones come straight back, and the user only finds out after
## painting a tree stroke that drops a boulder. Replay the plugin's own logic
## here instead of finding out in the editor.
##
## Mirrors: AssetFolder.name_passes_filters() + FilterByNameRule.do_filter()
## (case-insensitive substring), and Synchronize's supported-extension check.
##
## Run: godot --headless --path godot --script tools/verify_sync_excludes.gd

const LIB := "user://asset_library.json"
const SUPPORTED := ["tscn", "scn", "glb", "fbx", "obj", "gltf", "blend"]

# Anything matching these must never end up in the library.
const FORBIDDEN := ["pebble", "rock"]


func _init() -> void:
	var f := FileAccess.open(LIB, FileAccess.READ)
	if f == null:
		push_error("no library at %s" % LIB)
		quit(1)
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()

	var folders: Array = data.get("folders", [])
	var existing := {}
	for a in data.get("assets", []):
		existing[str(a["name"])] = true

	print("現有資產 %d 件，註冊資料夾 %d 個\n" % [existing.size(), folders.size()])

	var would_add: Array = []
	var scanned := 0

	for fo in folders:
		var fpath: String = fo["path"]
		var rules: Array = fo.get("rules", [])
		var d := DirAccess.open(fpath)
		if d == null:
			print("[warn] 無法開啟 %s" % fpath)
			continue
		for file in d.get_files():
			if not file.get_extension().to_lower() in SUPPORTED:
				continue
			scanned += 1
			if not _passes(file, rules):
				continue
			if existing.has(file):
				continue
			if not file in would_add:
				would_add.append(file)

	print("掃描 %d 次檔案比對" % scanned)
	if would_add.is_empty():
		print("[ok] Sync 不會加入任何新資產")
	else:
		print("[注意] Sync 會新增 %d 件: %s" % [
			would_add.size(), ", ".join(would_add)])

	# The real question: can any forbidden asset get back in?
	var leaks: Array = []
	for name in would_add:
		var lower := str(name).to_lower()
		for bad in FORBIDDEN:
			if lower.contains(bad):
				leaks.append(name)
				break
	# Also check nothing forbidden is already present.
	for name in existing:
		var lower := str(name).to_lower()
		for bad in FORBIDDEN:
			if lower.contains(bad):
				leaks.append("%s (已在庫中)" % name)
				break

	print("")
	if leaks.is_empty():
		print("[PASS] 石頭類不會出現在資產庫，隨機生成不會抓到石頭")
		quit(0)
	else:
		print("[FAIL] 石頭類仍會進入: %s" % ", ".join(leaks))
		quit(1)


## AssetFolder.name_passes_filters — true if ANY rule matches, or no rules exist.
func _passes(file_name: String, rules: Array) -> bool:
	if rules.is_empty():
		return true
	for r in rules:
		if r.get("type", "") != "filter_by_name":
			continue
		var pat: String = r.get("pattern", "")
		if pat.is_empty():
			return true
		if file_name.to_lower().contains(pat.to_lower()):
			return true
	return false
