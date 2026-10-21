extends SceneTree
## 診斷視角：直接載入 shrine_v2.tscn（自帶天空／光），依 JSON 逐張拍照；可隱藏指定群組、可用正交俯視。
##   godot --path godot --resolution 1280x720 --script res://tools/shrine_v2/diag_view.gd -- --shots=<json> --out=<dir> [--map=res://maps/shrine_v2/shrine_v2.tscn]
## JSON 項目：{"name","cam":[x,y,z],"look":[x,y,z],"hide":["樹木","下層植栽"],"ortho":60,"fov":60}
## 注意：只有天空光；沒有玩家／HUD。時間固定正午（天象系統預設）。

var _shots: Array = []
var _out := "D:/神社/shrine/_review/shrine_v2/diag"
var _map := "res://maps/shrine_v2/shrine_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = JSON.parse_string(FileAccess.get_file_as_string(a.substr(8)))
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--map="):
			_map = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var world := Node3D.new()
	root.add_child(world)
	var scene := (load(_map) as PackedScene).instantiate()
	world.add_child(scene)
	var cam := Camera3D.new()
	cam.far = 4000.0
	world.add_child(cam)
	cam.current = true
	for i in 12:
		await process_frame
	for sh in _shots:
		var hidden: Array = []
		var water_old: Material = null
		var water_node := scene.get_node_or_null("池塘水面") as MeshInstance3D
		if sh.get("flat_water", false) and water_node != null:
			water_old = water_node.material_override
			var fm := StandardMaterial3D.new()
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fm.albedo_color = Color(0.0, 0.45, 1.0)
			fm.cull_mode = BaseMaterial3D.CULL_DISABLED
			water_node.material_override = fm
		for hn in sh.get("hide", []):
			var n := scene.get_node_or_null(String(hn))
			if n != null:
				(n as Node3D).visible = false
				hidden.append(n)
		var c: Array = sh["cam"]
		var l: Array = sh["look"]
		cam.global_position = Vector3(c[0], c[1], c[2])
		var up := Vector3.UP
		if absf(Vector3(l[0] - c[0], l[1] - c[1], l[2] - c[2]).normalized().dot(Vector3.UP)) > 0.98:
			up = Vector3.FORWARD
		cam.look_at(Vector3(l[0], l[1], l[2]), up)
		if sh.has("ortho"):
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = float(sh["ortho"])
		else:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = float(sh.get("fov", 60.0))
		for i in 8:
			await process_frame
		root.get_texture().get_image().save_png("%s/%s.png" % [_out, sh["name"]])
		print("[DIAG] ", sh["name"])
		for n in hidden:
			(n as Node3D).visible = true
		if water_old != null:
			water_node.material_override = water_old
	quit()
