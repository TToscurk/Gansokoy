extends SceneTree
## Contract for the B1 visual chunks. Run after tools/split_b1_chunks.gd.

const CHUNKS := [
	"res://maps/slice/gen/b1_north.tscn",
	"res://maps/slice/gen/b1_central.tscn",
	"res://maps/slice/gen/b1_south.tscn",
]
const WRAPPER := "res://maps/slice/gen/b1_streamed.tscn"

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	for path in CHUNKS:
		var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if packed == null:
			push_error("[b1 chunks] missing chunk " + path)
			failures += 1
			continue
		var instance := packed.instantiate()
		var visual_roots := instance.get_child_count()
		if visual_roots < 2 or visual_roots > 25:
			push_error("[b1 chunks] unsafe root count %d in %s" % [visual_roots, path])
			failures += 1
		instance.free()
	var wrapper := ResourceLoader.load(WRAPPER, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if wrapper == null:
		push_error("[b1 chunks] missing streamed wrapper")
		failures += 1
	elif not (wrapper.instantiate() as Node).has_method("_load_one"):
		push_error("[b1 chunks] streamed wrapper has no chunk loader")
		failures += 1
	if failures == 0:
		print("[b1 chunks] PASS: %d chunks and streamed wrapper are loadable" % CHUNKS.size())
	quit(failures)

func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total
