extends SceneTree
# 產生獨立測試場景 res://characters/yoriichi/v2/yoriichi_v2_test.tscn
#  - 緣一 V2 GLB（Humanoid retarget 骨名；haori_* / clothcol_* / Weapon_R / Grip_* / Blade_* 為 Extra Bones，不在 BoneMap）
#  - 骨鏈負責動態：SpringBoneSimulator3D 只模擬 haori_<區>_01..03 與 haori_sleeve_01..02（末端骨，無動畫軌）
#  - Collision Proxy 負責防穿模：膠囊掛在 clothcol_* 代理骨（head＝膠囊中心、+Y＝膠囊軸），跟 Skeleton 動、不參與 retarget
#  - 碰撞體為 simulator 的子節點（掛在 skeleton 下不會註冊，godot#110274）
#  - 畫面：2×2 SubViewport（Front / Side / Back / TPS）同時看
const GLB := "res://characters/yoriichi/v2/yoriichi_v2_combat.glb"
const OUT := "res://characters/yoriichi/v2/yoriichi_v2_test.tscn"
# 區：{k=stiffness, d=drag(damping), g=gravity, r=碰撞半徑(末端), rc=半徑曲線[根,末], kc=stiffness 曲線[根,末], cols}
# 局部 cloth tuning v4J（Side View 目視比對 v3nosim/v4/C/D/E/F/G/H/I/J 後選定；骨架與 proxy 不動）：
#   Front：root follow 強（k 8、kc 1→0.9）＋ drag 0.95 → 不再單片飛出；碰撞安全距離 4→8.5 cm（只前片）
#   Side ：k 2.5、drag 0.8、gravity 0.8 → 下擺往下垂、不翹成架子；安全距離 4→7 cm（只側片，骨盆 collider 不放大）
#   Back ：k 0.18–0.32、drag 0.72–0.9、碰撞半徑 0.5–0.8 cm（幾乎不被推）；三條 k/d/g 錯開 → 自然頻率不同 → 不同 phase
const REGIONS := {
	"front_L": {"k": 8.0, "d": 0.95, "g": 0.30, "r": 0.085, "rc": [0.47, 1.0], "kc": [1.0, 0.9], "cols": ["thigh.L", "calf.L", "thigh.R"]},
	"front_R": {"k": 8.0, "d": 0.95, "g": 0.30, "r": 0.085, "rc": [0.47, 1.0], "kc": [1.0, 0.9], "cols": ["thigh.R", "calf.R", "thigh.L"]},
	"side_L": {"k": 2.5, "d": 0.80, "g": 0.80, "r": 0.070, "rc": [0.57, 1.0], "kc": [1.0, 0.9], "cols": ["pelvis", "thigh.L", "calf.L"]},
	"side_R": {"k": 2.5, "d": 0.80, "g": 0.80, "r": 0.070, "rc": [0.57, 1.0], "kc": [1.0, 0.9], "cols": ["pelvis", "thigh.R", "calf.R"]},
	"back_L": {"k": 0.25, "d": 0.80, "g": 0.90, "r": 0.008, "rc": [0.625, 1.0], "kc": [1.0, 0.40], "cols": ["thigh.L", "calf.L"]},
	"back_C": {"k": 0.18, "d": 0.90, "g": 1.00, "r": 0.008, "rc": [0.625, 1.0], "kc": [1.0, 0.35], "cols": ["thigh.L", "thigh.R"]},
	"back_R": {"k": 0.32, "d": 0.72, "g": 0.80, "r": 0.008, "rc": [0.625, 1.0], "kc": [1.0, 0.45], "cols": ["thigh.R", "calf.R"]},
}
# 代理膠囊：半徑。Rest 距離設計（Blender probe_proxy_design.py）：
#   羽織下擺鏈節點離大腿軸 rest 最近 0.175 m（側）、0.27 m（前）→ 大腿 0.14 + 節點半徑 0.03 = 0.17 < 0.175：
#   Idle 不被推開，只要腿往下擺靠近就擋住；安全餘裕由節點半徑 3 cm 提供（膠囊面到布節點中心）。
const JOINT_R := 0.03
const PROXY := {
	"pelvis": [0.10, 0.34],        # 半徑, 總長（橫向，骨 +Y＝左右）
	"thigh.L": [0.14, -1.0],       # -1＝依骨長自動（大腿全長）
	"thigh.R": [0.14, -1.0],
	"calf.L": [0.13, 0.30 + 0.26],
	"calf.R": [0.13, 0.30 + 0.26],
}

# ================= Hair（v1 最小可用版）=================
# 每條鏈：hair_<區>_root（Head 子骨、不模擬 → 根部不晃）＋ _01.._0N（中段/末端交給 SpringBone）
# 註：_01 起點釘在 _root 尾端（位置不動），模擬的是 _01 的旋轉；_02 起才有位置延遲。見 work/yoriichi_mixamo/baseline_hair_v1/README.md
# 物理梯度（沿鏈 root→tip）：stiffness 高→低、drag 高→中；tip 延遲最大，但 drag 不低於 0.5 → 不甩成鞭子
# 羽織 baseline（REGIONS / PROXY）一律不動；頭髮只用自己的 5 個代理
const HAIR := {
	"hair_ponytail": {"n": 3, "sfx": "", "k": 1.6, "d": 0.75, "g": 0.35, "r": 0.03, "kc": [1.0, 0.35], "dc": [1.0, 0.7], "cols": ["head", "neck", "upperback"]},
	"hair_back.L": {"n": 3, "sfx": ".L", "k": 1.5, "d": 0.72, "g": 0.35, "r": 0.03, "kc": [1.0, 0.35], "dc": [1.0, 0.7], "cols": ["head", "neck", "shoulder.L", "upperback"]},
	"hair_back.R": {"n": 3, "sfx": ".R", "k": 1.7, "d": 0.78, "g": 0.35, "r": 0.03, "kc": [1.0, 0.35], "dc": [1.0, 0.7], "cols": ["head", "neck", "shoulder.R", "upperback"]},
	"hair_side.L": {"n": 3, "sfx": ".L", "k": 1.4, "d": 0.70, "g": 0.35, "r": 0.03, "kc": [1.0, 0.35], "dc": [1.0, 0.7], "cols": ["head", "shoulder.L", "upperback"]},
	"hair_side.R": {"n": 3, "sfx": ".R", "k": 1.45, "d": 0.72, "g": 0.35, "r": 0.03, "kc": [1.0, 0.35], "dc": [1.0, 0.7], "cols": ["head", "shoulder.R", "upperback"]},
	"hair_front.L": {"n": 2, "sfx": ".L", "k": 2.2, "d": 0.85, "g": 0.30, "r": 0.02, "kc": [1.0, 0.5], "dc": [1.0, 0.8], "cols": ["head", "neck", "shoulder.L"]},
	"hair_front.R": {"n": 2, "sfx": ".R", "k": 2.2, "d": 0.85, "g": 0.30, "r": 0.02, "kc": [1.0, 0.5], "dc": [1.0, 0.8], "cols": ["head", "neck", "shoulder.R"]},
}
# 頭髮代理：[半徑, 總長]（量自 rest 身體/羽織：顱 x ±0.10 y -0.16..0.04 z 1.72..1.98；頸半徑 ~0.06；
#   肩頂（羽織）z 1.73–1.75；上背羽織 y +0.10..+0.16 @ z 1.35–1.60）
const HAIR_PROXY := {
	"head": [0.105, 0.26],
	"neck": [0.065, 0.16],
	"shoulder.L": [0.07, 0.26],
	"shoulder.R": [0.07, 0.26],
	"upperback": [0.15, 0.40],
}

func _own(n: Node, owner_: Node) -> void:
	n.owner = owner_
	for c in n.get_children():
		_own(c, owner_)

func _lin(v: Array) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, v[0]))
	c.add_point(Vector2(1.0, v[1]))
	return c

func _init() -> void:
	var root := Node3D.new()
	root.name = "YoriichiV2Test"
	get_root().add_child(root)
	var ch: Node3D = (load(GLB) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	ch.name = "Yoriichi"
	root.add_child(ch)
	var skel: Skeleton3D = ch.find_child("GeneralSkeleton", true, false)
	var sim := SpringBoneSimulator3D.new()
	sim.name = "HaoriSpring"
	skel.add_child(sim)
	# ---- Collision Proxy
	var cols := {}
	for k in PROXY:
		var bn: String = "clothcol_" + str(k)
		var bi := skel.find_bone(bn)
		if bi < 0:
			print("BUILD ERROR missing proxy bone ", bn); quit(); return
		var c := SpringBoneCollisionCapsule3D.new()
		c.name = "Col_" + str(k).replace(".", "_")
		sim.add_child(c)
		c.bone_name = bn
		c.radius = PROXY[k][0]
		var h: float = PROXY[k][1]
		if h < 0.0:
			var th := skel.find_bone("LeftUpperLeg" if str(k).ends_with("L") else "RightUpperLeg")
			var kn := skel.find_bone("LeftLowerLeg" if str(k).ends_with("L") else "RightLowerLeg")
			h = skel.get_bone_global_rest(kn).origin.distance_to(skel.get_bone_global_rest(th).origin) + 2.0 * c.radius
		c.height = h
		cols[k] = c
	# ---- 骨鏈（羽織）
	var n := REGIONS.size() + 2
	sim.set_setting_count(n)
	var i := 0
	for k in REGIONS:
		var p: Dictionary = REGIONS[k]
		sim.set_root_bone_name(i, "haori_%s_01" % k)
		sim.set_end_bone_name(i, "haori_%s_03" % k)
		sim.set_extend_end_bone(i, true)
		sim.set_end_bone_length(i, 0.05)
		sim.set_stiffness(i, p.k)
		sim.set_drag(i, p.d)
		sim.set_gravity(i, p.g)
		sim.set_radius(i, p.r)
		sim.set_stiffness_damping_curve(i, _lin(p.kc))
		sim.set_radius_damping_curve(i, _lin(p.rc))
		sim.set_enable_all_child_collisions(i, false)
		var lst: Array = p.cols
		sim.set_collision_count(i, lst.size())
		for j in lst.size():
			sim.set_collision_path(i, j, sim.get_path_to(cols[lst[j]]))
		i += 1
	for s in ["L", "R"]:
		sim.set_root_bone_name(i, "haori_sleeve_01.%s" % s)
		sim.set_end_bone_name(i, "haori_sleeve_02.%s" % s)
		sim.set_extend_end_bone(i, true)
		sim.set_end_bone_length(i, 0.05)
		sim.set_stiffness(i, 0.7)
		sim.set_drag(i, 0.3)
		sim.set_gravity(i, 0.3)
		sim.set_radius(i, 0.02)
		sim.set_enable_all_child_collisions(i, false)
		sim.set_collision_count(i, 2)
		sim.set_collision_path(i, 0, sim.get_path_to(cols["pelvis"]))
		sim.set_collision_path(i, 1, sim.get_path_to(cols["thigh." + s]))
		i += 1
	# ---- 頭髮：獨立 SpringBoneSimulator3D（與羽織分開調、互不影響 baseline）
	var hsim := SpringBoneSimulator3D.new()
	hsim.name = "HairSpring"
	skel.add_child(hsim)
	var hcols := {}
	for k in HAIR_PROXY:
		var bn: String = "clothcol_" + str(k)
		if skel.find_bone(bn) < 0:
			print("BUILD ERROR missing hair proxy bone ", bn); quit(); return
		var c := SpringBoneCollisionCapsule3D.new()
		c.name = "Col_" + str(k).replace(".", "_")
		hsim.add_child(c)
		c.bone_name = bn
		c.radius = HAIR_PROXY[k][0]
		c.height = HAIR_PROXY[k][1]
		hcols[k] = c
	hsim.set_setting_count(HAIR.size())
	var hi := 0
	for k in HAIR:
		var p: Dictionary = HAIR[k]
		var base: String = str(k).split(".")[0]
		# 模擬從 _01 開始（root 不模擬 → 跟 Head 剛性）
		hsim.set_root_bone_name(hi, "%s_01%s" % [base, p.sfx])
		hsim.set_end_bone_name(hi, "%s_%02d%s" % [base, p.n, p.sfx])
		hsim.set_extend_end_bone(hi, true)
		hsim.set_end_bone_length(hi, 0.06)
		hsim.set_stiffness(hi, p.k)
		hsim.set_drag(hi, p.d)
		hsim.set_gravity(hi, p.g)
		hsim.set_radius(hi, p.r)
		hsim.set_stiffness_damping_curve(hi, _lin(p.kc))
		hsim.set_drag_damping_curve(hi, _lin(p.dc))
		hsim.set_enable_all_child_collisions(hi, false)
		var lst: Array = p.cols
		hsim.set_collision_count(hi, lst.size())
		for j in lst.size():
			hsim.set_collision_path(hi, j, hsim.get_path_to(hcols[lst[j]]))
		hi += 1
	root.set_script(load("res://characters/yoriichi/v2/yoriichi_v2_test.gd"))
	# ---- 光與地面
	var sun := DirectionalLight3D.new(); sun.name = "Sun"; root.add_child(sun)
	sun.rotation_degrees = Vector3(-50, 30, 0); sun.shadow_enabled = true
	var env := WorldEnvironment.new(); env.name = "Env"; root.add_child(env)
	env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.34, 0.37); env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.62)
	var floor_ := MeshInstance3D.new(); floor_.name = "Floor"; root.add_child(floor_)
	var pm := PlaneMesh.new(); pm.size = Vector2(12, 12); floor_.mesh = pm
	# ---- 2×2 視角（角色面向 +Z：Godot 匯入後 Blender -Y 前 → +Z）
	var ui := GridContainer.new(); ui.name = "Views"; ui.columns = 2; root.add_child(ui)
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_theme_constant_override("h_separation", 2); ui.add_theme_constant_override("v_separation", 2)
	var views := {"Front": [Vector3(0, 1.15, 3.4), Vector3(0, 1.0, 0)], "Side (L)": [Vector3(3.4, 1.15, 0), Vector3(0, 1.0, 0)],
		"Back": [Vector3(0, 1.15, -3.4), Vector3(0, 1.0, 0)], "TPS": [Vector3(-0.9, 1.8, -3.2), Vector3(0, 1.1, 0.6)]}
	var made := [sun, env, floor_, ui]
	for vn in views:
		var box := SubViewportContainer.new(); box.name = vn; box.stretch = true
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		ui.add_child(box)
		var vp := SubViewport.new(); vp.name = "VP"; box.add_child(vp)
		vp.msaa_3d = Viewport.MSAA_4X
		var cam := Camera3D.new(); cam.name = "Cam"; vp.add_child(cam)
		cam.fov = 40.0
		cam.look_at_from_position(views[vn][0], views[vn][1], Vector3.UP)
		cam.current = true
		var lb := Label.new(); lb.name = "Label"; lb.text = vn; box.add_child(lb)
		lb.add_theme_color_override("font_color", Color(1, 1, 0.3)); lb.position = Vector2(8, 6)
	var clip_lb := Label.new(); clip_lb.name = "ClipLabel"; root.add_child(clip_lb)
	clip_lb.add_theme_color_override("font_color", Color(1, 1, 1)); clip_lb.add_theme_font_size_override("font_size", 22)
	clip_lb.position = Vector2(12, 36); made.append(clip_lb)
	ch.owner = root
	root.set_editable_instance(ch, true)     # 在 GLB 實例內部（GeneralSkeleton 下）加節點需 Editable Children
	_own(sim, root)
	_own(hsim, root)
	for nnode in made:
		_own(nnode, root)
	get_root().remove_child(root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	print("BUILD pack ", err, " settings ", sim.get_setting_count(), " colliders ", sim.get_child_count(),
		" per-setting ", range(sim.get_setting_count()).map(func(q): return sim.get_collision_count(q)),
		" | hair settings ", hsim.get_setting_count(), " joints ", range(hsim.get_setting_count()).map(func(q): return hsim.get_joint_count(q)))
	print("BUILD save ", ResourceSaver.save(ps, OUT))
	quit()
