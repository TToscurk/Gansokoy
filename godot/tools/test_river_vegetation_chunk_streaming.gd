extends SceneTree
## Contract: all river vegetation bands load independently; wrapper has streamer.

const CHUNKS := [
	"res://maps/slice/gen/river_vegetation_south.tscn",
	"res://maps/slice/gen/river_vegetation_lower.tscn",
	"res://maps/slice/gen/river_vegetation_upper.tscn",
	"res://maps/slice/gen/river_vegetation_north.tscn",
]
const WRAPPER := "res://maps/slice/gen/river_vegetation_streamed.tscn"

func _init() -> void:
	for path: String in CHUNKS:
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("Missing river vegetation chunk %s" % path)
			quit(1)
			return
		var instance := packed.instantiate()
		if instance.get_child_count() == 0:
			push_error("Empty river vegetation chunk %s" % path)
			quit(2)
			return
		var crest_count := 0
		for row: Node in instance.get_children():
			for child: Node in row.get_children():
				if child.name.begins_with("Crest"):
					crest_count += 1
		if crest_count == 0:
			push_error("No clipped crest paths in %s" % path)
			quit(5)
			return
		print("[RIVER TEST] %s: %d scatter rows, %d crest paths" % [path, instance.get_child_count(), crest_count])
		instance.free()
	var wrapper := load(WRAPPER) as PackedScene
	if wrapper == null:
		push_error("Missing river vegetation wrapper")
		quit(3)
		return
	var proxy := wrapper.instantiate()
	if not proxy.get_script() is Script:
		push_error("River vegetation wrapper has no streamer")
		quit(4)
		return
	proxy.free()
	print("[RIVER TEST] streaming contract passed")
	quit(0)
