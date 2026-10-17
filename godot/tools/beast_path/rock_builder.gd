extends RefCounted
## 獸道 自然岩石網格建造器（V1.1，只用在 S04）。
## 取代 V0.1 的「6×6 細分方盒＋平面著色」岩片與「二十面體圓石」（使用者：岩石全是同款多邊形變體、岩壁重複幾何感）。
##
## 做法：焊接的立方體球（每面 n×n）→ 圓角方盒映射（rho 小＝方塊岩、rho 大＝圓石）→ 多層位移：
##   大塊起伏（lump）／水平層理的進退（strata，岩層一層凸一層凹）／脊線裂隙（ridge）／表面粗糙（rough）
## → 平滑法線（焊接頂點，不再平面著色）→ 頂點屬性給 bp_rock.gdshader：
##   COLOR.r 苔（上向面、潮濕）／g 環境遮蔽（凹處、貼地處暗）／b 層理色差／a 腳邊泥土（貼地 1.3 m 內）。
## 碰撞：凸包（取位移後的所有頂點）。
##
## 座標：本地 X＝寬、Y＝高（底部貼 y=0，呼叫端把它埋進地面）、Z＝厚。
## prm 欄位：seed, n（每面格數）, rho（圓角 0.2~0.9）, taper（頂端收窄 0~0.5）, lean（Vector2，頂端相對高度的偏移比例）,
##           lump, strata, ridge, rough（振幅，單位＝最小邊長的比例）, moss（0~1）, step（層理厚度 m）。

static func build(sz: Vector3, prm: Dictionary, xf: Transform3D, ground: Callable) -> Dictionary:
	var n := int(prm.get("n", 10))
	var rho := clampf(float(prm.get("rho", 0.4)), 0.12, 0.95)
	var sd := int(prm["seed"])
	var taper := float(prm.get("taper", 0.25))
	var lean: Vector2 = prm.get("lean", Vector2.ZERO)
	var mn := minf(sz.x, sz.z)
	var a_lump := float(prm.get("lump", 0.16)) * mn
	var a_strata := float(prm.get("strata", 0.05)) * mn
	var a_ridge := float(prm.get("ridge", 0.07)) * mn
	var a_rough := float(prm.get("rough", 0.02)) * mn
	var moss_k := float(prm.get("moss", 0.4))
	var step := float(prm.get("step", 1.6))
	var seed_f := float(sd % 997) * 0.37
	var nz1 := FastNoiseLite.new()
	nz1.seed = sd % 100000
	nz1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz1.frequency = 1.0
	var nz2 := FastNoiseLite.new()
	nz2.seed = (sd + 7919) % 100000
	nz2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz2.frequency = 1.0
	# ---- 1) 焊接立方體球
	var idx := {}
	var U := PackedVector3Array()          # 圓角方盒單位座標 [-1,1]
	var D := PackedVector3Array()          # 位移方向（近似單位法線）
	var tris := PackedInt32Array()
	var inner := 1.0 - rho
	for face in 6:
		var ax := face / 2
		var sg := 1 if face % 2 == 0 else -1
		var a1 := (ax + 1) % 3
		var a2 := (ax + 2) % 3
		var ids := PackedInt32Array()
		ids.resize((n + 1) * (n + 1))
		for j in n + 1:
			for i in n + 1:
				var t := [0, 0, 0]
				t[ax] = sg * n
				t[a1] = 2 * i - n
				t[a2] = 2 * j - n
				var key := Vector3i(t[0], t[1], t[2])
				if not idx.has(key):
					var c := Vector3(float(t[0]), float(t[1]), float(t[2])) / float(n)
					var q := Vector3(clampf(c.x, -inner, inner), clampf(c.y, -inner, inner), clampf(c.z, -inner, inner))
					var d := c - q
					var u := c
					var nd := Vector3.ZERO
					nd[ax] = float(sg)
					if d.length() > 1e-6:
						nd = d.normalized()
						u = q + nd * rho
					idx[key] = U.size()
					U.append(u)
					D.append(nd)
				ids[j * (n + 1) + i] = idx[key]
		for j in n:
			for i in n:
				var v00 := ids[j * (n + 1) + i]
				var v10 := ids[j * (n + 1) + i + 1]
				var v01 := ids[(j + 1) * (n + 1) + i]
				var v11 := ids[(j + 1) * (n + 1) + i + 1]
				# Godot 正面＝由外看順時針。+軸面的 (v00,v10,v11) 由外看是逆時針 → 交換；-軸面本來就是順時針。
				if sg > 0:
					tris.append_array(PackedInt32Array([v00, v11, v10, v00, v01, v11]))
				else:
					tris.append_array(PackedInt32Array([v00, v10, v11, v00, v11, v01]))
	# ---- 2) 位移
	var half := Vector3(sz.x * 0.5, 0.0, sz.z * 0.5)
	var nv := U.size()
	var P := PackedVector3Array()
	P.resize(nv)
	var lump_s := PackedFloat32Array()
	lump_s.resize(nv)
	var tint := PackedFloat32Array()
	tint.resize(nv)
	for k in nv:
		var u := U[k]
		var t := u.y * 0.5 + 0.5
		var tp := 1.0 - taper * smoothstep(0.0, 1.0, t) + 0.05 * sin(t * 11.0 + seed_f)
		var x := u.x * half.x * tp
		var z := u.z * half.z * tp
		var y := t * sz.y
		x += lean.x * sz.y * t * t
		z += lean.y * sz.y * t * t
		var kb := smoothstep(0.03, 0.24, t)                   # 底部不位移（埋在地下，落地線整齊）
		var lp := Vector3(x, y, z)
		var lump := nz1.get_noise_3d(lp.x * 0.20 + seed_f, lp.y * 0.15, lp.z * 0.20) * a_lump \
			+ nz1.get_noise_3d(lp.x * 0.52 + seed_f + 31.0, lp.y * 0.40, lp.z * 0.52) * a_lump * 0.45
		# 層理：每 step m 一層，層內「凸出→回縮」（鋸齒＋緩坡），層界帶雜訊讓它不水平
		var ph := y / step + 0.8 * nz2.get_noise_2d(lp.x * 0.12 + seed_f, lp.z * 0.12)
		var saw := ph - floorf(ph)
		var ledge := (smoothstep(0.0, 0.18, saw) * (1.0 - smoothstep(0.62, 1.0, saw)) - 0.35) * a_strata
		var rg := 1.0 - absf(nz2.get_noise_3d(lp.x * 0.33 + seed_f, lp.y * 0.11, lp.z * 0.33))
		var crack := -smoothstep(0.86, 0.99, rg) * a_ridge * 1.8 + (smoothstep(0.55, 0.85, rg) - 0.5) * a_ridge * 0.5
		var rough := nz2.get_noise_3d(lp.x * 1.35 + 5.0, lp.y * 1.2, lp.z * 1.35) * a_rough
		var disp := (lump + ledge + crack + rough) * kb
		# 側面主要往水平外推，頂面往上
		var nd2 := D[k]
		P[k] = lp + nd2 * disp
		lump_s[k] = lump * kb
		tint[k] = 0.5 + 0.5 * nz1.get_noise_3d(lp.x * 0.08 + 9.0, lp.y * 0.06, lp.z * 0.08)
	# ---- 3) 平滑法線（繞向由拓樸保證一致；逐三角形用「立方體球的外向 D」驗證，不用重心——細長岩片側緣會判錯）
	var NR := PackedVector3Array()
	NR.resize(nv)
	var bad := 0
	var ti := 0
	while ti < tris.size():
		var a := tris[ti]
		var b := tris[ti + 1]
		var c3 := tris[ti + 2]
		var fn := (P[c3] - P[a]).cross(P[b] - P[a])          # CW 三角形的外向法線
		if fn.dot(D[a] + D[b] + D[c3]) < 0.0:
			bad += 1
		NR[a] += fn
		NR[b] += fn
		NR[c3] += fn
		ti += 3
	for k in nv:
		NR[k] = NR[k].normalized() if NR[k].length() > 1e-9 else Vector3.UP
	var fixed := tris
	# ---- 4) 頂點屬性
	var C := PackedColorArray()
	C.resize(nv)
	for k in nv:
		var wp := xf * P[k]
		var gh: float = ground.call(Vector2(wp.x, wp.z))
		var above := wp.y - gh
		var foot := 1.0 - smoothstep(-0.4, 1.3, above)
		var up := clampf((NR[k].y - 0.30) * 1.7, 0.0, 1.0)
		var moss := clampf(moss_k * (up * (0.55 + 0.9 * nz1.get_noise_3d(wp.x * 0.5 + 3.0, wp.y * 0.4, wp.z * 0.5))) + moss_k * 0.35 * foot, 0.0, 1.0)
		var cav := clampf(0.78 + 2.2 * lump_s[k] / maxf(a_lump, 1e-4) * 0.35, 0.45, 1.0)
		var ao := cav * lerpf(0.52, 1.0, smoothstep(0.0, 1.9, above))
		C[k] = Color(moss, ao, tint[k], foot)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = P
	arrays[Mesh.ARRAY_NORMAL] = NR
	arrays[Mesh.ARRAY_COLOR] = C
	arrays[Mesh.ARRAY_INDEX] = fixed
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": mesh, "pts": P, "ntri": fixed.size() / 3, "nv": nv, "bad": bad}


# ================================================================= V1.2 F：Blender Hero Rock
## assets/beast_path/rocks/hero_rock_{a,b,c}.glb（Blender 5.2.1，src/build_hero_rocks.py；Y 向上、原點在底面中心、單一網格）。
## 做法：執行期用 GLTFDocument 讀 GLB（不依賴編輯器匯入快取）→ 取頂點／法線／索引 → 縮放到目標尺寸 →
## 以與 build() 相同的規則算頂點色（COLOR.r 苔、g 環境遮蔽、b 層理色差、a 腳邊泥土）→ 材質仍是同一個 bp_rock.tres。
static var _hero_cache := {}


static func load_hero(hname: String) -> Dictionary:
	if _hero_cache.has(hname):
		return _hero_cache[hname]
	var path := "res://assets/beast_path/rocks/%s.glb" % hname
	if not FileAccess.file_exists(path):
		_hero_cache[hname] = {}
		return {}
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		push_error("Hero Rock 讀不進來：%s" % path)
		_hero_cache[hname] = {}
		return {}
	var scn := doc.generate_scene(st)
	var out := {}
	var stack: Array = [scn]
	while not stack.is_empty() and out.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var m: Mesh = null
		if n is MeshInstance3D:
			m = (n as MeshInstance3D).mesh
		elif n is ImporterMeshInstance3D:
			m = ((n as ImporterMeshInstance3D).mesh as ImporterMesh).get_mesh()
		if m != null:
			var arr := m.surface_get_arrays(0)
			out = {"V": arr[Mesh.ARRAY_VERTEX], "N": arr[Mesh.ARRAY_NORMAL], "I": arr[Mesh.ARRAY_INDEX], "aabb": m.get_aabb(), "sha": FileAccess.get_sha256(path)}
	scn.free()
	_hero_cache[hname] = out
	return out


static func build_hero(hname: String, sz: Vector3, prm: Dictionary, xf: Transform3D, ground: Callable) -> Dictionary:
	var h := load_hero(hname)
	if h.is_empty():
		return {}
	var V0: PackedVector3Array = h["V"]
	var N0: PackedVector3Array = h["N"]
	var I0: PackedInt32Array = h["I"]
	var ab: AABB = h["aabb"]
	var mirror := bool(prm.get("mirror", false))
	var sd := int(prm["seed"])
	var moss_k := float(prm.get("moss", 0.4))
	var sx := sz.x / ab.size.x
	var sy := sz.y / ab.size.y
	var szz := sz.z / ab.size.z
	var cx := ab.position.x + ab.size.x * 0.5
	var cz := ab.position.z + ab.size.z * 0.5
	var mx := -1.0 if mirror else 1.0
	var nz1 := FastNoiseLite.new()
	nz1.seed = sd % 100000
	nz1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz1.frequency = 1.0
	var nv := V0.size()
	var P := PackedVector3Array()
	P.resize(nv)
	var NR := PackedVector3Array()
	NR.resize(nv)
	var C := PackedColorArray()
	C.resize(nv)
	for k in nv:
		var v := V0[k]
		P[k] = Vector3((v.x - cx) * sx * mx, v.y * sy, (v.z - cz) * szz)
		var n := N0[k]
		NR[k] = Vector3(n.x / sx * mx, n.y / sy, n.z / szz).normalized()
	for k in nv:
		var wp := xf * P[k]
		var gh: float = ground.call(Vector2(wp.x, wp.z))
		var above := wp.y - gh
		var foot := 1.0 - smoothstep(-0.4, 1.3, above)
		var up := clampf((NR[k].y - 0.30) * 1.7, 0.0, 1.0)
		var moss := clampf(moss_k * (up * (0.55 + 0.9 * nz1.get_noise_3d(wp.x * 0.5 + 3.0, wp.y * 0.4, wp.z * 0.5))) + moss_k * 0.35 * foot, 0.0, 1.0)
		var tint := 0.5 + 0.5 * nz1.get_noise_3d(P[k].x * 0.08 + 9.0, P[k].y * 0.06, P[k].z * 0.08)
		var cav := clampf(0.82 + 0.28 * nz1.get_noise_3d(P[k].x * 0.7 + 21.0, P[k].y * 0.5, P[k].z * 0.7), 0.5, 1.0)
		var ao := cav * lerpf(0.52, 1.0, smoothstep(0.0, 1.9, above)) * lerpf(0.78, 1.0, smoothstep(-0.55, 0.15, NR[k].y))
		C[k] = Color(moss, ao, tint, foot)
	var idx := I0
	if mirror:                                        # 鏡射翻轉了繞向 → 三角形反過來
		idx = PackedInt32Array()
		idx.resize(I0.size())
		var ti := 0
		while ti < I0.size():
			idx[ti] = I0[ti]
			idx[ti + 1] = I0[ti + 2]
			idx[ti + 2] = I0[ti + 1]
			ti += 3
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = P
	arrays[Mesh.ARRAY_NORMAL] = NR
	arrays[Mesh.ARRAY_COLOR] = C
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": mesh, "pts": P, "ntri": idx.size() / 3, "nv": nv, "bad": 0}
