extends SceneTree
## 人間之里 V2：暖簾の字（noren_text_kit）をメッシュ／overlay へ反映する（2026-10-21 使用者指示：字の無い・幾何紋の布簾 → 相応の字）。
##   godot --headless --path godot --script res://tools/village_v2_noren_text_apply.gd             （全部反映。冪等）
##   godot --headless --path godot --script res://tools/village_v2_noren_text_apply.gd -- --check  （読み取りだけ：旧い無字／幾何紋の暖簾が残っていないか）
## 入力：data/village_v2_noren_text.json ＋ assets/village_v2/noren_text_kit/{atlas.json, noren_text_atlas.png, NT_Noren.tres}
##       （tools/build_village_v2_noren_text_atlas.py が産生）。町家 Kit の village_v2.tscn 側は tools/patch_village_v2_noren_text.py。
## ① kit：noren_text_kit/mesh/nr_noren_<cell>.res＝P6 の暖簾 1 枚（nr_noren_a_182.res）と同じ形で UV だけ字の区画へ。材質 NT_Noren。
## ② arch（W9R2）：w9r2_arch/mesh/<id>_L0.res の V2_MachiyaKit 面にある暖簾の三角形（旧 a–e 区画の UV）を新しい面（NT_Noren）へ移し、UV を張り替える。
##    割れ暖簾（左右の半幅 2 枚）は区画の左半分／右半分＝字数 2 か 4 の cell。冪等：旧区画の暖簾が無ければ何もしない
##    （build_w9r2_arch の再生成後にもう一度走らせれば字が戻る）。
## ③ 屋台・木戸（MarketP10／MarketWestP10）：メッシュ資源を書き換え（1 節点ずつしか使われていない）。MK_Market 面の旧区画（noren_mon／noren_dango）→ NT_Noren。
## ④ 掀げ暖簾（ms_noren_age_*）：水引 4 枚（0.42×0.25 m）を NT_Noren に移して字 2 つを 2 回。節点ごとに字が違うので、cell ごとに新メッシュを作り、
##    overlay の .scn（MarketWestP10／EnrichW9*）の該当節点の LOD0／LOD1 の mesh を差し替える。束ね布（藍の丸紋）は無地の藍に。
const DATA := "res://data/village_v2_noren_text.json"
const KIT := "res://assets/village_v2/noren_text_kit/"
const BASE_MESH := "res://assets/village_v2/machiya_kit/mesh/nr_noren_a_182.res"
const ARCH_DIR := "res://assets/village_v2/w9r2_arch/mesh/"
const AGE_DIR := "res://assets/village_v2/mise_kit/mesh/"
const KIT_MAT := "machiya_kit/V2_MachiyaKit.tres"
const MK_MAT := "market_kit/MK_Market.tres"
# P6 暖簾 5 種の旧区画（machiya_kit atlas 2048・UV 正規化）
const OLD := {"a": Rect2(0.75, 0.25, 0.25, 0.125), "b": Rect2(0.75, 0.375, 0.25, 0.125), "c": Rect2(0.0, 0.625, 0.25, 0.125),
	"d": Rect2(0.25, 0.75, 0.25, 0.125), "e": Rect2(0.25, 0.875, 0.25, 0.125)}
const OLD_INSET := 12.0 / 2048.0
# market_kit atlas の旧区画（1024、余白なし）
const MKT := {"noren_mon": Rect2(0.48828125, 0.20703125, 0.35546875, 0.052734375), "noren_dango": Rect2(0.48828125, 0.3203125, 0.35546875, 0.052734375)}
const AWN_AI_TEXEL := Vector2(0.082, 0.808)      # market_kit の awn_ai（無地の藍）
const TEXT_ROW := 0.575      # 字の中心（区画の内側の高さに対する割合）
var meta: Dictionary
var doc: Dictionary
var W := 2048.0
var H := 4256.0
var fails := 0
var check := false


func _initialize() -> void:
	doc = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	meta = JSON.parse_string(FileAccess.get_file_as_string(KIT + "atlas.json"))
	W = float(meta["atlas_px"][0]); H = float(meta["atlas_px"][1])
	check = "--check" in OS.get_cmdline_user_args()
	if not check:
		_build_kit_meshes()
	_arch()
	_inplace()
	_age()
	print("[NOREN] 結果：失敗 %d" % fails)
	quit(1 if fails > 0 else 0)


func _fail(msg: String) -> void:
	printerr("[NOREN] FAIL ", msg)
	fails += 1


# ───────────── 共通：UV ─────────────
func _cell_px(cell: String) -> Rect2:
	var p: Array = meta["cells"][cell]["px"]
	return Rect2(float(p[0]), float(p[1]), float(p[2]), float(p[3]))


func _cell_ins(cell: String) -> float:
	return float(meta["cells"][cell]["inset"])


## 区画の内側に対する割合 (ru, rv)（範囲 ulo..uhi × vlo..vhi の中）→ atlas の uv
func _place(ru: float, rv: float, cell: String, ulo: float, uhi: float, vlo: float, vhi: float) -> Vector2:
	var cp := _cell_px(cell)
	var ins := _cell_ins(cell)
	var cw := cp.size.x - 2.0 * ins
	var ch := cp.size.y - 2.0 * ins
	return Vector2((cp.position.x + ins + (ulo + ru * (uhi - ulo)) * cw) / W, (cp.position.y + ins + (vlo + rv * (vhi - vlo)) * ch) / H)


func _map_uv(uv: Vector2, old: Rect2, old_ins: float, cell: String, ulo: float, uhi: float, vlo: float, vhi: float) -> Vector2:
	var ru := clampf((uv.x - old.position.x - old_ins) / (old.size.x - 2.0 * old_ins), 0.0, 1.0)
	var rv := clampf((uv.y - old.position.y - old_ins) / (old.size.y - 2.0 * old_ins), 0.0, 1.0)
	return _place(ru, rv, cell, ulo, uhi, vlo, vhi)


func _slot_aspect(cell: String, frac_u: float) -> float:
	var cp := _cell_px(cell)
	var ins := _cell_ins(cell)
	return (cp.size.x - 2.0 * ins) * frac_u / (cp.size.y - 2.0 * ins)


## 字の行を中心に縦を切り出す範囲（縦横比 a の板に、横 1 区画ぶんの比 slot_a の絵を歪めず貼る）
func _vcrop(slot_a: float, a: float, fmin: float) -> Vector2:
	var f := 1.0
	if a > slot_a * 1.2:
		f = clampf(slot_a / a, fmin, 1.0)
	var lo := clampf(TEXT_ROW - f * 0.5, 0.0, 1.0 - f)
	return Vector2(lo, lo + f)


# ───────────── 共通：面の分割 ─────────────
func _pick(src, order: PackedInt32Array, stride: int):
	if src == null:
		return null
	match typeof(src):
		TYPE_PACKED_VECTOR3_ARRAY:
			var o := PackedVector3Array()
			for vi in order: o.append((src as PackedVector3Array)[vi])
			return o
		TYPE_PACKED_VECTOR2_ARRAY:
			var o := PackedVector2Array()
			for vi in order: o.append((src as PackedVector2Array)[vi])
			return o
		TYPE_PACKED_COLOR_ARRAY:
			var o := PackedColorArray()
			for vi in order: o.append((src as PackedColorArray)[vi])
			return o
		TYPE_PACKED_FLOAT32_ARRAY:
			var o := PackedFloat32Array()
			for vi in order:
				for k in stride: o.append((src as PackedFloat32Array)[vi * stride + k])
			return o
	return null


## tri_verts＝頂点番号の三角形リスト → 頂点を詰めた surface 配列
func _subset(arr: Array, tri_verts: PackedInt32Array) -> Array:
	var remap := {}
	var order := PackedInt32Array()
	var idx := PackedInt32Array()
	for vi in tri_verts:
		if not remap.has(vi):
			remap[vi] = order.size()
			order.append(vi)
		idx.append(remap[vi])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for ai in Mesh.ARRAY_MAX:
		if ai == Mesh.ARRAY_INDEX or arr[ai] == null:
			continue
		var src = arr[ai]
		if ai == Mesh.ARRAY_TANGENT:
			out[ai] = _pick(src, order, 4)
		elif ai in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
			out[ai] = _pick(src, order, 1)
		elif (src is PackedFloat32Array or src is PackedByteArray) and (src as Variant).size() > 0:
			_fail("想定外の頂点配列 index=%d" % ai)
	out[Mesh.ARRAY_INDEX] = idx
	return out


func _surface_of(mesh: Mesh, mat_suffix: String) -> int:
	var found := -1
	for si in mesh.get_surface_count():
		var mt := mesh.surface_get_material(si)
		if mt != null and mt.resource_path.ends_with(mat_suffix):
			found = si
	return found


## 四角形（三角形 2 枚＝頂点 4）を探す。pred(t, verts: Array, V, N, UV) → 文字列（"" ならその三角形は対象外）。
## 返り値：{"quads": [{t, tag, verts, cx, cy, w, h, front, bb}], "keep": PackedInt32Array}
func _find_quads(arr: Array, pred: Callable) -> Dictionary:
	var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var N: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var UV: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var quads: Array = []
	var keep := PackedInt32Array()
	var t := 0
	while t < idx.size():
		var tag := ""
		var vs: Array = []
		if t + 5 < idx.size():
			var d := {}
			for k in 6: d[idx[t + k]] = true
			vs = d.keys()
			if vs.size() == 4:
				tag = String(pred.call(t, vs, V, N, UV, idx))
		if tag != "":
			var mn := Vector3(1e9, 1e9, 1e9)
			var mx := Vector3(-1e9, -1e9, -1e9)
			for vi in vs:
				mn = mn.min(V[vi]); mx = mx.max(V[vi])
			var dd := mx - mn
			quads.append({"t": t, "tag": tag, "verts": vs, "cx": (mn.x + mx.x) * 0.5, "cy": (mn.y + mx.y) * 0.5, "front": N[idx[t]].z >= 0.0,
				"w": dd.x, "h": sqrt(dd.y * dd.y + dd.z * dd.z), "bb": AABB(mn, dd)})
			t += 6
		else:
			keep.append(idx[t]); keep.append(idx[t + 1]); keep.append(idx[t + 2])
			t += 3
	return {"quads": quads, "keep": keep}


func _old_kit_of(uv: Vector2) -> String:
	for k in OLD:
		if (OLD[k] as Rect2).grow(0.0004).has_point(uv):
			return k
	return ""


## 暖簾の三角形を新しい面（NT_Noren）へ移して保存。keep_arr＝残す三角形の頂点番号、moved＝移す三角形、uv_new＝頂点ごとの新 uv。
func _rebuild_and_save(mesh: ArrayMesh, mat_si: int, arr: Array, keep: PackedInt32Array, moved: PackedInt32Array, uv_new: PackedVector2Array, out_path: String) -> bool:
	arr[Mesh.ARRAY_TEX_UV] = uv_new
	var kept := _subset(arr, keep)
	var mv := _subset(arr, moved)
	var nm := ArrayMesh.new()
	var before := 0
	var after := 0
	for si in mesh.get_surface_count():
		var sa := mesh.surface_get_arrays(si)
		before += (sa[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var use_arr: Array = sa
		if si == mat_si:
			use_arr = kept
			if (kept[Mesh.ARRAY_INDEX] as PackedInt32Array).size() == 0:
				continue
		nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, use_arr)
		var ns := nm.get_surface_count() - 1
		nm.surface_set_material(ns, mesh.surface_get_material(si))
		nm.surface_set_name(ns, mesh.surface_get_name(si))
	nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mv)
	nm.surface_set_material(nm.get_surface_count() - 1, load(KIT + "NT_Noren.tres"))
	nm.surface_set_name(nm.get_surface_count() - 1, "noren_text")
	for si in nm.get_surface_count():
		after += (nm.surface_get_arrays(si)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	if after != before:
		_fail("%s: 三角形数が変わった %d → %d" % [out_path, before, after])
		return false
	nm.resource_name = mesh.resource_name
	var err := ResourceSaver.save(nm, out_path)
	if err != OK:
		_fail("保存できない %s (%d)" % [out_path, err])
		return false
	return true


# ───────────── ① kit ─────────────
func _build_kit_meshes() -> void:
	var base: ArrayMesh = load(BASE_MESH)
	var mat: Material = load(KIT + "NT_Noren.tres")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(KIT + "mesh"))
	var n := 0
	for key in doc["cells"]:
		if String(doc["cells"][key].get("kind", "kit")) != "kit":
			continue
		var arr := base.surface_get_arrays(0)
		var UV: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var nuv := PackedVector2Array()
		for u in UV:
			nuv.append(_map_uv(u, OLD["a"], OLD_INSET, key, 0.0, 1.0, 0.0, 1.0))
		arr[Mesh.ARRAY_TEX_UV] = nuv
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, mat)
		m.resource_name = "nr_noren_" + key
		var p: String = KIT + "mesh/nr_noren_%s.res" % key
		if ResourceSaver.save(m, p) != OK:
			_fail("保存できない " + p)
		n += 1
	print("[NOREN] kit メッシュ %d 枚" % n)


# ───────────── ② arch ─────────────
func _arch() -> void:
	var changed := 0
	var left := 0
	var pred := func(t: int, vs: Array, V, N, UV, idx) -> String:
		var a := _old_kit_of((UV[idx[t]] + UV[idx[t + 1]] + UV[idx[t + 2]]) / 3.0)
		var b := _old_kit_of((UV[idx[t + 3]] + UV[idx[t + 4]] + UV[idx[t + 5]]) / 3.0)
		return a if (a != "" and a == b) else ""
	for id in doc["buildings"]:
		var p: String = ARCH_DIR + "%s_L0.res" % id
		if not ResourceLoader.exists(p):
			continue
		var mesh: ArrayMesh = load(p)
		var cell: String = doc["buildings"][id]
		var slots := int(meta["cells"][cell]["slots"])
		var kit_si := _surface_of(mesh, KIT_MAT)
		if kit_si < 0:
			continue
		var arr := mesh.surface_get_arrays(kit_si)
		var f := _find_quads(arr, pred)
		var quads: Array = f["quads"]
		if quads.is_empty():
			continue
		if check:
			left += quads.size()
			print("[NOREN] 未変換 %s：幾何紋の暖簾 %d 枚" % [id, quads.size()])
			continue
		if slots != 2 and slots != 4:
			_fail("%s: 割れ暖簾には字数 2 か 4 の cell が必要（%s＝%d 字）" % [id, cell, slots])
			continue
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var UV: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var noren_v := {}
		for q in quads:
			for k in 6: noren_v[idx[int(q["t"]) + k]] = true
		for i in (f["keep"] as PackedInt32Array):
			if noren_v.has(i):
				_fail("%s: 暖簾の頂点が他の三角形と共有されている" % id)
				break
		var fronts: Array = quads.filter(func(q): return q["front"])
		fronts.sort_custom(func(a, b): return float(a["cx"]) < float(b["cx"]))
		var uv_new := UV.duplicate()
		var mv := PackedInt32Array()
		var report := []
		for q in quads:
			var half := 0
			var best := 1e9
			for i in fronts.size():
				var fq: Dictionary = fronts[i]
				var dd := absf(float(fq["cx"]) - float(q["cx"])) + absf(float(fq["cy"]) - float(q["cy"]))
				if dd < best:
					best = dd
					half = i % 2
			var a := float(q["w"]) / maxf(float(q["h"]), 0.01)
			var vc := _vcrop(_slot_aspect(cell, 0.5), a, 0.72)
			var ulo := 0.0 if half == 0 else 0.5
			for k in 6:
				var vi := idx[int(q["t"]) + k]
				uv_new[vi] = _map_uv(UV[vi], OLD[q["tag"]], OLD_INSET, cell, ulo, ulo + 0.5, vc.x, vc.y)
				mv.append(vi)
			report.append("%s/%s" % ["F" if q["front"] else "B", "LR"[half]])
		if _rebuild_and_save(mesh, kit_si, arr, f["keep"], mv, uv_new, p):
			changed += 1
			print("[NOREN] arch %s → %s「%s」暖簾 %d 枚 %s" % [id, cell, doc["cells"][cell]["text"], quads.size(), ",".join(report)])
	if check:
		print("[NOREN] check：arch に残る幾何紋の暖簾 %d 枚" % left)
		if left > 0: fails += 1
	else:
		print("[NOREN] arch メッシュ %d 棟を更新" % changed)


# ───────────── ③ 屋台・木戸（メッシュ資源をそのまま）─────────────
func _inplace() -> void:
	var changed := 0
	for e in doc["inplace_meshes"]:
		var p: String = e["mesh"]
		if not ResourceLoader.exists(p):
			_fail("メッシュが無い " + p)
			continue
		var mesh: ArrayMesh = load(p)
		var cell: String = e["cell"]
		var old: Rect2 = MKT[e["region"]]
		var mk_si := _surface_of(mesh, MK_MAT)
		if mk_si < 0:
			continue
		var arr := mesh.surface_get_arrays(mk_si)
		var reg: String = e["region"]
		var pred := func(t: int, vs: Array, V, N, UV, idx) -> String:
			var a := (old.grow(0.0004)).has_point((UV[idx[t]] + UV[idx[t + 1]] + UV[idx[t + 2]]) / 3.0)
			var b := (old.grow(0.0004)).has_point((UV[idx[t + 3]] + UV[idx[t + 4]] + UV[idx[t + 5]]) / 3.0)
			return reg if (a and b) else ""
		var f := _find_quads(arr, pred)
		var quads: Array = f["quads"]
		if quads.is_empty():
			continue
		if check:
			print("[NOREN] 未変換 %s：%s の暖簾 %d 枚" % [p.get_file(), reg, quads.size()])
			fails += 1
			continue
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var UV: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var uc: Array = e.get("ucrop", [0.0, 1.0])
		var uv_new := UV.duplicate()
		var mv := PackedInt32Array()
		for q in quads:
			for k in 6:
				var vi := idx[int(q["t"]) + k]
				uv_new[vi] = _map_uv(UV[vi], old, 0.0, cell, float(uc[0]), float(uc[1]), 0.0, 1.0)
				mv.append(vi)
		if _rebuild_and_save(mesh, mk_si, arr, f["keep"], mv, uv_new, p):
			changed += 1
			print("[NOREN] 屋台／木戸 %s → %s「%s」暖簾 %d 枚" % [p.get_file(), cell, doc["cells"][cell]["text"], quads.size()])
	if not check:
		print("[NOREN] 屋台・木戸メッシュ %d 本を更新" % changed)


# ───────────── ④ 掀げ暖簾 ─────────────
func _is_panel(t: int, vs: Array, V, N, UV, idx) -> String:
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	for vi in vs:
		mn = mn.min(V[vi]); mx = mx.max(V[vi])
	var d := mx - mn
	if d.x > 0.36 and d.x < 0.48 and d.y > 0.2 and d.y < 0.3 and d.z < 0.03 and mx.y < 0.001 and mn.y > -0.275:
		return "panel"
	return ""


func _age_variant(cell: String, lod: String) -> String:
	var color: String = doc["cells"][cell]["age_color"]
	var src := AGE_DIR + "ms_noren_age_%s%s.res" % [color, lod]
	var out := KIT + "mesh/ms_%s%s.res" % [cell, lod]
	var mesh: ArrayMesh = load(src)
	var arr := mesh.surface_get_arrays(0)
	var f := _find_quads(arr, _is_panel)
	var quads: Array = f["quads"]
	if quads.size() != 8:
		_fail("%s: 水引の板が 8 枚（前後 4 組）でない（%d）" % [src.get_file(), quads.size()])
		return ""
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var UV: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var uv_new := UV.duplicate()
	# 水引以外：藍は束ね布に丸紋が乗っているので無地の藍へ（紅・生成りは元から無地の色票）
	if color == "ai":
		var moved := {}
		for q in quads:
			for k in 6: moved[idx[int(q["t"]) + k]] = true
		for vi in V.size():
			if not moved.has(vi) and MKT["noren_mon"].grow(0.0004).has_point(UV[vi]):
				uv_new[vi] = AWN_AI_TEXEL
	var fronts: Array = quads.filter(func(q): return q["front"])
	fronts.sort_custom(func(a, b): return float(a["cx"]) < float(b["cx"]))
	var slots := int(meta["cells"][cell]["slots"])
	var mv := PackedInt32Array()
	var N: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for q in quads:
		var pi := 0
		var best := 1e9
		for i in fronts.size():
			var fq: Dictionary = fronts[i]
			var dd := absf(float(fq["cx"]) - float(q["cx"])) + absf(float(fq["cy"]) - float(q["cy"]))
			if dd < best:
				best = dd
				pi = i
		var bb: AABB = q["bb"]
		var slot := pi % slots
		var ulo := float(slot) / slots
		var uhi := float(slot + 1) / slots
		var vc := _vcrop(_slot_aspect(cell, 1.0 / slots), bb.size.x / maxf(bb.size.y, 0.01), 0.5)
		for k in 6:
			var vi := idx[int(q["t"]) + k]
			var ru := (V[vi].x - bb.position.x) / maxf(bb.size.x, 0.001)
			if not q["front"]:
				ru = 1.0 - ru          # 背面は左右を逆に貼って、後ろから見ても字が鏡像にならない
			var rv := 1.0 - (V[vi].y - bb.position.y) / maxf(bb.size.y, 0.001)
			uv_new[vi] = _place(ru, rv, cell, ulo, uhi, vc.x, vc.y)
			mv.append(vi)
	if not _rebuild_and_save(mesh, 0, arr, f["keep"], mv, uv_new, out):
		return ""
	return out


func _age() -> void:
	var cells_done := {}
	var props: Dictionary = doc.get("age_props", {})
	if check:
		var left := 0
		for key in props:
			var cell: String = props[key]["cell"]
			if not ResourceLoader.exists(KIT + "mesh/ms_%s.res" % cell):
				left += 1
		var kl := 0
		var kp: Dictionary = doc.get("kit_props", {})
		for key in kp:
			var inst0: Node = (load(kp[key]["scene"]) as PackedScene).instantiate()
			var nd := inst0.get_node_or_null(NodePath(kp[key]["path"])) as MeshInstance3D
			if nd == null or nd.mesh.resource_path != KIT + "mesh/nr_noren_%s.res" % kp[key]["cell"]:
				kl += 1
			inst0.free()
		left += kl
		print("[NOREN] check：掀げ暖簾の変種メッシュが無い節点／overlay 内の旧 Kit 暖簾 %d" % left)
		if left > 0: fails += 1
		return
	for key in props:
		var cell: String = props[key]["cell"]
		if cells_done.has(cell):
			continue
		cells_done[cell] = true
		_age_variant(cell, "")
		_age_variant(cell, "_l1")
	print("[NOREN] 掀げ暖簾の変種メッシュ %d 種（LOD0／LOD1）" % cells_done.size())
	# overlay の .scn の該当節点の mesh を差し替える
	var by_scene := {}
	for key in props:
		var sc: String = props[key]["scene"]
		if not by_scene.has(sc): by_scene[sc] = []
		(by_scene[sc] as Array).append(props[key])
	var kprops: Dictionary = doc.get("kit_props", {})
	for key in kprops:
		var sc2: String = kprops[key]["scene"]
		if not by_scene.has(sc2): by_scene[sc2] = []
		var e: Dictionary = (kprops[key] as Dictionary).duplicate()
		e["kind"] = "kit"
		(by_scene[sc2] as Array).append(e)
	for sc in by_scene:
		var ps: PackedScene = load(sc)
		var inst: Node = ps.instantiate()
		var n_before := inst.find_children("*", "", true, false).size()
		var swapped := 0
		for pr in by_scene[sc]:
			var node := inst.get_node_or_null(NodePath(pr["path"]))
			if node == null:
				_fail("%s に節点が無い %s" % [sc, pr["path"]])
				continue
			if String(pr.get("kind", "age")) == "kit":      # 町家 Kit の暖簾 1 枚（節点そのものが MeshInstance3D）
				var km := node as MeshInstance3D
				var kwant: String = KIT + "mesh/nr_noren_%s.res" % pr["cell"]
				if km != null and km.mesh.resource_path != kwant:
					km.mesh = load(kwant)
					swapped += 1
				continue
			for lod in ["LOD0", "LOD1"]:
				var mi := node.get_node_or_null(lod) as MeshInstance3D
				if mi == null:
					_fail("%s/%s に %s が無い" % [sc.get_file(), pr["path"], lod])
					continue
				var want: String = KIT + "mesh/ms_%s%s.res" % [pr["cell"], "" if lod == "LOD0" else "_l1"]
				if mi.mesh.resource_path != want:
					mi.mesh = load(want)
					swapped += 1
		if swapped > 0:
			var np := PackedScene.new()
			var err := np.pack(inst)
			if err != OK:
				_fail("pack 失敗 " + sc)
			else:
				err = ResourceSaver.save(np, sc)
				if err != OK:
					_fail("保存失敗 %s (%d)" % [sc, err])
		var n_after := inst.find_children("*", "", true, false).size()
		if n_after != n_before:
			_fail("%s: 節点数が変わった %d → %d" % [sc, n_before, n_after])
		print("[NOREN] overlay %s：mesh %d 本を差し替え（節点 %d）" % [sc.get_file(), swapped, n_after])
		inst.free()
