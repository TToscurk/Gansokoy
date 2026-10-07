extends SceneTree
## R3c W3 Drink A/B metric probe (read-only; never saves scenes/resources).
## For each candidate clip on chaya_f01, samples 30 fps and measures, in the
## Head-bone local frame: cup rim vs mouth/nose/forehead, shoulder raise, elbow
## flare, and cup-vs-head/hair vertex penetration (normal-side test).
const CLIPS={"A_drinking_a030":"drinking_a030","B1_drinking_im1_a030":"drinking_im1_a030","B2_watercooler_a030":"watercooler_a030"}
var sk: Skeleton3D
func _initialize():
 run.call_deferred()
func bone(nm: String) -> Transform3D:
 return sk.global_transform*sk.get_bone_global_pose(sk.find_bone(nm))
func cup_xf(side: String) -> Transform3D:
 # Same formula as npc_activity_overlay.gd (left); right is the mirror.
 var hand=bone(side+"Hand")
 var palm=bone(side+"MiddleProximal").origin
 if side=="Left":
  return Transform3D(Basis(hand.basis.y,-hand.basis.x,hand.basis.z),palm+hand.basis.z*0.022+hand.basis.x*0.020)
 return Transform3D(Basis(-hand.basis.y,hand.basis.x,hand.basis.z),palm+hand.basis.z*0.022-hand.basis.x*0.020)
func run():
 var out_path=OS.get_cmdline_user_args()[0]
 var n=load("res://characters/npc/chaya_f01/chaya_f01.tscn").instantiate()
 root.add_child(n)
 await process_frame
 sk=n.find_child("GeneralSkeleton",true,false)
 var head_i=sk.find_bone("Head")
 var head_rest_inv=(sk.global_transform*sk.get_bone_global_rest(head_i)).affine_inverse()
 # Rigid head/hair vertices (dominant weight on Head) in head-local rest frame.
 var pts=PackedVector3Array(); var nrm=PackedVector3Array(); var face=PackedVector3Array()
 for mi in sk.find_children("*","MeshInstance3D",true,false):
  var a=mi.mesh.surface_get_arrays(0)
  var v: PackedVector3Array=a[Mesh.ARRAY_VERTEX]; var nn: PackedVector3Array=a[Mesh.ARRAY_NORMAL]
  var bo=a[Mesh.ARRAY_BONES]; var we=a[Mesh.ARRAY_WEIGHTS]
  var stride=bo.size()/v.size()
  for i in v.size():
   var w=0.0
   for k in stride:
    if int(bo[i*stride+k])==head_i: w+=we[i*stride+k]
   if w<0.6: continue
   var gp=mi.global_transform*v[i]
   var lp=head_rest_inv*gp
   pts.append(lp); nrm.append((head_rest_inv.basis*(mi.global_transform.basis*nn[i])).normalized())
   if mi.name=="NPC_Body": face.append(lp)
 # Face-front strip -> chin..brow range, normalized face height (0 chin, 1 brow top).
 var fwd_axis=(head_rest_inv.basis*n.global_basis.z).normalized()
 var up_axis=(head_rest_inv.basis*Vector3.UP).normalized()
 var maxf_=-1e9
 for p in face: maxf_=maxf(maxf_,p.dot(fwd_axis))
 var ymin=1e9; var ymax=-1e9
 for p in face:
  if p.dot(fwd_axis)>maxf_-0.025:
   ymin=minf(ymin,p.dot(up_axis)); ymax=maxf(ymax,p.dot(up_axis))
 var mouth_h=ymin+0.22*(ymax-ymin)
 var mouth=Vector3.ZERO
 var best=1e9
 for p in face:
  var d=absf(p.dot(up_axis)-mouth_h)+absf(p.dot(fwd_axis)-maxf_)*0.5
  if d<best: best=d; mouth=p
 # Cup sample points (rim top + body) in cup-local.
 var cup_pts=[]
 for j in 4:
  for i in 12:
   var r=[0.027,0.036,0.034,0.031][j]; var y=[0.0,0.072,0.05,0.025][j]
   cup_pts.append(Vector3(sin(TAU*i/12.0)*r,y,cos(TAU*i/12.0)*r))
 var ap: AnimationPlayer=n.player
 var report={"mouth_head_local":str(mouth),"face_chin_h":ymin,"face_top_h":ymax,"candidates":{}}
 for key in CLIPS:
  var an: Animation=load("res://animations/npc_activity_p10/chaya_f01/%s_grounded.res"%CLIPS[key])
  var lib=AnimationLibrary.new(); lib.add_animation(&"c",an)
  if ap.has_animation_library(&"ab"): ap.remove_animation_library(&"ab")
  ap.add_animation_library(&"ab",lib)
  ap.play(&"ab/c"); ap.speed_scale=0.0
  ap.seek(0.0,true); await process_frame
  var rest={}
  for side in ["Left","Right"]:
   var hips=bone("Hips")
   rest[side]={"sh":bone(side+"UpperArm").origin.y,"el":absf((hips.affine_inverse()*bone(side+"LowerArm").origin).x)}
  var per_side={}
  for side in ["Left","Right"]:
   per_side[side]={"min_rim_mouth_m":1e9,"rim_face_h_at_min":0.0,"t_at_min":0.0,"max_shoulder_raise_m":-1e9,"max_elbow_flare_m":-1e9,"pen_frames":0,"max_pen_m":0.0,"frames_near_face":0,"max_rim_face_h":-1e9}
  var frames=int(an.length*30.0)
  for f in frames:
   var t=f/30.0
   ap.seek(t,true)
   var head_inv=bone("Head").affine_inverse()
   var hips=bone("Hips")
   for side in ["Left","Right"]:
    var s=per_side[side]
    var cx=cup_xf(side)
    var rim=head_inv*(cx*Vector3(0,0.072,0))
    var d=rim.distance_to(mouth)
    var fh=(rim.dot(up_axis)-ymin)/(ymax-ymin)
    if d<s.min_rim_mouth_m: s.min_rim_mouth_m=d; s.rim_face_h_at_min=fh; s.t_at_min=t
    s.max_shoulder_raise_m=maxf(s.max_shoulder_raise_m,bone(side+"UpperArm").origin.y-rest[side].sh)
    s.max_elbow_flare_m=maxf(s.max_elbow_flare_m,absf((hips.affine_inverse()*bone(side+"LowerArm").origin).x)-rest[side].el)
    if d<0.12:
     s.frames_near_face+=1
     s.max_rim_face_h=maxf(s.max_rim_face_h,fh)
     var pen=0.0
     for cp in cup_pts:
      var lp=head_inv*(cx*cp)
      var bi=-1; var bd=1e9
      for i in pts.size():
       var dd=lp.distance_squared_to(pts[i])
       if dd<bd: bd=dd; bi=i
      var depth=-(lp-pts[bi]).dot(nrm[bi])
      if depth>0.004 and sqrt(bd)<0.03: pen=maxf(pen,depth)
     if pen>0.0: s.pen_frames+=1; s.max_pen_m=maxf(s.max_pen_m,pen)
  report.candidates[key]={"clip":CLIPS[key],"length_s":an.length,"frames30":frames,"sides":per_side}
  print("[DRINKAB] ",key," ",JSON.stringify(per_side))
 var fo=FileAccess.open(out_path,FileAccess.WRITE)
 fo.store_string(JSON.stringify(report,"  "))
 quit(0)
