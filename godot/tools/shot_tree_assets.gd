extends SceneTree
## 把每種樹資產單獨渲染成一張圖，用來認出「三角形葉片的舊式低模樹」。
##   Godot --path godot --script tools/shot_tree_assets.gd

const OUT := "D:/神社/shrine/_review/shrine_trees/"
const LIST := [
	"res://assets/models/tree_round_far.glb",
	"res://assets/vista_lod/針葉樹1_far.glb",
	"res://assets/vista_lod/針葉林樹3_far.glb",
	"res://assets/vista_lod/針葉林樹4_far.glb",
	"res://assets/vista_lod/普通樹_far.glb",
]


func _init() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.72)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.9)
	e.ambient_light_energy = 1.4
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(35.0), 0.0)
	world.add_child(sun)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true

	for p in LIST:
		var ps: PackedScene = load(p)
		if ps == null:
			print("LOAD_FAIL %s" % p)
			continue
		var inst: Node3D = ps.instantiate()
		world.add_child(inst)
		await _wait(4)
		var acc := AABB()
		var has := false
		var faces := 0
		var st: Array = [inst]
		while not st.is_empty():
			var n: Node = st.pop_back()
			st.append_array(n.get_children())
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var b: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).mesh.get_aabb()
				acc = acc.merge(b) if has else b
				has = true
				faces += (n as MeshInstance3D).mesh.get_faces().size() / 3
		var h: float = maxf(acc.size.y, 0.01)
		var ctr: Vector3 = acc.position + acc.size * 0.5
		cam.global_position = ctr + Vector3(0.0, h * 0.12, h * 1.85)
		cam.look_at(ctr, Vector3.UP)
		await _wait(8)
		var nm: String = p.get_file().get_basename()
		root.get_viewport().get_texture().get_image().save_png(OUT + nm + ".png")
		print("SHOT %-14s faces=%6d size=(%.2f,%.2f,%.2f) min_y=%.3f -> %s.png" % [nm, faces, acc.size.x, acc.size.y, acc.size.z, acc.position.y, nm])
		inst.queue_free()
		await _wait(3)
	quit(0)
