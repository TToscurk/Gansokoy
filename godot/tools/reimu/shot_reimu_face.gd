extends SceneTree
## 靈夢臉部特寫：三種太陽方向（順光／側光／逆光）＋天空環境光，存一張 3 格圖；並印出臉部材質參數。
## godot --path godot -s res://tools/reimu/shot_reimu_face.gd -- --out=<png> [--nofill]
var out := "D:/神社/shrine/docs/reimu/face_light.png"
var nofill := false
var unshaded := false
var sets := []   # --set=節點.屬性:值（例：FaceNormals.strength:0.5、FaceFill.day_energy:0.1）
var npc: Node3D
var sun: DirectionalLight3D
var cam: Camera3D
var frames := 0
var imgs := []
const SUNS := [Vector3(-35, 20, 0), Vector3(-35, 95, 0), Vector3(-55, 180, 0)]   # 順光／側光／逆光（模型正面 +Z）

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a == "--nofill": nofill = true
		if a == "--unshaded": unshaded = true   # 判斷線條是貼圖畫的還是光影造成的
		if a.begins_with("--set="):
			var kv := a.substr(6).split(":"); var np := kv[0].split(".")
			sets.append([np[0], np[1], str_to_var(kv[1])])
	var w := Node3D.new(); get_root().add_child(w)
	var env := WorldEnvironment.new(); var e := Environment.new()
	var sky := Sky.new(); var sm := ProceduralSkyMaterial.new(); sky.sky_material = sm
	e.background_mode = Environment.BG_SKY; e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e; w.add_child(env)
	sun = DirectionalLight3D.new(); sun.light_energy = 1.2; sun.shadow_enabled = true; w.add_child(sun)
	npc = (load("res://characters/reimu/reimu.tscn") as PackedScene).instantiate()
	npc.set("frozen", true)
	for st in sets: npc.get_node(st[0]).set(st[1], st[2])
	w.add_child(npc)
	if nofill and npc.has_node("FaceFill"): npc.get_node("FaceFill").queue_free()
	cam = Camera3D.new(); cam.fov = 22; w.add_child(cam); cam.current = true
	get_root().size = Vector2i(600, 700)

func _process(_d: float) -> bool:
	frames += 1
	var sk: Skeleton3D = npc.find_child("GeneralSkeleton", true, false)
	if frames == 3:
		var h := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin
		cam.look_at_from_position(h + Vector3(0.05, 0.06, 0.75), h + Vector3(0, 0.07, 0))
		for mi in npc.find_children("*", "MeshInstance3D", true, false):
			var m: MeshInstance3D = mi
			for s in m.mesh.get_surface_count():
				var mat := m.get_active_material(s)
				if mat is StandardMaterial3D:
					var sm: StandardMaterial3D = mat
					if unshaded:
						var u := sm.duplicate() as StandardMaterial3D; u.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.set_surface_override_material(s, u)
					print("MAT %s/%d %s rough %.2f metal %.2f spec %.2f normal %s ao %s rim %s shading %d" % [m.name, s, sm.resource_name, sm.roughness, sm.metallic, sm.metallic_specular, sm.normal_enabled, sm.ao_enabled, sm.rim_enabled, sm.shading_mode])
	var idx := (frames - 10) / 8
	if frames >= 10 and (frames - 10) % 8 == 0 and idx < SUNS.size():
		sun.rotation_degrees = SUNS[idx]
	if frames >= 10 and (frames - 10) % 8 == 7 and idx < SUNS.size():
		imgs.append(get_root().get_texture().get_image())
		if imgs.size() == SUNS.size():
			var W: int = imgs[0].get_width(); var H: int = imgs[0].get_height()
			var all := Image.create(W * 3, H, false, imgs[0].get_format())
			for i in 3: all.blit_rect(imgs[i], Rect2i(0, 0, W, H), Vector2i(W * i, 0))
			all.save_png(out); print("SAVED ", out); quit(0)
	return false
