extends SceneTree
## 風系統工前盤點：把「會被風影響」的來源節點與材質列成事實清單。
## 用法（不需要顯示；只讀 mesh／material 資料，MultiMesh 只讀 instance_count）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path godot \
##     --script res://tools/wind/inspect_wind_sources.gd -- --scene=res://maps/village_v2/village_v2.tscn
## 注意：headless 的 MultiMesh transform 全是 0，這裡不看位置，只看數量與材質。

const DEFAULT_SCENES := [
	"res://maps/village_v2/village_v2.tscn",
	"res://maps/beast_path/s01_entrance.tscn",
]

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var scenes := DEFAULT_SCENES
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scenes = [a.substr(8)]
	for path in scenes:
		_dump(String(path))
	quit(0)

func _dump(path: String) -> void:
	var t0 := Time.get_ticks_msec()
	var ps := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if ps == null:
		print("!! 載入失敗 ", path)
		return
	var root := ps.instantiate()
	print("\n===== ", path, " =====")
	var mi := 0
	var mmi := 0
	var veg_mi := 0
	var veg_mmi := 0
	var mats := {}          # key -> {nodes, kind, shader, surfs}
	var mesh_users := {}    # mesh res path -> count
	var noren := []         # noren 節點細節
	_walk(root, func(n: Node):
		if n is MultiMeshInstance3D:
			mmi += 1
			var m := (n as MultiMeshInstance3D)
			var key := _mat_key(m.material_override if m.material_override else _mm_material(m))
			var e: Dictionary = mats.get(key, {"nodes": 0, "inst": 0, "kind": "mm"})
			e["nodes"] += 1
			if m.multimesh:
				e["inst"] += m.multimesh.instance_count
			mats[key] = e
		elif n is MeshInstance3D:
			mi += 1
			var m2 := n as MeshInstance3D
			var mesh: Mesh = m2.mesh
			var shared := "%s" % [mesh.resource_path if mesh else "<none>"]
			mesh_users[shared] = int(mesh_users.get(shared, 0)) + 1
			var key2 := _mat_key(m2.material_override if m2.material_override else (mesh.surface_get_material(0) if mesh and mesh.get_surface_count() > 0 else null))
			var e2: Dictionary = mats.get(key2, {"nodes": 0, "inst": 0, "kind": "mi"})
			e2["nodes"] += 1
			mats[key2] = e2
			if String(n.name).begins_with("nr_noren"):
				noren.append({"node": str(root.get_path_to(n)), "mesh": shared,
					"aabb": str(mesh.get_aabb()) if mesh else "?",
					"mat": key2})
	)
	print("MeshInstance3D=", mi, "  MultiMeshInstance3D=", mmi)
	print("--- 材質（節點數 / MultiMesh 實例數 / 種類） ---")
	var keys := mats.keys()
	keys.sort()
	for k in keys:
		var e: Dictionary = mats[k]
		print("  %-70s nodes=%4d inst=%6d %s" % [k, int(e["nodes"]), int(e.get("inst", 0)), e.get("kind", "")])
	print("--- noren ---")
	for r in noren.slice(0, 12):
		print("  ", r)
	print("  noren 總數=", noren.size())
	print("耗時 ", Time.get_ticks_msec() - t0, " ms")

func _mm_material(m: MultiMeshInstance3D) -> Material:
	if m.material_override:
		return m.material_override
	if m.multimesh and m.multimesh.mesh and m.multimesh.mesh.get_surface_count() > 0:
		return m.multimesh.mesh.surface_get_material(0)
	return null

func _mat_key(m: Material) -> String:
	if m == null:
		return "<null>"
	var p := m.resource_path
	var sh := ""
	if m is ShaderMaterial and (m as ShaderMaterial).shader:
		sh = (m as ShaderMaterial).shader.resource_path.get_file()
	return "%s [%s]" % [p if p != "" else "<embedded:%s>" % m.get_class(), sh]

func _walk(n: Node, fn: Callable) -> void:
	fn.call(n)
	for c in n.get_children():
		_walk(c, fn)
