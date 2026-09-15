extends SceneTree
## Hips 垂直跨度 1.4584 m 的來源追查。
##
## make_form08_thrust.py 寫的沉腰是 -0.018 m（1.8 cm），但 verify_form08 量到
## .res 裡的 Hips Z 跨度是 1.4584 m —— 差了 80 倍。在改任何數字之前先確認
## 那 1.4584 是「真的位移」還是「rest 基準沒扣掉」。
##
## Hips rest 的 Z ≈ 0.986（髖高，probe_yoriichi_rig 實測）。若軌上的值是
## 「絕對骨架座標」而非「相對 rest 的偏移」，跨度就會包含 rest 本身。

const RES := "res://characters/yoriichi/animations/yoriichi_form08_thrust.res"
const FBX := "res://characters/yoriichi/yoriichi_body.fbx"


func _init() -> void:
	var anim: Animation = load(RES)
	var ps := load(FBX) as PackedScene
	var inst := ps.instantiate()
	var skel: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	var hips_rest := skel.get_bone_rest(skel.find_bone("Hips"))

	print("=== Hips 垂直追查 ===")
	print("FBX Hips rest origin = (%.4f, %.4f, %.4f)" % [
		hips_rest.origin.x, hips_rest.origin.y, hips_rest.origin.z])

	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		print("\n軌 %s，%d keys" % [anim.track_get_path(t), anim.track_get_key_count(t)])
		print("  %-6s %-10s %-10s %-10s   相對 rest 的 Z" % ["time", "x", "y", "z"])
		var zs: Array[float] = []
		for k in anim.track_get_key_count(t):
			var time := anim.track_get_key_time(t, k)
			var v: Vector3 = anim.track_get_key_value(t, k)
			zs.append(v.z)
			# 只印代表性的幀，不洗版
			if k % 5 == 0 or k == anim.track_get_key_count(t) - 1:
				print("  %-6.3f %-10.4f %-10.4f %-10.4f   %+.4f" % [
					time, v.x, v.y, v.z, v.z - hips_rest.origin.z])
		var zmin: float = zs.min()
		var zmax: float = zs.max()
		print("\n  Z 範圍 %.4f ~ %.4f（跨度 %.4f）" % [zmin, zmax, zmax - zmin])
		print("  rest Z = %.4f" % hips_rest.origin.z)
		print("  相對 rest：%.4f ~ %.4f" % [zmin - hips_rest.origin.z, zmax - hips_rest.origin.z])
		if absf(zmax - zmin) > 0.5:
			print("  ⚠ 跨度 > 50 cm：這不是沉腰，是單位或基準錯了")
			print("     Blender 端寫入 pb.location.y = dz * 100（骨架 local 公分制）")
			print("     若 GLB 匯出已經換算成公尺，×100 就是多餘的 → 實際大 100 倍")

	inst.free()
	quit(0)
