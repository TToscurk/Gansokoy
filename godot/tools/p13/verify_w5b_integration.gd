extends "res://tools/p13/verify_w5a_sample.gd"
## W5B integration local audit. Historical sample verifier remains available as a base.
const WS := preload("res://tools/p13/w4_walk_surface.gd")
const UP := preload("res://tools/p13/w5b_upper_plan.gd")

func _s_lat(p: Vector3) -> Vector2:
	var best := INF
	var bk := 0
	for k in range(maxi(W5.scope_lo - 60, 0), mini(W5.scope_hi + 60, cl.size() - 1)):
		var d := cl[k].distance_squared_to(Vector2(p.x, p.z))
		if d < best:
			best = d
			bk = k
	return Vector2(bk * 0.05, sqrt(best))

func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 6:
		await physics_frame
	cl = SA.centerline()
	sp = v.get_world_3d().direct_space_state
	var H := SA.ramp_profile(v, cl)
	var st := SA.steps(cl, H)
	var rp := SA.ramp_points(st, H)
	var kr := W4.pilot_k_range(st)
	var plan := W4.replan(cl, H, st, rp)
	var touts := [W4.outer_profile(sp, cl, kr, -1.0), W4.outer_profile(sp, cl, kr, 1.0)]
	var tfars := [W4.outer_profile(sp, cl, kr, -1.0, W4.U_FAR), W4.outer_profile(sp, cl, kr, 1.0, W4.U_FAR)]
	var lanterns := []
	for ls in SA.lantern_specs(cl, H, st, sp):
		var sl := float(ls["s"])
		if sl >= kr.x * 0.05 - 2.0 and sl <= kr.y * 0.05 + 2.0 and not lanterns.has(sl):
			lanterns.append(sl)
	W5.setup(v, sp, cl)
	W4.flags = {"w5b": false}
	var before := W4.build_meshes(cl, H, plan, touts, tfars, lanterns)
	W4.flags = {}
	var after := W4.build_meshes(cl, H, plan, touts, tfars, lanterns)
	var added := _diff(_tris(after["steps"]), _tris(before["steps"]))
	var removed := _diff(_tris(before["steps"]), _tris(after["steps"]))
	var soil := _diff(_tris(after["soil"]), _tris(before["soil"]))
	_ok(added.size() > 0 and removed.size() > 0, "W5B replaces old sides, not an empty overlay")
	_ok(_scope_bad(added, 37.1, 64.3) == 0 and _scope_bad(removed, 37.1, 64.3) == 0, "changed stones inside approved lower range")
	_ok(_ground_bad(soil, -0.06, 0.62) == 0, "soil actually grounded on P1; no sunk/floating patch")
	_ok(_lantern_bad(added, lanterns, 1.62) == 0, "new stones avoid lantern feet")
	var nb := 0
	var fl := 0
	var worst := INF
	for d: Dictionary in W4.diag:
		if not bool(d.get("base", false)):
			continue
		var y := _terr(d["p"])
		if is_nan(y):
			fl += 1
			continue
		nb += 1
		var gap := y - float(d["ybot"])
		worst = minf(worst, gap)
		if gap < 0.08:
			fl += 1
	_ok(nb > 50 and fl == 0, "base stones grounded %d; violations %d; minimum embed %.3f m" % [nb, fl, worst])
	for sd in W5.stats:
		var r: Dictionary = W5.stats[sd]
		_ok(_cover_ok(float(r["stats"]["cover_max"])), "soil cover side %s within approved limit" % str(sd))
		print("[W5B] side %s bands %s" % [str(sd), str(r["bands"])])
	var ov := v.get_node(W4.NODE_NAME)
	var changed_walk := 0
	for t: Array in added.values()+removed.values():
		var c: Vector3 = ((t[0] as Vector3)+(t[1] as Vector3)+(t[2] as Vector3))/3.0
		if _s_lat(c).y<0.98:
			changed_walk+=1
	_ok(changed_walk==0,"approved lower tread/platform/joint geometry unchanged; changed walking triangles %d"%changed_walk)
	if "--approved" in OS.get_cmdline_user_args():
		var approved_path := OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--approved")+1]
		var ap := (load(approved_path) as PackedScene).instantiate()
		var approved_tris := _tris((ap.get_node("W4Steps") as MeshInstance3D).mesh)
		var changed := _diff(approved_tris,_tris(after["steps"]))
		var added_approved := _diff(_tris(after["steps"]),approved_tris)
		var touched := 0
		for t: Array in changed.values()+added_approved.values():
			var c: Vector3=((t[0] as Vector3)+(t[1] as Vector3)+(t[2] as Vector3))/3.0
			if _s_lat(c).y<0.98:
				touched+=1
		_ok(touched==0,"actual a6fe076 approved saved walking geometry unchanged; altered %d"%touched)
		ap.free()
	await _cap_holes(v,ov,cl,W5.runs,touts,tfars,lanterns)
	_ok(ov.find_children("*", "CollisionObject3D", true, false).is_empty(), "no added collision bodies")
	var wb := SA.winding_bad(ov)
	_ok(int(wb[0]) == 0, "winding wrong %d / %d" % [int(wb[0]), int(wb[1])])
	for nm in ["W4Steps", "W4Soil"]:
		var a: PackedVector3Array = (ov.get_node(nm) as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var b: PackedVector3Array = (after["steps" if nm == "W4Steps" else "soil"] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var md := 0.0
		if a.size() == b.size():
			for j in a.size():
				md = maxf(md, a[j].distance_to(b[j]))
		_ok(a.size() == b.size() and md < 1e-4, "%s saved=recomputed vertices %d max delta %.6f" % [nm, a.size(), md])
	var pn := ov.get_node("W5Plants")
	_ok(pn.get_child_count() == W5.plants.size(), "saved plant count = generator")
	var badplant := 0
	for it: Dictionary in W5.plants:
		var p: Vector3 = it["p"]
		var dy := p.y - _terr(Vector2(p.x, p.z))
		if not is_finite(dy) or dy < -0.12 or dy > 0.45:
			badplant += 1
	_ok(badplant == 0, "plants on actual soil, no floating")
	# Reuse same ground/scope functions with deliberately broken data.
	var far := Vector3(cl[600].x, 10, cl[600].y)
	_ok(_scope_bad({"bad": [far, far + Vector3(0.1,0,0), far + Vector3(0,0,0.1)]},37.1,64.3)>0,"negative: outside lower scope")
	var bad := {}
	for key in soil:
		var t: Array = soil[key]
		var n := ((t[2] as Vector3)-(t[0] as Vector3)).cross((t[1] as Vector3)-(t[0] as Vector3))
		if n.length()>0.001 and n.normalized().y>0.5:
			bad[key]=[(t[0] as Vector3)+Vector3.UP*1.2,(t[1] as Vector3)+Vector3.UP*1.2,(t[2] as Vector3)+Vector3.UP*1.2]
			break
	_ok(_ground_bad(bad,-0.06,0.62)>0,"negative: floating soil")
	_ok(not _cover_ok(0.8),"negative: excessive soil cover")
	await _verify_upper(v,H,st,rp,lanterns)
	print("[W5B] result failures %d" % fails)
	quit(1 if fails else 0)

func _verify_upper(v: Node3D,H: PackedFloat32Array,st: Array,rp: Array,lamps0: Array) -> void:
	var ov := v.get_node(W4.NODE_NAME)
	var upper := ov.get_node_or_null("W5Upper")
	_ok(upper != null,"upper production group exists")
	if upper == null:
		return
	var lamps := lamps0.duplicate()
	for it in SA.lantern_specs(cl,H,st,sp):
		if not lamps.has(float(it["s"])):
			lamps.append(float(it["s"]))
	var plan := UP.plan(cl,H,st,rp)
	var kr := Vector2i(UP.START,UP.END)
	W5.scope_lo = UP.START
	W5.scope_hi = UP.END
	W5.setup(v,sp,cl)
	W4.flags = {"mesh_seed":UP.SEED,"initial_y":UP.initial_y(st)}
	var ms := W4.build_meshes(cl,H,plan,[W4.outer_profile(sp,cl,kr,-1.0),W4.outer_profile(sp,cl,kr,1.0)],
		[W4.outer_profile(sp,cl,kr,-1.0,W4.U_FAR),W4.outer_profile(sp,cl,kr,1.0,W4.U_FAR)],lamps)
	await _cap_holes(v,upper,cl,W5.runs,[W4.outer_profile(sp,cl,kr,-1.0),W4.outer_profile(sp,cl,kr,1.0)],
		[W4.outer_profile(sp,cl,kr,-1.0,W4.U_FAR),W4.outer_profile(sp,cl,kr,1.0,W4.U_FAR)],lamps)
	var same := true
	for nm in ["W4Steps","W4Soil"]:
		var a: PackedVector3Array = (upper.get_node(nm) as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var b: PackedVector3Array = (ms["steps" if nm=="W4Steps" else "soil"] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		if a.size()!=b.size():
			same=false
		else:
			for j in a.size():
				if a[j].distance_to(b[j])>1e-4:
					same=false
	_ok(same,"upper saved meshes = recomputed same-seed production generator")
	var upper_soil := {}
	var all_upper_soil:=_tris(ms["soil"])
	for key in all_upper_soil:
		var t: Array=all_upper_soil[key]
		var c: Vector3=((t[0] as Vector3)+(t[1] as Vector3)+(t[2] as Vector3))/3.0
		if _s_lat(c).y>1.38:
			upper_soil[key]=t
	_ok(_ground_bad(upper_soil,-0.06,0.62)==0,"upper soil grounded on frozen P1")
	var psame: bool = upper.get_node("W5Plants").get_child_count()==W5.plants.size()
	_ok(psame,"upper plants saved count = generator")
	var pbad := 0
	var rd := W4.ramp_dense(rp,cl.size())
	var prev := UP.initial_y(st)
	for a: Dictionary in plan:
		if a["kind"]=="landing":
			var orig: Dictionary = st.filter(func(x: Dictionary)->bool:return x["kind"]=="landing" and x["k0"]==a["k0"])[0]
			if a["k1"]!=orig["k1"] or a["y0"]!=orig["y0"] or a["y1"]!=orig["y1"]:
				pbad+=1
		else:
			var rise := float(a["y0"])-prev
			for k in range(int(a["k0"]),int(a["k1"])+1):
				if absf(rd[k]-float(a["y0"]))>W4.dev_limit(rise)+0.001:
					pbad+=1
		prev=float(a["y1"])
	_ok(pbad==0,"upper tread plan remains within original collision band; platform position/elevation unchanged")
	var grounded := 0
	var gbad := 0
	var embed := INF
	for d: Dictionary in W4.diag:
		if bool(d.get("base",false)):
			var gap := _terr(d["p"])-float(d["ybot"])
			grounded+=1
			embed=minf(embed,gap)
			if not is_finite(gap) or gap<0.08:
				gbad+=1
	_ok(gbad==0 and grounded>0,"upper base stones %d grounded; minimum embed %.3f m; violations %d" % [grounded,embed,gbad])
	var baseline := (load("res://maps/village_v2/gen/shrine_approach_p10.scn") as PackedScene).instantiate()
	var g0 := WS.TopGrid.new()
	g0.add_mesh((baseline.get_node("StoneSteps") as MeshInstance3D).mesh)
	var g1 := WS.TopGrid.new()
	g1.add_mesh((v.get_node("ShrineApproachP10/StoneSteps") as MeshInstance3D).mesh)
	for n in ov.find_children("*","MeshInstance3D",true,false):
		if String(n.name) in ["W4Steps","W4Soil"]:
			g1.add_mesh((n as MeshInstance3D).mesh)
	var lats := [0.0,0.5,-0.5,0.85,-0.85]
	var measured := WS.measure(sp,cl,UP.START,UP.END,lats,[g0,g1])
	var vok := true
	for u in lats:
		var before := WS.summarize(measured[0][u])
		var after := WS.summarize(measured[1][u])
		print("[UPPER-SURFACE] u=%s %s | %s" % [str(u),WS.fmt("before",before),WS.fmt("after",after)])
		if int(after["n"])<UP.END-UP.START-2 or not WS.gate_ok(after,before):
			vok=false
	_ok(vok,"upper visible stone vs actual saved ramp: no missing walk surface and no deterioration")
	var join_bad := 0
	for kk in [1284,1542,1797]:
		for u: float in lats:
			for k in range(kk-3,kk+4):
				var t:=SA.tangent(cl,k)
				var p:=cl[k]+Vector2(-t.y,t.x)*u
				var y:=g1.top_at(p.x,p.y)
				if is_nan(y) or absf(y-WS.ramp_y(sp,p))>0.15:
					join_bad+=1
	_ok(join_bad==0,"joins s64.2 /77.1 /89.85 have no walk hole or >15 cm surface mismatch; bad %d"%join_bad)
	# Original r8 triangles removed exactly once in replaced range.
	var expected := W4.r8_without_range((baseline.get_node("StoneSteps") as MeshInstance3D).mesh as ArrayMesh,cl,Vector2i(744,UP.END))
	var actual := (v.get_node("ShrineApproachP10/StoneSteps") as MeshInstance3D).mesh
	_ok(expected.surface_get_arrays(0)[Mesh.ARRAY_INDEX]==actual.surface_get_arrays(0)[Mesh.ARRAY_INDEX],"no old/new double visible steps/walls in replaced range")
	baseline.free()
	W4.flags={}
	W5.scope_lo=744
	W5.scope_hi=1284

func _cover_ok(value: float) -> bool:
	return is_finite(value) and value<=W5.MAX_COVER+0.01

func _cap_holes(v: Node3D,ov: Node,cline: PackedVector2Array,runs: Dictionary,touts: Array,tfars: Array,lamps: Array) -> void:
	var body := StaticBody3D.new()
	body.collision_layer=1<<29
	body.collision_mask=0
	for nm in ["W4Steps","W4Soil"]:
		var sh := CollisionShape3D.new()
		sh.shape=(ov.get_node(nm) as MeshInstance3D).mesh.create_trimesh_shape()
		body.add_child(sh)
	v.add_child(body)
	await physics_frame
	await physics_frame
	var probes := 0
	var holes := 0
	var control: PhysicsRayQueryParameters3D
	for si in 2:
		var sd: float=[-1.0,1.0][si]
		var ctx := W5._make_ctx(cline,sd,runs[sd],touts[si],tfars[si],lamps)
		for k in range(int(ctx["ka"])+2,int(ctx["kb"])-2,2):
			var normal:=SA.tangent(cline,k)
			var outward:=Vector2(-normal.y,normal.x)*sd
			var u:=W5._at(ctx,"u_top",float(k))
			for drop: float in [0.10,0.18,0.25]:
				var y:=W5._at(ctx,"line",float(k))-drop
				var p:=cline[k]+outward*(u+0.04)
				if y<=_terr(p)+0.04:
					continue  # buried in real P1 hill, not a visible opening
				var start:=cline[k]+outward*(u+0.4)
				var end:=cline[k]+outward*(u-0.12)
				var q:=PhysicsRayQueryParameters3D.create(Vector3(start.x,y,start.y),Vector3(end.x,y,end.y),1<<29)
				q.hit_back_faces=true
				var hit:=sp.intersect_ray(q)
				probes+=1
				if not hit.is_empty():
					control=q
				if hit.is_empty():
					holes+=1
					print("[CAP-HOLE] sd=%s s=%.2f drop=%.2f u=%.3f y=%.3f"%[str(sd),k*0.05,drop,u,y])
					var grid:=WS.TopGrid.new()
					grid.add_mesh((ov.get_node("W4Steps") as MeshInstance3D).mesh)
					for du: float in [-0.08,-0.03,0.0,0.03,0.08]:
						var cp:=cline[k]+outward*(u+du)
						print("[CAP-PROFILE] du %.3f actual top %.4f"%[du,grid.top_at(cp.x,cp.y)])
	_ok(probes>20 and holes==0,"actual under-cap geometry rays %d; visible holes %d"%[probes,holes])
	body.collision_layer=0
	await physics_frame
	_ok(control!=null and sp.intersect_ray(control).is_empty(),"negative: removed isolated backing has no ray hit")
	body.free()
