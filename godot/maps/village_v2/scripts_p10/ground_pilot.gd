extends Node3D
## P10 R5a Ground Pilot（overlay `GroundPilotP10`，由 tools/village_v2_ground_pilot_lib.gd 產生）。
## _ready：Terrain 段（田格修正）與 Pilot 道路（外緣侵蝕）的 material_override 換成 pilot shader 的 ShaderMaterial 複本
## （逐一複製原材質的 shader 參數，再寫 pilot 參數）。enabled=false 還原原材質。只改執行期覆寫，不改任何資源檔。
@export var pilot_shader: Shader
@export var terrain_paths: PackedStringArray = PackedStringArray()
@export var road_paths: PackedStringArray = PackedStringArray()
@export var road_params: Array[Dictionary] = []
@export var farm_soil := 0.32
@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			apply(v)

var _orig: Array = []   # [MeshInstance3D, 原 material_override]
var applied := 0


func _ready() -> void:
	if enabled:
		apply.call_deferred(true)


static func _clone(src: ShaderMaterial, sh: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = src.render_priority
	for u in src.shader.get_shader_uniform_list():
		var nm := String(u["name"])
		var v = src.get_shader_parameter(nm)
		if v != null:
			m.set_shader_parameter(nm, v)
	return m


func apply(on: bool) -> void:
	for o in _orig:
		if is_instance_valid(o[0]):
			(o[0] as MeshInstance3D).material_override = o[1]
	_orig.clear()
	applied = 0
	if not on or pilot_shader == null:
		return
	var par := get_parent()
	var cache := {}
	for p in terrain_paths:
		var mi := par.get_node_or_null(NodePath(p)) as MeshInstance3D
		if mi == null or not (mi.material_override is ShaderMaterial):
			continue
		var src := mi.material_override as ShaderMaterial
		if not cache.has(src):
			var m := _clone(src, pilot_shader)
			m.set_shader_parameter("farm_soil", farm_soil)
			cache[src] = m
		_orig.append([mi, src])
		mi.material_override = cache[src]
		applied += 1
	for i in road_paths.size():
		var mi := par.get_node_or_null(NodePath(road_paths[i])) as MeshInstance3D
		if mi == null or not (mi.material_override is ShaderMaterial):
			continue
		var src := mi.material_override as ShaderMaterial
		var m := _clone(src, pilot_shader)
		var prm: Dictionary = road_params[i] if i < road_params.size() else {}
		for k in prm:
			m.set_shader_parameter(String(k), prm[k])
		_orig.append([mi, src])
		mi.material_override = m
		applied += 1
