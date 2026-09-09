extends Node3D
## 掉落的小果實 —— 逃跑妖怪留下的東西。程序化：紅色小球 + 一片葉。
## 讓玩家看到「它們留下的不是武器」。

func _ready() -> void:
	var b := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 14
	sm.rings = 8
	b.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.82, 0.16, 0.14)
	m.roughness = 0.35
	b.material_override = m
	b.position.y = 0.09
	add_child(b)
	var leaf := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.05)
	leaf.mesh = qm
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.32, 0.55, 0.22)
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf.material_override = lm
	leaf.position = Vector3(0.02, 0.19, 0.0)
	leaf.rotation_degrees = Vector3(-60, 20, 0)
	add_child(leaf)
