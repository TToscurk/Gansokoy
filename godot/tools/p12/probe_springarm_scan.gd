extends SceneTree
## P12 Wave 1（只讀、headless）：Population 加入 2.46 s の容疑＝npc_population_actor.gd _ready の
## get_tree().root.find_children("*", "SpringArm3D") 全樹走査 ×51。村を木に入れた状態で 1 回の走査コストを測る。
const SCENE := "res://maps/village_v2/village_v2.tscn"

func _init() -> void:
	_run.call_deferred()

func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c

func _run() -> void:
	var ps := ResourceLoader.load(SCENE) as PackedScene
	var v := ps.instantiate()
	var pop := v.get_node("Population")
	var idx := pop.get_index()
	v.remove_child(pop)
	root.add_child(v)
	await process_frame
	var nodes := _count(root)
	var ts := []
	for i in 3:
		var a := Time.get_ticks_usec()
		var arms := root.find_children("*", "SpringArm3D", true, false)
		ts.append((Time.get_ticks_usec() - a) / 1000.0)
	var a2 := Time.get_ticks_usec()
	v.add_child(pop)
	v.move_child(pop, idx)
	var pop_ms := (Time.get_ticks_usec() - a2) / 1000.0
	print("[P12ARM] 木の節点 %d（Population 除く）・root.find_children(SpringArm3D) 1 回 %.1f / %.1f / %.1f ms → ×51 ≈ %.0f ms；Population 同期加入 %.0f ms" % [
		nodes, ts[0], ts[1], ts[2], ts[1] * 51.0, pop_ms])
	quit(0)
