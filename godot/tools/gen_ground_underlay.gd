extends SceneTree
## Continuous-ground underlay for maps/slice.
## Samples every existing ground mesh's top height on a grid and emits a
## single watertight sheet 0.35 m below it, so gaps between Terrain /
## VillageLandExtension / OuterTerrainTransition / bank skirts show ground
## instead of sky. Over the river channel the sheet dives below the bed.
## Output: res://maps/slice/gen/slice_ground_underlay.res
## Run: godot --headless --path godot --script tools/gen_ground_underlay.gd

const CELL := 5.0
const X0 := -560.0
const X1 := 560.0
const Z0 := -460.0
const Z1 := 572.0
const DROP := 0.22          # sheet sits this far below sampled ground
const CHANNEL_Y := -9.6     # below the deepest river bed (-8.85)
const GROUND_NODES := [
	"Terrain",
	"RiverV3_Candidate/VillageLandExtension",
	"RiverV3_Candidate/OuterTerrainTransition",
	"RiverV3_Candidate/EastTailLandConnection",
	"RiverV3_Candidate/WestTailLandConnection",
	"RiverV3_Candidate/InnerDryBank",
	"RiverV3_Candidate/OuterDryBank",
]
const WATER_NODE := "RiverV3_Candidate/RiverWater"

var _bins: Dictionary = {}
const BIN := 40.0

func _bin_key(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / BIN)), int(floor(z / BIN)))

func _add_mesh(mi: MeshInstance3D, tag: int) -> void:
	var mesh: ArrayMesh = mi.mesh as ArrayMesh
	if mesh == null:
		return
	var off: Vector3 = mi.transform.origin
	for s in range(mesh.get_surface_count()):
		var arr: Array = mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var n: int = idx.size() if idx.size() > 0 else vs.size()
		for f in range(0, n, 3):
			var a: Vector3
			var b: Vector3
			var c: Vector3
			if idx.size() > 0:
				a = vs[idx[f]] + off; b = vs[idx[f + 1]] + off; c = vs[idx[f + 2]] + off
			else:
				a = vs[f] + off; b = vs[f + 1] + off; c = vs[f + 2] + off
			var minx: float = min(a.x, min(b.x, c.x))
			var maxx: float = max(a.x, max(b.x, c.x))
			var minz: float = min(a.z, min(b.z, c.z))
			var maxz: float = max(a.z, max(b.z, c.z))
			var k0 := _bin_key(minx, minz)
			var k1 := _bin_key(maxx, maxz)
			for bx in range(k0.x, k1.x + 1):
				for bz in range(k0.y, k1.y + 1):
					var key := Vector2i(bx, bz)
					if not _bins.has(key):
						_bins[key] = []
					(_bins[key] as Array).append([a, b, c, tag])

func _sample(x: float, z: float) -> Vector2:
	# returns (ground_top or -1e9, water_flag)
	var key := _bin_key(x, z)
	var top: float = -1e9
	var water: float = 0.0
	if not _bins.has(key):
		return Vector2(top, water)
	for t_any in (_bins[key] as Array):
		var t: Array = t_any
		var y: float = _tri_y(t[0], t[1], t[2], x, z)
		if y > -1e8:
			if int(t[3]) == 1:
				water = 1.0
			else:
				top = max(top, y)
	return Vector2(top, water)

func _tri_y(a: Vector3, b: Vector3, c: Vector3, px: float, pz: float) -> float:
	var d: float = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if abs(d) < 0.000001:
		return -1e9
	var w0: float = ((b.z - c.z) * (px - c.x) + (c.x - b.x) * (pz - c.z)) / d
	var w1: float = ((c.z - a.z) * (px - c.x) + (a.x - c.x) * (pz - c.z)) / d
	var w2: float = 1.0 - w0 - w1
	if w0 < -0.02 or w1 < -0.02 or w2 < -0.02:
		return -1e9
	return a.y * w0 + b.y * w1 + c.y * w2

func _init() -> void:
	var ps: PackedScene = load("res://maps/slice/slice.tscn")
	var root: Node = ps.instantiate()
	for path in GROUND_NODES:
		var mi: MeshInstance3D = root.get_node(path) as MeshInstance3D
		if mi == null:
			print("MISSING ground node: ", path)
			continue
		_add_mesh(mi, 0)
	var wm: MeshInstance3D = root.get_node(WATER_NODE) as MeshInstance3D
	_add_mesh(wm, 1)
	print("bins: ", _bins.size())

	var nx: int = int((X1 - X0) / CELL) + 1
	var nz: int = int((Z1 - Z0) / CELL) + 1
	var hs: PackedFloat32Array = PackedFloat32Array()
	hs.resize(nx * nz)
	var covered: PackedByteArray = PackedByteArray()
	covered.resize(nx * nz)
	var holes: int = 0
	for iz in range(nz):
		for ix in range(nx):
			var x: float = X0 + ix * CELL
			var z: float = Z0 + iz * CELL
			var r: Vector2 = _sample(x, z)
			var i: int = iz * nx + ix
			if r.y > 0.5 and r.x < -1e8:
				hs[i] = CHANNEL_Y; covered[i] = 1      # channel interior
			elif r.x > -1e8:
				hs[i] = min(r.x - DROP, r.x * 0.0 + r.x - DROP); covered[i] = 1
				if r.y > 0.5:
					hs[i] = min(hs[i], CHANNEL_Y)      # water also present -> stay low
			else:
				hs[i] = -0.6; covered[i] = 0; holes += 1
	print("grid %dx%d, uncovered=%d" % [nx, nz, holes])

	# smooth uncovered points from covered neighbours (3 passes)
	for pass_i in range(3):
		for iz in range(nz):
			for ix in range(nx):
				var i: int = iz * nx + ix
				if covered[i] == 1:
					continue
				var acc: float = 0.0
				var cnt: int = 0
				for o in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
					var jx: int = ix + o.x
					var jz: int = iz + o.y
					if jx < 0 or jz < 0 or jx >= nx or jz >= nz:
						continue
					acc += hs[jz * nx + jx]; cnt += 1
				if cnt > 0:
					hs[i] = acc / cnt

	# build the sheet — front faces up, project winding rule (clockwise)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in range(nz - 1):
		for ix in range(nx - 1):
			var x0: float = X0 + ix * CELL
			var z0: float = Z0 + iz * CELL
			var x1: float = x0 + CELL
			var z1: float = z0 + CELL
			var ha: float = hs[iz * nx + ix]
			var hb: float = hs[iz * nx + ix + 1]
			var hc: float = hs[(iz + 1) * nx + ix]
			var hd: float = hs[(iz + 1) * nx + ix + 1]
			var va := Vector3(x0, ha, z0)
			var vb := Vector3(x1, hb, z0)
			var vc := Vector3(x0, hc, z1)
			var vd := Vector3(x1, hd, z1)
			st.add_vertex(va); st.add_vertex(vb); st.add_vertex(vc)
			st.add_vertex(vb); st.add_vertex(vd); st.add_vertex(vc)
	st.generate_normals()
	var mesh_out: ArrayMesh = st.commit()
	# self-check: normals must point up; flip if not
	var arr0: Array = mesh_out.surface_get_arrays(0)
	var nrm: PackedVector3Array = arr0[Mesh.ARRAY_NORMAL]
	if nrm.size() > 0 and nrm[0].y < 0.0:
		print("normals down -> flipping winding")
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for iz in range(nz - 1):
			for ix in range(nx - 1):
				var x0: float = X0 + ix * CELL
				var z0: float = Z0 + iz * CELL
				var x1: float = x0 + CELL
				var z1: float = z0 + CELL
				var ha: float = hs[iz * nx + ix]
				var hb: float = hs[iz * nx + ix + 1]
				var hc: float = hs[(iz + 1) * nx + ix]
				var hd: float = hs[(iz + 1) * nx + ix + 1]
				var va := Vector3(x0, ha, z0)
				var vb := Vector3(x1, hb, z0)
				var vc := Vector3(x0, hc, z1)
				var vd := Vector3(x1, hd, z1)
				st.add_vertex(va); st.add_vertex(vc); st.add_vertex(vb)
				st.add_vertex(vb); st.add_vertex(vc); st.add_vertex(vd)
		st.generate_normals()
		mesh_out = st.commit()
	DirAccess.make_dir_recursive_absolute("res://maps/slice/gen")
	var err: int = ResourceSaver.save(mesh_out, "res://maps/slice/gen/slice_ground_underlay.res")
	print("saved err=", err, " faces=", mesh_out.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3)
	quit()
