extends RefCounted
## 人間之里 V2 永久 build rule（2026-10-03 使用者裁定）：MultiMesh 烘焙防呆。
##   1. 任何把 MultiMesh 存進 .scn/.tscn/.res 的 generator，`--build` 必須在有 rendering display 的行程跑（不可 `--headless`）：
##      dummy RenderingServer 會保留 instance_count 與 custom_aabb，但 instance transform 全部寫成 0 → 整層看不見、而擺放 gate 照樣 PASS。
##   2. 存檔後必須 reload（CACHE_MODE_IGNORE）並以 audit 驗：每個 instance 的 basis 行列式 ≠ 0。
##   3. 回歸總表 tag MMBAKE（tools/verify_village_v2_multimesh_bake.gd）以非 headless 掃描整個 village_v2 場景的全部 MultiMesh。
## headless 下 MultiMesh 的 transform 也讀不到（全 0），所以 audit 在 headless 一律回報 headless，不得當成 PASS。

const DET_EPS := 1e-12


static func display_ok() -> bool:
	return DisplayServer.get_name() != "headless"


## 一個 MultiMesh 的退化 instance 數（basis 行列式 ≈ 0）；回傳 [instance 數, 退化數]
static func zero_instances(mm: MultiMesh) -> PackedInt32Array:
	var n := mm.instance_count
	if n == 0:
		return PackedInt32Array([0, 0])
	var bad := 0
	if mm.transform_format == MultiMesh.TRANSFORM_3D:
		var buf := mm.buffer
		var stride := 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)
		if buf.size() < n * stride:
			return PackedInt32Array([n, n])
		for i in n:
			var o := i * stride
			# 列優先 3×4：[xx, yx, zx, ox, xy, yy, zy, oy, xz, yz, zz, oz]
			var det := buf[o] * (buf[o + 5] * buf[o + 10] - buf[o + 6] * buf[o + 9]) \
				- buf[o + 1] * (buf[o + 4] * buf[o + 10] - buf[o + 6] * buf[o + 8]) \
				+ buf[o + 2] * (buf[o + 4] * buf[o + 9] - buf[o + 5] * buf[o + 8])
			if absf(det) < DET_EPS:
				bad += 1
	else:
		for i in n:
			if absf(mm.get_instance_transform_2d(i).determinant()) < DET_EPS:
				bad += 1
	return PackedInt32Array([n, bad])


## 節點樹內全部 MultiMeshInstance3D：{"display", "nodes", "instances", "zero", "bad": [path…]}
static func audit_node(root: Node) -> Dictionary:
	var out := {"display": display_ok(), "nodes": 0, "instances": 0, "zero": 0, "bad": []}
	if not display_ok():
		return out
	for n in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm == null:
			continue
		var r := zero_instances(mm)
		out["nodes"] = int(out["nodes"]) + 1
		out["instances"] = int(out["instances"]) + r[0]
		out["zero"] = int(out["zero"]) + r[1]
		if r[1] > 0:
			(out["bad"] as Array).append("%s（%d/%d）" % [root.get_path_to(n), r[1], r[0]])
	return out


## 存檔後回讀：不走快取重新載入場景檔再 audit
static func audit_saved_scene(path: String) -> Dictionary:
	var ps := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if ps == null:
		return {"display": display_ok(), "nodes": 0, "instances": 0, "zero": -1, "bad": ["無法載入 " + path]}
	var n := ps.instantiate()
	var r := audit_node(n)
	n.free()
	return r


## 一行摘要；ok＝有 display、至少 1 個 MultiMesh、退化 0
static func ok(r: Dictionary) -> bool:
	return bool(r["display"]) and int(r["nodes"]) > 0 and int(r["zero"]) == 0


static func summary(r: Dictionary) -> String:
	if not bool(r["display"]):
		return "headless（讀不到 MultiMesh 資料，不得當 PASS）"
	return "MultiMesh 節點 %d、instance %d、零矩陣 %d %s" % [r["nodes"], r["instances"], r["zero"], ", ".join((r["bad"] as Array).slice(0, 4))]
