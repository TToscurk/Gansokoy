extends SceneTree
## 阿求 正座時的袴「垂放」修正形狀（blend shape SeizaDrape）。在 Godot 端用正座 clip 的實際骨姿計算，存成帶 blend shape 的 ArrayMesh。
## 做法（不是逐點推開，而是「每個方位一條垂布鏈」）：
##   1. CPU 蒙皮出正座時的衣身；袴頂點依靜止時的方位角 φ 與「離腰的布長」s 分組
##   2. 每 sectors 個方位各建一條鏈：從腰（該方位 s≈0 的蒙皮位置，固定）往下，節點間距 = 布長，
##      重力 + 距離約束 + 碰撞（大腿／小腿／腳／臀膠囊、地板；落地後有摩擦）→ 布會蓋過大腿成「膝上平台」、越過膝蓋落到地上攤開，後片蓋過臀部與腳跟
##   3. 每個頂點的目標 = 鏈上 (φ, s) 的位置（相鄰兩鏈內插），保留原本的徑向褶深（沿鏈的外法線）
##   4. 位移轉回 rest 空間（逐頂點 LBS 線性部分反算）→ blend shape（normalized）
## godot --headless --path . -s res://tools/akyuu/build_akyuu_seiza_drape.gd -- [--clip=…] [--out=res://characters/akyuu/akyuu_kimono_seiza.res]
const GLB := "res://characters/akyuu/akyuu.glb"
var sk: Skeleton3D

func _initialize() -> void: _go.call_deferred()

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="): return a.split("=", true, 1)[1]
	return d

func _seg(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a; var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0); return a + ab * t

func _bp(n: String) -> Vector3: return sk.get_bone_global_pose(sk.find_bone(n)).origin

func _go() -> void:
	var clip_path := _arg("clip", "res://characters/akyuu/anim/seiza_idle_a030_final.res")
	var out := _arg("out", "res://characters/akyuu/akyuu_kimono_seiza.res")
	var t_at := float(_arg("t", "0.0"))
	var margin := float(_arg("margin", "0.02"))
	var floor_clear := float(_arg("floor_clear", "0.006"))
	var sectors := int(_arg("sectors", "48"))
	var ds := float(_arg("ds", "0.012"))
	var iters := int(_arg("iters", "300"))
	var friction := float(_arg("friction", "0.6"))
	var pleat_keep := float(_arg("pleat_keep", "0.4"))
	var m: Node3D = (load(GLB) as PackedScene).instantiate(); root.add_child(m)
	sk = m.find_child("GeneralSkeleton", true, false)
	var ap := AnimationPlayer.new(); m.add_child(ap); ap.root_node = NodePath("../Armature")
	var lib := AnimationLibrary.new(); lib.add_animation(&"c", load(clip_path)); ap.add_animation_library(&"", lib); ap.play(&"c"); ap.speed_scale = 0.0
	ap.seek(t_at, true)
	await process_frame
	var mi: MeshInstance3D = m.find_child("衣身", true, false)
	var mesh := mi.mesh as ArrayMesh
	var arr := mesh.surface_get_arrays(0)
	var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]; var Bn: PackedInt32Array = arr[Mesh.ARRAY_BONES]; var W: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var skin := mi.skin
	var Mb := []
	for j in skin.get_bind_count():
		var bi := skin.get_bind_bone(j)
		if bi < 0: bi = sk.find_bone(skin.get_bind_name(j))
		Mb.append(sk.get_bone_global_pose(bi) * skin.get_bind_pose(j))
	var nv := V.size()
	var P := PackedVector3Array(); P.resize(nv)
	var Mv := []
	for i in nv:
		var bas := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO); var p := Vector3.ZERO
		for q in 4:
			var w := W[i * 4 + q]
			if w > 0.0:
				var T: Transform3D = Mb[Bn[i * 4 + q]]
				p += T * V[i] * w
				bas = Basis(bas.x + T.basis.x * w, bas.y + T.basis.y * w, bas.z + T.basis.z * w)
		P[i] = p; Mv.append(bas)
	# 依貼圖顏色分內外層：紅＝袴（外層）、其他（上衣黃色下襬等）＝內層 → 垂放時壓到袴面之下 inner_push 公尺
	var inner := PackedByteArray(); inner.resize(nv)
	var mat := mesh.surface_get_material(0) as BaseMaterial3D
	var img: Image = null
	if mat and mat.albedo_texture:
		img = mat.albedo_texture.get_image()
		if img.is_compressed(): img.decompress()
	var UV: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var n_inner := 0
	if img:
		for i in nv:
			var c := img.get_pixel(clampi(int(UV[i].x * img.get_width()), 0, img.get_width() - 1), clampi(int(UV[i].y * img.get_height()), 0, img.get_height() - 1))
			if not (c.r > 0.35 and c.r > c.g * 1.6 and c.r > c.b * 1.4):
				inner[i] = 1; n_inner += 1
	var inner_push := float(_arg("inner_push", "0.025"))
	var layer_gap := float(_arg("layer_gap", "1.0"))   # 比外層袴面縮進超過此值的（背板內襯等第二層）也當內層，避免兩層疊在同一面 z-fighting
	# 靜止空間：方位角、布長（從 Hips 高度往下的布才重新垂放）
	var hips_r := sk.get_bone_global_rest(sk.find_bone("Hips")).origin
	var y0 := hips_r.y + float(_arg("waist_up", "0.06"))   # 從腰帶（Hips 上方，權重屬軀幹、不被大腿拖動）開始重新垂放
	var phi := PackedFloat32Array(); phi.resize(nv)
	var sarc := PackedFloat32Array(); sarc.resize(nv)
	var rad := PackedFloat32Array(); rad.resize(nv)
	var smax := 0.0
	for i in nv:
		var v := V[i]
		phi[i] = atan2(v.x - hips_r.x, v.z - hips_r.z)
		rad[i] = Vector2(v.x - hips_r.x, v.z - hips_r.z).length()
		sarc[i] = y0 - v.y
		if sarc[i] > 0.0: smax = maxf(smax, sarc[i])
	var ns := int(ceil(smax / ds)) + 2
	# 每方位、每 s 的平均靜止半徑（保留褶深用）與沿裙面的實際布長
	var rsum := []; rsum.resize(sectors)
	for k in sectors:
		var a := PackedFloat32Array(); a.resize(ns); var c := PackedFloat32Array(); c.resize(ns)
		rsum[k] = [a, c]
	var rmax := []; rmax.resize(sectors)
	for k in sectors:
		var z := PackedFloat32Array(); z.resize(ns); rmax[k] = z
	for i in nv:
		if sarc[i] <= 0.0: continue
		var k := int(floor((phi[i] + PI) / TAU * sectors)) % sectors
		var j := clampi(int(round(sarc[i] / ds)), 0, ns - 1)
		rsum[k][0][j] += rad[i]; rsum[k][1][j] += 1.0
		for jj in range(maxi(0, j - 1), mini(ns, j + 2)): rmax[k][jj] = maxf(rmax[k][jj], rad[i])
	var rmean := []; rmean.resize(sectors)
	var slen := []; slen.resize(sectors)
	for k in sectors:
		var r := PackedFloat32Array(); r.resize(ns)
		var last := 0.0
		for j in ns:
			if rsum[k][1][j] > 0: last = rsum[k][0][j] / rsum[k][1][j]
			r[j] = last
		for j in range(ns - 2, -1, -1):
			if r[j] == 0.0: r[j] = r[j + 1]
		var L := PackedFloat32Array(); L.resize(ns)
		for j in range(1, ns): L[j] = L[j - 1] + sqrt(ds * ds + pow(r[j] - r[j - 1], 2))
		rmean[k] = r; slen[k] = L
	# 碰撞體（正座骨姿）
	var caps := []
	var Rr := {"UpperLeg": 0.071, "LowerLeg": 0.058, "Foot": 0.07}
	for s in ["Left", "Right"]:
		caps.append([_bp(s + "UpperLeg"), _bp(s + "LowerLeg"), Rr.UpperLeg + margin])
		caps.append([_bp(s + "LowerLeg"), _bp(s + "Foot"), Rr.LowerLeg + margin])
		caps.append([_bp(s + "Foot"), _bp(s + "Foot").lerp(_bp(s + "Toes"), 1.8), Rr.Foot + margin])   # 厚底鞋：膠囊加粗、延伸過腳尖
	caps.append([_bp("LeftUpperLeg"), _bp("RightUpperLeg"), 0.095 + margin])   # 臀
	caps.append([_bp("Hips"), _bp("Spine"), 0.10 + margin])
	var hc := _bp("Hips")
	# 每方位的起點（腰）：該方位 s∈[0, 0.02] 蒙皮位置的平均
	var tops := []; tops.resize(sectors)
	for k in sectors:
		var ang := -PI + (k + 0.5) * TAU / sectors
		var acc := Vector3.ZERO; var wsum := 0.0
		for widen in [1.0, 2.0, 4.0]:
			for i in nv:
				if sarc[i] < 0.0 or sarc[i] > 0.02 * widen: continue
				var dphi := absf(wrapf(phi[i] - ang, -PI, PI))
				var lim: float = 1.5 * widen * TAU / sectors
				if dphi > lim: continue
				var w := 1.0 - dphi / lim
				acc += P[i] * w; wsum += w
			if wsum > 0.0: break
		tops[k] = acc / maxf(wsum, 1e-6)
	# 腰點離群（例如背後吊帶、蝴蝶結垂尾混進 s≈0 的窗）→ 用相鄰正常的腰點內插
	var ys := PackedFloat32Array()
	for k in sectors: ys.append((tops[k] as Vector3).y)
	var ys2 := ys.duplicate(); ys2.sort()
	var ymed := ys2[sectors / 2]
	var bad := []
	for k in sectors:
		if absf(ys[k] - ymed) > 0.04: bad.append(k)
	for kb2 in bad:
		var k: int = kb2
		var a: int = k; var b: int = k
		while a in bad: a = posmod(a - 1, sectors)
		while b in bad: b = (b + 1) % sectors
		var da := posmod(k - a, sectors); var db := posmod(b - k, sectors)
		tops[k] = (tops[a] as Vector3).lerp(tops[b], float(da) / float(da + db))
	print("TOPS y_median ", snappedf(ymed, 0.001), " outliers_fixed ", bad.size())
	# 每方位一條「布的走線」：在該方位的垂直剖面上，取障礙物（腿／臀／腳膠囊）的上緣包絡 env(r)，
	# 布從腰往外走：有支撐就貼著包絡（膝上平台、蓋過腳跟），沒支撐就近乎垂直落下（最陡 drop_deg），落地後沿地板往外（壓縮 floor_bunch 模擬堆疊）
	var drop_deg := float(_arg("drop_deg", "78"))
	var overhang := float(_arg("overhang", "0.03"))
	var floor_bunch := float(_arg("floor_bunch", "0.45"))
	var bridge := float(_arg("bridge", "0.12"))   # 布會橫跨兩腿之間的縫（膝上成一片平台）
	var chains := []; chains.resize(sectors)
	var DR := 0.004
	for k in sectors:
		var ang := -PI + (k + 0.5) * TAU / sectors
		var od := Vector3(sin(ang), 0, cos(ang))
		var top: Vector3 = tops[k]
		var rw := Vector2(top.x - hc.x, top.z - hc.z).length()
		var origin := Vector3(hc.x, 0, hc.z)
		# 包絡（含往外 overhang 的延伸）
		var NR := int(1.2 / DR)
		var env := PackedFloat32Array(); env.resize(NR)
		for ri in NR:
			var r := ri * DR
			var hmax := floor_clear
			var side := Vector3(od.z, 0, -od.x)
			for lo in [-bridge, -bridge * 0.5, 0.0, bridge * 0.5, bridge]:
				var px: Vector3 = origin + od * r + side * float(lo)
				for c in caps:
					var A: Vector3 = c[0]; var B: Vector3 = c[1]; var R: float = c[2]
					for ti in 17:
						var q := A.lerp(B, ti / 16.0)
						var dxz := Vector2(px.x - q.x, px.z - q.z).length()
						if dxz < R: hmax = maxf(hmax, q.y + sqrt(R * R - dxz * dxz))
			env[ri] = hmax
		var envo := PackedFloat32Array(); envo.resize(NR)
		var ow := int(overhang / DR)
		for ri in NR:
			var mx := env[ri]
			for q in range(maxi(0, ri - ow), ri + 1): mx = maxf(mx, env[q])
			envo[ri] = mx
		# 走線（r, y）：從腰開始
		var pts := PackedVector2Array()
		var r := rw; var y := top.y
		pts.append(Vector2(r, y))
		var slope := tan(deg_to_rad(drop_deg))
		while r < 1.15:
			r += DR
			var ri := mini(int(r / DR), NR - 1)
			var want := maxf(envo[ri], y - slope * DR)
			# 若包絡比目前還高（往外遇到更高的支撐），直接爬上去
			y = maxf(want, floor_clear)
			pts.append(Vector2(r, y))
			if y <= floor_clear + 1e-5 and envo[ri] <= floor_clear + 1e-5:
				break
		# 垂直落下段：若相鄰兩點高度差很大（懸崖），插入細分點讓弧長正確
		var cum := PackedFloat32Array(); cum.resize(pts.size())
		for q in range(1, pts.size()): cum[q] = cum[q - 1] + pts[q].distance_to(pts[q - 1])
		var L: PackedFloat32Array = slen[k]
		var X := PackedVector3Array(); X.resize(ns)
		var q := 0
		for j in ns:
			var sj := L[j]
			var pr: Vector2
			if sj <= cum[cum.size() - 1]:
				while q < cum.size() - 2 and cum[q + 1] < sj: q += 1
				var tt := (sj - cum[q]) / maxf(cum[q + 1] - cum[q], 1e-6)
				pr = pts[q].lerp(pts[q + 1], clampf(tt, 0.0, 1.0))
			else:
				var last := pts[pts.size() - 1]
				pr = Vector2(last.x + (sj - cum[cum.size() - 1]) * floor_bunch, floor_clear)
			X[j] = origin + od * pr.x + Vector3.UP * pr.y
		chains[k] = X
	# 相鄰方位平滑（布會在大腿邊緣與地板之間拉成斜面，不會一條貼腿、隔壁一條直落而撕開），平滑後再推出障礙物
	var xsmooth := int(_arg("xsmooth", "60"))
	var s_smooth := float(_arg("s_smooth", "0.3"))
	for itx in xsmooth:
		var nc := []; nc.resize(sectors)
		for k in sectors:
			var A0: PackedVector3Array = chains[k]; var Am: PackedVector3Array = chains[posmod(k - 1, sectors)]; var Ap: PackedVector3Array = chains[(k + 1) % sectors]
			var Xn := A0.duplicate()
			for j in range(1, ns):
				var p := A0[j].lerp((Am[j] + Ap[j]) * 0.5, 0.5)
				if j < ns - 1: p = p.lerp((A0[j - 1] + A0[j + 1]) * 0.5, s_smooth)   # 沿布長方向也平滑（去掉膠囊上緣的凹凸）
				for c in caps:
					var sq := _seg(p, c[0], c[1]); var dv := p - sq; var dlen := dv.length()
					if dlen < c[2]: p = sq + (dv / maxf(dlen, 1e-5) if dlen > 1e-5 else Vector3.UP) * c[2]
				p.y = maxf(p.y, floor_clear)
				Xn[j] = p
			nc[k] = Xn
		chains = nc
	# 診斷：鏈的約束誤差、相鄰鏈距離
	var cerr := 0.0; var adj := 0.0; var adjk := -1; var adjj := -1
	for k in sectors:
		var X: PackedVector3Array = chains[k]; var Xn: PackedVector3Array = chains[(k + 1) % sectors]; var L: PackedFloat32Array = slen[k]
		for j in range(1, ns):
			cerr = maxf(cerr, absf(X[j].distance_to(X[j - 1]) - (L[j] - L[j - 1])))
			var d := X[j].distance_to(Xn[j])
			if d > adj: adj = d; adjk = k; adjj = j
	print("CHAIN constraint_err_max ", snappedf(cerr, 0.0001), " adjacent_max ", snappedf(adj, 0.001), " at sector ", adjk, " node ", adjj, " top ", tops[adjk], " ", tops[(adjk + 1) % sectors])
	# 頂點目標
	var BS := PackedVector3Array(); BS.resize(nv)
	var PO := PackedVector3Array(); PO.resize(nv)
	var below := 0; var maxd := 0.0
	for i in nv:
		var s := sarc[i]
		if s <= 0.0:
			BS[i] = V[i]; PO[i] = P[i]; continue
		var f := (phi[i] + PI) / TAU * sectors - 0.5
		var k0 := int(floor(f)); var fk := f - k0
		var tgt := Vector3.ZERO
		for pair in [[posmod(k0, sectors), 1.0 - fk], [posmod(k0 + 1, sectors), fk]]:
			var kk: int = pair[0]
			var X: PackedVector3Array = chains[kk]
			var fj := clampf(s / ds, 0.0, ns - 1.001); var j0 := int(floor(fj)); var tj := fj - j0
			var p: Vector3 = X[j0].lerp(X[j0 + 1], tj)
			var tan_s := (X[mini(j0 + 1, ns - 1)] - X[maxi(j0 - 1, 0)]).normalized()
			var ang := -PI + (kk + 0.5) * TAU / sectors
			var tan_phi := Vector3(cos(ang), 0, -sin(ang))
			var nrm := tan_phi.cross(tan_s).normalized()
			if nrm.dot(Vector3(sin(ang), 0, cos(ang)) * 0.7 + Vector3.UP * 0.7) < 0: nrm = -nrm
			var ro: PackedFloat32Array = rmax[kk]
			p += nrm * (minf(rad[i] - ro[clampi(j0, 0, ns - 1)], 0.0) * pleat_keep - (inner_push if (inner[i] == 1 or rad[i] < ro[clampi(j0, 0, ns - 1)] - layer_gap) else 0.0))   # 只往內：褶的凹處與內層（上衣下襬）都在外層袴面之下
			tgt += p * float(pair[1])
		var wv := clampf(s / 0.06, 0.0, 1.0)
		var posed := P[i].lerp(tgt, wv)
		posed.y = maxf(posed.y, floor_clear * 0.5)
		PO[i] = posed
		if posed.y < 0.0: below += 1
		var bas: Basis = Mv[i]
		var dr := bas.inverse() * (posed - P[i]) if absf(bas.determinant()) > 1e-6 else Vector3.ZERO
		maxd = maxf(maxd, (posed - P[i]).length())
		BS[i] = V[i] + dr
	# 拉伸統計（正座＋垂放 vs 靜止邊長）
	var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var smx := 0.0; var sn := 0; var ne := 0
	for t in range(0, I.size(), 3):
		for e in [[I[t], I[t + 1]], [I[t + 1], I[t + 2]], [I[t + 2], I[t]]]:
			var l0 := V[e[0]].distance_to(V[e[1]])
			if l0 < 0.003: continue
			ne += 1
			var r := PO[e[0]].distance_to(PO[e[1]]) / l0
			smx = maxf(smx, r)
			if r > 1.5: sn += 1
	var stats := {"inner_verts": n_inner, "sectors": sectors, "nodes_per_chain": ns, "skirt_len_m": snappedf(smax, 0.001), "below_floor_after": below,
		"max_disp_m": snappedf(maxd, 0.001), "edge_stretch_max": snappedf(smx, 0.01), "edges_over_1.5x": sn, "edges": ne}
	var nm := ArrayMesh.new()
	nm.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	nm.add_blend_shape(&"SeizaDrape")
	var bs_arr := []; bs_arr.resize(Mesh.ARRAY_MAX)
	bs_arr[Mesh.ARRAY_VERTEX] = BS
	# 垂放後的法線：在正座空間依三角形重算（同位置頂點合併平滑），再以 LBS 線性部分的轉置轉回 rest 空間
	var NB: PackedVector3Array = (arr[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate()
	var keyp := {}; var gid := PackedInt32Array(); gid.resize(nv)
	for i in nv:
		var kk := str(V[i].snappedf(0.00001))
		if not keyp.has(kk): keyp[kk] = keyp.size()
		gid[i] = keyp[kk]
	var acc_n := PackedVector3Array(); acc_n.resize(keyp.size())
	for t in range(0, I.size(), 3):
		var fn := (PO[I[t + 1]] - PO[I[t]]).cross(PO[I[t + 2]] - PO[I[t]])
		for q in 3: acc_n[gid[I[t + q]]] += fn
	for i in nv:
		if sarc[i] <= 0.0: continue
		var npz := acc_n[gid[i]]
		if npz.length() < 1e-9: continue
		var nr := ((Mv[i] as Basis).transposed() * npz.normalized()).normalized()
		if nr.dot(NB[i]) < -0.2 and sarc[i] < 0.03: nr = -nr
		var wv := clampf(sarc[i] / 0.06, 0.0, 1.0)
		NB[i] = NB[i].lerp(nr, wv).normalized()
	bs_arr[Mesh.ARRAY_NORMAL] = NB
	if arr[Mesh.ARRAY_TANGENT] != null: bs_arr[Mesh.ARRAY_TANGENT] = arr[Mesh.ARRAY_TANGENT]
	var fmt := mesh.surface_get_format(0) & ~Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
	nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [bs_arr], {}, fmt)
	nm.surface_set_material(0, mesh.surface_get_material(0))
	nm.surface_set_name(0, mesh.surface_get_name(0))
	var e2 := ResourceSaver.save(nm, out)
	print("DRAPE ", JSON.stringify(stats), " save ", e2, " → ", out)
	quit()
