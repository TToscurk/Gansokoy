extends Node3D
## P10 R6b Shrine Approach Pilot（overlay `ShrineApproachP10`，由 tools/village_v2_shrine_approach_lib.gd 產生）。
## _ready：參道 ribbon 換成 ground pilot shader 的複本（外緣侵蝕＋石段範圍挖洞 cut_s／cut_hw）；enabled=false → 隱藏石段／鳥居／燈籠、
## 停用碰撞（含斜坡碰撞帶）、ribbon 還原。只改執行期，不改任何資源檔。
const GP := preload("res://maps/village_v2/scripts_p10/ground_pilot.gd")
const PILOT_SHADER := "res://maps/village_v2/shaders_p10/ground_p10_pilot.gdshader"
@export var ribbon_path: NodePath
@export var ribbon_params: Dictionary = {}
@export var cut_s := Vector2.ZERO
@export var cut_hw := 0.0
@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			apply(v)

var _orig: Material
var _ribbon: MeshInstance3D
var swapped := false


func _ready() -> void:
	# ROUND 2：enabled=false で読み込まれた時も apply(false)（石段・燈籠を隠し斜坡碰撞を止める）。
	# r1–r8 は enabled の時だけ apply → 掛載ノードに enabled=false を書いても斜坡碰撞が残っていた。
	apply.call_deferred(enabled)


func apply(on: bool) -> void:
	for c in get_children():
		if c is Node3D:
			(c as Node3D).visible = on
		for b in c.find_children("*", "CollisionShape3D", true, false):
			(b as CollisionShape3D).disabled = not on
		if c is CollisionObject3D:
			for b in c.get_children():
				if b is CollisionShape3D:
					(b as CollisionShape3D).disabled = not on
	if _ribbon == null:
		_ribbon = get_parent().get_node_or_null(ribbon_path) as MeshInstance3D
	if _ribbon == null:
		return
	if on:
		if not swapped and _ribbon.material_override is ShaderMaterial:
			_orig = _ribbon.material_override
			var m := GP._clone(_orig as ShaderMaterial, load(PILOT_SHADER))
			for k in ribbon_params:
				m.set_shader_parameter(String(k), ribbon_params[k])
			m.set_shader_parameter("cut_s", cut_s)
			m.set_shader_parameter("cut_hw", cut_hw)
			_ribbon.material_override = m
			swapped = true
	else:
		if swapped and _orig:
			_ribbon.material_override = _orig
		swapped = false
