extends StaticBody3D
class_name TrainingDummy
## Martial arts training post (木人樁) for testing combat hits, sound, sparks, and hitstop.

const CombatVFX = preload("res://characters/yoriichi/vfx/combat_vfx.gd")

@export var max_health := 1000.0
var health := 1000.0

@onready var visual_root: Node3D = $Visual
@onready var post_mesh: MeshInstance3D = $Visual/Post
var _initial_transform: Transform3D
var _wobble_tween: Tween = null
var _flash_tween: Tween = null


func _ready() -> void:
	if visual_root:
		_initial_transform = visual_root.transform
	add_to_group("hittable")


func take_hit(hit_data: Dictionary) -> void:
	var damage: float = float(hit_data.get("damage", 10.0))
	var hit_pos: Vector3 = hit_data.get("hit_pos", global_position + Vector3(0, 1, 0))
	var hit_dir: Vector3 = hit_data.get("hit_dir", -global_transform.basis.z)
	var heavy: bool = bool(hit_data.get("heavy", false))

	health = maxf(health - damage, 0.0)

	# 1. Spawn VFX sparks
	CombatVFX.spawn_hit_spark(self, hit_pos, -hit_dir, heavy)

	# 2. Physics wobble / tilt reaction
	if visual_root:
		if _wobble_tween and _wobble_tween.is_valid():
			_wobble_tween.kill()
		_wobble_tween = create_tween()
		var tilt_axis := hit_dir.cross(Vector3.UP).normalized()
		var tilt_angle := deg_to_rad(15.0 if heavy else 8.0)
		var tilted_basis := Basis(tilt_axis, tilt_angle) * _initial_transform.basis

		_wobble_tween.tween_property(visual_root, "transform:basis", tilted_basis, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_wobble_tween.tween_property(visual_root, "transform:basis", Basis(tilt_axis, -tilt_angle * 0.4) * _initial_transform.basis, 0.12).set_trans(Tween.TRANS_SINE)
		_wobble_tween.tween_property(visual_root, "transform:basis", _initial_transform.basis, 0.20).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	# 3. Hit flash
	if post_mesh and post_mesh.material_override:
		var mat := post_mesh.material_override as StandardMaterial3D
		if mat:
			if _flash_tween and _flash_tween.is_valid():
				_flash_tween.kill()
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.8, 0.4) if heavy else Color(1.0, 0.9, 0.8)
			mat.emission_energy_multiplier = 3.0
			_flash_tween = create_tween()
			_flash_tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.12)
