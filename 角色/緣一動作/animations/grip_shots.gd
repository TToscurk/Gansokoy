extends SceneTree
# Sword grip tuning: render candidate Sword_Hand local transforms from a
# close-up camera to infer the hand-bone axes, then refine.
# Usage: edit CANDIDATES, run, inspect 角色/gameplay_bugfix_review/grip_tuning/.

const OUT := "D:/神社/shrine-yoriichi/角色/gameplay_bugfix_review/grip_tuning/"

# label -> Transform3D（Sword_Hand 相對 HandSocket 的 local transform）
var CANDIDATES := {
	"identity_007": Transform3D(Basis(), Vector3(0, 0.07, 0)),
	"identity_012": Transform3D(Basis(), Vector3(0, 0.12, 0)),
	"identity_017": Transform3D(Basis(), Vector3(0, 0.17, 0)),
}

class Driver extends Node:
	var chr: CharacterBody3D
	var cams := {}
	var candidates := {}

	func wait(s: float) -> void:
		await get_tree().create_timer(s).timeout

	func shot(name: String) -> void:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
		print("shot ", name)

	func _ready() -> void:
		run()

	func run() -> void:
		await wait(0.8)
		chr.request_draw()
		await wait(1.2)
		var sword: Node3D = chr.find_children("Sword_Hand", "", true, false)[0]
		for label in candidates:
			sword.transform = candidates[label]
			await wait(0.1)
			for view in cams:
				(cams[view] as Camera3D).current = true
				await wait(0.05)
				await shot("%s_%s" % [label, view])
		get_tree().quit()

func _initialize():
	DirAccess.make_dir_recursive_absolute(OUT)
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(10, 0.2, 10)
	cs.shape = bs
	floor_body.add_child(cs)
	floor_body.position.y = -0.1
	level.add_child(floor_body)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	level.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.6, 0.65, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.8)
	env.environment = e
	level.add_child(env)
	var chr: CharacterBody3D = (load("res://yoriichi_character_meshy_full.tscn") as PackedScene).instantiate()
	chr.position = Vector3(0, 0.5, 0)
	level.add_child(chr)

	var d := Driver.new()
	d.chr = chr
	d.candidates = CANDIDATES
	# 三視角近距相機：front（+Z 看向角色正面）、side（右側 -X）、three_quarter
	var views := {
		"front": [Vector3(0, 1.0, 2.0), Vector3(-0.2, 0.8, 0)],
		"side": [Vector3(-2.0, 1.0, 0.3), Vector3(-0.1, 0.8, 0.1)],
		"three_quarter": [Vector3(-1.5, 1.2, 1.6), Vector3(-0.2, 0.8, 0)],
	}
	for v in views:
		var cam := Camera3D.new()
		var pos: Vector3 = views[v][0]
		var target: Vector3 = views[v][1]
		cam.transform = Transform3D(Basis.looking_at(target - pos, Vector3.UP), pos)
		cam.fov = 40
		level.add_child(cam)
		d.cams[v] = cam
	root.add_child(d)
