extends SceneTree
## 阿求 正座袴：把 Blender 布料模擬結果（bake_akyuu_seiza_drape.py 的 npz → 轉成 .bin）做成衣身的 blend shape（可多個）。
## .bin：int32 N，接著 N×3 float32 rest（Godot 座標）、N×3 float32 posed（該姿勢空間，Godot 座標）
## 每個 Godot 頂點以 rest 位置最近點對應到 Blender 頂點（glTF 會在 UV 縫拆點，同位置共用結果），
## 目標＝Blender 該姿勢的布位置；位移以本端 CPU 蒙皮的逐頂點 LBS 線性部分反算回 rest 空間（與 Godot 實際權重一致）。
## 每個 shape：Taubin 平滑 → 推出身體／鞋 → （可選）背後下段放鬆 → 法線（該姿勢空間重算，繞序以多數決對齊原法線）。
## 多個 shape（轉場用的姿勢修正）：重複 --shape=名稱|bin|clip|時間|back_relax
##   例：--shape=SeizaDrape|v5.bin|res://…/seiza_idle_a030_final.res|1.0|40 --shape=SitK60|k60.bin|res://…/seiza_sit_final.res|2.0|0
## 單一舊式：--bin=<file> [--clip=…] [--t=1.0] [--back_relax=40] → 名稱 SeizaDrape
## 定案參數（2026-10-19）：--smooth=16 --smooth_k=0.5；SeizaDrape back_relax 40（輸入 v5：subdiv=1 bend=5 sthick=0.03 cquality=3 quality=6）
## godot --headless --path . -s res://tools/akyuu/apply_akyuu_seiza_bake.gd -- … [--smooth=16] [--margin=0.008] [--out=res://characters/akyuu/akyuu_kimono_seiza_cloth.res]
const GLB := "res://characters/akyuu/akyuu.glb"

var m: Node3D
var sk: Skeleton3D
var ap: AnimationPlayer
var lib: AnimationLibrary

func _initialize() -> void: _go.call_deferred()

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="): return a.split("=", true, 1)[1]
	return d

func _args(k: String) -> PackedStringArray:
	var r := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="): r.append(a.split("=", true, 1)[1])
	return r

func _nearest(p: Vector3, bgrid: Dictionary, BPp: PackedVector3Array, r2: float) -> int:
	var c := Vector3i((p / 0.02).floor()); var best := -1; var bd := r2
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				var k := c + Vector3i(dx, dy, dz)
				if bgrid.has(k):
					for j in bgrid[k]:
						var d := p.distance_squared_to(BPp[j])
						if d < bd: bd = d; best = j
	return best

## 把 mask>0 的布點推出皮膚面（沿最近皮膚點法線距離 < margin 者）；回傳 [新陣列, 推動數]
func _push(G: PackedVector3Array, mask: PackedFloat32Array, bgrid: Dictionary, BPp: PackedVector3Array, BNn: PackedVector3Array, margin: float) -> Array:
	var n := 0
	for g in G.size():
		if mask[g] <= 0.0: continue
		var p := G[g]; var best := _nearest(p, bgrid, BPp, 0.0016)
		if best < 0: continue
		var dn := (p - BPp[best]).dot(BNn[best])
		if dn < margin:
			G[g] = p + BNn[best] * (margin - dn); n += 1
	return [G, n]

## 區域內布點到最近支撐（身體／鞋 3 cm 內；沒有就是到地板）的平均距離＝鼓起量
func _bulge(G: PackedVector3Array, mask: PackedFloat32Array, BPp: PackedVector3Array, bgrid: Dictionary) -> float:
	var s := 0.0; var c := 0
	for g in G.size():
		if mask[g] <= 0.0: continue
		var p := G[g]; var best := _nearest(p, bgrid, BPp, 0.0009)
		s += p.distance_to(BPp[best]) if best >= 0 else p.y
		c += 1
	return s / maxf(c, 1)

func _read_bin(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	var n := f.get_32()
	var BR := PackedVector3Array(); var BP := PackedVector3Array(); BR.resize(n); BP.resize(n)
	for i in n: BR[i] = Vector3(f.get_float(), f.get_float(), f.get_float())
	for i in n: BP[i] = Vector3(f.get_float(), f.get_float(), f.get_float())
	return [BR, BP]

func _go() -> void:
	var specs := []
	for s in _args("shape"):
		var p := s.split("|")
		specs.append({"name": p[0], "bin": p[1], "clip": p[2], "t": float(p[3]), "back": int(p[4]) if p.size() > 4 else 0})
	if specs.is_empty():
		specs.append({"name": "SeizaDrape", "bin": _arg("bin", ""), "clip": _arg("clip", "res://characters/akyuu/anim/seiza_idle_a030_final.res"),
			"t": float(_arg("t", "1.0")), "back": int(_arg("back_relax", "40"))})
	var out := _arg("out", "res://characters/akyuu/akyuu_kimono_seiza_cloth.res")
	m = (load(GLB) as PackedScene).instantiate(); root.add_child(m)
	sk = m.find_child("GeneralSkeleton", true, false)
	ap = AnimationPlayer.new(); m.add_child(ap); ap.root_node = NodePath("../Armature")
	lib = AnimationLibrary.new(); ap.add_animation_library(&"", lib); ap.speed_scale = 0.0
	var mi: MeshInstance3D = m.find_child("衣身", true, false)
	var mesh := mi.mesh as ArrayMesh
	var arr := mesh.surface_get_arrays(0)
	var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]; var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var nv := V.size()
	# 拓樸（同位置頂點合為一點）
	var keyp := {}; var gid := PackedInt32Array(); gid.resize(nv)
	for i in nv:
		var kk := str(V[i].snappedf(0.00001))
		if not keyp.has(kk): keyp[kk] = keyp.size()
		gid[i] = keyp[kk]
	var ng := keyp.size()
	var nb := []; nb.resize(ng)
	for g in ng: nb[g] = {}
	for t in range(0, I.size(), 3):
		for q in 3:
			var a0 := gid[I[t + q]]; var b0 := gid[I[t + (q + 1) % 3]]
			if a0 != b0: nb[a0][b0] = true; nb[b0][a0] = true
	var topo := {"gid": gid, "ng": ng, "nb": nb}
	var bs_list := []
	for k in specs.size():
		var sp: Dictionary = specs[k]
		var res = await _shape(mi, arr, topo, sp, k)
		bs_list.append(res[0])
		print("APPLY ", sp.name, " ", JSON.stringify(res[1]))
	var nm := ArrayMesh.new()
	nm.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	for sp in specs: nm.add_blend_shape(StringName(sp.name))
	var fmt := mesh.surface_get_format(0) & ~Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
	nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, bs_list, {}, fmt)
	nm.surface_set_material(0, mesh.surface_get_material(0))
	nm.surface_set_name(0, mesh.surface_get_name(0))
	var e2 := ResourceSaver.save(nm, out)
	print("SAVE shapes ", specs.size(), " → ", out, " err ", e2)
	quit()

func _shape(mi: MeshInstance3D, arr: Array, topo: Dictionary, sp: Dictionary, k: int) -> Array:
	var bb := _read_bin(sp.bin)
	var BR: PackedVector3Array = bb[0]; var BP: PackedVector3Array = bb[1]; var n := BR.size()
	var cname := StringName("c%d" % k)
	lib.add_animation(cname, load(sp.clip))
	ap.play(cname); ap.seek(sp.t, true)
	await process_frame
	var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]; var Bn: PackedInt32Array = arr[Mesh.ARRAY_BONES]; var W: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var gid: PackedInt32Array = topo.gid; var ng: int = topo.ng; var nb: Array = topo.nb
	var skin := mi.skin
	var Mb := []
	for j in skin.get_bind_count():
		var bi := skin.get_bind_bone(j)
		if bi < 0: bi = sk.find_bone(skin.get_bind_name(j))
		Mb.append(sk.get_bone_global_pose(bi) * skin.get_bind_pose(j))
	var nv := V.size()
	var grid := {}
	for i in n:
		var key := Vector3i((BR[i] / 0.02).floor())
		if not grid.has(key): grid[key] = PackedInt32Array()
		grid[key].append(i)
	var BS := PackedVector3Array(); BS.resize(nv); var PO := PackedVector3Array(); PO.resize(nv)
	var Mv := []; Mv.resize(nv); var SP := PackedVector3Array(); SP.resize(nv)
	var match_max := 0.0; var maxd := 0.0; var below := 0
	for i in nv:
		var bas := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO); var p := Vector3.ZERO
		for q in 4:
			var w := W[i * 4 + q]
			if w > 0.0:
				var T: Transform3D = Mb[Bn[i * 4 + q]]
				p += T * V[i] * w
				bas = Basis(bas.x + T.basis.x * w, bas.y + T.basis.y * w, bas.z + T.basis.z * w)
		Mv[i] = bas
		var c := Vector3i((V[i] / 0.02).floor()); var best := -1; var bd := 1e9
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var kk := c + Vector3i(dx, dy, dz)
					if grid.has(kk):
						for j in grid[kk]:
							var d := V[i].distance_squared_to(BR[j])
							if d < bd: bd = d; best = j
		match_max = maxf(match_max, sqrt(bd))
		PO[i] = BP[best] if best >= 0 else p
		SP[i] = p
	# 平滑（只動有被模擬移動的頂點）
	var smooth_n := int(_arg("smooth", "16")); var smooth_k := float(_arg("smooth_k", "0.5"))
	var G := PackedVector3Array(); G.resize(ng); var gw := PackedFloat32Array(); gw.resize(ng)
	for i in nv:
		G[gid[i]] = PO[i]; gw[gid[i]] = clampf(((PO[i] - SP[i]).length() - 0.01) / 0.03, 0.0, 1.0)
	for it in smooth_n:
		var kk := smooth_k if it % 2 == 0 else -smooth_k * 1.06   # Taubin
		var G2 := G.duplicate()
		for g in ng:
			if gw[g] <= 0.0 or (nb[g] as Dictionary).is_empty(): continue
			var avg := Vector3.ZERO
			for h in nb[g]: avg += G[h]
			avg /= (nb[g] as Dictionary).size()
			var pp := G[g].lerp(avg, kk * gw[g])
			pp.y = maxf(pp.y, 0.003)
			G2[g] = pp
		G = G2
	# 去穿模：該姿勢 CPU 蒙皮身體（腰以下）與鞋子
	var margin := float(_arg("margin", "0.008"))
	var bgrid := {}; var BPp := PackedVector3Array(); var BNn := PackedVector3Array()
	for nm in ["身體", "鞋子右", "鞋子左"]:
		var bm := m.find_child(nm, true, false) as MeshInstance3D
		if bm == null: continue
		var ba := bm.mesh.surface_get_arrays(0)
		var bV: PackedVector3Array = ba[Mesh.ARRAY_VERTEX]; var bN: PackedVector3Array = ba[Mesh.ARRAY_NORMAL]
		var bB: PackedInt32Array = ba[Mesh.ARRAY_BONES]; var bW: PackedFloat32Array = ba[Mesh.ARRAY_WEIGHTS]
		var bMb := []
		for j in bm.skin.get_bind_count():
			var bi := bm.skin.get_bind_bone(j)
			if bi < 0: bi = sk.find_bone(bm.skin.get_bind_name(j))
			bMb.append(sk.get_bone_global_pose(bi) * bm.skin.get_bind_pose(j))
		var nbw := bB.size() / bV.size()
		for i in bV.size():
			var p := Vector3.ZERO; var nn := Vector3.ZERO
			for q in nbw:
				var w := bW[i * nbw + q]
				if w > 0.0:
					var T: Transform3D = bMb[bB[i * nbw + q]]
					p += T * bV[i] * w; nn += T.basis * bN[i] * w
			if p.y > 0.8: continue
			var key := Vector3i((p / 0.02).floor())
			if not bgrid.has(key): bgrid[key] = PackedInt32Array()
			bgrid[key].append(BPp.size()); BPp.append(p); BNn.append(nn.normalized())
	var pushed := 0
	for rep in 2:
		var r := _push(G, gw, bgrid, BPp, BNn, margin)
		G = r[0]; pushed += r[1]
	# 背後下段放鬆（只給正座）
	var back_n: int = sp.back
	var bulge := [0.0, 0.0]
	if back_n > 0:
		var hz := (sk.get_bone_global_pose(sk.find_bone("Hips")).origin).z
		var bz0 := hz + float(_arg("back_z", "0.08")); var by0 := float(_arg("back_y", "0.30"))
		var wb := PackedFloat32Array(); wb.resize(ng)
		for g in ng:
			var p := G[g]
			wb[g] = gw[g] * clampf((bz0 - p.z) / 0.08, 0.0, 1.0) * clampf((by0 + 0.08 - p.y) / 0.08, 0.0, 1.0)
		bulge[0] = _bulge(G, wb, BPp, bgrid)
		for it in back_n:
			var G2 := G.duplicate()
			for g in ng:
				if wb[g] <= 0.0 or (nb[g] as Dictionary).is_empty(): continue
				var avg := Vector3.ZERO
				for h in nb[g]: avg += G[h]
				avg /= (nb[g] as Dictionary).size()
				var pp := G[g].lerp(avg, 0.5 * wb[g]) + Vector3.DOWN * 0.0015 * wb[g]
				pp.y = maxf(pp.y, 0.003)
				G2[g] = pp
			G = G2
			if it % 4 == 3 or it == back_n - 1:
				G = _push(G, wb, bgrid, BPp, BNn, margin)[0]
		bulge[1] = _bulge(G, wb, BPp, bgrid)
	for i in nv:
		PO[i] = G[gid[i]]
		var bas: Basis = Mv[i]; var tgt := PO[i]; var p := SP[i]
		if tgt.y < 0.0: below += 1
		maxd = maxf(maxd, (tgt - p).length())
		BS[i] = V[i] + (bas.inverse() * (tgt - p) if absf(bas.determinant()) > 1e-6 else Vector3.ZERO)
	var smx := 0.0; var sn := 0; var ne := 0
	for t in range(0, I.size(), 3):
		for e in [[I[t], I[t + 1]], [I[t + 1], I[t + 2]], [I[t + 2], I[t]]]:
			var l0: float = V[e[0]].distance_to(V[e[1]])
			if l0 < 0.003: continue
			ne += 1
			var r: float = PO[e[0]].distance_to(PO[e[1]]) / l0
			smx = maxf(smx, r)
			if r > 1.5: sn += 1
	# 法線：該姿勢空間按三角形重算，繞序以「小位移頂點」新舊法線多數決對齊（Godot 正面＝順時針），轉回 rest 空間
	var NB: PackedVector3Array = (arr[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate()
	var acc := PackedVector3Array(); acc.resize(ng)
	for t in range(0, I.size(), 3):
		var fn := (PO[I[t + 1]] - PO[I[t]]).cross(PO[I[t + 2]] - PO[I[t]])
		for q in 3: acc[gid[I[t + q]]] += fn
	var agree := 0; var disagree := 0
	for i in nv:
		var d := (PO[i] - SP[i]).length()
		if d < 0.002 or d > 0.03: continue
		var npz0 := acc[gid[i]]
		if npz0.length() < 1e-12: continue
		var nr0 := ((Mv[i] as Basis).transposed() * npz0.normalized()).normalized()
		if nr0.dot(NB[i]) >= 0.0: agree += 1
		else: disagree += 1
	var sgn := -1.0 if disagree > agree else 1.0
	for i in nv:
		if (PO[i] - SP[i]).length() < 0.002: continue   # 沒被移動的（上衣等）保留原法線
		var npz := acc[gid[i]] * sgn
		if npz.length() < 1e-12: continue
		NB[i] = ((Mv[i] as Basis).transposed() * npz.normalized()).normalized()
	var bs_arr := []; bs_arr.resize(Mesh.ARRAY_MAX)
	bs_arr[Mesh.ARRAY_VERTEX] = BS; bs_arr[Mesh.ARRAY_NORMAL] = NB
	if arr[Mesh.ARRAY_TANGENT] != null: bs_arr[Mesh.ARRAY_TANGENT] = arr[Mesh.ARRAY_TANGENT]
	var stats := {"blender_verts": n, "match_max_m": snappedf(match_max, 0.0001), "max_disp_m": snappedf(maxd, 0.001), "below_floor": below,
		"edge_stretch_max": snappedf(smx, 0.01), "edges_over_1.5x": sn, "edges": ne, "pushed": pushed, "winding": [agree, disagree, sgn],
		"back_gap_cm": [snappedf(bulge[0] * 100.0, 0.01), snappedf(bulge[1] * 100.0, 0.01)]}
	return [bs_arr, stats]
