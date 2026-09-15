extends SceneTree
## Contract: Machi visual chunks are independently loadable and wrapper references them.

const CHUNKS := [
	"res://maps/slice/gen/machi_waterworks.tscn",
	"res://maps/slice/gen/machi_bank_dressing.tscn",
]
const WRAPPER := "res://maps/slice/gen/machi_streamed.tscn"

func _init() -> void:
	for path: String in CHUNKS:
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("Missing Machi chunk %s" % path)
			quit(1)
			return
		var instance := packed.instantiate()
		if instance.get_child_count() == 0:
			push_error("Empty Machi chunk %s" % path)
			quit(2)
			return
		print("[MACHI TEST] %s: %d root branches" % [path, instance.get_child_count()])
		instance.free()
	var wrapper := load(WRAPPER) as PackedScene
	if wrapper == null:
		push_error("Missing Machi wrapper")
		quit(3)
		return
	var proxy := wrapper.instantiate()
	if not proxy.get_script() is Script:
		push_error("Machi wrapper has no streamer")
		quit(4)
		return
	proxy.free()
	print("[MACHI TEST] streaming contract passed")
	quit(0)
