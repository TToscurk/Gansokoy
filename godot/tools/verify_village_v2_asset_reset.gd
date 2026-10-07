extends SceneTree
## 人間之里 V2：P5 Asset Reset gate（headless，唯讀，不寫任何檔）。
##   Godot --headless --path godot --script res://tools/verify_village_v2_asset_reset.gd
##
## 依據 data/village_v2_asset_registry.json（P5 Asset Reset，使用者 2026-09-24 指令）：
##   1 V2 場景的依賴閉包（含 .gd preload）只能落在 v2_allowed 前綴／shared_runtime，或 v2_assets 已過 Asset Gate 的新資產。
##   2 V2 產生器與 layout 原始碼裡的 res:// 字串同樣受白名單限制；不得出現專案外模型絕對路徑或「資產glb」。
##   3 V2 引用與封存清單（archived_moved／archived_in_place／external_reference_only）交集必須為 0。
##   4 Protected（龍神像、火見櫓、神社關聯）：狀態不得為 RETIRE；每個模型檔 sha256 不變（lock=exists 的共用原始檔只驗存在）；
##     受保護目錄的非 .import 檔數與總位元組不變；專案外素材庫存在時一併驗（不存在則 SKIP，不算失敗）。
##   5 archived_moved：封存位置雜湊相符、原位置已不存在（封存 ≠ 刪除）。
##   6 v2_assets：每件新資產的 Asset Gate 11 項（共享材質庫 4 項）都要 PASS、entry 雜湊與 gate.json 一致才算登記有效
##     （gate：tools/verify_village_v2_hero_gate.gd；登記：tools/build_village_v2_asset_registry.py）。
## 每項一行 [ASSET] PASS/FAIL；結尾 quit(失敗項數)。

const REG := "res://data/village_v2_asset_registry.json"
const GATE_KEYS: Array[String] = ["size", "parcel_fit", "grounding", "materials", "geometry", "pivot_scale",
	"collision", "lod", "performance", "player_screenshot", "f5_f6"]
const MATLIB_KEYS: Array[String] = ["license", "texture_size", "vram_compressed", "tres_valid"]

var fails := 0
var repo_root := ""


func check(label: String, ok: bool) -> void:
	print("[ASSET] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _abs(p: String) -> String:
	if p.begins_with("res://"):
		return ProjectSettings.globalize_path(p)
	return p


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


func _closure(root: String) -> PackedStringArray:
	var seen := {}
	var stack: Array[String] = [root]
	var out := PackedStringArray()
	while not stack.is_empty():
		var path: String = stack.pop_back()
		if seen.has(path):
			continue
		seen[path] = true
		out.append(path)
		for d: String in ResourceLoader.get_dependencies(path):
			var p := _dep_path(d)
			if not p.begins_with("res://") or seen.has(p):
				continue
			if p.get_extension().to_lower() in ["tscn", "tres", "scn", "res", "gd"] and ResourceLoader.exists(p):
				stack.append(p)
			else:
				seen[p] = true
				out.append(p)
	return out


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


func _dir_stats(root: String) -> Vector2i:
	var n := 0
	var b := 0
	var stack: Array[String] = [root]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			return Vector2i(-1, -1)
		for f: String in da.get_files():
			if f.ends_with(".import"):
				continue
			var fa := FileAccess.open(d.path_join(f), FileAccess.READ)
			if fa == null:
				return Vector2i(-1, -1)
			n += 1
			b += fa.get_length()
		for sub: String in da.get_directories():
			stack.append(d.path_join(sub))
	return Vector2i(n, b)


func _verify_files(files: Array, bad: PackedStringArray) -> int:
	var ok := 0
	for f: Dictionary in files:
		var p := _abs(String(f["path"]))
		if not FileAccess.file_exists(p):
			bad.append("缺 " + String(f["path"]))
		elif String(f.get("lock", "sha256")) == "exists":
			ok += 1   # 共用原始檔（產生腳本、神社材質）：只驗存在，不鎖雜湊
		elif FileAccess.get_sha256(p) != String(f["sha256"]):
			bad.append("雜湊變了 " + String(f["path"]))
		else:
			ok += 1
	return ok


func _verify_dirs(dirs: Array, bad: PackedStringArray) -> int:
	var ok := 0
	for d: Dictionary in dirs:
		var s := _dir_stats(_abs(String(d["path"])))
		if s.x != int(d["files"]) or s.y != int(d["bytes"]):
			bad.append("%s 檔數/位元組 %d/%d（登記 %d/%d）" % [d["path"], s.x, s.y, int(d["files"]), int(d["bytes"])])
		else:
			ok += 1
	return ok


func _init() -> void:
	repo_root = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	# 反向測試用：-- --registry=<另一份 registry>（預設讀正式 REG）
	var reg_path := REG
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--registry="):
			reg_path = a.trim_prefix("--registry=")
	var txt := FileAccess.get_file_as_string(reg_path)
	var parsed: Variant = JSON.parse_string(txt)
	check("registry 可讀（%s）" % reg_path, parsed is Dictionary)
	if not parsed is Dictionary:
		print("[ASSET] 結果：%d 項失敗" % fails)
		quit(fails)
		return
	var reg: Dictionary = parsed
	print("[ASSET] registry version = ", reg.get("version", "?"))

	# 封存路徑（前綴比對用）
	var archived := PackedStringArray()
	for a: Dictionary in reg["archived_moved"]:
		archived.append(String(a["from"]))
	for a: Dictionary in reg["archived_in_place"]:
		archived.append(String(a["path"]))
	for a: Dictionary in reg["external_reference_only"]:
		archived.append(String(a["path"]).split("{")[0])

	# ── 1 V2 場景依賴閉包
	var deps := _closure(String(reg["v2_scene"]))
	var viol := PackedStringArray()
	for p: String in deps:
		if not _allowed(p, reg):
			viol.append(p)
	check("V2 場景依賴 %d 個全在白名單內（違規 %d：%s）" % [deps.size(), viol.size(), ", ".join(viol.slice(0, 6))], viol.is_empty())

	# ── 2 產生器／layout 原始碼字串
	var re_res := RegEx.create_from_string("res://[^\"'\\s\\)\\]]+")
	# (?<![A-Za-z])：避免把 res://…glb 裡的「s:/」誤判成磁碟代號
	var re_abs := RegEx.create_from_string("(?<![A-Za-z])[A-Za-z]:[/\\\\][^\"'\\s]*\\.(glb|gltf|fbx|obj|blend)")
	var src_viol := PackedStringArray()
	var src_refs := PackedStringArray()
	for s: String in reg["v2_generator_sources"]:
		var body := FileAccess.get_file_as_string(s)
		if body == "":
			src_viol.append("讀不到 " + s)
			continue
		for m: RegExMatch in re_res.search_all(body):
			var r := m.get_string()
			src_refs.append(r)
			if not _allowed(r, reg):
				src_viol.append("%s → %s" % [s.get_file(), r])
		for m: RegExMatch in re_abs.search_all(body):
			src_viol.append("%s → 絕對路徑 %s" % [s.get_file(), m.get_string()])
		if body.contains("資產glb"):
			src_viol.append("%s → 含「資產glb」" % s.get_file())
	check("產生器／layout %d 檔的 res:// 字串全在白名單內（違規 %d：%s）" % [
		reg["v2_generator_sources"].size(), src_viol.size(), ", ".join(src_viol.slice(0, 6))], src_viol.is_empty())

	# ── 3 與封存清單交集
	var hits := PackedStringArray()
	for p: String in deps + src_refs:
		for a: String in archived:
			if p.begins_with(a) or (a.ends_with("/") and p.begins_with(a.trim_suffix("/"))):
				hits.append("%s（封存 %s）" % [p, a])
	check("V2 引用與 %d 條封存登記交集 0（實際 %d）" % [archived.size(), hits.size()], hits.is_empty())

	# ── 4 Protected
	var ext_root_ok := DirAccess.dir_exists_absolute("D:/資產glb")
	for g: Dictionary in reg["protected"]:
		var name := String(g["group"]).split("（")[0]
		check("Protected「%s」狀態不是 RETIRE（%s）" % [name, g["status"]], not String(g["status"]).contains("RETIRE"))
		var bad := PackedStringArray()
		var nf := _verify_files(g["files"], bad)
		var nd := _verify_dirs(g["dirs"], bad)
		var ne := 0
		for f: Dictionary in g["files"]:
			if String(f.get("lock", "sha256")) == "exists":
				ne += 1
		check("Protected「%s」專案內 %d 檔完好（鎖雜湊 %d、只驗存在 %d）、%d 目錄完整（問題 %d：%s）" % [
			name, nf, g["files"].size() - ne, ne, nd, bad.size(), ", ".join(bad.slice(0, 4))], bad.is_empty())
		if g["external_files"].is_empty() and g["external_dirs"].is_empty():
			continue
		if not ext_root_ok:
			print("[ASSET] SKIP Protected「%s」專案外素材庫（D:/資產glb 不存在於此機器）" % name)
			continue
		var ebad := PackedStringArray()
		var enf := _verify_files(g["external_files"], ebad)
		var end := _verify_dirs(g["external_dirs"], ebad)
		check("Protected「%s」專案外 %d 檔雜湊不變、%d 目錄完整（問題 %d：%s）" % [
			name, enf, end, ebad.size(), ", ".join(ebad.slice(0, 4))], ebad.is_empty())

	# ── 5 archived_moved
	var mbad := PackedStringArray()
	for a: Dictionary in reg["archived_moved"]:
		var dst := repo_root.path_join(String(a["to"]))
		if FileAccess.file_exists(_abs(String(a["from"]))):
			mbad.append("原位置仍在 " + String(a["from"]))
		if not FileAccess.file_exists(dst):
			mbad.append("封存缺 " + String(a["to"]))
		elif FileAccess.get_sha256(dst) != String(a["sha256"]):
			mbad.append("封存雜湊不符 " + String(a["to"]))
	check("archived_moved %d 檔已在 archive/ 且雜湊相符、原位置已清空（問題 %d：%s）" % [
		reg["archived_moved"].size(), mbad.size(), ", ".join(mbad.slice(0, 4))], mbad.is_empty())

	# ── 6 v2_assets 登記有效性
	#    hero／landmark＝11 項、material_library＝4 項；entry 雜湊＝登記值＝gate.json（gate 之後改過檔就失效）；
	#    path 必須是 res://assets/village_v2/<id>（白名單只放行登記的目錄，不是整個 village_v2/）
	var abad := PackedStringArray()
	for a: Dictionary in reg["v2_assets"]:
		var lib := String(a.get("kind", "")) == "material_library"
		var keys: Array[String] = MATLIB_KEYS if lib else GATE_KEYS
		var gate: Dictionary = a.get("gate", {})
		for k: String in keys:
			if String(gate.get(k, "")) != "PASS":
				abad.append("%s.%s" % [a.get("id", "?"), k])
		var entry := String(a.get("entry", ""))
		var p := String(a.get("path", ""))
		if p != "res://assets/village_v2/" + String(a.get("id", "?")) or not entry.begins_with(p + "/"):
			abad.append("%s 路徑不合規約（%s）" % [a.get("id", "?"), p])
		if not FileAccess.file_exists(entry):
			abad.append("缺檔 " + entry)
		elif FileAccess.get_sha256(entry) != String(a.get("entry_sha256", "")):
			abad.append("%s entry 雜湊與登記不一致（gate 之後改過）" % a.get("id", "?"))
		var gj: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(a.get("gate_json", ""))))
		if not gj is Dictionary or String(gj.get("entry_sha256", "")) != String(a.get("entry_sha256", "")):
			abad.append("%s gate.json 缺或雜湊不符" % a.get("id", "?"))
		else:
			for k: String in keys:
				# P9 veg_kit 的 gate.json 寫 perf（已封存不改）；與 tools/build_village_v2_asset_registry.py GATE_ALIAS 同一對應
				var gk := "perf" if k == "performance" and not gj["checks"].has(k) and gj["checks"].has("perf") else k
				if String(gj["checks"].get(gk, {}).get("result", "")) != "PASS":
					abad.append("%s gate.json %s 不是 PASS" % [a.get("id", "?"), k])
	check("v2_assets %d 件（hero／landmark 11 項、材質庫 4 項）全 PASS、雜湊與 gate.json 一致（問題 %d：%s）" % [
		reg["v2_assets"].size(), abad.size(), ", ".join(abad.slice(0, 4))], abad.is_empty())

	print("[ASSET] 結果：%d 項失敗" % fails)
	quit(fails)
