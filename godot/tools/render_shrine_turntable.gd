extends SceneTree
## 委製資產四向轉台圖：判斷哪一面是正面（階梯／入口／水盤朝哪）。
## 憲法第 5 條：截圖是視覺證據，不是量測來源——這裡只用來定朝向。
##
##   Godot --path godot --script tools/render_shrine_turntable.gd -- --out=<dir>

const TARGETS := [
	"res://assets/_lod/踏石.glb",
	"res://assets/_lod/_t0.02.glb",
	"res://assets/_lod/_t0.01.glb",
]
const ANGLES := [
	{"name": "z+", "dir": Vector3(0, 0, 1)},
	{"name": "x+", "dir": Vector3(1, 0, 0)},
	{"name": "z-", "dir": Vector3(0, 0, -1)},
	{"name": "x-", "dir": Vector3(-1, 0, 0)},
]

var _out := "D:/神社/shrine/_review/tt2"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)

	var world := Node3D.new()
	root.add_child(world)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.60, 0.66)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.60, 0.64, 0.70)
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = e
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	world.add_child(sun)
	sun.global_position = Vector3(6, 14, 6)
	sun.look_at(Vector3.ZERO, Vector3.UP)

	var cam := Camera3D.new()
	cam.fov = 40.0
	world.add_child(cam)
	cam.current = true

	for path in TARGETS:
		var ps := ResourceLoader.load(path, "PackedScene") as PackedScene
		if ps == null:
			print("[TT] 載入失敗 ", path)
			continue
		var inst := ps.instantiate() as Node3D
		world.add_child(inst)
		await process_frame
		var bb := _aabb_of(inst)
		var c := bb.get_center()
		var r := bb.size.length() * 0.5
		var label: String = ("lod_" if "_lod" in path else "") + String(path).get_file().get_basename()
		for a in ANGLES:
			var d: Vector3 = a["dir"]
			cam.global_position = c + (d * 2.3 + Vector3(0, 0.75, 0)) * r
			cam.look_at(c, Vector3.UP)
			for i in 4:
				await process_frame
			var img := root.get_texture().get_image()
			var p := "%s/%s_%s.png" % [_out, label, a["name"]]
			img.save_png(p)
			print("[TT] %s" % p)
		inst.queue_free()
		await process_frame

	print("[TT] done")
	quit(0)


func _aabb_of(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(n):
		var b := mi.global_transform * mi.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
