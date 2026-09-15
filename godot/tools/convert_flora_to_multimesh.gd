extends SceneTree
## 把 /slice/灌木叢 底下大量重複的小型植物個體（三葉草、花瓣、灌木等）
## 從各自獨立的 Node3D+MeshInstance3D 轉成共用的 MultiMeshInstance3D，
## 大幅減少場景節點數（object/node_count）。
##
## 保留不轉的（手擺樣板，維持可單獨選取）：
##   /slice/灌木叢/樹木、/slice/灌木叢/枯木、/slice/灌木叢/鋪路石、
##   /slice/灌木叢/Bush_Common_Flowers2（頂層唯一一顆）
##
## 轉換來源：
##   /slice/灌木叢 直接子節點：Clover_12 / Clover_22 / Plant_1_Big2 /
##     Flower_4_Single2 / Bush_Common2
##   /slice/灌木叢/花瓣 子節點：Petal_42 / Petal_52
##   /slice/灌木叢/灌木叢（巢狀同名容器）子節點：Bush_Common2 / Bush_Common_Flowers2
##
## 執行後直接覆寫 res://maps/slice/slice.tscn。執行前必須確認編輯器內該場景
## 沒有未存檔的手動修改（會被這次寫入覆蓋）。

const FLORA_NAMES: Array[String] = [
	"Petal_42", "Petal_52", "Clover_12", "Clover_22",
	"Plant_1_Big2", "Flower_4_Single2", "Bush_Common2", "Bush_Common_Flowers2",
]

const SCENE_PATH := "res://maps/slice/slice.tscn"


func _init() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("載入失敗：%s" % SCENE_PATH)
		quit(1)
		return

	var root: Node3D = packed.instantiate()

	var bushes: Node3D = root.get_node_or_null("灌木叢") as Node3D
	if bushes == null:
		push_error("找不到 /slice/灌木叢 節點")
		root.free()
		quit(1)
		return

	var containers: Array = [bushes]
	var nested_flower := bushes.get_node_or_null("花瓣")
	var nested_bush := bushes.get_node_or_null("灌木叢")
	if nested_flower != null:
		containers.append(nested_flower)
	if nested_bush != null:
		containers.append(nested_bush)

	# base_name -> Array[Node3D]（來源容器節點，待刪除）
	var collected: Dictionary = {}

	for container in containers:
		for child in container.get_children():
			if not (child is Node3D):
				continue
			var base := _strip_suffix(String(child.name))
			if not FLORA_NAMES.has(base):
				continue
			# 頂層唯一一顆 Bush_Common_Flowers2 保留當手擺樣板
			if container == bushes and base == "Bush_Common_Flowers2":
				continue
			if not collected.has(base):
				collected[base] = []
			(collected[base] as Array).append(child)

	var bushes_inv: Transform3D = _manual_global_transform(bushes, root).affine_inverse()
	# 第一階段：只讀 transform、建 MultiMesh，先不動原始節點——
	# 確保任何一批的座標全部落在原點（headless 樹外的典型失敗徵兆）都能
	# 在刪除任何東西之前被擋下來。
	var plan: Array = []  # [{base, nodes, mm, mmi}]
	var skipped: Array = []
	var origin_hits_total: int = 0
	var pos_samples_total: int = 0

	for base_name in collected.keys():
		var nodes: Array = collected[base_name]
		if nodes.size() < 2:
			skipped.append("%s(僅%d顆,跳過)" % [base_name, nodes.size()])
			continue

		var sample_mi := _find_mesh_instance(nodes[0])
		if sample_mi == null or sample_mi.mesh == null:
			skipped.append("%s(找不到mesh,跳過)" % base_name)
			continue

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = sample_mi.mesh
		mm.instance_count = nodes.size()

		var origin_hits: int = 0
		var flat := PackedFloat32Array()
		flat.resize(nodes.size() * 12)
		for i in nodes.size():
			var n: Node3D = nodes[i]
			var local_xform: Transform3D = bushes_inv * _manual_global_transform(n, root)
			_write_xform_to_buffer(flat, i * 12, local_xform)
			pos_samples_total += 1
			if local_xform.origin.length() < 0.001:
				origin_hits += 1
		# headless 模式下 set_instance_transform() 只寫進假渲染器，不會落進
		# 可序列化的 .buffer——必須直接賦值 buffer 屬性才會真正存進場景檔。
		mm.buffer = flat
		origin_hits_total += origin_hits

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "MM_" + base_name
		mmi.multimesh = mm
		mmi.cast_shadow = sample_mi.cast_shadow
		mmi.gi_mode = sample_mi.gi_mode

		plan.append({"base": base_name, "nodes": nodes, "mmi": mmi})

	# 驗證關卡：如果絕大多數實例的本地座標落在原點附近，
	# 這是 global_transform 讀取失敗的訊號（上次事故的根因），
	# 直接中止、不刪節點、不存檔。
	var origin_ratio: float = 0.0
	if pos_samples_total > 0:
		origin_ratio = float(origin_hits_total) / float(pos_samples_total)
	print("[convert_flora] 驗證：%d/%d 個實例本地座標落在原點附近（比例 %.1f%%）"
			% [origin_hits_total, pos_samples_total, origin_ratio * 100.0])
	if origin_ratio > 0.05:
		push_error("[convert_flora] 中止：座標讀取異常（%.1f%% 落在原點），疑似樹外讀取失敗——未刪除任何節點、未存檔。"
				% (origin_ratio * 100.0))
		root.free()
		quit(1)
		return

	# 第二階段：驗證通過，才真正刪除原始節點並掛上新的 MultiMeshInstance3D。
	var total_converted: int = 0
	for entry in plan:
		var nodes: Array = entry["nodes"]
		for n in nodes:
			n.get_parent().remove_child(n)
			n.free()
		total_converted += nodes.size()
		bushes.add_child(entry["mmi"])
		entry["mmi"].owner = root

	print("[convert_flora] 轉換節點數：%d 顆 -> %d 個 MultiMeshInstance3D" % [total_converted, plan.size()])
	if skipped.size() > 0:
		print("[convert_flora] 跳過：%s" % ", ".join(skipped))

	var out := PackedScene.new()
	var pack_err := out.pack(root)
	if pack_err != OK:
		push_error("pack 失敗：%d" % pack_err)
		root.free()
		quit(1)
		return

	var save_err := ResourceSaver.save(out, SCENE_PATH)
	if save_err != OK:
		push_error("save 失敗：%d" % save_err)
		root.free()
		quit(1)
		return

	print("[convert_flora] 已存檔：%s" % SCENE_PATH)
	root.free()
	quit()


func _strip_suffix(n: String) -> String:
	var idx := n.rfind(" (")
	if idx == -1:
		return n
	return n.substr(0, idx)


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var found := _find_mesh_instance(c)
		if found != null:
			return found
	return null


## 手動沿父節點鏈往上乘 transform，取代 global_transform ——
## headless SceneTree --script 模式下 instantiate() 出的節點永遠不在
## 真正的場景樹內，global_transform 會全部回單位矩陣（本次轉換事故的根因）。
## transform（本地屬性）不需要在樹內就能正確讀取，逐層乘上去即可還原全域座標。
func _manual_global_transform(node: Node3D, stop_at: Node) -> Transform3D:
	var xform: Transform3D = node.transform
	var p: Node = node.get_parent()
	while p != null and p != stop_at.get_parent():
		if p is Node3D:
			xform = (p as Node3D).transform * xform
		if p == stop_at:
			break
		p = p.get_parent()
	return xform


## MultiMesh TRANSFORM_3D 的 .buffer 是列主序 3x4：
##   row0 = basis.row0.x/y/z, origin.x
##   row1 = basis.row1.x/y/z, origin.y
##   row2 = basis.row2.x/y/z, origin.z
## 對應 audit_village_trees.gd 讀取時假設的 stride=12、offset 3/7/11 放 origin。
func _write_xform_to_buffer(flat: PackedFloat32Array, offset: int, xform: Transform3D) -> void:
	var b := xform.basis
	var o := xform.origin
	# Basis 存的是欄向量 x/y/z；row(i) 是 (x[i], y[i], z[i])。
	flat[offset + 0] = b.x.x; flat[offset + 1] = b.y.x; flat[offset + 2] = b.z.x; flat[offset + 3] = o.x
	flat[offset + 4] = b.x.y; flat[offset + 5] = b.y.y; flat[offset + 6] = b.z.y; flat[offset + 7] = o.y
	flat[offset + 8] = b.x.z; flat[offset + 9] = b.y.z; flat[offset + 10] = b.z.z; flat[offset + 11] = o.z
