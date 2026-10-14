extends Node3D
## P13 Wave 7 TASK 3（使用者 2026-10-14 承認）：P8 EarthBanks（田埂土・220 件）と周辺地形の亮度差の局部補正 overlay。
## 根因：village_v2 farmland_visual.gd `_bund_soil_mat`＝同じ P7 ground shader の ground_k を 0.19 × 1.6 ＝ 0.304（埂坡は背光側が多い想定の補償）。
##   実機 TPS では埂土が隣の地形より平均 +19 %（luma 比 中央値 1.19）明るく浮く。
## 方法：元の共用材質（farmland_p8.scn::ShaderMaterial_ko36i）には触れず、**複製**した材質の ground_k だけを変えて、EarthBanks 直下 MeshInstance3D の
##   material_override にだけ差し替える（他の節点が同じ材質を共有していても影響しない）。水利の幾何・水面・坡降・碰撞・伏越し・竜骨車・P8 ファイルは不変。
## enabled=false で元の材質に戻る。
@export var bank_path := "Districts/FarmlandEast/FarmlandP8/EarthBanks"
@export var ground_k := 0.21
@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			apply(v)

var _orig := {}   # MeshInstance3D → 元の material_override
var applied := 0


func _ready() -> void:
	if enabled:
		apply.call_deferred(true)


func apply(on: bool) -> void:
	for mi in _orig.keys():
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_override = _orig[mi]
	_orig.clear()
	applied = 0
	if not on:
		return
	var par := get_parent()
	var bank := par.get_node_or_null(NodePath(bank_path)) if par != null else null
	if bank == null:
		return
	var cache := {}   # 元の材質 → 複製
	for c in bank.get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		var src := mi.material_override as ShaderMaterial
		if src == null or src.shader == null:
			continue
		if not cache.has(src):
			var d := src.duplicate() as ShaderMaterial
			d.set_shader_parameter("ground_k", ground_k)
			d.resource_name = "EarthBank_tone_p13"
			cache[src] = d
		_orig[mi] = src
		mi.material_override = cache[src]
		applied += 1
