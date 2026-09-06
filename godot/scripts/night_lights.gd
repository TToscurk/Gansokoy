@tool
class_name 夜間燈火
extends Node3D
## Switches practical lights on at dusk and off at dawn, and makes the lantern
## meshes themselves emit.
##
## Two separate problems, one node:
##
##   1. The scene's 14 街燈 OmniLight3D nodes burn at full energy around the
##      clock. At noon they are invisible waste; the moment a day-night cycle
##      exists they are simply wrong.
##   2. Turning a light on does not make the lantern LOOK lit. A paper lantern
##      at night is a glowing object, and without emission on its own material
##      it stays a dark shape with a puddle of light beside it — the giveaway
##      of a scene where someone added lights but not emissive materials.
##
## Both are driven from 天象系統's 時刻 so the village lights up on the same
## schedule the sun sets on, rather than a second, drifting clock.
##
## Materials are duplicated per-node before editing: Godot shares imported GLB
## materials across every instance, so writing emission straight onto the mesh
## would light every lantern in the project, including ones in other scenes.

## 燈火開始亮起的時刻（黃昏）。
@export_range(0.0, 24.0, 0.25) var 點燈時刻: float = 17.6

## 燈火完全熄滅的時刻（清晨）。
@export_range(0.0, 24.0, 0.25) var 熄燈時刻: float = 5.8

## 點燈與熄燈的漸變長度（小時）。真實的燈不會瞬間全亮。
@export_range(0.05, 3.0, 0.05) var 漸變小時: float = 0.7

## 燈光最大強度倍率，套在各燈自身的能量上。
@export_range(0.0, 4.0, 0.05) var 亮度倍率: float = 1.0:
	set(v):
		亮度倍率 = v
		_dirty = true

## 燈籠紙罩的自發光強度。這是「燈籠看起來是亮的」的來源。
@export_range(0.0, 8.0, 0.1) var 自發光強度: float = 2.6:
	set(v):
		自發光強度 = v
		_dirty = true

## 燈火顏色。和路燈本身的 light_color 分開，用來統一整村色調。
@export var 燈火顏色: Color = Color(1.0, 0.72, 0.38):
	set(v):
		燈火顏色 = v
		_dirty = true

## 每盞燈的隨機閃爍幅度。0 = 完全穩定。
@export_range(0.0, 0.5, 0.01) var 閃爍幅度: float = 0.07

## 這些名稱片段的 MeshInstance3D 會被加上自發光。
@export var 發光網格關鍵字: PackedStringArray = PackedStringArray([
	"Lantern", "lantern", "燈籠", "行燈", "提灯",
])

@export var 編輯器中即時更新: bool = true

## 有自發光但附近沒有 OmniLight 的燈籠（鯢吞亭鯨燈、霧雨店招牌燈、河岸石燈籠）
## 會自動掛一盞燈，不然晚上只有燈籠本體亮、地上不亮。半徑與能量依燈籠
## AABB 高度縮放：3 m 的鯨燈比 0.6 m 的石燈籠照得遠。
@export var 自動補光: bool = true
## 補光基準：燈籠高 1 m 時的照射半徑（公尺）與能量。
@export_range(1.0, 20.0, 0.5) var 補光半徑每米: float = 4.0
@export_range(0.0, 8.0, 0.1) var 補光能量每米: float = 1.6
## 補光是否投影。石燈籠×5 + 鯨燈 + 招牌燈 = 7 盞；每盞投影一次立方體貼圖。
@export var 補光投影: bool = false

## Object metadata keys must be valid identifiers; a CJK key made set_meta()
## fail on every lamp ("Invalid metadata identifier", 18x per scan), so no
## base energy was ever stored and every light silently fell back to 1.0.
const META_BASE_ENERGY := &"night_light_base_energy"

var _lights: Array[Light3D] = []
var _emissive: Array[MeshInstance3D] = []
var _phase: Array[float] = []
var _dirty := true
var _last_level := -1.0
var _sky: Node = null


func _ready() -> void:
	_collect()
	_dirty = true
	set_process(true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not 編輯器中即時更新:
		return
	if _lights.is_empty():
		_collect()

	var level := _target_level()
	# Only push values when something actually changed, or this walks 14 lights
	# and their materials every single frame for nothing.
	if absf(level - _last_level) > 0.002 or _dirty:
		_apply(level)
		_last_level = level
		_dirty = false

	if 閃爍幅度 > 0.001 and level > 0.01 and not Engine.is_editor_hint():
		_flicker(delta, level)


## 找出天象系統，讀它的時刻。找不到就用自己的預設。
func _current_hour() -> float:
	if _sky == null or not is_instance_valid(_sky):
		_sky = _find_sky(_scene_root())
	if _sky != null and is_instance_valid(_sky):
		var h = _sky.get("時刻")
		if h != null:
			return float(h)
	return 12.0


## Resolve the scene root the same way in editor, game and headless. Relying on
## get_tree().current_scene alone returns null when the scene is instantiated
## manually (which every headless verification does), and the rig then silently
## never finds the sky.
func _scene_root() -> Node:
	var r: Node = null
	if Engine.is_editor_hint():
		r = get_tree().get_edited_scene_root()
	if r == null:
		r = get_tree().current_scene
	if r == null:
		var n: Node = self
		while n.get_parent() != null and n.get_parent() != get_tree().root:
			n = n.get_parent()
		r = n
	return r


func _find_sky(node: Node) -> Node:
	if node == null:
		return null
	# Match on the exported property rather than the script path: script
	# resource_path comparisons break for instanced/packed scenes and are the
	# reason the first version reported "找不到天象系統" while the node was
	# right there in the tree.
	if node.get("時刻") != null and node.get("天氣") != null:
		return node
	for c in node.get_children():
		var r := _find_sky(c)
		if r != null:
			return r
	return null


## 0 = 全暗，1 = 全亮。跨午夜的時段要特別處理，不能單純比大小。
func _target_level() -> float:
	var h := _current_hour()
	var f: float = maxf(漸變小時, 0.01)

	# Distance past the switch-on time, wrapping at 24.
	var 亮起進度: float = clampf(fposmod(h - 點燈時刻, 24.0) / f, 0.0, 1.0)
	# Distance past the switch-off time.
	var 熄滅進度: float = clampf(fposmod(h - 熄燈時刻, 24.0) / f, 0.0, 1.0)

	# Night is the window from 點燈 to 熄燈, crossing midnight.
	var 夜長 := fposmod(熄燈時刻 - 點燈時刻, 24.0)
	var 自點燈起 := fposmod(h - 點燈時刻, 24.0)
	var 在夜裡 := 自點燈起 <= 夜長

	if 在夜裡:
		# Ramp up just after 點燈, ramp down just before 熄燈.
		var 到熄燈 := 夜長 - 自點燈起
		return minf(亮起進度, clampf(到熄燈 / f, 0.0, 1.0))
	return 0.0


func _collect() -> void:
	_lights.clear()
	_emissive.clear()
	_phase.clear()

	_walk(_scene_root())

	# A stable per-light phase so they do not all flicker in lockstep.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260903
	for i in _lights.size():
		_phase.append(rng.randf() * TAU)

	if 自動補光:
		_add_fill_lights(rng)


## Lanterns whose mesh glows but which have no practical light nearby get one.
## "Nearby" = any collected OmniLight/SpotLight within the lantern's own AABB
## height — the 街燈 poles keep their hand-placed 光 child.
func _add_fill_lights(rng: RandomNumberGenerator) -> void:
	for mi in _emissive:
		if not is_instance_valid(mi) or mi.mesh == null:
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		var h: float = maxf(box.size.y, 0.3)
		var centre := box.get_center()
		var has_light := false
		for l in _lights:
			if is_instance_valid(l) and l.global_position.distance_to(centre) < maxf(h, 2.0):
				has_light = true
				break
		if has_light:
			continue
		# One light per lantern mesh, named so a re-collect finds it again.
		var existing := mi.get_node_or_null("補光")
		var fill: OmniLight3D = existing as OmniLight3D
		if fill == null:
			fill = OmniLight3D.new()
			fill.name = "補光"
			mi.add_child(fill)
		# Put it at the upper third of the lantern (where the flame is), in
		# the mesh's local space so it rides scale/rotation.
		var local_top := mi.get_aabb().position + mi.get_aabb().size * Vector3(0.5, 0.7, 0.5)
		fill.position = local_top
		fill.light_color = 燈火顏色
		fill.omni_range = 補光半徑每米 * h
		fill.omni_attenuation = 1.4
		fill.light_energy = 補光能量每米 * h
		fill.shadow_enabled = 補光投影
		fill.set_meta(META_BASE_ENERGY, fill.light_energy)
		_lights.append(fill)
		_phase.append(rng.randf() * TAU)


func _walk(node: Node) -> void:
	# Never touch the sun/moon: they belong to 天象系統.
	if node is DirectionalLight3D:
		return
	if node is OmniLight3D or node is SpotLight3D:
		var l := node as Light3D
		if not l.has_meta(META_BASE_ENERGY):
			l.set_meta(META_BASE_ENERGY, l.light_energy)
		_lights.append(l)
	elif node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for key in 發光網格關鍵字:
			if _name_chain_has(mi, key):
				_emissive.append(mi)
				break
	for c in node.get_children():
		_walk(c)


## Lantern meshes are usually named generically (mesh_node) inside a parent that
## carries the real name, so check the ancestry rather than the leaf alone.
func _name_chain_has(node: Node, key: String) -> bool:
	var n: Node = node
	var depth := 0
	while n != null and depth < 4:
		if String(n.name).findn(key) != -1:
			return true
		n = n.get_parent()
		depth += 1
	return false


func _apply(level: float) -> void:
	for l in _lights:
		if not is_instance_valid(l):
			continue
		var base: float = float(l.get_meta(META_BASE_ENERGY, 1.0))
		l.light_energy = base * level * 亮度倍率
		l.visible = l.light_energy > 0.004

	var e := 燈火顏色 * (自發光強度 * level)
	for mi in _emissive:
		if not is_instance_valid(mi):
			continue
		var mat := mi.get_surface_override_material(0)
		if mat == null:
			var base_mat := mi.mesh.surface_get_material(0) if mi.mesh else null
			# Duplicate before writing: imported GLB materials are shared, and
			# editing one in place would light every copy of this lantern
			# everywhere in the project.
			mat = base_mat.duplicate() if base_mat else StandardMaterial3D.new()
			mi.set_surface_override_material(0, mat)
		if mat is BaseMaterial3D:
			var bm := mat as BaseMaterial3D
			bm.emission_enabled = level > 0.01
			bm.emission = 燈火顏色
			bm.emission_energy_multiplier = 自發光強度 * level
			# Meshy lamp models are ONE mesh / ONE material: pole, bracket and
			# paper shade share surface 0. A flat emission therefore lit the whole
			# iron pole white (路燈_08 screenshot, 2026-09-03). Route emission
			# through the base-colour texture instead: the shade is painted
			# bright warm, the pole dark, so the albedo itself is the mask.
			# emission_operator MULTIPLY makes it emission_colour × albedo,
			# and the dark pole multiplies to ~0.
			if bm.albedo_texture != null:
				bm.emission_texture = bm.albedo_texture
				bm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY


func _flicker(_delta: float, level: float) -> void:
	var t := float(Time.get_ticks_msec()) * 0.001
	for i in _lights.size():
		var l := _lights[i]
		if not is_instance_valid(l) or not l.visible:
			continue
		var base: float = float(l.get_meta(META_BASE_ENERGY, 1.0))
		# Two incommensurate sines read as an organic flame rather than a pulse.
		var f := sin(t * 2.7 + _phase[i]) * 0.6 + sin(t * 6.1 + _phase[i] * 1.7) * 0.4
		l.light_energy = base * level * 亮度倍率 * (1.0 + f * 閃爍幅度)


## 給外部呼叫：重新掃描場景中的燈（新增燈籠後用）。
func 重新掃描() -> void:
	_collect()
	_dirty = true
