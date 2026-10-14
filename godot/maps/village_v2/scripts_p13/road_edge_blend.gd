extends Node3D
## P13 Wave 6 RoadEdgeBlendP13（overlay `RoadEdgeBlendP13`，由 tools/p13/w6/build_w6_road_edge.gd 產生）。
##
## 根因：道路帶（Roads/**）是一片等寬、邊緣筆直的 ribbon，用 ground.gdshader 繪製——ribbon 邊緣到地形（草）之間
## 沒有任何材質過渡。P10 R5a 已對 5 條外圍道路（FarmPath_1／4、CrossStreetSouth、RiversidePath、HillApproach）套用
## 「外緣侵蝕」（ground_p10_pilot.gdshader 的 edge_w／edge_irreg／edge_core：沿路低頻起伏＋草舌＋0.4 m 草混色），
## 其餘外圍道路（CrossStreetMid、HillFootStreet、RiverNorthPath、EntranceRoad、FarmPath_2／3／5）仍是裸邊，
## 在草地旁形成長直線（實測 CrossStreetMid 東端 路 RGB 126,110,85 對 草 81,86,58，ΔRGB≈45，像尺切出來的邊）。
##
## 修正：把「已核准的同一個 pilot shader＋同一組參數語彙」套到這些道路的 material_override（逐一複製原材質的 shader 參數，
## 再寫侵蝕參數）。只改執行期材質，不改任何 mesh／資源檔／封存雜湊；enabled=false 即還原原材質。與 GroundPilotP10 同一做法。
## 村內主街／巷道不動（它們的邊緣由 frontage 與 GroundcoverP9 Macro 地被接住）。
@export var pilot_shader: Shader
@export var road_paths: PackedStringArray = PackedStringArray()
@export var road_params: Array[Dictionary] = []
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
	for i in road_paths.size():
		var mi := par.get_node_or_null(NodePath(road_paths[i])) as MeshInstance3D
		if mi == null or not (mi.material_override is ShaderMaterial):
			continue
		var src := mi.material_override as ShaderMaterial
		if src.shader == pilot_shader:
			continue      # 既に pilot shader（他の overlay が処理済み）なら触らない
		var m := _clone(src, pilot_shader)
		var prm: Dictionary = road_params[i] if i < road_params.size() else {}
		for k in prm:
			m.set_shader_parameter(String(k), prm[k])
		_orig.append([mi, src])
		mi.material_override = m
		applied += 1
