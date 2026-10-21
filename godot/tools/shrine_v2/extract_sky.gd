extends SceneTree
## 一次性：從舊神社場景抽出 天象系統（太陽／月亮／天空環境＋sky_system.gd）存成 gen/sky_rig.tscn，
## 讓新場景沿用同一組天空與光照設定，不必載入整個舊場景。
## godot --headless --path godot --script res://tools/shrine_v2/extract_sky.gd

const OLD := "res://maps/shrine/shrine.tscn"
const OUT := "res://maps/shrine_v2/gen/sky_rig.tscn"


func _init() -> void:
	_run.call_deferred()


func _own(n: Node, o: Node) -> void:
	for c in n.get_children():
		c.owner = o
		_own(c, o)


func _run() -> void:
	var ps := load(OLD) as PackedScene
	var old := ps.instantiate()
	var sky := old.get_node("天象系統")
	print("[SKY] 找到 ", sky.name, " 子節點：", sky.get_children().map(func(c): return c.name))
	var copy := sky.duplicate(Node.DUPLICATE_USE_INSTANTIATION | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS)
	_own(copy, copy)
	var pk := PackedScene.new()
	var e := pk.pack(copy)
	var e2 := ResourceSaver.save(pk, OUT)
	print("[SKY] pack=%d save=%d -> %s" % [e, e2, OUT])
	old.free()
	copy.free()
	quit()
