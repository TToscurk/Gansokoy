extends SceneTree
## Measure where the audit probe targets ACTUALLY are today, so
## audit_slice_collision.gd's probe table can be rewritten from evidence.
## Prints, for each named node: world AABB centre + size, and the hull body
## (if any) under 建物碰撞 whose name starts with it.
##
## Run: godot --headless --path godot --script tools/probe_audit_targets.gd

const TARGETS := [
	"B1_Street/machiya_西_00", "B1_Street/komachiya_東_00", "B1_Street/kura_東_09",
	"B1_Street/shouka_西_03", "B1_Street/shouka_東_02",
	"B1_Street/大鳥居", "倉庫", "倉庫2",
	"MachiCanal/VillageStoneBank", "MachiCanal",
	"鯢吞亭", "霧雨店", "鈴奈庵", "寺子屋", "龍石像橋",
]

var _main: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	_main.load_map("slice", "")
	for i in 6:
		await physics_frame
	var map: Node = _main.map_root
	print("玩家出生點 (%.1f, %.2f, %.1f)" % [
		_main.player.global_position.x, _main.player.global_position.y, _main.player.global_position.z])

	for t in TARGETS:
		var n := map.get_node_or_null(t)
		if n == null:
			print("%-32s 不存在" % t)
			continue
		var b := _aabb(n)
		var c := b.get_center()
		print("%-32s 中心(%.1f, %.2f, %.1f) 尺寸(%.1f × %.1f × %.1f)  底 %.2f" % [
			t, c.x, c.y, c.z, b.size.x, b.size.y, b.size.z, b.position.y])

	print("── 建物碰撞 中與探針目標同名的 body ──")
	var bc := map.get_node_or_null("建物碰撞")
	if bc:
		for c in bc.get_children():
			var nm := String(c.name)
			for t in TARGETS:
				var leaf: String = String(t).get_file()
				if nm.begins_with(leaf):
					var cs: CollisionShape3D = c.get_child(0)
					var hb: AABB = cs.global_transform * cs.shape.get_debug_mesh().get_aabb()
					var hc := hb.get_center()
					print("  %-44s 中心(%.1f, %.2f, %.1f) 尺寸(%.1f × %.1f × %.1f)" % [
						nm, hc.x, hc.y, hc.z, hb.size.x, hb.size.y, hb.size.z])
					break

	print("── 地面碰撞_刷筆用 ──")
	var gc := map.get_node_or_null("地面碰撞_刷筆用")
	if gc:
		for c in gc.get_children():
			var cs: CollisionShape3D = c.get_child(0)
			var hb: AABB = cs.global_transform * cs.shape.get_debug_mesh().get_aabb()
			var hc := hb.get_center()
			print("  %-36s 中心(%.1f, %.2f, %.1f) 尺寸(%.1f × %.1f × %.1f) layer=%d" % [
				c.name, hc.x, hc.y, hc.z, hb.size.x, hb.size.y, hb.size.z, c.collision_layer])
	print("done")
	quit(0)


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _find(n, "MeshInstance3D"):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _find(n: Node, cls: String) -> Array:
	var out := []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(_find(c, cls))
	return out
