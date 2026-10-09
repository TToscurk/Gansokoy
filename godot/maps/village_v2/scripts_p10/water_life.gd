extends Node3D
## P10 R5b Water Pilot（overlay `WaterLifeP10`，由 tools/village_v2_water_life_lib.gd 產生）。
## ROUND 3：水車 2＝純動力水車。揚水部材なし（ROUND 1／2 の柄杓の掛け替え・P8 木部の調暗は撤去）。
## R5b.1（2026-10-10）：P8 の高架落とし樋は P8 生成器側で撤去・竜骨車へ置換。本 overlay は P8 のノードに一切触れない
##   （ROUND 3 の runtime 非表示／碰撞停止は撤去）。
## enabled=false → 本 overlay を隠し碰撞を止める。
@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			apply(v)


func _ready() -> void:
	# enabled=false で読み込まれた時も apply(false)（ROUND 2 の修正を継承）
	apply.call_deferred(enabled)


func apply(on: bool) -> void:
	for c in get_children():
		if c is Node3D:
			(c as Node3D).visible = on
		for b in c.find_children("*", "CollisionShape3D", true, false):
			(b as CollisionShape3D).disabled = not on
