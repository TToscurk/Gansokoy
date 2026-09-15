extends SceneTree
## Split the reviewed B1 source scene without regenerating or changing it.
## Re-run this after an intentional edit to b1_street.tscn.

const SOURCE := "res://maps/slice/gen/b1_street.tscn"
const OUT := {
	"north": "res://maps/slice/gen/b1_north.tscn",
	"central": "res://maps/slice/gen/b1_central.tscn",
	"south": "res://maps/slice/gen/b1_south.tscn",
	"support": "res://maps/slice/gen/b1_support.tscn",
}

func _init() -> void:
	var packed := ResourceLoader.load(SOURCE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		push_error("[B1 chunks] cannot load source")
		quit(1)
		return
	var source := packed.instantiate() as Node3D
	var buckets := {
		"north": _root("B1_North"),
		"central": _root("B1_Central"),
		"south": _root("B1_South"),
		"support": _root("B1_Support"),
	}
	for child in source.get_children():
		source.remove_child(child)
		_set_owner_recursive(child, null)
		var target: Node3D = buckets[_key_for(child as Node3D)]
		target.add_child(child)
		_set_owner_recursive(child, target)
	for key in OUT:
		var out := PackedScene.new()
		var pack_err := out.pack(buckets[key])
		var save_err := ResourceSaver.save(out, OUT[key]) if pack_err == OK else pack_err
		if save_err != OK:
			push_error("[B1 chunks] write %s failed: %d" % [key, save_err])
			quit(save_err)
			return
	print("[B1 chunks] north=%d central=%d south=%d support=%d" % [
		buckets["north"].get_child_count(), buckets["central"].get_child_count(),
		buckets["south"].get_child_count(), buckets["support"].get_child_count()])
	quit(0)

func _root(name: String) -> Node3D:
	var node := Node3D.new()
	node.name = name
	return node

func _key_for(node: Node3D) -> String:
	if node.name == "StreetPaving":
		return "support"
	if node.name == "PlazaMarket":
		return "central"
	if node.position.z < 0.0:
		return "north"
	if node.position.z < 46.0:
		return "central"
	return "south"

func _set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		_set_owner_recursive(child, owner)
