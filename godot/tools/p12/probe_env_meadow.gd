extends SceneTree
## P12 Final Cleanup A2（只讀、headless）：ENV の MeadowP9 規劃株再計算を、ENV と同じ前処理で
## 「現状」と「P11 R2D 支線（R5-3 封存後に追加）を除いた状態」の 2 通りで出す。
const MD := preload("res://tools/village_v2_meadow_lib.gd")
const BR := "Districts/FarmlandEast/FarmlandP8/ZoneWorks/ZoneIrrigation/Branches"

func _init() -> void:
	_run.call_deferred()

func _count(hide_br: bool) -> int:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	for nm in ["Props/EnvironmentP9", "Vegetation/GroundcoverP9", "Vegetation/MeadowP9"]:
		var o := v.get_node_or_null(nm)
		if o:
			o.get_parent().remove_child(o)
			o.free()
	if hide_br:
		var b := v.get_node(BR) as Node3D
		b.visible = false
	root.add_child(v)
	await physics_frame
	var Pm: Dictionary = MD.base_plan(v)
	var MC := MD.context(Pm, v)
	var Fm := MD.fields(Pm, MC)
	var Mm := MD.plan(Pm, MC, Fm)
	var n := (Mm["p"] as PackedVector2Array).size()
	v.queue_free()
	await process_frame
	return n

func _run() -> void:
	var a := await _count(false)
	var b := await _count(true)
	print("[ENVM] 規劃株：現状 %d／R2D Branches 不可視 %d（R5-3 封存 114105）" % [a, b])
	quit(0)
