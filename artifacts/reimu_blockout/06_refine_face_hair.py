"""Refine v002 anatomy and hair in the live Blender scene via MCP."""
import bpy, math, json, ast
from pathlib import Path
from mathutils import Vector
ROOT=Path('D:/神社/shrine/artifacts/reimu_blockout')
scene=bpy.context.scene
assert Path(bpy.data.filepath).name=='reimu_8head_v002.blend'
assert not (ROOT/'reimu_8head_v003.blend').exists()
COL={n:bpy.data.collections['Reimu_'+n] for n in ('Body','Face','Hair','Costume','Accessories','Studio','Reference')}
# Reuse the mesh/curve authoring functions already used for this asset.
source=ast.parse((ROOT/'01_build.py').read_text(encoding='utf-8'))
nodes=[n for n in source.body if isinstance(n,ast.FunctionDef) and n.name in ('mesh','line','loft','ellipsoid','material','panel')]
exec(compile(ast.Module(body=nodes,type_ignores=[]),'reimu_geometry_helpers','exec'))
def mat(name):return bpy.data.materials['Reimu_'+name]
skin=mat('skin'); red=mat('vermilion_cloth'); red2=mat('ribbon_red'); white=mat('warm_ivory'); hair=mat('dark_brown_hair'); ink=mat('lashes'); gold=mat('gold_necktie')
# Maintain the old version on disk; only replace this asset's owned objects.
for ob in list(COL['Face'].objects)+list(COL['Hair'].objects):
    bpy.data.objects.remove(ob,do_unlink=True)
bpy.data.objects.remove(bpy.data.objects['Reimu_Head'],do_unlink=True)

# Smooth scalar interpolation, shared by head anatomy and hair splines.
def interp(seq,t):
    f=max(0,min(1,t))*(len(seq)-1);i=min(int(f),len(seq)-2);u=f-i
    p0=seq[max(i-1,0)];p1=seq[i];p2=seq[i+1];p3=seq[min(i+2,len(seq)-1)]
    return .5*((2*p1)+(-p0+p2)*u+(2*p0-5*p1+4*p2-p3)*u*u+(-p0+3*p1-3*p2+p3)*u*u*u)
profile=[(1.44375,.001,.001,-.012),(1.454,.025,.028,-.008),(1.472,.048,.043,-.002),(1.495,.066,.054,.003),(1.52,.074,.061,.006),(1.548,.076,.066,.008),(1.582,.074,.068,.012),(1.615,.06,.055,.013),(1.64,.035,.033,.013),(1.65,.001,.001,.013)]
def head_profile(z):
    k=next((i for i in range(len(profile)-1) if z<=profile[i+1][0]),len(profile)-2)
    t=(z-profile[k][0])/(profile[k+1][0]-profile[k][0])
    vals=[]
    for c in (1,2,3):
        p0=profile[max(0,k-1)][c];p1=profile[k][c];p2=profile[k+1][c];p3=profile[min(len(profile)-1,k+2)][c]
        vals.append(.5*(2*p1+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t))
    return max(.0005,vals[0]),max(.0005,vals[1]),vals[2]
def sculpt_delta(x,z):
    # Integrated low bridge / tiny nose tip and lip mound; no glued-on nose.
    bridge=.0045*math.exp(-(x/.008)**2-((z-1.524)/.022)**2)
    tip=.008*math.exp(-(x/.006)**2-((z-1.504)/.0065)**2)
    lip=.0019*math.exp(-(x/.014)**2-((z-1.480)/.006)**2)
    cheek=.0015*sum(math.exp(-((x-s*.045)/.019)**2-((z-1.509)/.015)**2) for s in (-1,1))
    return bridge+tip+lip+cheek

def face_y(x,z):
    rx,ry,cy=head_profile(z)
    return cy-ry*(max(0,1-min(.999999,abs(x/rx))**2)**.27)-sculpt_delta(x,z)

verts=[];faces=[];N=96;R=80
for j in range(R+1):
    z=1.44375+.20625*j/R
    rx,ry,cy=head_profile(z)
    for i in range(N):
        a=2*math.pi*i/N
        x=rx*math.sin(a);c=math.cos(a)
        y=cy-ry*math.copysign(abs(c)**.54,c)
        if c>0:y-=sculpt_delta(x,z)*(c**4)
        verts.append((x,y,z))
for j in range(R):
    for i in range(N):
        a=j*N+i;b=j*N+(i+1)%N
        faces.append((a,b,b+N,a+N))
faces.extend([tuple(reversed(range(N))),tuple(R*N+i for i in range(N))])
head=mesh('Head',verts,faces,skin,'Body')
head['anatomical_head_height_m']=.20625
# Smooth cheek tint stored on the mesh, not a floating blush disc.
face_skin=skin.copy();face_skin.name='Reimu_Face_skin_tint'
head.data.materials[0]=face_skin
colors=head.data.color_attributes.new(name='FaceTint',type='FLOAT_COLOR',domain='POINT')
for i,v in enumerate(head.data.vertices):
    x,y,z=v.co
    blend=.24*sum(math.exp(-((x-s*.047)/.016)**2-((z-1.510)/.008)**2) for s in (-1,1))*(1 if y<-.035 else 0)
    base=(.82,.625,.50);blush=(.93,.32,.30)
    colors.data[i].color=tuple(base[k]*(1-blend)+blush[k]*blend for k in range(3))+(1,)

# Curved eye surface lies just outside the measured facial surface.
def eye_z(q,top=True):
    return ( .0132 if top else -.0100)*max(0,1-q*q)**.66+.0023*q

def eye_y(x,z,cx):
    q=(x-cx)/.026
    return face_y(x,z)-.0012-.0014*max(0,1-q*q)

sclera=mat('eye_white')
irismats=[material('iris_rim',(.055,.013,.021)),material('iris_upper',(.16,.023,.031)),material('iris_middle',(.40,.05,.065)),material('iris_lower',(.63,.12,.115)),material('iris_radial',(.50,.071,.064))]
for s,side in ((-1,'L'),(1,'R')):
    cx=s*.035;cz=1.533
    vs=[(cx,eye_y(cx,cz,cx),cz)]
    for i in range(64):
        a=2*math.pi*i/64;q=math.cos(a);z=cz+eye_z(q,math.sin(a)>=0)
        x=cx+s*.026*q
        vs.append((x,eye_y(x,z,cx),z))
    fs=[(0,1+i,1+(i+1)%64) for i in range(64)]
    eye=mesh('Eye_white_'+side,vs,fs,sclera,'Face')
    # Flattened iris with radial topology and multiple real colour bands.
    vs=[];fs=[];radii=(0,.34,.58,.78,.91,1)
    for r in radii:
        for i in range(64):
            a=2*math.pi*i/64
            x=cx+.0105*r*math.cos(a);z=cz+.001+.0122*r*math.sin(a)
            # Upper lid clips the iris, avoiding the previous bulging doll eye.
            q=s*(x-cx)/.026
            z=min(z,cz+eye_z(q,True)-.0005)
            z=max(z,cz+eye_z(q,False)+.0004)
            vs.append((x,eye_y(x,z,cx)-.00065,z))
    for j in range(len(radii)-1):
        for i in range(64):
            a=j*64+i;b=j*64+(i+1)%64;fs.append((a,b,b+64,a+64))
    ob=mesh('Iris_'+side,vs,fs,irismats[0],'Face')
    for m in irismats[1:]:ob.data.materials.append(m)
    for p in ob.data.polygons:
        z=sum(ob.data.vertices[v].co.z for v in p.vertices)/len(p.vertices)
        band=p.index//64
        p.material_index=0 if band==4 else 1 if z>cz+.004 else 3 if z<cz-.003 else 2
        if band in (2,3) and p.index%5==0 and z<cz+.006:p.material_index=4
    def disc(name,dx,dz,rx,rz,material):
        vv=[]
        for i in range(49):
            a=2*math.pi*(i-1)/48 if i else 0
            x=cx+dx+(rx*math.cos(a) if i else 0);z=cz+dz+(rz*math.sin(a) if i else 0)
            vv.append((x,eye_y(x,z,cx)-.00135,z))
        return mesh(name,vv,[(0,1+i,1+(i+1)%48) for i in range(48)],material,'Face')
    disc('Pupil_'+side,0,.002,.0037,.0070,ink)
    disc('Eye_glint_'+side,-.0038,.0074,.0028,.0031,sclera)
    disc('Eye_glint_small_'+side,.004,-.005,.0012,.0012,sclera)
    # Tapered eyeliner ribbons, rather than uniform black tubes.
    vv=[]
    for i in range(41):
        q=-1+2*i/40;x=cx+s*.026*q;z=cz+eye_z(q,True)
        thick=.0004+.0022*(math.sin(math.pi*i/40)**.7)+.0008*max(q,0)
        for dz in (0,thick):vv.append((x,eye_y(x,z+dz,cx)-.0016,z+dz))
    mesh('Upper_lash_'+side,vv,[(i*2,i*2+1,i*2+3,i*2+2) for i in range(40)],ink,'Face',solid=.0003)
    for k in range(2):
        x=cx+s*(.0215+k*.0034);z=cz+.009-k*.0017
        panel('Lash_tip_'+side+str(k),[(x,eye_y(x,z,cx)-.002,z),(x+s*.008,eye_y(x,z,cx)-.001,z+.004+k*.001),(x+s*.002,eye_y(x,z,cx)-.002,z-.001)],ink,'Face',.00025)
    pts=[]
    for i in range(13):
        q=-.92+1.84*i/12;x=cx+s*.026*q;z=cz+eye_z(q,False)
        pts.append((x,eye_y(x,z,cx)-.0011,z))
    line('Lower_lid_'+side,pts,.00055,mat('lip'),'Face')
    vs=[]
    for i in range(21):
        u=i/20;x=cx+s*(-.02+.042*u);z=1.561+.004*math.sin(math.pi*u)-.001*u
        for dz in (0,.0015*math.sin(math.pi*u)+.0001):vs.append((x,face_y(x,z+dz)-.001,z+dz))
    mesh('Brow_'+side,vs,[(i*2,i*2+1,i*2+3,i*2+2) for i in range(20)],hair,'Face')
    # Ears include a shallow concha instead of an undifferentiated sphere.
    ellipsoid('Ear_'+side,(s*.075,.012,1.514),(.0105,.012,.021),skin,'Face')
    concha=material('ear_inner_'+side,(.62,.35,.28))
    ellipsoid('Ear_inner_'+side,(s*.081,.002,1.514),(.005,.007,.013),concha,'Face',24,12)
pts=[]
for i in range(17):
    x=-.0105+.021*i/16;z=1.479+.001*(abs(x)/.0105)**2
    pts.append((x,face_y(x,z)-.0011,z))
line('Mouth',pts,.00065,mat('lip'),'Face')

# Main cap: continuous root volume, correctly oriented surface normals.
verts=[];faces=[];N=80;R=24
for j in range(R+1):
    for i in range(N):
        a=2*math.pi*i/N;end=1.1+1.23*((1-math.cos(a))/2)**.62
        p=.008+(end-.008)*j/R
        verts.append((.082*math.sin(p)*math.sin(a),.013-.076*math.sin(p)*math.cos(a),1.55+.112*math.cos(p)))
for j in range(R):
    for i in range(N):
        a=j*N+i;b=j*N+(i+1)%N;faces.append((a,a+N,b+N,b))
mesh('Hair_cap',verts,faces,hair,'Hair',sub=1,solid=.002)

# Solid curved strips with broad planes and sharp tapering ends.
def lock(name,points,widths,normal,shade=hair,groove=False):
    pts=[Vector(p) for p in points];normal=Vector(normal).normalized()
    vs=[];fs=[];rows=32;cols=8;guide=[]
    for j in range(rows+1):
        u=j/rows;c=interp(pts,u)
        tangent=(interp(pts,min(1,u+.003))-interp(pts,max(0,u-.003))).normalized()
        wdir=tangent.cross(normal).normalized()
        w=max(.0001,interp(widths,u))
        n=wdir.cross(tangent).normalized()
        depth=.0035*math.sin(math.pi*u)**.6
        for k in range(cols+1):
            v=2*k/cols-1
            co=c+wdir*(v*w)+n*(depth*(1-v*v))
            vs.append(tuple(co))
        guide.append(tuple(c+n*(depth+.00045)))
    for j in range(rows):
        for k in range(cols):
            a=j*(cols+1)+k;fs.append((a,a+1,a+cols+2,a+cols+1))
    ob=mesh(name,vs,fs,shade,'Hair',sub=1,solid=.0013)
    if groove:line(name+'_strand_accent',guide[5:-5:2],.00038,mat('hair_planes'),'Hair')
    return ob

# Rear silhouette ends at varied heights near the sash; no blunt comb edge.
for i in range(11):
    t=(i-5)/5
    endz=1.07+.050*(.5+.5*math.sin(i*2.3))+.025*abs(t)
    p=[(t*.026,.057,1.622),(t*.070,.078+.012*(1-abs(t)),1.51),(t*.111+.007*math.sin(i),.108+.015*(1-abs(t)),1.36),(t*.15+.01*math.sin(i*1.9),.138,1.20),(t*.145-.018*math.sin(i*1.4),.092,endz)]
    lock('Back_hair_%02d'%i,p,[.014,.022,.027,.024,.0001],(0,1,0),groove=i%2==0)
for s,side in ((-1,'L'),(1,'R')):
    for k in range(3):
        p=[(s*.053,.043+k*.01,1.593),(s*.082,.06+k*.02,1.46),(s*(.105+.012*k),.063+.018*k,1.32),(s*(.15+.014*k),.043+.02*k,1.18),(s*(.13+.016*k),.015+.01*k,1.085+.032*k)]
        lock('Side_sweep_'+side+str(k),p,[.012,.020,.023,.012,.0001],(s*.7,.7,0),groove=k==1)
    p=[(s*.067,-.007,1.616),(s*.080,-.031,1.545),(s*.087,-.039,1.457),(s*.098,-.033,1.37),(s*.095,-.019,1.31)]
    lock('Face_frame_'+side,p,[.017,.016,.014,.015,.0001],(s*.2,-1,0))
# Asymmetric swept fringe with broader roots, separated only near its ends.
bangs=[([(-.010,-.026,1.65),(-.027,-.063,1.608),(-.029,-.076,1.57),(-.019,-.077,1.548)],[.013,.023,.017,.0001]),([(0,-.018,1.651),(.007,-.059,1.615),(.006,-.076,1.58),(.016,-.078,1.553)],[.015,.023,.019,.0001]),([(.013,-.025,1.646),(.035,-.058,1.61),(.044,-.071,1.575),(.052,-.066,1.549)],[.014,.022,.017,.0001]),([(-.024,-.018,1.64),(-.048,-.054,1.597),(-.059,-.064,1.55),(-.063,-.049,1.518)],[.016,.019,.016,.0001]),([(.026,-.014,1.64),(.056,-.046,1.596),(.068,-.043,1.553),(.072,-.025,1.512)],[.015,.019,.015,.0001])]
for i,(points,widths) in enumerate(bangs):lock('Bangs_%02d'%i,points,widths,(0,-1,0),groove=i in (0,2))

# More coherent stylized response removes the hard plastic highlight.
def toon(m,base,tint=False):
    m.diffuse_color=(*base,1);m.use_nodes=True
    nodes=m.node_tree.nodes;nodes.clear();links=m.node_tree.links
    out=nodes.new('ShaderNodeOutputMaterial')
    diff=nodes.new('ShaderNodeBsdfDiffuse');diff.inputs['Color'].default_value=(.8,.8,.8,1);diff.inputs['Roughness'].default_value=1
    rgb=nodes.new('ShaderNodeShaderToRGB');links.new(diff.outputs[0],rgb.inputs[0])
    ramp=nodes.new('ShaderNodeValToRGB');ramp.color_ramp.interpolation='EASE'
    ramp.color_ramp.elements[0].position=.05;ramp.color_ramp.elements[0].color=(.47,.43,.44,1)
    ramp.color_ramp.elements[1].position=.72;ramp.color_ramp.elements[1].color=(1,1,1,1)
    e=ramp.color_ramp.elements.new(.36);e.color=(.82,.78,.77,1)
    links.new(rgb.outputs[0],ramp.inputs[0])
    multiply=nodes.new('ShaderNodeMixRGB');multiply.blend_type='MULTIPLY';multiply.inputs[0].default_value=1;multiply.inputs[1].default_value=(*base,1)
    links.new(ramp.outputs[0],multiply.inputs[2])
    if tint:
        vc=nodes.new('ShaderNodeVertexColor');vc.layer_name='FaceTint';links.new(vc.outputs['Color'],multiply.inputs[1])
    emission=nodes.new('ShaderNodeEmission');links.new(multiply.outputs[0],emission.inputs['Color']);links.new(emission.outputs[0],out.inputs['Surface'])
for m in list(bpy.data.materials):
    if not m.name.startswith('Reimu_'):continue
    c=tuple(m.diffuse_color[:3])
    if m==skin:c=(.82,.625,.50)
    if m==hair:c=(.037,.018,.020)
    if m==mat('hair_planes'):c=(.065,.033,.031)
    if m==red:c=(.49,.030,.035)
    if m==red2:c=(.58,.037,.047)
    if m==white:c=(.92,.90,.84)
    if m==ink:c=(.018,.008,.012)
    toon(m,c,m==face_skin)
scene.view_settings.view_transform='Standard'
scene['iteration']='v003 face and swept hair refinement; work in progress'
scene.camera=bpy.data.objects['Reimu_FaceClose'];scene.render.resolution_x=1000;scene.render.resolution_y=1000
scene.render.filepath=str(ROOT/'v003_face.png')
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'reimu_8head_v003_work.blend'),check_existing=False)
bpy.ops.render.render(write_still=True)
print(json.dumps({'face_vertices':len(head.data.vertices),'hair_objects':len(COL['Hair'].objects),'saved':bpy.data.filepath,'face_render':scene.render.filepath},ensure_ascii=False))
