extends SceneTree
## 把委製石階套件（_lod/*.glb）的網格抽成獨立 .res，讓場景以 MeshInstance3D＋外部網格引用（不攤平進 .tscn、不多一層 GLB 實例）。
##   godot --headless --path godot --script res://tools/shrine_v2/build_kit.gd
## 產出 assets/shrine_v2/kit/<name>.res（含 Godot 自動 LOD 與原材質）＋ kit.json（各件 AABB，供生成器取尺寸）。

const OUT := "res://assets/shrine_v2/kit/"
const PIECES := {
	"tread": "res://assets/_lod/踏石.glb",
	"landing": "res://assets/_lod/平台石.glb",
	"sleeve": "res://assets/_lod/袖石垣.glb",
	"cap": "res://assets/_lod/收頭石.glb",
}


func _init() -> void:
	_run.call_deferred()


func _find_mi(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return n
	for c in n.get_children():
		var r := _find_mi(c)
		if r != null:
			return r
	return null


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var info := {}
	for k in PIECES:
		var ps := load(PIECES[k]) as PackedScene
		var inst := ps.instantiate()
		var mi := _find_mi(inst)
		var mesh := mi.mesh as ArrayMesh
		# 節點相對根的變換（GLB 內可能有位移）
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != inst:
			if cur is Node3D:
				xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var bb := xf * mesh.get_aabb()
		var e := ResourceSaver.save(mesh, OUT + k + ".res")
		info[k] = {"pos": [bb.position.x, bb.position.y, bb.position.z],
			"size": [bb.size.x, bb.size.y, bb.size.z],
			"node_xf_origin": [xf.origin.x, xf.origin.y, xf.origin.z],
			"surfaces": mesh.get_surface_count()}
		print("[KIT] %s err=%d size=%s node_origin=%s surfs=%d" % [k, e, bb.size, xf.origin, mesh.get_surface_count()])
		inst.free()
	var f := FileAccess.open(OUT + "kit.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "  "))
	f.close()
	quit()
