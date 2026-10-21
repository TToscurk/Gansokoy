extends SceneTree
## 把一個場景所有 MeshInstance3D 的頂點（走完整 transform 鏈）傾倒成 float32 xyz 檔，給 Python 做切片分析。
##   godot --headless --path godot --script res://tools/shrine_v2/dump_verts.gd -- --scene=<res path> --out=<file.f32>
## 每個 mesh 最多取樣 120000 個頂點（均勻抽樣），避免巨檔。

func _init() -> void:
	_run.call_deferred()


func _walk(n: Node, xf: Transform3D, out: PackedFloat32Array) -> void:
	var cur := xf
	if n is Node3D:
		cur = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mesh := (n as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var stride := maxi(1, v.size() / 120000)
			var i := 0
			while i < v.size():
				var w := cur * v[i]
				out.append(w.x)
				out.append(w.y)
				out.append(w.z)
				i += stride
	for c in n.get_children():
		_walk(c, cur, out)


func _run() -> void:
	var scene := ""
	var outp := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene = a.substr(8)
		elif a.begins_with("--out="):
			outp = a.substr(6)
	var ps := load(scene) as PackedScene
	var inst := ps.instantiate()
	var out := PackedFloat32Array()
	_walk(inst, Transform3D.IDENTITY, out)
	var f := FileAccess.open(outp, FileAccess.WRITE)
	f.store_buffer(out.to_byte_array())
	f.close()
	print("[DUMP] %s -> %s  verts=%d" % [scene, outp, out.size() / 3])
	quit()
