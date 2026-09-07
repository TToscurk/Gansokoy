"""Garment construction pass: replace intersecting flat panels with fitted shells."""
import bpy, math, ast, json
from pathlib import Path
from mathutils import Vector
ROOT=Path('D:/神社/shrine/artifacts/reimu_blockout')
scene=bpy.context.scene
assert Path(bpy.data.filepath).name=='reimu_8head_v003_work.blend'
COL={n:bpy.data.collections['Reimu_'+n] for n in ('Body','Face','Hair','Costume','Accessories','Studio','Reference')}
for filename,names in [('01_build.py',('mesh','line','loft','ellipsoid','material','panel')),('06_refine_face_hair.py',('interp','toon','lock'))]:
    src=ast.parse((ROOT/filename).read_text(encoding='utf-8'))
    if filename=='06_refine_face_hair.py':
        hair=bpy.data.materials['Reimu_dark_brown_hair']
    exec(compile(ast.Module(body=[n for n in src.body if isinstance(n,ast.FunctionDef) and n.name in names],type_ignores=[]),filename,'exec'))
def mat(n):return bpy.data.materials['Reimu_'+n]
red=mat('vermilion_cloth');red2=mat('ribbon_red');white=mat('warm_ivory');skin=mat('skin');gold=mat('gold_necktie')
def remove_prefixes(prefixes,groups=('Costume','Accessories')):
    for group in groups:
        for ob in list(COL[group].objects):
            if any(ob.name.startswith('Reimu_'+p) for p in prefixes):bpy.data.objects.remove(ob,do_unlink=True)
remove_prefixes(('Bodice','Upper_bodice','Collar','Gold_necktie','Tie_fold','Tie_knot','Head_bow','Head_ribbon_tail','Tail_white_edge','Waist_back_bow','Waist_tail','Skirt','White_petticoat','Detached_sleeve','Sleeve_red_dash','Sleeve_upper_red_band','Hair_red_cuff','Hair_cuff_frill'))
# Hide underlying chest polygons that cannot be seen in the clothed character;
# retain the complete original body in v002, and retain torso here for later retopo.
torso=bpy.data.objects['Reimu_Torso']
torso['note']='Separate body proxy. Garment fitted outside this surface; not retopologized.'
body_profile=[(.82,.067,.049,.018),(.87,.124,.076,.02),(.93,.137,.082,.016),(1.005,.11,.07,0),(1.065,.096,.061,0),(1.14,.112,.069,0),(1.22,.142,.081,-.003),(1.285,.15,.075,.003),(1.33,.162,.064,.007),(1.365,.133,.05,.012),(1.397,.048,.036,.012)]
def profile(z):
    k=next((i for i in range(len(body_profile)-1) if z<=body_profile[i+1][0]),len(body_profile)-2)
    t=max(0,min(1,(z-body_profile[k][0])/(body_profile[k+1][0]-body_profile[k][0])))
    return tuple(body_profile[k][c]*(1-t)+body_profile[k+1][c]*t for c in (1,2,3))
def cloth_y(x,z,front=True):
    rx,ry,cy=profile(z)
    surface=(ry+.009)*math.sqrt(max(.025,1-(x/(rx+.01))**2))
    return cy+(-1 if front else 1)*(surface+.004)
# Lower blouse, draped darts and a doubled hem.
rings=[]
for j in range(20):
    z=1.079+(1.29-1.079)*j/19
    rx,ry,cy=profile(z)
    rings.append((z,0,cy,rx+.008,ry+.011))
blouse=loft('Bodice',rings,red,'Costume',sides=80,sub=1,caps=False)
for v in blouse.data.vertices:
    a=math.atan2(v.co.y,v.co.x)
    amp=.0028*math.exp(-((v.co.z-1.115)/.06)**2)
    v.co.y+=amp*math.sin(9*a+v.co.z*14)
solid=blouse.modifiers.new('Fabric shell','SOLIDIFY');solid.thickness=.0025
# Fitted upper chest: curved grid follows the measured torso profile.
for front,label in ((True,'Front'),(False,'Back')):
    vs=[];fs=[];NX=36;NY=16
    for j in range(NY+1):
        u=j/NY
        for i in range(NX+1):
            x=-.145+.29*i/NX
            ax=abs(x)
            top=1.35+.044*math.exp(-((ax-.068)/.042)**4)-.064*(ax/.145)**8
            if not front:top+=.023*math.exp(-(ax/.075)**2)
            z=1.274+(top-1.274)*u
            y=cloth_y(x,z,front)+(-.001 if front else .001)
            vs.append((x,y,z))
    for j in range(NY):
        for i in range(NX):
            a=j*(NX+1)+i;fs.append((a,a+1,a+NX+2,a+NX+1))
    mesh('Upper_bodice_'+label,vs,fs,red,'Costume',sub=1,solid=.0025)
# Curved shoulder bridges are attached to front and back, no loose flat tabs.
for s,side in ((-1,'L'),(1,'R')):
    vs=[];fs=[]
    for j in range(17):
        u=j/16;y=-.047+.094*u
        for k in range(7):
            x=s*(.06+.041*k/6)
            z=1.377+.017*math.sin(math.pi*u)-.007*k/6
            vs.append((x,y,z))
    for j in range(16):
        for k in range(6):
            a=j*7+k;fs.append((a,a+1,a+8,a+7))
    mesh('Shoulder_bridge_'+side,vs,fs,red,'Costume',sub=1,solid=.0025)
    corners=[Vector((s*.006,-.10,1.332)),Vector((s*.048,-.096,1.329)),Vector((s*.108,-.059,1.38)),Vector((s*.044,-.043,1.405))]
    vs=[];fs=[]
    for j in range(13):
        u=j/12
        a=corners[0].lerp(corners[3],u);b=corners[1].lerp(corners[2],u)
        for k in range(7):
            t=k/6;co=a.lerp(b,t);co.y-=.003*math.sin(math.pi*t)*math.sin(math.pi*u);vs.append(tuple(co))
    for j in range(12):
        for k in range(6):
            a=j*7+k;fs.append((a,a+1,a+8,a+7))
    mesh('Collar_'+side,vs,fs,white,'Costume',sub=1,solid=.002)
    # Small inset zigzag stitches, raised in front of the collar.
    pts=[]
    for i in range(25):
        t=i/24;c=corners[1].lerp(corners[2],t)
        c.x-=s*(.005+(.0015 if i%2 else -.0015));c.y-=.004
        pts.append(tuple(c))
    line('Collar_stitch_'+side,pts,.00065,red2)
    # Fine white edge follows the outer armhole, not a floating straight stripe.
    line('Armhole_binding_'+side,[(s*.107,-.047,1.376),(s*.128,-.04,1.34),(s*.147,-.012,1.292),(s*.147,.029,1.295),(s*.122,.048,1.357)],.002,white)
# Cloth necktie: three broad folds, gold not a solid triangular plaque.
vs=[];fs=[]
for j in range(17):
    u=j/16;z=1.328-.104*u
    w=.01+.026*u
    for k in range(17):
        v=2*k/16-1
        vs.append((w*v,-.108-.010*math.sin(3*math.pi*v)*u,z+.008*v*v*u))
for j in range(16):
    for k in range(16):
        a=j*17+k;fs.append((a,a+1,a+18,a+17))
mesh('Gold_necktie',vs,fs,gold,'Costume',sub=1,solid=.0018)
ellipsoid('Tie_knot',(0,-.103,1.332),(.012,.010,.014),gold)
line('Tie_hem',[(-.034,-.112,1.233),(-.018,-.104,1.224),(0,-.110,1.224),(.018,-.117,1.224),(.034,-.11,1.233)],.0015,white)

# Skirt uses waist-directed irregular folds; trim is evaluated on the same surface.
def skirt_point(a,u,offset=0):
    rx=.112+.225*(u**.80);ry=.078+.165*(u**.82)
    fold=(.003+.012*u)*math.sin(14*a+.16*math.sin(3*a)*(u**.5))+.0035*u*math.sin(27*a+.2)
    z=1.044-.474*u+.006*(u**3)*math.sin(7*a+.4)
    return Vector(((rx+fold+offset)*math.cos(a),.012*u+(ry+fold*.75+offset)*math.sin(a),z))
vs=[];fs=[];N=168;R=28
for j in range(R+1):
    for i in range(N):vs.append(tuple(skirt_point(2*math.pi*i/N,j/R)))
for j in range(R):
    for i in range(N):
        a=j*N+i;b=j*N+(i+1)%N;fs.append((a,a+N,b+N,b))
skirt=mesh('Skirt',vs,fs,red,'Costume',sub=1,solid=.0025)
# Petticoat flounce, fine waves rather than a single rigid white ring.
vs=[];fs=[]
for j in range(9):
    u=j/8
    for i in range(N):
        a=2*math.pi*i/N;p=skirt_point(a,1)
        ruffle=.005+.008*u+.008*u*math.cos(42*a)
        p+=Vector((ruffle*math.cos(a),ruffle*math.sin(a),-.008-.042*u+.004*u*math.sin(42*a)))
        vs.append(tuple(p))
for j in range(8):
    for i in range(N):
        a=j*N+i;b=j*N+(i+1)%N;fs.append((a,a+N,b+N,b))
mesh('White_petticoat',vs,fs,white,'Costume',sub=1,solid=.0018)
# Continuous embroidery tracks the actual folds at every angle.
pts=[]
for i in range(385):
    a=2*math.pi*i/384;triangle=(2/math.pi)*math.asin(math.sin(32*a))
    p=skirt_point(a,.910+.025*triangle,.0022);pts.append(tuple(p))
line('Skirt_zigzag',pts,.0015,white,cyclic=True)
for k in range(64):
    a=2*math.pi*k/64;p=skirt_point(a,.953 if k%2 else .866,.0028)
    ellipsoid('Skirt_dot_%02d'%k,p,(.0015,.0015,.0015),white,n=12,rows=6)
line('Skirt_hem_seam',[tuple(skirt_point(2*math.pi*i/192,.988,.0017)) for i in range(193)],.0007,mat('shoe_leather'),cyclic=True)

# Hanging sleeves: each opening follows the arm, with gravity-shaped lower cloth.
for s,side in ((-1,'L'),(1,'R')):
    def sleeve_point(a,u,extra=0):
        cx=s*(.215+.104*u);cy=.012+.006*u
        rx=.047+.059*u**1.6;ry=.047+.043*u**1.4
        fold=.003*u*math.sin(8*a+.7*u)
        z=1.289-.291*u+.030*u**2*s*math.cos(a)-.022*u**2*max(0,math.sin(a))
        return Vector((cx+(rx+fold+extra)*math.cos(a),cy+(ry+fold+extra)*math.sin(a),z))
    vs=[];fs=[];SN=64;SR=24
    for j in range(SR+1):
        for i in range(SN):vs.append(tuple(sleeve_point(2*math.pi*i/SN,j/SR)))
    for j in range(SR):
        for i in range(SN):
            a=j*SN+i;b=j*SN+(i+1)%SN;fs.append((a,a+SN,b+SN,b))
    mesh('Detached_sleeve_'+side,vs,fs,white,'Costume',sub=1,solid=.002)
    # Red blocks are surface patches: no floating wire dashes across folds.
    for k in range(12):
        a0=2*math.pi*(k+.15)/12;a1=2*math.pi*(k+.70)/12
        vs=[];fs=[]
        for j in range(3):
            u=.89+.025*j
            for i in range(5):vs.append(tuple(sleeve_point(a0+(a1-a0)*i/4,u,.0018)))
        for j in range(2):
            for i in range(4):
                a=j*5+i;fs.append((a,a+1,a+6,a+5))
        mesh('Sleeve_red_dash_'+side+str(k),vs,fs,red2,'Costume')
    line('Sleeve_hem_stitch_'+side,[tuple(sleeve_point(2*math.pi*i/96,.984,.0013)) for i in range(97)],.00065,mat('skin'),cyclic=True)
    # Upper folded cuff in the same surface coordinates.
    vs=[];fs=[]
    for j in range(4):
        u=.007+.055*j/3
        for i in range(SN):vs.append(tuple(sleeve_point(2*math.pi*i/SN,u,.0035)))
    for j in range(3):
        for i in range(SN):
            a=j*SN+i;b=j*SN+(i+1)%SN;fs.append((a,b,b+SN,a+SN))
    mesh('Sleeve_upper_cuff_'+side,vs,fs,white,'Costume',sub=1,solid=.002)
    loft('Hair_red_cuff_'+side,[(1.369,s*.096,-.033,.020,.018),(1.375,s*.096,-.033,.020,.018),(1.403,s*.094,-.035,.019,.018),(1.408,s*.094,-.035,.019,.018)],red2,'Accessories',sides=40,sub=1,caps=False)
    loft('Hair_cuff_frill_'+side,[(1.357,s*.096,-.033,.024,.023),(1.368,s*.096,-.033,.023,.021)],white,'Accessories',sides=64,sub=0,caps=False,fold=.003)
    line('Hair_cuff_stitch_'+side,[(s*.096+.021*math.cos(2*math.pi*i/48),-.033+.019*math.sin(2*math.pi*i/48),1.378+(.002 if i%2 else 0)) for i in range(49)],.0006,white,cyclic=True)

# Ribbon bows with actual folded loops, white ruffles, zigzag thread and tails.
def detailed_bow(name,center,size,ruffled):
    cx,cy,cz=center
    for s,side in ((-1,'L'),(1,'R')):
        def bow_point(u,v):
            x=cx+s*size*(.085+.915*u)
            half=size*(.09+.45*u)
            y=cy-size*.22*math.sin(math.pi*u)*(1-v*v)+size*.055*math.sin(3*math.pi*v)*math.sin(math.pi*u)
            z=cz+size*.16*u+half*v
            return Vector((x,y,z))
        vs=[];fs=[];BU=20;BV=20
        for j in range(BU+1):
            for k in range(BV+1):vs.append(tuple(bow_point(j/BU,2*k/BV-1)))
        for j in range(BU):
            for k in range(BV):
                a=j*(BV+1)+k;fs.append((a,a+1,a+BV+2,a+BV+1))
        mesh(name+'_loop_'+side,vs,fs,red2,'Accessories',sub=1,solid=.002)
        if ruffled:
            vs=[];fs=[]
            for j in range(5):
                u=j/4
                for k in range(65):
                    v=2*k/64-1;p=bow_point(1,v)
                    p.x+=s*size*(.012+.084*u)
                    p.y+=size*.034*math.sin(10*math.pi*v)*u
                    p.z+=size*.015*math.cos(10*math.pi*v)*u
                    vs.append(tuple(p))
            for j in range(4):
                for k in range(64):
                    a=j*65+k;fs.append((a,a+1,a+66,a+65))
            mesh(name+'_ruffle_'+side,vs,fs,white,'Accessories',sub=1,solid=.001)
            pts=[]
            for k in range(41):
                v=2*k/40-1;p=bow_point(.93 if k%2 else .88,v);p.y-=.002;pts.append(tuple(p))
            line(name+'_embroidery_'+side,pts,.0008,white)
    ellipsoid(name+'_knot',(cx,cy-.005,cz),(.13*size,.12*size,.17*size),red2)

detailed_bow('Head_bow',(0,.076,1.652),.132,True)
detailed_bow('Waist_back_bow',(0,.115,1.029),.096,False)
for s,side in ((-1,'L'),(1,'R')):
    for is_head in (True,False):
        name=('Head_ribbon_tail_' if is_head else 'Waist_tail_')+side
        start=Vector((s*.025,.077 if is_head else .12,1.642 if is_head else 1.02))
        end=Vector((s*.118,.087 if is_head else .198,1.483 if is_head else .805))
        vs=[];fs=[]
        for j in range(21):
            u=j/20;c=start.lerp(end,u);c.y-=.012*math.sin(math.pi*u)
            for k in range(9):
                v=2*k/8-1;p=c.copy();p.x+=s*v*(.012+.02*u);p.y+=.005*math.sin(2*math.pi*v)*u
                p.z+=.012*abs(v)*u**6
                vs.append(tuple(p))
        for j in range(20):
            for k in range(8):
                a=j*9+k;fs.append((a,a+1,a+10,a+9))
        mesh(name,vs,fs,red2,'Accessories',sub=1,solid=.002)
        if is_head:
            edge=[Vector(vs[20*9+k]) for k in range(9)]
            for p in edge:p.y-=.002
            line('Tail_white_edge_'+side,[tuple(p) for p in edge],.0035,white)
            line('Tail_zigzag_'+side,[(p.x,p.y-.001,p.z+.012+(.002 if i%2 else 0)) for i,p in enumerate(edge)],.0007,white)
# Existing tiny bows should not have white piping where the reference has plain red.
remove_prefixes(('Sock_bow_L_white_edge','Sock_bow_R_white_edge','Sleeve_tie_L_white_edge','Sleeve_tie_R_white_edge'))
scene['iteration']='v003 face/hair + fitted clothing, embroidery and folded bows'
scene.camera=bpy.data.objects['Reimu_Front'];scene.render.resolution_x=900;scene.render.resolution_y=1200
scene.render.filepath=str(ROOT/'v003_front.png')
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'reimu_8head_v003_work.blend'),check_existing=False)
for name in ('Front','Side','Back'):
    scene.camera=bpy.data.objects['Reimu_'+name];scene.render.filepath=str(ROOT/('v003_'+name.lower()+'.png'))
    bpy.ops.render.render(write_still=True)
    print('RENDERED '+name)
scene.camera=bpy.data.objects['Reimu_Front']
print(json.dumps({'objects':len(scene.objects),'saved':bpy.data.filepath},ensure_ascii=False))
