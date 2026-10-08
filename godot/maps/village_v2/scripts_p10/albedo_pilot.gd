extends Node3D
## P10 R6a 材質亮度基準 Pilot（overlay `AlbedoPilotP10`，由 tools/village_v2_albedo_pilot_lib.gd 產生）。
## _ready：對 targets（相對於父節點＝village 根）內每個 MeshInstance3D，凡表面材質（或 material_override）的 resource_path
## 在 src_paths 中 → 以同索引的 cal_mats 覆寫。enabled=false 還原。只改執行期的表面覆寫，不改任何資源檔。
@export var targets: PackedStringArray = PackedStringArray()
@export var src_paths: PackedStringArray = PackedStringArray()
@export var cal_mats: Array[Material] = []
## R6a 街區調色盤（r5）：每棟的變體＝{來源材質路徑: variant_mats 索引}，與 targets 同序；空＝用 cal_mats
@export var variant_mats: Array[Material] = []
@export var target_variants: Array = []
@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			apply(v)

var _applied: Array = []   # [MeshInstance3D, surface(-1=override), 原材質]
var applied_surfaces := 0


func _ready() -> void:
	if enabled:
		apply.call_deferred(true)


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
			if m.material_override != null and bmap.has(m.material_override.resource_path):
				_applied.append([m, -1, m.material_override])
				m.material_override = bmap[m.material_override.resource_path]
				applied_surfaces += 1
				continue
			if m.mesh == null:
				continue
			for si in m.mesh.get_surface_count():
				var sm := m.mesh.surface_get_material(si)
				if sm != null and bmap.has(sm.resource_path) and m.get_surface_override_material(si) == null:
					m.set_surface_override_material(si, bmap[sm.resource_path])
					_applied.append([m, si, null])
					applied_surfaces += 1
