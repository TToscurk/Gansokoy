extends SceneTree
## 診斷：Kit 各構件的真實 mesh AABB vs lib 的 HALF/CEN 近似。
## 目的：確認「lib 粗篩 vs gate 實際 AABB」的量尺落差是否讓石頭被誤判為淨空。
const DIR := "res://assets/village_v2/riverbank_kit/mesh"
const HALF := {"rev": Vector3(1.2, 0.45, 0.2), "revb": Vector3(1.2, 0.45, 0.2), "cap": Vector3(0.56, 0.12, 0.24),
	"bld": Vector3(0.6, 0.5, 0.55)}
const CEN := {"rev": Vector3(0, 0, -0.11), "revb": Vector3(0, 0, -0.1), "cap": Vector3(0, 0.08, 0),
	"bld": Vector3(0, 0.12, 0)}

func _init() -> void:
	var files := DirAccess.get_files_at(DIR)
	if files.is_empty():
		print("[bb] 找不到 %s" % DIR)
		quit(1)
		return
	var bykind := {}
	for f in files:
		if not f.ends_with(".res") or f.ends_with("_l1.res"):
			continue
		var m: Mesh = load(DIR + "/" + f)
		if m == null:
			print("[bb] 載入失敗 %s" % f)
			continue
		var a := m.get_aabb()
		var one: Vector3 = a.size * 0.5
		var kind := String(f).get_basename().trim_prefix("rb_").get_slice("_", 0)
		print("[bb] %-14s AABB half %s  center %s" % [String(f).get_basename(), str(one).pad_decimals(3), str(a.get_center()).pad_decimals(3)])
		var key: String = String({"cap": "cap", "bld": "bld"}.get(kind, kind))
		if not bykind.has(key):
			bykind[key] = []
		bykind[key].append(one)
	print("")
	for k: String in ["rev", "cap", "bld"]:
		if not bykind.has(k):
			continue
		var arr: Array = bykind[k]
		var mx := Vector3.ZERO
		for v: Vector3 in arr:
			mx = mx.max(v)
		var h: Vector3 = HALF.get(k, Vector3.ZERO)
		var ratio := Vector3(mx.x / maxf(h.x, 1e-6), mx.y / maxf(h.y, 1e-6), mx.z / maxf(h.z, 1e-6))
		print("[bb] %-5s n=%d  實際最大 half %s vs HALF %s  → 比例 %s" % [
			k, arr.size(), str(mx).pad_decimals(3), str(h).pad_decimals(3), str(ratio).pad_decimals(2)])
	quit()
