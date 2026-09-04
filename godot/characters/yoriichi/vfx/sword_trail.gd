extends MeshInstance3D
class_name SwordTrail3D
## Procedural ribbon slash trail for Yoriichi's katana.
## Uses ImmediateMesh with additive blending, emitting fiery sun-breathing
## gradient arcs along the blade's sweep path.

@export var base_node: Node3D
@export var tip_node: Node3D
@export var lifetime := 0.20
@export var min_distance := 0.04
@export var tip_color := Color(1.0, 0.92, 0.45, 0.95)   # Golden core
@export var base_color := Color(1.0, 0.25, 0.05, 0.70)  # Fiery orange/crimson

var is_emitting := false
var _segments: Array[Dictionary] = []
var _imm_mesh: ImmediateMesh
var _mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_imm_mesh = ImmediateMesh.new()
	mesh = _imm_mesh
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.vertex_color_use_as_albedo = true
	material_override = _mat


func start_trail() -> void:
	is_emitting = true
	_segments.clear()
	if tip_node and base_node:
		_segments.append({
			"tip": tip_node.global_position,
			"base": base_node.global_position,
			"age": 0.0
		})


func stop_trail() -> void:
	is_emitting = false


func _process(delta: float) -> void:
	# Age points
	var i := 0
	while i < _segments.size():
		_segments[i].age += delta
		if _segments[i].age >= lifetime:
			_segments.remove_at(i)
		else:
			i += 1

	# Sample new point if emitting
	if is_emitting and tip_node and base_node:
		var cur_tip: Vector3 = tip_node.global_position
		var cur_base: Vector3 = base_node.global_position
		var should_add := true
		if not _segments.is_empty():
			var last_tip: Vector3 = _segments.back().tip
			if cur_tip.distance_squared_to(last_tip) < (min_distance * min_distance):
				should_add = false
		if should_add:
			_segments.append({
				"tip": cur_tip,
				"base": cur_base,
				"age": 0.0
			})

	# Rebuild mesh
	_imm_mesh.clear_surfaces()
	if _segments.size() < 2:
		return

	_imm_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _mat)
	var n := _segments.size()
	for idx in range(n):
		var seg: Dictionary = _segments[idx]
		var t: float = clampf(seg.age / lifetime, 0.0, 1.0)
		# Smooth ease out
		var alpha: float = (1.0 - t) * (1.0 - t)
		var c_tip := tip_color
		c_tip.a *= alpha
		var c_base := base_color
		c_base.a *= alpha

		_imm_mesh.surface_set_color(c_base)
		_imm_mesh.surface_set_uv(Vector2(float(idx) / float(n - 1), 0.0))
		_imm_mesh.surface_add_vertex(seg.base)

		_imm_mesh.surface_set_color(c_tip)
		_imm_mesh.surface_set_uv(Vector2(float(idx) / float(n - 1), 1.0))
		_imm_mesh.surface_add_vertex(seg.tip)

	_imm_mesh.surface_end()
