extends SceneTree
## P12 Wave 2（只讀、headless）：P5 asset reset gate の項目 1「V2 場景依賴閉包の白名單違規」を全件列挙し、
## 違規ごとに「どの依存元から来たか」（最初に辿った親）と種別（前綴）を出す。gate と同じ _closure／_allowed を使う。
##   godot --headless --path . --script res://tools/p12/audit_p5_whitelist.gd -- --out=<abs json>
const REG := "res://data/village_v2_asset_registry.json"

func _dep_path(d: String) -> String:
	var parts := d.split("::")
	for p: String in parts:
		if p.begins_with("res://"):
			return p
	if parts.size() > 0 and parts[0].begins_with("uid://"):
		var id := ResourceUID.text_to_id(parts[0])
		if ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
	return parts[0] if parts.size() > 0 else ""

func _allowed(p: String, reg: Dictionary) -> bool:
	var al: Dictionary = reg["v2_allowed"]
	for pre: String in al["prefixes"]:
		if p.begins_with(pre):
			return true
	if p in al["shared_runtime"]:
		return true
	for a: Dictionary in reg["v2_assets"]:
		if p == String(a.get("path", "")) or p.begins_with(String(a.get("path", "")) + "/"):
			return true
	return false

func _init() -> void:
	var out := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var reg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REG))
	var root_p := String(reg["v2_scene"])
	var parent := {}
	var seen := {}
	var stack: Array[String] = [root_p]
	var order: Array[String] = []
	while not stack.is_empty():
		var path: String = stack.pop_back()
		if seen.has(path):
			continue
		seen[path] = true
		order.append(path)
		for d: String in ResourceLoader.get_dependencies(path):
			var p := _dep_path(d)
			if not p.begins_with("res://") or seen.has(p):
				continue
			if not parent.has(p):
				parent[p] = path
			if p.get_extension().to_lower() in ["tscn", "tres", "scn", "res", "gd"] and ResourceLoader.exists(p):
				stack.append(p)
			else:
				seen[p] = true
				order.append(p)
	var viol := []
	for p: String in order:
		if _allowed(p, reg):
			continue
		var chain := [p]
		var q := p
		while parent.has(q) and chain.size() < 8:
			q = parent[q]
			chain.append(q)
		viol.append({"path": p, "exists": FileAccess.file_exists(p) or ResourceLoader.exists(p), "chain": chain})
	var by_dir := {}
	for v in viol:
		var parts := String(v["path"]).trim_prefix("res://").split("/")
		var key := "/".join(parts.slice(0, mini(3, parts.size() - 1)))
		by_dir[key] = int(by_dir.get(key, 0)) + 1
	print("[P5W] 依賴閉包 %d、違規 %d（存在しない %d）" % [order.size(), viol.size(), viol.filter(func(v): return not v["exists"]).size()])
	var keys := by_dir.keys()
	keys.sort_custom(func(a, b): return int(by_dir[a]) > int(by_dir[b]))
	for k in keys:
		print("[P5W]   %4d %s" % [by_dir[k], k])
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"count": viol.size(), "by_dir": by_dir, "items": viol}, " "))
	quit(0)
