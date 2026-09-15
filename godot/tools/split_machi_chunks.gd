extends SceneTree
## Split the authored MachiCanal scene without editing its source scene.
## Collisions are independently baked in ground_collision.scn and stay resident.

const SOURCE := "res://maps/slice/prototypes/waterway_art_review.tscn"
const OUTPUTS := {
	"res://maps/slice/gen/machi_waterworks.tscn": [
		"ChannelGeometry", "VillageStoneBank", "Waterworks", "PaddyFields", "BankRailing",
	],
	"res://maps/slice/gen/machi_bank_dressing.tscn": [
		"TakeFence", "Grove", "BankTalus", "CopingGrass", "BankMasonry",
	],
}

func _init() -> void:
	var source := load(SOURCE) as PackedScene
	if source == null:
		push_error("Missing %s" % SOURCE)
		quit(1)
		return
	var authored := source.instantiate() as Node3D
	for out_path in OUTPUTS:
		var chunk := Node3D.new()
		chunk.name = out_path.get_file().get_basename().capitalize()
		for child_name: String in OUTPUTS[out_path]:
			var child := authored.get_node_or_null(child_name)
			if child == null:
				push_error("Missing root branch %s" % child_name)
				quit(2)
				return
			authored.remove_child(child)
			chunk.add_child(child)
			_set_owner_recursive(child, chunk)
		var packed := PackedScene.new()
		var pack_error := packed.pack(chunk)
		if pack_error != OK:
			push_error("Pack failed %s: %d" % [out_path, pack_error])
			quit(3)
			return
		var save_error := ResourceSaver.save(packed, out_path)
		if save_error != OK:
			push_error("Save failed %s: %d" % [out_path, save_error])
			quit(4)
			return
		print("[MACHI SPLIT] %s <- %s" % [out_path, ", ".join(OUTPUTS[out_path])])
	authored.free()
	quit(0)

func _set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		_set_owner_recursive(child, owner)
