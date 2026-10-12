extends Node3D
## P13 W3 土渠美術樣本（overlay `CanalSampleP13`、root 直下）。T0 支線 伏越し出口→末端の 1 区間だけ。
## _ready：封存 farmland_p8.scn の土渠メッシュ／水面メッシュを記憶體内で差し替え（頂点重み・水面材質だけ；幾何・高さ・碰撞は不変）。
## enabled=false で元のメッシュへ戻す。封存ファイルは書かない。
const CS := preload("res://tools/village_v2_canal_sample_lib.gd")

@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			_apply_sample(v)

var _keep := {}


func _ready() -> void:
	_apply_sample.call_deferred(enabled)


func _apply_sample(on: bool) -> void:
	var v := get_parent() as Node3D
	if not _keep.is_empty():
		CS.restore(v, _keep)
		_keep = {}
	if on:
		_keep = CS.apply(v, "fix")
		set_meta("applied_earth_verts", int(_keep.get("earth_verts", 0)))
		set_meta("applied_water_tris", int(_keep.get("water_tris", 0)))


func _exit_tree() -> void:
	if not _keep.is_empty():
		CS.restore(get_parent() as Node3D, _keep)
		_keep = {}
