extends Node3D
## P13 W7 TASK 5：R6a 第一批 50 棟の材質 overlay（`AlbedoBatch1P13`、tools/p13/w7/build_w7_batch1.gd が産生）。
## 仕組みは P10 R6a の albedo_pilot.gd と同じ（封存済みのため複製）：targets（village 根からの相対パス）内の MeshInstance3D で、表面材質（または material_override）の
## resource_path が src_paths にあるものを、cal_mats／variant_mats の登記済み変体で覆寫する。enabled=false で還原。実行期の表面覆寫だけで、資源ファイルは書かない。
## albedo_pilot.gd との差は 1 点だけ：skip_prefixes に当てはまる部品名（LOD1／LOD2 の屋根 l_rh_*）は覆寫しない。
##   理由：LOD1／LOD2 の屋根はアトラス（V2_MachiyaKit）で描かれ、K 版（kit_cal.gdshader）は暗部を ×0.75 にして屋根瓦まで明るくする
##   → LOD0 の屋根（Kawara・不校正）より 1.7 倍明るい屋根が遠景に現れ、壁との対比が失われる（W7 実測：batch の LOD1／2 屋根 輝度 70.7→122.7）。
##   屋根を覆寫しなければ LOD1／2 の屋根は未校正アトラスのまま（＝主街 W2 と同じ 71.7）。壁・木・窓（l_box_*／l_f*／l_slab_*／l_u_*）は K 版のまま。
@export var targets: PackedStringArray = PackedStringArray()
@export var src_paths: PackedStringArray = PackedStringArray()
@export var cal_mats: Array[Material] = []
@export var variant_mats: Array[Material] = []
@export var target_variants: Array = []
@export var skip_prefixes: PackedStringArray = PackedStringArray()
@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			apply(v)

var _applied: Array = []   # [MeshInstance3D, surface(-1=override), 原材質]
var applied_surfaces := 0
var skipped_surfaces := 0


func _ready() -> void:
	if enabled:
		apply.call_deferred(true)


func _is_skipped(m: MeshInstance3D) -> bool:
	var nm := String(m.name)
	for p in skip_prefixes:
		if nm.begins_with(p):
			return true
	return false


func apply(on: bool) -> void:
	for a in _applied:
		var mi: MeshInstance3D = a[0]
		if not is_instance_valid(mi):
			continue
		if int(a[1]) < 0:
			mi.material_override = a[2]
		else:
			mi.set_surface_override_material(int(a[1]), null)
	_applied.clear()
	applied_surfaces = 0
	skipped_surfaces = 0
	if not on:
		return
	var map := {}
	for i in mini(src_paths.size(), cal_mats.size()):
		map[src_paths[i]] = cal_mats[i]
	var par := get_parent()
	for ti in targets.size():
		var p := targets[ti]
		var b := par.get_node_or_null(NodePath(p))
		if b == null:
			continue
		var bmap := map
		if ti < target_variants.size() and not (target_variants[ti] as Dictionary).is_empty():
			bmap = map.duplicate()
			var tv: Dictionary = target_variants[ti]
			for sp in tv:
				var vi := int(tv[sp])
				if vi >= 0 and vi < variant_mats.size():
					bmap[String(sp)] = variant_mats[vi]
		for mi in b.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var skip := _is_skipped(m)
			if m.material_override != null and bmap.has(m.material_override.resource_path):
				if skip:
					skipped_surfaces += 1
					continue
				_applied.append([m, -1, m.material_override])
				m.material_override = bmap[m.material_override.resource_path]
				applied_surfaces += 1
				continue
			if m.mesh == null:
				continue
			for si in m.mesh.get_surface_count():
				var sm := m.mesh.surface_get_material(si)
				if sm != null and bmap.has(sm.resource_path) and m.get_surface_override_material(si) == null:
					if skip:
						skipped_surfaces += 1
						continue
					m.set_surface_override_material(si, bmap[sm.resource_path])
					_applied.append([m, si, null])
					applied_surfaces += 1
