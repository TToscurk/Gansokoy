extends Node3D
## 鞘中刀：只畫刀柄＋鍔，刀身（刀本地 y > clip_y）丟棄。
## 原因：刀身彎度比鞘大（刀 7.9%、新鞘 2.6%），刀身放進鞘裡會從鞘背穿出；刀身本來就該被鞘蓋住，乾脆不畫。
## 沿用 GLB 原材質的貼圖（albedo／normal／roughness+metallic），不另存貼圖。

@export var clip_y := 0.135

const SHADER := preload("res://characters/yoriichi/sheath_v2/sword_hilt_only.gdshader")

func _ready() -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var src := m.get_active_material(0) as StandardMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = SHADER
		sm.set_shader_parameter("clip_y", clip_y)
		if src != null:
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
			sm.set_shader_parameter("albedo_color", src.albedo_color)
			sm.set_shader_parameter("normal_tex", src.normal_texture)
			sm.set_shader_parameter("use_normal", src.normal_enabled and src.normal_texture != null)
			sm.set_shader_parameter("orm_tex", src.roughness_texture)
			sm.set_shader_parameter("roughness", src.roughness)
			sm.set_shader_parameter("metallic", src.metallic)
		m.material_override = sm
