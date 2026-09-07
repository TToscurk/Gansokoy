"""Correct profile intersections, relaxed anime eyes and matte shading."""
import bpy, math, ast, json
from pathlib import Path
from mathutils import Vector
ROOT=Path('D:/神社/shrine/artifacts/reimu_blockout')
scene=bpy.context.scene
assert Path(bpy.data.filepath).name=='reimu_8head_v003_work.blend'
COL={n:bpy.data.collections['Reimu_'+n] for n in ('Body','Face','Hair','Costume','Accessories','Studio','Reference')}
def mat(n):return bpy.data.materials['Reimu_'+n]
hair=mat('dark_brown_hair');skin=mat('skin');white=mat('warm_ivory')
for filename,names in [('01_build.py',('mesh','line','loft','ellipsoid')),('06_refine_face_hair.py',('interp','lock','head_profile','sculpt_delta','face_y'))]:
    source=ast.parse((ROOT/filename).read_text(encoding='utf-8'))
    exec(compile(ast.Module(body=[n for n in source.body if isinstance(n,ast.FunctionDef) and n.name in names],type_ignores=[]),filename,'exec'))
profile=[(1.44375,.001,.001,-.012),(1.454,.025,.028,-.008),(1.472,.048,.043,-.002),(1.495,.066,.054,.003),(1.52,.074,.061,.006),(1.548,.076,.066,.008),(1.582,.074,.068,.012),(1.615,.06,.055,.013),(1.64,.035,.033,.013),(1.65,.001,.001,.013)]
# Cache old surface samples before changing the facial profile.
oldcoords={}
for ob in COL['Face'].objects:
    if ob.name.startswith(('Reimu_Ear',)):
        continue
    if ob.type=='MESH':oldcoords[ob.name]=[(v.co.copy(),face_y(v.co.x,v.co.z)) for v in ob.data.vertices]
    if ob.type=='CURVE':oldcoords[ob.name]=[(p.co.copy(),face_y(p.co.x,p.co.z)) for p in ob.data.splines[0].bezier_points]
# Give the chin an intentional forward plane instead of a receding cone tip.
head=bpy.data.objects['Reimu_Head']
for v in head.data.vertices:
    z=v.co.z
    v.co.y-=.018*math.exp(-((z-1.44375)/.013)**2)
profile[0]=(1.44375,.001,.001,-.030)
profile[1]=(1.454,.025,.028,-.017)
# Move the eye/brow group slightly down, with larger irises and fitted depths.
for ob in COL['Face'].objects:
    if ob.name not in oldcoords:continue
    mouth=ob.name=='Reimu_Mouth'
    dz=-.006 if mouth else -.007
    side=-1 if ob.name.endswith('_L') or '_L0' in ob.name or '_L1' in ob.name else 1
    cx=side*.035
    iris_part=any(x in ob.name for x in ('Iris_','Pupil_','Eye_glint'))
    eyebrow='Brow_' in ob.name
    for i,(old,old_surface) in enumerate(oldcoords[ob.name]):
        co=old.copy()
        if not mouth and not eyebrow:
            co.x=cx+(old.x-cx)*(.94 if not iris_part else 1.08)
            # Upper eye closes gently; lower lid unchanged except translation.
            if old.z>1.533:co.z=1.533+(old.z-1.533)*.84
        co.z+=dz
        co.y=face_y(co.x,co.z)+(old.y-old_surface)
        if ob.type=='MESH':ob.data.vertices[i].co=co
        else:ob.data.splines[0].bezier_points[i].co=co
# Follow the revised cheek placement in the painted vertex colors.
colors=head.data.color_attributes['FaceTint']
for i,v in enumerate(head.data.vertices):
    x,y,z=v.co
    blend=.19*sum(math.exp(-((x-s*.047)/.016)**2-((z-1.504)/.008)**2) for s in (-1,1))*(1 if y<-.035 else 0)
    base=(.82,.625,.50);blush=(.93,.32,.30)
    colors.data[i].color=tuple(base[k]*(1-blend)+blush[k]*blend for k in range(3))+(1,)
# The old spherical hair cap did not enclose the flatter anime facial cross-section.
bpy.data.objects.remove(bpy.data.objects['Reimu_Hair_cap'],do_unlink=True)
vs=[];fs=[];N=96;R=28
for j in range(R+1):
    for i in range(N):
        a=2*math.pi*i/N;end=1.32+1.14*((1-math.cos(a))/2)**.62
        p=.008+(end-.008)*j/R;c=math.cos(a)
        vs.append((.085*math.sin(p)*math.sin(a),.013-.082*math.sin(p)*math.copysign(abs(c)**.54,c),1.55+.114*math.cos(p)))
for j in range(R):
    for i in range(N):
        a=j*N+i;b=j*N+(i+1)%N;fs.append((a,a+N,b+N,b))
mesh('Hair_cap',vs,fs,hair,'Hair',sub=1,solid=.002)
# Replace squared-off temple roots with tapered continuous roots under the cap.
for s,side in ((-1,'L'),(1,'R')):
    bpy.data.objects.remove(bpy.data.objects['Reimu_Face_frame_'+side],do_unlink=True)
    lock('Face_frame_'+side,[(s*.043,-.012,1.64),(s*.077,-.036,1.552),(s*.088,-.041,1.46),(s*.096,-.035,1.37),(s*.094,-.022,1.311)],[.004,.016,.014,.014,.0001],(s*.2,-1,0))
# Inner rear mass fills the profile gaps beneath the decorative strand layers.
vs=[];fs=[];N=64;R=24
for j in range(R+1):
    u=j/R
    z=interp([1.54,1.41,1.29,1.18,1.12],u)
    rx=interp([.076,.098,.13,.142,.128],u)
    cy=interp([.033,.061,.081,.091,.081],u)
    ry=interp([.055,.047,.042,.039,.027],u)
    for i in range(N+1):
        a=math.pi*i/N
        zz=z+.014*u**5*math.sin(9*a)
        vs.append((rx*math.cos(a),cy+ry*math.sin(a),zz))
for j in range(R):
    for i in range(N):
        a=j*(N+1)+i;fs.append((a,a+N+1,a+N+2,a+1))
mesh('Back_hair_core',vs,fs,hair,'Hair',sub=1,solid=.012)
# Socks enclose the measured calf/ankle rather than using narrower placeholder radii.
for s,side in ((-1,'L'),(1,'R')):
    bpy.data.objects.remove(bpy.data.objects['Reimu_Sock_'+side],do_unlink=True)
    loft('Sock_'+side,[(.035,s*.091,-.032,.036,.086),(.055,s*.091,-.032,.038,.087),(.08,s*.091,-.015,.038,.066),(.105,s*.091,.003,.038,.047),(.15,s*.091,.012,.041,.050),(.184,s*.091,.014,.042,.052),(.193,s*.091,.014,.044,.054),(.196,s*.091,.014,.044,.054)],white,'Costume',sides=64,sub=1,caps=False)
    loft('Sock_cuff_'+side,[(.184,s*.091,.014,.044,.054),(.185,s*.091,.014,.045,.055),(.196,s*.091,.014,.045,.055),(.198,s*.091,.014,.044,.054)],white,'Costume',sides=64,sub=1,caps=False)
# Use a matte PBR component to preserve sculptural form beneath the anime palette.
for m in bpy.data.materials:
    if not m.name.startswith('Reimu_') or not m.use_nodes:continue
    nodes=m.node_tree.nodes;links=m.node_tree.links
    out=next((n for n in nodes if n.type=='OUTPUT_MATERIAL'),None)
    if not out or not out.inputs['Surface'].links:continue
    old_shader=out.inputs['Surface'].links[0].from_socket
    bs=nodes.new('ShaderNodeBsdfPrincipled');bs.name='Refinement_matte_form'
    bs.inputs['Base Color'].default_value=m.diffuse_color
    bs.inputs['Roughness'].default_value=.75
    bs.inputs['Specular IOR Level'].default_value=.12
    if 'Face_skin_tint' in m.name:
        vc=next((n for n in nodes if n.type=='VERTEX_COLOR'),None)
        if vc:links.new(vc.outputs['Color'],bs.inputs['Base Color'])
    mix=nodes.new('ShaderNodeMixShader')
    factor=.52
    if any(t in m.name for t in ('eye_','iris_','lashes','lip','garnet','pupil')):factor=.1
    if 'hair' in m.name:factor=.62
    if m==skin or 'Face_skin_tint' in m.name:factor=.40
    mix.inputs[0].default_value=factor
    links.new(old_shader,mix.inputs[1]);links.new(bs.outputs[0],mix.inputs[2]);links.new(mix.outputs[0],out.inputs['Surface'])
scene.world.node_tree.nodes.get('Background').inputs[1].default_value=.26
bpy.data.lights['Reimu_Fill'].energy=180
scene['iteration']='v003 refined face, enclosed scalp/socks, folded cloth, matte anime shading'
scene.camera=bpy.data.objects['Reimu_Front'];scene.render.resolution_x=900;scene.render.resolution_y=1200
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'reimu_8head_v003_work.blend'),check_existing=False)
for name in ('Front','Side','Back','FaceClose'):
    scene.camera=bpy.data.objects['Reimu_'+name]
    scene.render.resolution_x=1000 if name=='FaceClose' else 900
    scene.render.resolution_y=1000 if name=='FaceClose' else 1200
    scene.render.filepath=str(ROOT/('v003_'+('face' if name=='FaceClose' else name.lower())+'.png'))
    bpy.ops.render.render(write_still=True)
    print('RENDERED '+name)
scene.camera=bpy.data.objects['Reimu_Front'];scene.render.resolution_x=900;scene.render.resolution_y=1200
print('PROFILE_AND_MATERIAL_PASS_COMPLETE')
