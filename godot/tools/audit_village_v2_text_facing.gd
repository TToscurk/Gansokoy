extends SceneTree
## 字の向き監査（読み取り専用）：village_v2 の全メッシュ（kit の mesh/*.res と Hero の *.scn）で、atlas の「字のある領域」に
## UV が乗った三角形ごとに、表から見て字が読める向きか（鏡像でないか）を測る。
##   T＝dP/du、B＝dP/dv（画像の v は下向き）、n＝頂点法線の平均（表）。読める＝(T×B)·n < 0、鏡像＝> 0。
##   逆さま＝縦の面で B·up > 0（v が上向き）。材質が両面描画（cull disabled）なら、裏面の板がない字の面は裏から鏡像に見える。
## 使い方：godot --headless --path godot --script res://tools/audit_village_v2_text_facing.gd -- [--out=<json>] [--strict] [--only=street_kit,market_kit]
##   --strict：鏡像・逆さま・両面描画で裏から鏡像になる字の面が 1 つでもあれば exit 2（gate 用）。
const L := preload("res://tools/village_v2_text_facing_lib.gd")
## 例外（修正しない理由を測って確認済み、2026-10-07）：key の部分一致＋region
const EXEMPT := {
	"machiya_kit/mesh/kbs_kanban": ["kanban", "袖看板は無字・左右対称の紋（円・六角・菱）＝鏡像でも見た目が同じ"],
	"kirisame/kirisame.scn": ["sign", "裏面は建物の碰撞の中（probe_village_v2_text_back.gd：裏 0.6／1.2 m 先 30/30 が碰撞内）＝玩家から見えない"],
	"suzunaan/suzunaan.scn": ["sign|spines", "裏面は建物の碰撞の中（同 probe：sign 24/24、spines 2/2）＝玩家から見えない"],
	"mise_kit/mesh/ms_noren_age_ai": ["noren_mon", "掲げた暖簾の折り返し（布が上へ折れる部分）＝紋の模様で字ではない"],
}
var lib := L.new()

func walk_scene(n: Node, label: String, out: Dictionary) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		var ov := []
		for i in mi.mesh.get_surface_count(): ov.append(mi.get_surface_override_material(i))
		lib.audit_mesh(mi.mesh, label + ":" + String(mi.name), out, ov)
	for c in n.get_children(): walk_scene(c, label, out)

func list_files(dir: String, ext: String, acc: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null: return
	for f in d.get_files():
		if f.ends_with(ext): acc.append(dir + "/" + f)
	for s in d.get_directories():
		if s.begins_with("_") or s == "src": continue
		list_files(dir + "/" + s, ext, acc)

func _initialize():
	var outp := ""; var strict := false; var only := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): outp = a.trim_prefix("--out=")
		if a == "--strict": strict = true
		if a.begins_with("--only="): only = a.trim_prefix("--only=").split(",")
	var out := {}
	var res_files := []; list_files("res://assets/village_v2", ".res", res_files)
	for f in res_files:
		if not only.is_empty() and not Array(only).any(func(o): return f.contains(o)): continue
		var m = load(f)
		if m is Mesh: lib.audit_mesh(m, f, out)
	var scn := []; list_files("res://assets/village_v2", ".scn", scn)
	for f in scn:
		if not only.is_empty() and not Array(only).any(func(o): return f.contains(o)): continue
		var ps = load(f)
		if ps is PackedScene:
			var inst: Node = ps.instantiate()
			walk_scene(inst, f, out)
			inst.free()
	var bad := 0
	var lines := []
	for k in out:
		for rn in out[k].regions:
			var r: Dictionary = out[k].regions[rn]
			var flag: bool = r.mirrored > 0 or r.upside_down > 0 or r.no_back_double > 0
			var why := ""
			for ek in EXEMPT:
				if String(k).contains(ek) and String(rn).match("*") and (EXEMPT[ek][0] as String).split("|").has(String(rn).trim_suffix("_b").trim_suffix("_c")):
					why = EXEMPT[ek][1]
			if flag and why != "":
				lines.append("- %s [%s] 例外：%s" % [k, rn, why]); continue
			if flag: bad += 1
			lines.append("%s %s [%s] readable %d mirrored %d upside %d dbl_no_back %d" % ["✗" if flag else "·", k, rn, r.readable, r.mirrored, r.upside_down, r.no_back_double])
	lines.sort()
	for l in lines: print("[TXT] ", l)
	print("[TXT] 結果：字の面を持つ surface %d、問題のある (surface, region) %d" % [out.size(), bad])
	if outp != "": FileAccess.open(outp, FileAccess.WRITE).store_string(JSON.stringify(out, "  "))
	quit(2 if strict and bad > 0 else 0)
