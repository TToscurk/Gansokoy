extends SceneTree
## x=283.6 z=32.0 的 4.014 m 差在「格點簡化」與「箱體代理」兩種完全不同的
## 做法下數值一模一樣 —— 這代表它不是簡化造成的。查清楚它是什麼。
##
##   Godot --headless --path godot --script tools/probe_weir_hotspot.gd
##
## 手法：對該點做 intersect_ray 的**全部**命中（逐次抬高起點往下打），列出
## 每一層命中的高度。若新舊兩份在同一位置有相同的多層結構、只是首擊順序不同，
## 那就是共面／重疊三角面的排序不定，不是幾何改變。

const NEW := "res://maps/slice/gen/ground_collision.scn"
const OLD := "res://maps/slice/gen/ground_collision_baseline.scn"

const SPOTS := [
	Vector2(283.6, 32.0),
	Vector2(283.6, 32.4),
	Vector2(283.6, 32.2),
	Vector2(282.8, 32.8),
	Vector2(292.8, -15.6),
]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var wn := _world(NEW)
	var wo := _world(OLD)
	for i in 4:
		await physics_frame

	for s in SPOTS:
		print("[SPOT] === x=%.1f z=%.1f ===" % [s.x, s.y])
		print("[SPOT]   新: %s" % _layers(wn, s))
		print("[SPOT]   舊: %s" % _layers(wo, s))
	print("[SPOT] done")
	quit(0)


## 從高處往下逐層打：命中後把起點降到命中點下方一點，繼續打，直到沒有命中。
func _layers(w: World3D, xz: Vector2) -> String:
	var out := PackedStringArray()
	var y := 40.0
	for i in 24:
		var q := PhysicsRayQueryParameters3D.create(
			Vector3(xz.x, y, xz.y), Vector3(xz.x, -40.0, xz.y), 0xFFFFFFFF)
		var hit := w.direct_space_state.intersect_ray(q)
		if hit.is_empty():
			break
		var hy: float = hit["position"].y
		var c: Node = hit["collider"]
		out.append("%.3f(%s)" % [hy, c.name])
		y = hy - 0.001
		if y < -40.0:
			break
	return " → ".join(out) if out.size() > 0 else "（無命中）"


func _world(path: String) -> World3D:
	var packed := ResourceLoader.load(path, "PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var vp := SubViewport.new()
	root.add_child(vp)
	vp.world_3d = World3D.new()
	vp.add_child(packed.instantiate())
	return vp.world_3d
