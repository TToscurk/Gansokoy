extends RefCounted

## Module declarations that are not yet part of town_modules.json.
## Measured dimensions are guarded by tools/asset_dims_check.gd.
const PHASE5A_FAMILIES := {
	"family_standard_machiya_02": {"w": 9.56, "d": 11.60, "h": 5.42, "fw": 9.56, "fd": 11.60, "glb": "res://assets/models/family_standard_machiya_02.glb"},
	"family_standard_machiya_03": {"w": 7.96, "d": 12.61, "h": 5.72, "fw": 7.96, "fd": 12.61, "glb": "res://assets/models/family_standard_machiya_03.glb"},
	"family_small_merchant_01": {"w": 7.16, "d": 9.70, "h": 4.87, "fw": 7.16, "fd": 9.70, "glb": "res://assets/models/family_small_merchant_01.glb"},
	"family_small_merchant_03": {"w": 10.74, "d": 11.70, "h": 4.62, "fw": 10.74, "fd": 11.70, "glb": "res://assets/models/family_small_merchant_03.glb"},
	"family_kura_compact": {"w": 7.30, "d": 8.09, "h": 5.95, "fw": 7.30, "fd": 8.09, "glb": "res://assets/models/family_kura_compact.glb"},
	# These sizes are measured from the Godot AABB of each joined mesh. Never
	# edit them by hand: re-measure and update the asset dimension gate instead.
	"asset_proof_hatago": {"w": 9.90, "d": 13.20, "h": 7.30, "fw": 9.90, "fd": 13.20, "centered": true, "glb": "res://assets/models/asset_proof_hatago.glb"},
	"asset_proof_sake_shop": {"w": 13.20, "d": 9.36, "h": 5.30, "fw": 13.20, "fd": 9.36, "centered": true, "glb": "res://assets/models/asset_proof_sake_shop.glb"},
	"asset_proof_workshop": {"w": 11.11, "d": 9.88, "h": 6.49, "fw": 11.11, "fd": 9.88, "centered": true, "glb": "res://assets/models/asset_proof_workshop.glb"},
}


static func is_house_kind(kind: String) -> bool:
	return kind.begins_with("machiya") or PHASE5A_FAMILIES.has(kind)


static func emit_house_batches(lib, root: Node3D, batches: Dictionary,
		modules: Dictionary, out_dir: String, audit: Array[String]) -> void:
	var group := lib.add(root, Node3D.new(), "町家")
	var total := 0
	var names := batches.keys()
	names.sort()
	for kind in names:
		var transforms: Array = batches[kind]
		var probe: Array = lib.semantic_mesh(String(modules[kind]["glb"]))
		var mesh: Mesh = probe[0]
		if mesh.get_surface_count() > 1:
			audit.append("　%s：語意材質 %d surface %s"
				% [kind, mesh.get_surface_count(), str(probe[1])])
		else:
			mesh = lib.prop_mesh(String(modules[kind]["glb"]))
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = lib.make_multimesh(mesh, transforms, [],
			out_dir + "gen/mm_%s.res" % kind)
		lib.add(group, instance, "MM_%s" % kind)
		total += transforms.size()
	audit.append("町家 %d 棟 / %d 種模組（%d draw call）"
		% [total, names.size(), names.size()])


static func emit_house_collisions(root: Node3D, dump: Array, modules: Dictionary,
		audit: Array[String]) -> void:
	var body := StaticBody3D.new()
	body.name = "町家碰撞"
	root.add_child(body)
	body.owner = root
	var count := 0
	for entry in dump:
		if not is_house_kind(String(entry[0])):
			continue
		var module: Dictionary = modules[entry[0]]
		var yaw: float = entry[4]
		var forward := Vector2(sin(yaw), cos(yaw))
		var center := Vector2(entry[1], entry[3])
		if not bool(module.get("centered", false)):
			center -= forward * (float(module["d"]) * 0.5)
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(module["w"]), float(module["h"]), float(module["d"]))
		collision.shape = box
		collision.position = Vector3(center.x,
			float(entry[2]) + float(module["h"]) * 0.5, center.y)
		collision.rotation.y = yaw
		body.add_child(collision)
		collision.owner = root
		count += 1
	audit.append("町家碰撞箱 %d 個（1 個 StaticBody3D）" % count)
