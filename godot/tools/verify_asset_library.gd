extends SceneTree
## Verify the generated Asset Placer library survives the plugin's own startup
## validation.
##
## Why this exists: the first generated library came back EMPTY after restarting
## the editor. Synchronize._update_assets() drops any asset for which
## _is_asset_valid() is false, and that check is
##     asset.has_resource() and lib.asset_has_folder(asset)
## — so an asset whose folder_path matches no registered AssetFolder is deleted
## on load, silently. Re-running the generator and restarting again is a slow way
## to discover that; this replays both conditions headlessly instead.
##
## Run: godot --headless --path godot --script tools/verify_asset_library.gd

const LIB := "user://asset_library.json"


func _init() -> void:
	var f := FileAccess.open(LIB, FileAccess.READ)
	if f == null:
		push_error("no library at %s" % LIB)
		quit(1)
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()

	var assets: Array = data.get("assets", [])
	var folders: Array = data.get("folders", [])
	var cols: Array = data.get("collections", [])

	print("讀入: 資產 %d / 資料夾 %d / 分類 %d" % [assets.size(), folders.size(), cols.size()])
	if folders.is_empty():
		print("\n[致命] folders 是空的 — 外掛啟動時會刪光所有資產")
		quit(1)
		return
	for fo in folders:
		print("  已註冊資料夾: %s (含子目錄 %s)" % [fo["path"], fo["include_subfolders"]])

	var bad_res: Array = []
	var bad_folder: Array = []

	for a in assets:
		var id: String = a["id"]
		# AssetResource.has_resource()
		var ok_res := false
		if id.begins_with("uid://"):
			ok_res = ResourceUID.has_id(ResourceUID.text_to_id(id))
		else:
			ok_res = ResourceLoader.exists(id)
		if not ok_res:
			bad_res.append(a["name"])

		# AssetLibrary.asset_has_folder() -> AssetFolder.has_asset()
		var claimed := false
		for fo in folders:
			var fpath: String = fo["path"]
			var apath: String = a.get("folder_path", "")
			var is_parent := fpath == apath
			var is_sub: bool = bool(fo["include_subfolders"]) and apath.begins_with(fpath + "/")
			if is_parent or is_sub:
				claimed = true
				break
		if not claimed:
			bad_folder.append(a["name"])

	print("")
	if bad_res.is_empty():
		print("[ok] 全部 %d 件都能解析到實際檔案" % assets.size())
	else:
		print("[失敗] %d 件找不到檔案: %s" % [bad_res.size(), ", ".join(bad_res.slice(0, 8))])

	if bad_folder.is_empty():
		print("[ok] 全部 %d 件都被已註冊資料夾認領 — 重開不會被清空" % assets.size())
	else:
		print("[失敗] %d 件沒有歸屬資料夾，重開會被刪: %s" % [
			bad_folder.size(), ", ".join(bad_folder.slice(0, 8))])

	var tally := {}
	for a in assets:
		var c := int(a["primary_collection"])
		tally[c] = tally.get(c, 0) + 1
	var names := {}
	for c in cols:
		names[int(c["id"])] = c["name"]
	print("\n分類統計:")
	var keys := tally.keys()
	keys.sort()
	for k in keys:
		print("  %-8s %d 件" % [names.get(k, "?%d" % k), tally[k]])

	if bad_res.is_empty() and bad_folder.is_empty():
		print("\n[PASS] 資產庫可存活")
		quit(0)
	else:
		print("\n[FAIL] 重開後會掉資產")
		quit(1)
