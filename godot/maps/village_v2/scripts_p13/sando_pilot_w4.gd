extends Node3D
## P13 Wave 4 参道試作 overlay `SandoPilotW4P13`（生成: tools/p13/build_w4_pilot.gd、lib: tools/village_v2_sando_w4_lib.gd）。
## 見た目だけ：ShrineApproachP10/StoneSteps の mesh を「r8 から試作区間を除いたもの」に差し替え、区間は子 `W4Steps`（不規則な踏面・踊り場・笠石・石垣）と
## `W4Soil`（石垣の根元の土の裾＝地形と同じ材質）が描く。
## 碰撞は一切持たない・触れない（斜坡碰撞 RampCollision/Ramp、鳥居、燈籠、相機、玩家は r8 のまま）。
## enabled=false → StoneSteps の元の mesh へ戻し、子を隠す（同じ場景で Before／After を切り替えられる）。場景ファイルは書き換えない。
@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			apply(v)
@export var steps_path: NodePath = NodePath("../ShrineApproachP10/StoneSteps")
@export var soil_material_from: NodePath = NodePath("../Terrain/MainTerrain")
@export var rest_mesh: Mesh

var _orig_mesh: Mesh
var _steps: MeshInstance3D


func _ready() -> void:
	apply.call_deferred(enabled)


func apply(on: bool) -> void:
	for c in get_children():
		if c is Node3D:
			(c as Node3D).visible = on
	var soil := get_node_or_null("W4Soil") as MeshInstance3D
	if soil != null and soil.material_override == null:
		# 土の裾は地形と同じ ShaderMaterial（world XZ 投影・頂点ウェイト）を共有＝地形の材質を後で調整しても追従する
		var tm := get_node_or_null(soil_material_from) as MeshInstance3D
		if tm != null and tm.material_override != null:
			soil.material_override = tm.material_override
		else:
			var fb := StandardMaterial3D.new()
			fb.albedo_color = Color(0.30, 0.22, 0.15)
			fb.roughness = 1.0
			soil.material_override = fb
	if _steps == null:
		_steps = get_node_or_null(steps_path) as MeshInstance3D
	if _steps == null:
		return
	if on:
		if _orig_mesh == null:
			_orig_mesh = _steps.mesh
		if rest_mesh != null:
			_steps.mesh = rest_mesh
	elif _orig_mesh != null:
		_steps.mesh = _orig_mesh
