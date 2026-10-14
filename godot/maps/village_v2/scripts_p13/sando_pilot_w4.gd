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
## P13 W5C：参道の歩く幅に載っている封存済み ForestP9 の植物〔Near の節点＋遠景 MultiMesh の 1 インスタンス〕を実行時だけ隠す。
## 封存ファイル（forest_p9.scn）は書き換えない。enabled=false で元に戻る。[{near, name, origin, far, far_index}]（生成器が計算して書く）
@export var suppress_plants: Array = []

var _orig_mesh: Mesh
var _steps: MeshInstance3D
var _far_saved := {}


func _ready() -> void:
	apply.call_deferred(enabled)


func _apply_plants(on: bool) -> void:
	var host := get_parent()
	if host == null:
		return
	for e in suppress_plants:
		var near := host.get_node_or_null(NodePath(String(e["near"]))) as Node3D
		if near != null:
			near.visible = not on
		var far_path := String(e.get("far", ""))
		var idx := int(e.get("far_index", -1))
		if far_path == "" or idx < 0:
			continue
		var mmi := host.get_node_or_null(NodePath(far_path)) as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null or idx >= mmi.multimesh.instance_count:
			continue
		var key := far_path + "#" + str(idx)
		if on:
			if not _far_saved.has(key):
				_far_saved[key] = mmi.multimesh.get_instance_transform(idx)
			var orig: Transform3D = _far_saved[key]
			mmi.multimesh.set_instance_transform(idx, Transform3D(Basis().scaled(Vector3.ZERO), orig.origin))
		elif _far_saved.has(key):
			mmi.multimesh.set_instance_transform(idx, _far_saved[key])


func apply(on: bool) -> void:
	_apply_plants(on)
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
