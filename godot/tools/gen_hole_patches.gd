extends SceneTree
## Detect open-edge loops (holes) in Vista and OuterTerrainTransition and
## emit fan-fill patch geometry so no sky shows through the hills.
## Loops touching the mesh's outer rim are skipped (only interior holes and
## elevated arches are patched). Output: res://maps/slice/gen/slice_hole_patches.res
## Run: godot --headless --path godot --script tools/gen_hole_patches.gd

const TARGETS := ["Vista", "RiverV3_Candidate/OuterTerrainTransition"]
const MIN_LOOP := 3
const MAX_LOOP := 4000

func _init() -> void:
	var ps: PackedScene = load("res://maps/slice/slice.tscn")
	var root: Node = ps.instantiate()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var patched: int = 0
	for path in TARGETS:
		var mi: MeshInstance3D = root.get_node(path) as MeshInstance3D
		var mesh: ArrayMesh = mi.mesh as ArrayMesh
		var off: Vector3 = mi.transform.origin
		for surf in range(mesh.get_surface_count()):
			var arr: Array = mesh.surface_get_arrays(surf)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			# weld duplicated vertices by position (glb/procgen often split verts)
			var remap: PackedInt32Array = PackedInt32Array()
			remap.resize(vs.size())
			var seen: Dictionary = {}
			for i in range(vs.size()):
				var k := Vector3i(int(round(vs[i].x * 50.0)), int(round(vs[i].y * 50.0)), int(round(vs[i].z * 50.0)))
				if seen.has(k):
					remap[i] = seen[k]
				else:
					seen[k] = i
					remap[i] = i
			var n: int = idx.size() if idx.size() > 0 else vs.size()
			var edges: Dictionary = {}
			for f in range(0, n, 3):
				var a: int
				var b: int
				var c: int
				if idx.size() > 0:
					a = remap[idx[f]]; b = remap[idx[f + 1]]; c = remap[idx[f + 2]]
				else:
					a = remap[f]; b = remap[f + 1]; c = remap[f + 2]
				for e in [[a, b], [b, c], [c, a]]:
					var key := Vector2i(min(e[0], e[1]), max(e[0], e[1]))
					edges[key] = edges.get(key, 0) + 1
			# open edges -> adjacency
			var adj: Dictionary = {}
			var open_count: int = 0
			for key in edges:
				if edges[key] == 1:
					open_count += 1
					for pair in [[key.x, key.y], [key.y, key.x]]:
						if not adj.has(pair[0]):
							adj[pair[0]] = []
						(adj[pair[0]] as Array).append(pair[1])
			print("%s surf %d: open edges = %d" % [path, surf, open_count])
			# walk loops
			var visited: Dictionary = {}
			for start in adj:
				if visited.has(start):
					continue
				var loop: Array = [start]
				visited[start] = true
				var cur: int = start
				var prev: int = -1
				while true:
					var nbrs: Array = adj.get(cur, [])
					var nxt: int = -1
					for nb in nbrs:
						if nb != prev and not visited.has(nb):
							nxt = nb
							break
					if nxt == -1:
						# closed back to start?
						break
					visited[nxt] = true
					loop.append(nxt)
					prev = cur
					cur = nxt
					if loop.size() > MAX_LOOP:
						break
				if loop.size() < MIN_LOOP or loop.size() > MAX_LOOP:
					continue
				# loop stats
				var lo := Vector3(1e9, 1e9, 1e9)
				var hi := Vector3(-1e9, -1e9, -1e9)
				var cen := Vector3.ZERO
				for vi in loop:
					var p: Vector3 = vs[vi] + off
					lo = lo.min(p); hi = hi.max(p); cen += p
				cen /= float(loop.size())
				var span: Vector3 = hi - lo
				# skip the mesh's outer rim (huge loop hugging the AABB border)
				var maabb: AABB = mesh.get_aabb()
				var rim: bool = span.x > maabb.size.x * 0.8 and span.z > maabb.size.z * 0.8
				if rim:
					print("  skip rim loop: %d verts span %s" % [loop.size(), str(span)])
					continue
				print("  HOLE loop: %d verts  center %s  span %s" % [loop.size(), str(cen), str(span)])
				# curtain: drop every open edge down to the ground so nothing
				# behind the rim shows through (arch segments become walls)
				var floor_y: float = -2.0
				for j in range(loop.size()):
					var a3: Vector3 = vs[loop[j]] + off
					var b3: Vector3 = vs[loop[(j + 1) % loop.size()]] + off
					if a3.distance_to(b3) > 60.0:
						continue  # not a real edge (loop-walk jump)
					var a0 := Vector3(a3.x, floor_y, a3.z)
					var b0 := Vector3(b3.x, floor_y, b3.z)
					st.add_vertex(a3); st.add_vertex(b3); st.add_vertex(a0)
					st.add_vertex(b3); st.add_vertex(b0); st.add_vertex(a0)
					st.add_vertex(a3); st.add_vertex(a0); st.add_vertex(b3)
					st.add_vertex(b3); st.add_vertex(a0); st.add_vertex(b0)
				patched += 1
	if patched == 0:
		print("no holes found; nothing written")
		quit()
		return
	st.generate_normals()
	var out: ArrayMesh = st.commit()
	var err: int = ResourceSaver.save(out, "res://maps/slice/gen/slice_hole_patches.res")
	print("patched %d loops, saved err=%d" % [patched, err])
	quit()
