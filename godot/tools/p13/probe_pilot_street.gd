extends SceneTree
## P13 W1（只讀）：試作候補棟の StreetP10 物件（building meta）と高さ、棟の root 相対 transform、現 Kit の LOD0 AABB（棟ローカル）。
const IDS := ["B_P_MKT_003", "B_P_MKT_004", "B_P_MKT_005", "B_P_MKT_006", "B_P_MKT_007", "B_P_MKT_008",
	"B_P_MKT_018", "B_P_MKT_019", "B_P_MKT_020", "B_P_MKT_021", "B_P_MKT_009", "B_P_MKT_010", "B_P_MKT_022"]

func _init() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	var st := v.get_node("Props/StreetP10")
	var per := {}
	for n in st.find_children("*", "Node3D", true, false):
		if n.has_meta("building"):
			var b := String(n.get_meta("building"))
			if b in IDS:
				var p := _rel(n as Node3D, v).origin
				per[b] = per.get(b, []) + ["%s@y%.2f" % [n.name, p.y]]
	for id in IDS:
		var body := v.find_child(id, true, false) as Node3D
		var kit := body.get_node("Kit") as Node3D
		var ab := AABB()
		var first := true
		for mi: MeshInstance3D in kit.get_node("LOD0").get_children():
			var a := (mi.transform * mi.mesh.get_aabb()) if mi.mesh else AABB()
			ab = a if first else ab.merge(a)
			first = false
		var hi := (per.get(id, []) as Array).filter(func(s: String) -> bool: return float(s.get_slice("@y", 1)) - body.position.y > 2.2)
		print("[PS] %s kit_aabb x %.2f..%.2f z %.2f..%.2f top %.2f | street %d 件 高所(>2.2) %s" % [id, ab.position.x, ab.end.x, ab.position.z, ab.end.z, ab.end.y, (per.get(id, []) as Array).size(), str(hi)])
	v.free()
	quit(0)

func _rel(n: Node3D, top: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != top:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
