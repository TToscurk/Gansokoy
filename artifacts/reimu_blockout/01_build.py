"""Reimu proportion/costume blockout. Run inside Blender via MCP.
New scene only. Coordinate system: Z up, -Y front; metres.
Not animation topology. No external generators, paid assets or source overwrites.
"""
import bpy
import math
import json
from pathlib import Path
from mathutils import Vector

OUT = Path('D:/神社/shrine/artifacts/reimu_blockout')
TARGET = OUT / 'reimu_8head_v001.blend'
if TARGET.exists() or bpy.data.scenes.get('Reimu_Blockout_v001'):
    raise RuntimeError('v001 already exists; refuse destructive rerun')
scene = bpy.data.scenes.new('Reimu_Blockout_v001')
bpy.context.window.scene = scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
scene['review_status'] = 'ART_REVIEW'
scene['reference'] = 'D:/參考圖概念圖/參考圖文理/角色概念圖/博麗靈夢.png'
scene['scope'] = 'Eight-head proportion and costume blockout; not production-ready topology'
scene['stature_definition'] = 'Shoe sole Z=0 to anatomical crown Z=1.65; excludes hair and bow'
scene['head_height_m'] = 1.65 / 8
COL = {}
for n in ('Body', 'Face', 'Hair', 'Costume', 'Accessories', 'Studio', 'Reference'):
    c = bpy.data.collections.new('Reimu_' + n)
    scene.collection.children.link(c)
    COL[n] = c


def material(name, rgb, roughness=0.72):
    m = bpy.data.materials.new('Reimu_' + name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*rgb, 1)
    p.inputs['Roughness'].default_value = roughness
    return m

skin = material('skin', (.72, .48, .37))
red = material('vermilion_cloth', (.46, .025, .042))
red2 = material('ribbon_red', (.62, .035, .055))
white = material('warm_ivory', (.88, .85, .78))
hair = material('dark_brown_hair', (.048, .026, .029), .48)
hair2 = material('hair_planes', (.075, .039, .036), .50)
gold = material('gold_necktie', (.86, .51, .075))
ink = material('lashes', (.022, .012, .017))
iris = material('garnet_iris', (.42, .033, .051), .4)
eye_white = material('eye_white', (.96, .91, .85), .4)
lips = material('lip', (.40, .105, .105))
sole = material('shoe_sole', (.042, .027, .033))
shoe = material('shoe_leather', (.29, .018, .03), .32)


def mesh(name, verts, faces, mat, group='Costume', sub=0, solid=0):
    data = bpy.data.meshes.new('Reimu_' + name + '_mesh')
    data.from_pydata(verts, [], faces)
    data.validate()
    data.update()
    ob = bpy.data.objects.new('Reimu_' + name, data)
    COL[group].objects.link(ob)
    if mat:
        data.materials.append(mat)
    for p in data.polygons:
        p.use_smooth = True
    if sub:
        mod = ob.modifiers.new('Surface smoothing', 'SUBSURF')
        mod.levels = sub
        mod.render_levels = sub
    if solid:
        mod = ob.modifiers.new('Cloth thickness', 'SOLIDIFY')
        mod.thickness = solid
        mod.offset = 0
    return ob


def loft(name, rings, mat, group='Body', sides=32, sub=1, caps=True, fold=0):
    # rings = (z, center_x, center_y, halfwidth, halfdepth)
    verts = []
    for j, (z, x, y, rx, ry) in enumerate(rings):
        for i in range(sides):
            a = 2 * math.pi * i / sides
            f = fold * math.sin(16*a) * (j/max(len(rings)-1, 1))
            verts.append((x+(rx+f)*math.cos(a), y+(ry+f*.7)*math.sin(a), z))
    faces = []
    for j in range(len(rings)-1):
        for i in range(sides):
            k = j*sides+i
            q = j*sides+(i+1)%sides
            faces.append((k, q, q+sides, k+sides))
    if caps:
        faces += [tuple(reversed(range(sides))), tuple((len(rings)-1)*sides+i for i in range(sides))]
    return mesh(name, verts, faces, mat, group, sub)


def ellipsoid(name, center, radii, mat, group='Accessories', n=32, rows=16):
    verts = []
    for j in range(rows+1):
        p = math.pi*j/rows
        for i in range(n):
            a = 2*math.pi*i/n
            verts.append((center[0]+radii[0]*math.sin(p)*math.cos(a), center[1]+radii[1]*math.sin(p)*math.sin(a), center[2]+radii[2]*math.cos(p)))
    faces = []
    for j in range(rows):
        for i in range(n):
            k=j*n+i; q=j*n+(i+1)%n
            faces.append((k, k+n, q+n, q))
    return mesh(name, verts, faces, mat, group)


def line(name, pts, radius, mat, group='Accessories', cyclic=False):
    data = bpy.data.curves.new('Reimu_'+name+'_curve', 'CURVE')
    data.dimensions='3D'
    data.resolution_u=16
    data.bevel_depth=radius
    data.bevel_resolution=3
    sp=data.splines.new('BEZIER')
    sp.bezier_points.add(len(pts)-1)
    for b, pt in zip(sp.bezier_points, pts):
        b.co=pt; b.handle_left_type='AUTO'; b.handle_right_type='AUTO'
    sp.use_cyclic_u=cyclic
    ob=bpy.data.objects.new('Reimu_'+name, data)
    COL[group].objects.link(ob)
    data.materials.append(mat)
    return ob


def panel(name, outline, mat, group='Costume', thickness=.003):
    return mesh(name, outline, [tuple(range(len(outline)))], mat, group, solid=thickness)

# Body proportions: crown/chin exact, hands separated from sleeves.
head = loft('Head', [(1.44375,0,-.012,.001,.001),(1.456,0,-.006,.027,.032),(1.477,0,0,.054,.051),(1.504,0,.003,.070,.061),(1.533,0,.005,.076,.067),(1.565,0,.006,.076,.070),(1.599,0,.009,.068,.063),(1.628,0,.012,.050,.047),(1.645,0,.012,.027,.026),(1.65,0,.012,.001,.001)], skin, sub=0, sides=64)
head['anatomical_head_height_m']=.20625
loft('Neck',[(1.36,0,.01,.041,.035),(1.39,0,.01,.034,.033),(1.44,0,.009,.027,.028),(1.46,0,.009,.03,.03)],skin)
loft('Torso',[(.82,0,.018,.067,.049),(.87,0,.02,.124,.076),(.93,0,.016,.137,.082),(1.005,0,0,.11,.07),(1.065,0,0,.096,.061),(1.14,0,0,.112,.069),(1.22,0,-.003,.142,.081),(1.285,0,.003,.15,.075),(1.33,0,.007,.162,.064),(1.365,0,.012,.133,.05),(1.397,0,.012,.048,.036)],skin)
for s, side in ((-1,'L'),(1,'R')):
    loft('Leg_'+side,[(.075,s*.091,.014,.026,.03),(.13,s*.091,.008,.029,.035),(.22,s*.093,.018,.039,.044),(.33,s*.096,.027,.046,.050),(.425,s*.094,-.003,.036,.040),(.48,s*.092,-.012,.042,.046),(.60,s*.087,.008,.053,.060),(.74,s*.078,.014,.064,.069),(.875,s*.071,.019,.072,.077)],skin)
    ellipsoid('Foot_'+side,(s*.091,-.037,.052),(.033,.086,.043),skin,'Body')
    loft('Arm_'+side,[(.975,s*.338,-.012,.022,.026),(1.025,s*.328,-.006,.025,.03),(1.105,s*.291,.002,.034,.037),(1.17,s*.259,.012,.031,.032),(1.225,s*.231,.012,.036,.038),(1.30,s*.198,.012,.044,.044),(1.35,s*.166,.012,.048,.047)],skin)
    palm=ellipsoid('Palm_'+side,(s*.353,-.014,.951),(.030,.018,.047),skin,'Body')
    for i, length in enumerate((.049,.063,.060,.046)):
        x=s*(.335+i*.013)
        line('Finger_'+side+str(i),[(x,-.018,.943),(x+s*.009,-.019,.923),(x+s*.015,-.013,.943-length)],.0065,skin,'Body')
    line('Thumb_'+side,[(s*.329,-.016,.972),(s*.320,-.025,.953),(s*.312,-.025,.936)],.008,skin,'Body')
    ellipsoid('Ear_'+side,(s*.075,.011,1.511),(.012,.013,.023),skin,'Face')

# Anime face plane. Readable feature proxies, not finished facial topology.
def eye_surface(name, cx, cz, w, h, y, mat):
    verts=[(cx,y-.002,cz)]
    for i in range(48):
        a=2*math.pi*i/48
        x=w*math.cos(a)
        z=h*math.sin(a)*(abs(math.sin(a))**.2)
        verts.append((cx+x,y+abs(x)*.16,cz+z+x*.10))
    return mesh(name,verts,[(0,1+i,1+(i+1)%48) for i in range(48)],mat,'Face')
for s, side in ((-1,'L'),(1,'R')):
    x=s*.031
    eye_surface('Eye_white_'+side,x,1.533,.025,.013,-.0605,eye_white)
    ellipsoid('Iris_'+side,(x,-.064,1.532),(.0107,.0035,.0122),iris,'Face')
    ellipsoid('Pupil_'+side,(x,-.068,1.534),(.0045,.0015,.0075),ink,'Face')
    ellipsoid('Eye_glint_'+side,(x-.003,-.0695,1.54),(.0033,.001,.0033),eye_white,'Face',16,8)
    line('Upper_lash_'+side,[(x-.025,-.0565,1.531),(x-.013,-.062,1.544),(x+.004,-.064,1.546),(x+.025,-.0565,1.536)],.0021,ink,'Face')
    line('Lower_lash_'+side,[(x-.022,-.057,1.53),(x,-.064,1.520),(x+.022,-.057,1.532)],.0008,lips,'Face')
    line('Brow_'+side,[(x-.020,-.058,1.56),(x,-.063,1.566),(x+.020,-.056,1.562)],.0017,hair,'Face')
mesh('Nose', [(-.006,-.058,1.526),(.006,-.058,1.526),(0,-.075,1.506),(-.006,-.061,1.502),(.006,-.061,1.502)],[(0,1,2),(0,2,3),(1,4,2),(3,2,4)],skin,'Face',sub=1)
line('Mouth',[(-.013,-.054,1.480),(0,-.058,1.4785),(.013,-.054,1.480)],.0012,lips,'Face')

# Short sleeveless red bodice and open white collar.
loft('Bodice',[(1.083,0,-.001,.103,.067),(1.088,0,-.001,.104,.068),(1.16,0,-.002,.119,.075),(1.235,0,-.006,.148,.087),(1.282,0,.002,.15,.080),(1.293,0,.002,.145,.076)],red,'Costume',caps=False)
for s, side in ((-1,'L'),(1,'R')):
    panel('Shoulder_strap_'+side,[(s*.05,-.041,1.386),(s*.095,-.039,1.382),(s*.137,-.04,1.286),(s*.075,-.079,1.268)],red)
    panel('Back_strap_'+side,[(s*.05,.046,1.386),(s*.095,.040,1.382),(s*.137,.043,1.286),(s*.075,.073,1.268)],red)
    panel('Collar_'+side,[(0,-.083,1.332),(s*.040,-.096,1.335),(s*.110,-.043,1.376),(s*.047,-.032,1.403)],white)
    line('Collar_stitch_'+side,[(s*.007,-.085,1.34),(s*.038,-.098,1.344),(s*.098,-.048,1.378)],.0013,red2)
loft('Waist_sash',[(1.025,0,0,.115,.075),(1.029,0,0,.115,.075),(1.059,0,0,.111,.073),(1.063,0,0,.109,.072)],red,'Costume',caps=False)
panel('Gold_necktie',[(-.011,-.087,1.33),(.011,-.087,1.33),(.037,-.093,1.235),(0,-.100,1.221),(-.037,-.093,1.235)],gold)
ellipsoid('Tie_knot',(0,-.087,1.329),(.015,.010,.016),gold)
line('Tie_fold',[(0,-.098,1.317),(0,-.105,1.25),(0,-.101,1.23)],.0015,white)

# Pleated bell silhouette with geometric petticoat and trim.
loft('Skirt',[(1.043,0,0,.111,.076),(1.032,0,0,.114,.079),(.98,0,.001,.145,.106),(.88,0,.005,.205,.148),(.76,0,.008,.267,.192),(.635,0,.012,.318,.232),(.578,0,.012,.333,.242),(.570,0,.012,.332,.241)],red,'Costume',sides=128,sub=1,caps=False,fold=.010)
loft('White_petticoat',[(.576,0,.012,.329,.240),(.562,0,.012,.337,.245),(.53,0,.012,.347,.254),(.522,0,.012,.346,.254)],white,'Costume',sides=192,sub=1,caps=False,fold=.016)
pts=[]
for i in range(129):
    a=2*math.pi*i/128
    z=.616+(.015 if i%4==2 else -.015 if i%4==0 else 0)
    rx=.322+( .616-z)*.22
    pts.append((rx*math.cos(a),.012+(rx*.735)*math.sin(a),z))
line('Skirt_zigzag',pts,.0022,white,cyclic=True)
for i in range(32):
    a=2*math.pi*i/32
    ellipsoid('Skirt_dot_'+str(i),(.323*math.cos(a),.012+.239*math.sin(a),.597),(.003,.003,.003),white,n=12,rows=6)

# Detached hanging sleeves, narrow upper cuffs and broad open hems.
for s, side in ((-1,'L'),(1,'R')):
    rings=[(1.291,s*.215,.012,.047,.048),(1.28,s*.217,.012,.048,.049),(1.22,s*.24,.016,.050,.05),(1.125,s*.278,.018,.07,.065),(1.025,s*.307,.018,.102,.085),(.995,s*.315,.018,.112,.092),(.986,s*.317,.018,.112,.092)]
    sleeve=loft('Detached_sleeve_'+side,rings,white,'Costume',sides=48,sub=1,caps=False)
    mod=sleeve.modifiers.new('Sleeve cloth thickness','SOLIDIFY'); mod.thickness=.003
    loft('Sleeve_upper_red_band_'+side,[(1.263,s*.222,.012,.049,.05),(1.27,s*.221,.012,.049,.05)],red2,'Costume',caps=False,sub=0)
    for k in range(12):
        a=2*math.pi*k/12
        b=a+.26
        line('Sleeve_red_dash_'+side+str(k),[(s*.31+.111*math.cos(a),.018+.093*math.sin(a),1.011),(s*.31+.111*math.cos(b),.018+.093*math.sin(b),1.011)],.0035,red2)
    loft('Sock_'+side,[(.064,s*.091,-.007,.034,.044),(.087,s*.091,0,.035,.041),(.165,s*.091,.010,.031,.037),(.181,s*.091,.010,.035,.040),(.185,s*.091,.01,.035,.040)],white,'Costume',caps=False)
    loft('Shoe_sole_'+side,[(0,s*.091,-.039,.036,.084),(.006,s*.091,-.039,.041,.091),(.024,s*.091,-.039,.041,.091),(.028,s*.091,-.039,.039,.089)],sole,'Costume',sides=48,sub=0)
    loft('Shoe_upper_'+side,[(.025,s*.091,-.039,.04,.09),(.044,s*.091,-.045,.042,.089),(.068,s*.091,-.052,.040,.078),(.082,s*.091,-.054,.033,.065)],shoe,'Costume',sides=48,sub=1,caps=False)
    line('Shoe_strap_'+side,[(s*.091-.037,-.048,.067),(s*.091-.027,-.058,.093),(s*.091,-.062,.100),(s*.091+.027,-.058,.093),(s*.091+.037,-.048,.067)],.008,shoe,'Costume')

# Hair cap and sculptable tapered hair masses.
verts=[]; faces=[]; n=64; rows=16
for j in range(rows+1):
    for i in range(n):
        a=2*math.pi*i/n
        end=1.04+1.32*((1-math.cos(a))/2)**.60
        p=.008+(end-.008)*j/rows
        verts.append((.082*math.sin(p)*math.sin(a),.011-.076*math.sin(p)*math.cos(a),1.55+.116*math.cos(p)))
for j in range(rows):
    for i in range(n):
        k=j*n+i; q=j*n+(i+1)%n
        faces.append((k,q,q+n,k+n))
mesh('Hair_cap',verts,faces,hair,'Hair',sub=1,solid=.004)


def strand(name, points, widths, depths, mat=hair):
    return loft(name,[(p[2],p[0],p[1],w,d) for p,w,d in zip(points,widths,depths)],mat,'Hair',sides=12,sub=2)

for i in range(11):
    t=(i-5)/5
    x=t*.075
    strand('Back_hair_%02d'%i,[(x*.65,.05,1.625),(x,.078,1.54),(t*.103,.094,1.42),(t*.128,.109,1.30),(t*.146,.10,1.20),(t*.131,.064,1.16+.035*abs(t))],[.021,.026,.028,.029,.023,.001],[.013,.024,.025,.021,.015,.001],hair2 if i%3==0 else hair)
# Bangs end above the eye line, swept to a central point.
for i in range(7):
    t=(i-3)/3
    x=t*.065
    tip=1.551+ .014*abs(t) + (.004 if i%2 else -.005)
    strand('Bangs_%02d'%i,[(x*.5,-.035,1.645),(x*.75,-.068,1.62),(x,-.074,1.585),(x+.007,-.077,tip)],[.015,.022,.021,.001],[.009,.012,.010,.001],hair2 if i%3==0 else hair)
for s, side in ((-1,'L'),(1,'R')):
    strand('Face_frame_'+side,[(s*.072,-.023,1.60),(s*.083,-.027,1.55),(s*.086,-.027,1.47),(s*.095,-.017,1.37),(s*.091,-.025,1.325)],[.02,.019,.017,.014,.001],[.015,.018,.015,.010,.001])
    loft('Hair_red_cuff_'+side,[(1.369,s*.094,-.019,.021,.016),(1.409,s*.092,-.024,.018,.017)],red2,'Accessories',sub=0)
    loft('Hair_cuff_frill_'+side,[(1.362,s*.094,-.019,.025,.022),(1.371,s*.094,-.019,.022,.019)],white,'Accessories',sides=32,sub=0,fold=.003)

# Structured bows: pinched cloth loops, not a flattened reference image.
def bow(name, center, size, mat=red2):
    cx,cy,cz=center
    for s, side in ((-1,'L'),(1,'R')):
        verts=[]
        for j in range(9):
            u=j/8
            x=s*size*(.08+.92*u)
            half=size*(.09+.43*u)
            for k in range(9):
                v=2*k/8-1
                y=cy-size*.14*math.sin(math.pi*u)*(1-v*v)+size*.065*math.sin(3*math.pi*v)*u
                z=cz+size*.15*u+half*v
                verts.append((cx+x,y,z))
        faces=[]
        for j in range(8):
            for k in range(8):
                a=j*9+k; faces.append((a,a+9,a+10,a+1))
        mesh(name+'_loop_'+side,verts,faces,mat,'Accessories',sub=1,solid=.005)
        pts=[]
        for k in range(17):
            v=2*k/16-1
            pts.append((cx+s*size,cy+size*.065*math.sin(3*math.pi*v)-.004,cz+size*.15+size*.52*v))
        line(name+'_white_edge_'+side,pts,size*.035,white)
    ellipsoid(name+'_knot',(cx,cy-.004,cz),(.14*size,.12*size,.18*size),mat)

bow('Head_bow',(0,.071,1.65),.16)
for s,side in ((-1,'L'),(1,'R')):
    panel('Head_ribbon_tail_'+side,[(s*.035,.067,1.647),(s*.101,.072,1.63),(s*.149,.081,1.499),(s*.107,.07,1.515),(s*.079,.065,1.488)],red2,'Accessories',.006)
    line('Tail_white_edge_'+side,[(s*.149,.078,1.499),(s*.107,.067,1.515),(s*.079,.062,1.488)],.004,white)
bow('Waist_back_bow',(0,.105,1.031),.098)
for s,side in ((-1,'L'),(1,'R')):
    panel('Waist_tail_'+side,[(s*.02,.113,1.018),(s*.063,.125,1.008),(s*.095,.189,.806),(s*.059,.193,.821),(s*.039,.19,.794)],red,'Accessories',.005)
    bow('Sleeve_tie_'+side,(s*.233,-.039,1.269),.029)
    line('Sleeve_tie_tail_'+side,[(s*.236,-.042,1.264),(s*.242,-.047,1.218),(s*.257,-.049,1.2)],.004,red2)
    bow('Sock_bow_'+side,(s*.12,-.01,.174),.019)

# Embedded reference for later sculpting, kept out of camera renders.
ref = bpy.data.images.load(scene['reference'],check_existing=True)
ref.pack()
reference=bpy.data.objects.new('Reimu_Reference_sheet',None)
reference.empty_display_type='IMAGE'; reference.data=ref
reference.empty_display_size=2.5
reference.location=(2, .5, 1)
reference.hide_render=True
COL['Reference'].objects.link(reference)
COL['Reference'].hide_viewport=True

# Neutral review studio, isolated from the user's original scene.
world=bpy.data.worlds.new('Reimu_Studio_world'); world.use_nodes=True
world.node_tree.nodes.get('Background').inputs[0].default_value=(.32,.32,.32,1)
world.node_tree.nodes.get('Background').inputs[1].default_value=.6
scene.world=world

def camera(name, loc, target, scale=1.96):
    data=bpy.data.cameras.new('Reimu_'+name)
    ob=bpy.data.objects.new('Reimu_'+name,data); COL['Studio'].objects.link(ob)
    ob.location=loc; ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
    data.type='ORTHO'; data.ortho_scale=scale
    return ob
camera('Front',(0,-5,.88),(0,0,.88))
camera('Side',(5,0,.88),(0,0,.88))
camera('Back',(0,5,.88),(0,0,.88))
camera('ThreeQuarter',(3,-5,2.4),(0,0,.87))
camera('FaceClose',(0,-5,1.54),(0,0,1.54),.43)
for n,loc,power,size in [('Key',(-3,-4,5),500,4),('Fill',(3,-2,3),350,3),('Rim',(0,3,4),550,3)]:
    data=bpy.data.lights.new('Reimu_'+n,'AREA'); data.energy=power; data.shape='DISK'; data.size=size
    ob=bpy.data.objects.new('Reimu_'+n,data); COL['Studio'].objects.link(ob)
    ob.location=loc; ob.rotation_euler=(Vector((0,0,1))-ob.location).to_track_quat('-Z','Y').to_euler()
scene.camera=bpy.data.objects['Reimu_Front']
scene.render.engine='BLENDER_EEVEE'
scene.render.resolution_x=900; scene.render.resolution_y=1200; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.render.film_transparent=True
scene.render.filepath=str(OUT/'front.png')
scene.view_settings.view_transform='AgX'
# Put the artist straight into a useful model view.
for area in bpy.context.screen.areas:
    if area.type=='VIEW_3D':
        area.spaces.active.region_3d.view_perspective='CAMERA'
        area.spaces.active.overlay.show_overlays=False
        area.spaces.active.shading.type='MATERIAL'
        area.spaces.active.region_3d.view_camera_zoom=0
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(TARGET), check_existing=False)
print(json.dumps({'created_scene':scene.name,'saved':bpy.data.filepath,'objects':len(scene.objects),'head_bounds_z':[min(v.co.z for v in head.data.vertices),max(v.co.z for v in head.data.vertices)],'status':'ART_REVIEW'},ensure_ascii=False))
