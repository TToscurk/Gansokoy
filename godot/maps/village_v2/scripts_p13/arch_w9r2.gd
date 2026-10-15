extends Node3D
## P13 W9 Round 2：建築外形サンプル overlay（`ArchW9R2P13`・tools/p13/w9/build_w9r2.gd が産生）。
## 子＝建築 id ごとの Node3D（body と同じ transform）＋ L0／L1 メッシュ。metadata：body_path（village 直下から）、hide（カテゴリごとの接頭辞）。
## enabled=true：該当建築の Kit 構件のうち hide0／hide12 の接頭辞に合うものを非表示にし、新メッシュを見せる。
##   材質は建築自身の Kit 構件に付いている覆寫（W7 Albedo／W8 LodCal）を同じ基底材質の面にコピーする（隣と明度がずれない）。
## enabled=false：非表示にした Kit 構件を元の visible に戻し、新メッシュを隠す（Before と同じ状態）。
@export var enabled := true:
	set(v):
		enabled = v
		if _booted:
			_apply(v)

var _booted := false
var _hidden: Array = []      # [MeshInstance3D, 元の visible]
var _mats: Array = []        # [MeshInstance3D, surface, 元の override]
var hidden_count := 0
var copied_surfaces := 0
var r1_hidden := 0
## W9 R1（EnrichW9P13）が壁・軒に『吊った』物のうち、R2 で作り直した正面・庇と重なるもの（簾・吊柿・杉玉・笊・草履）。R2／R2.1 の 16 棟でだけ隠す（暖簾・地面の物は残す）。
const R1_HANG := ["sudare", "kaki", "sugi", "zaru", "zori"]


func _ready() -> void:
	_boot.call_deferred()


func _boot() -> void:
	# W7 AlbedoBatch1P13／W8 LodCalBatch1P13 は call_deferred で apply する → それより後で材質を読む
	await get_tree().process_frame
	await get_tree().process_frame
	_booted = true
	_apply(enabled)


func _restore() -> void:
	r1_hidden = 0
	for h in _hidden:
		if is_instance_valid(h[0]):
			(h[0] as Node3D).visible = h[1]
	_hidden.clear()
	for a in _mats:
		if is_instance_valid(a[0]):
			(a[0] as MeshInstance3D).set_surface_override_material(int(a[1]), a[2])
	_mats.clear()
	hidden_count = 0
	copied_surfaces = 0


func _kit_meshes(kit: Node, lods: Array) -> Array:
	var out: Array = []
	for l: int in lods:
		var g := kit.get_node_or_null("LOD%d" % l)
		if g:
			for c in g.get_children():
				if c is MeshInstance3D:
					out.append(c)
	return out


func _apply(on: bool) -> void:
	_restore()
	visible = on
	if not on:
		return
	var vil := get_parent()
	var r1 := vil.get_node_or_null("EnrichW9P13")
	if r1 != null:
		var ids := {}
		for c in get_children():
			ids[String(c.get_meta("body_path", "")).get_file()] = true
		for z in r1.get_children():
			for cl in z.get_children():
				for it in cl.get_children():
					if it is Node3D and ids.has(String(it.get_meta("w9_b", ""))) and R1_HANG.has(String(it.get_meta("w9_feature", ""))):
						_hidden.append([it, (it as Node3D).visible])
						(it as Node3D).visible = false
						r1_hidden += 1
	for b in get_children():
		if not b is Node3D:
			continue
		var body := vil.get_node_or_null(NodePath(String(b.get_meta("body_path", "")))) as Node3D
		if body == null:
			continue
		var kit := body.get_node_or_null("Kit")
		if kit == null:
			continue
		for lod in 3:
			var pre: PackedStringArray = b.get_meta("hide0" if lod == 0 else "hide12", PackedStringArray())
			var g := kit.get_node_or_null("LOD%d" % lod)
			if g == null or pre.is_empty():
				continue
			for mi in g.get_children():
				if not mi is MeshInstance3D:
					continue
				for p in pre:
					if String(mi.name).begins_with(p):
						_hidden.append([mi, (mi as MeshInstance3D).visible])
						(mi as MeshInstance3D).visible = false
						hidden_count += 1
						break
		# 材質の覆寫をコピー：L0 ← Kit LOD0、L1 ← Kit LOD1／LOD2
		for lm in b.get_children():
			if not lm is MeshInstance3D:
				continue
			var src := _kit_meshes(kit, [0] if String(lm.name) == "L0" else [1, 2])
			var mesh := (lm as MeshInstance3D).mesh
			for si in mesh.get_surface_count():
				var base := mesh.surface_get_material(si)
				if base == null:
					continue
				var done := false
				for s in src:
					var sm := (s as MeshInstance3D).mesh
					for sj in sm.get_surface_count():
						if sm.surface_get_material(sj) == base:
							var ov := (s as MeshInstance3D).get_surface_override_material(sj)
							if ov != null:
								_mats.append([lm, si, (lm as MeshInstance3D).get_surface_override_material(si)])
								(lm as MeshInstance3D).set_surface_override_material(si, ov)
								copied_surfaces += 1
								done = true
								break
					if done:
						break
