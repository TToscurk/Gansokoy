extends SceneTree
## 新刀鞘（sheath_v2/yoriichi_sheath_v2.glb，Tripo，長 1.0 m 沿 Z、鞘口在 −Z、刃側 −X、下緒在 −Y）掛點換算。
## 1) 刀改等比縮放 SWORD_SCALE（舊值長 0.64／寬 1.05 不等比，刀身過寬）；鞘中刀的鞘口點（刀本地 y=MOUTH_Y）位置與方向不變。
## 2) 鞘 = 鞘中刀 × T：鞘 X→刀 X（刃背軸）、鞘 Z→刀 Y（刀尖）、鞘 Y→刀 −Z；鞘口中心 (0, SAYA_MOUTH_CY, −0.5) 對到刀本地 (0, MOUTH_Y, 0)。
## 3) 印出 Player 空間的刃向／刀尖向／下緒面向，確認佩刀「刃朝上、刀尖朝後下、下緒在外側」。
## 用法：godot --headless --path . -s tools/v24_anim/fit_sheath_v2.gd [-- write]

const SWORD_SCALE := 0.68
const MOUTH_Y := 0.128        # 刀本地：鍔（y≈0.12）前緣
const SAYA_MOUTH_CY := 0.136  # 鞘本地：鞘身截面中心高
const SAYA_K := 1.0           # 鞘長（刀本地單位）= 1.0 → 世界 0.68 m（刀身 0.65 m）

var _n := 0
var _p: Node3D

func _initialize() -> void:
	_p = (load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene).instantiate()
	root.add_child(_p)

func _fmt(t: Transform3D) -> String:
	var b := t.basis
	return var_to_str(t)   # Godot 字串是列優先（row-major），不可手拼欄向量

func _process(_d: float) -> bool:
	_n += 1
	if _n < 2:
		return false
	var ss: Node3D = _p.find_child("Sword_Sheathed", true, false)
	var sh: Node3D = _p.find_child("Sheath", true, false)
	var old := ss.transform
	var mouth_parent := old * Vector3(0, MOUTH_Y, 0)
	var nb := old.basis.orthonormalized().scaled_local(Vector3.ONE * SWORD_SCALE)
	var new_ss := Transform3D(nb, Vector3.ZERO)
	new_ss.origin = mouth_parent - nb * Vector3(0, MOUTH_Y, 0)
	var k := SAYA_K
	var tb := Basis(Vector3(k, 0, 0), Vector3(0, 0, -k), Vector3(0, k, 0))
	var to := Vector3(0, MOUTH_Y, 0) - tb * Vector3(0, SAYA_MOUTH_CY, -0.5)
	var new_sh := new_ss * Transform3D(tb, to)
	# Player 空間方向（Sheath 的 sway 腳本開跑前，用 parent 全域矩陣換算）
	var par: Node3D = ss.get_parent()
	var inv := _p.global_transform.affine_inverse() * par.global_transform
	var sw := inv * new_ss
	var edge := (sw.basis * Vector3(-1, 0, 0)).normalized()
	var tip := (sw.basis * Vector3(0, 1, 0)).normalized()
	var cord := (sw.basis * Vector3(0, 0, 1)).normalized()   # 鞘 −Y = 刀 +Z
	var mouth := sw * Vector3(0, MOUTH_Y, 0)
	var sk := inv * new_sh
	var kojiri := sk * Vector3(0, SAYA_MOUTH_CY, 0.5)
	print("PLAYER-SPACE  edge=", edge.snapped(Vector3.ONE * 0.01), " tip=", tip.snapped(Vector3.ONE * 0.01), " cord_face=", cord.snapped(Vector3.ONE * 0.01))
	print("  mouth=", mouth.snapped(Vector3.ONE * 0.001), " kojiri=", kojiri.snapped(Vector3.ONE * 0.001), " saya_len=", mouth.distance_to(kojiri))
	print("  hilt_end=", (sw * Vector3(0, -0.38, 0)).snapped(Vector3.ONE * 0.001), " sword_len=", (sw.basis * Vector3(0, 1.465, 0)).length())
	print("SS ", _fmt(new_ss))
	print("SH ", _fmt(new_sh))
	if "write" in OS.get_cmdline_user_args():
		var f := FileAccess.open("user://sheath_v2_fit.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"Sword_Sheathed": _fmt(new_ss), "Sheath": _fmt(new_sh)}))
		f.close()
		print("WROTE")
	quit()
	return true
