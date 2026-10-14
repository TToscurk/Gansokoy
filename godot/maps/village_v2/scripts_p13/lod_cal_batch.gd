extends Node3D
## P13 W8 TASK B：第一批 50 棟の LOD1／LOD2 町家 atlas 表面を、調色盤別の LOD 材質で覆寫する overlay（`LodCalBatch1P13`・tools/p13/w8/build_w8_lod.gd が産生）。
## W7 の AlbedoBatch1P13（封存）には触れない：こちらは LOD1／LOD2 の『V2_MachiyaKit を引く表面』だけを、W7 の K 版の上から差し替える（元の覆寫を記録して還原できる）。
##   LOD1：壁箱（l_box*）と正面（l_f*／l_u_*）→ l1 の材質（box_mul／face_mul）／LOD2：壁箱 → l2 の材質／屋根（部品名 l_rh_*）→ roof の材質（LOD1・LOD2 共通）。
## 材質は maps/village_v2/lod_cal_p13/lod_material_variants.json の登記変体だけ。LOD0・幾何・コリジョンには触れない。enabled=false で完全に還原。
@export var targets: PackedStringArray = PackedStringArray()
@export var mats: Array[Material] = []
@export var assign: Array = []          # 各 target：{"l1": 材質 index, "l2": 材質 index, "roof": 材質 index}
@export var base_path := "res://assets/village_v2/machiya_kit/V2_MachiyaKit.tres"
@export var roof_prefixes: PackedStringArray = PackedStringArray(["l_rh_"])
@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			apply(v)

var _applied: Array = []   # [MeshInstance3D, surface, 元の surface override（null 可）]
var applied_surfaces := 0
var roof_surfaces := 0
var lod_surfaces := {"1": 0, "2": 0}


func _ready() -> void:
	if enabled:
		apply.call_deferred(true)   # AlbedoBatch1P13（W7）の apply より後に走らせる


func _is_roof(n: String) -> bool:
	for p in roof_prefixes:
		if n.begins_with(p):
			return true
	return false


func apply(on: bool) -> void:
	for a in _applied:
		var mi: MeshInstance3D = a[0]
		if is_instance_valid(mi):
			mi.set_surface_override_material(int(a[1]), a[2])
	_applied.clear()
	applied_surfaces = 0
	roof_surfaces = 0
	lod_surfaces = {"1": 0, "2": 0}
	if not on:
		return
	var par := get_parent()
	for ti in targets.size():
		var b := par.get_node_or_null(NodePath(targets[ti]))
		if b == null or ti >= assign.size():
			continue
		var kit := b.get_node_or_null("Kit")
		if kit == null:
			continue
		var asg: Dictionary = assign[ti]
		for lod in [1, 2]:
			var ln := kit.get_node_or_null("LOD%d" % lod)
			if ln == null:
				continue
			for mi in ln.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				if m.mesh == null:
					continue
				var roof := _is_roof(String(m.name))
				var idx := int(asg["roof"]) if roof else int(asg["l%d" % lod])
				if idx < 0 or idx >= mats.size():
					continue
				for si in m.mesh.get_surface_count():
					var sm := m.mesh.surface_get_material(si)
					if sm != null and sm.resource_path == base_path:
						_applied.append([m, si, m.get_surface_override_material(si)])
						m.set_surface_override_material(si, mats[idx])
						applied_surfaces += 1
						lod_surfaces[str(lod)] += 1
						if roof:
							roof_surfaces += 1
