extends "res://scripts/npc_activity_overlay.gd"
## P10 R3e：Population/OuterP10 の住人へ R3c／R3c.1 封存 vocabulary を割り当てる私有 overlay（封存 overlay を継承、対象と割り当て表だけ差し替え）。
const OUTER := preload("res://tools/village_v2_population_outer_lib.gd")


func initialize():
	population = get_parent().get_node_or_null(OUTER.NODE_NAME)
	if population == null:
		push_error("[ACT-OUTER] missing Population/%s" % OUTER.NODE_NAME)
		return
	for path in OUTER.ASSIGN:
		var a: Array = OUTER.ASSIGN[path]
		var actor := population.get_node_or_null(path)
		if actor == null:
			push_error("[ACT-OUTER] missing actor " + path)
			return
		var npc: Node = actor.get_node("NPC")
		var ap: AnimationPlayer = npc.player
		var lib := ap.get_animation_library(&"").duplicate() as AnimationLibrary
		var baseline := lib.get_animation(StringName(a[3]))
		var opt: Dictionary = a[4] if a.size() > 4 else {}
		var clip: Animation = load(ROOT_ANIM + a[1] + "/" + a[2] + "_grounded.res")
		if clip == null or clip.get_track_count() < 30:
			push_error("[ACT-OUTER] invalid clip " + path)
			return
		lib.remove_animation(StringName(a[3]))
		lib.add_animation(StringName(a[3]), clip)
		ap.remove_animation_library(&"")
		ap.add_animation_library(&"", lib)
		var sk := npc.find_child("GeneralSkeleton", true, false) as Skeleton3D
		var e := {"path": path, "type": a[0], "actor": actor, "npc": npc, "ap": ap, "sk": sk, "lib": lib, "baseline": baseline,
			"slot": a[3], "clip": clip, "prop": null, "prop_kind": "", "opt": opt}
		if a[0] == "Carry":
			var cr: Array = opt.get("crate", ["res://assets/village_v2/suzu_kit/mesh/sz_hako.res", 0.30, 0.20])
			e.prop = mesh_prop(cr[0])
			e.prop_kind = "crate"
			e.crate_dh = Vector2(cr[1], cr[2])
		elif a[0] == "Sit":
			e.prop = mesh_prop(String(opt.get("seat", "res://assets/village_v2/suzu_kit/mesh/sz_stool.res")))
			e.prop_kind = "stool"
			e.bench = opt.has("seat")
			e.body = StaticBody3D.new()
			e.body.collision_layer = 1
			e.body.collision_mask = 0
			add_child(e.body)
			for i in 5:
				var cs := CollisionShape3D.new()
				cs.shape = BoxShape3D.new()
				e.body.add_child(cs)
		elif a[0] == "Drink":
			e.prop = tea_cup()
			add_child(e.prop)
			e.prop_kind = "cup"
		entries.append(e)
		npc.play_clip(npc.animation, float(npc.start_time))
	update_props()
	print("[ACT-OUTER] outer overlay ", entries.size(), " assignments; outer population ", population.find_children("*", "AnimatableBody3D", true, false).size())
