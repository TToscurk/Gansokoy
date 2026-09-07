import bpy, math, json
from pathlib import Path
scene=bpy.data.scenes['Reimu_Blockout_v001']
bpy.context.window.scene=scene
# Replace only the initial bang proxies from this task.
for ob in list(bpy.data.collections['Reimu_Hair'].objects):
    if ob.name.startswith('Reimu_Bangs_'):
        bpy.data.objects.remove(ob,do_unlink=True)
col=bpy.data.collections['Reimu_Hair']
hair=bpy.data.materials['Reimu_dark_brown_hair']
for i in range(7):
    t=(i-3)/3
    vs=[]; fs=[]
    for j in range(13):
        u=j/12
        x=t*(.025+.041*math.sin(u*math.pi/2))
        cy=-.018-.059*math.sin(u*math.pi/2)
        end=1.548+.016*abs(t)+(.005 if i%2 else -.003)
        z=1.652*(1-u)+end*u+.016*math.sin(math.pi*u)
        w=(.012+.010*math.sin(math.pi*u))*(1-u**7)+.0003
        for k in range(7):
            v=2*k/6-1
            vs.append((x+w*v,cy-.003*(1-v*v),z+.008*v*v*u))
    for j in range(12):
        for k in range(6):
            a=j*7+k;fs.append((a,a+7,a+8,a+1))
    me=bpy.data.meshes.new('Reimu_Bangs_surface_%d'%i);me.from_pydata(vs,[],fs);me.update()
    ob=bpy.data.objects.new('Reimu_Bangs_%02d'%i,me);col.objects.link(ob);me.materials.append(hair)
    for p in me.polygons:p.use_smooth=True
    sub=ob.modifiers.new('Smooth hair planes','SUBSURF');sub.levels=2;sub.render_levels=2
    so=ob.modifiers.new('Hair thickness','SOLIDIFY');so.thickness=.003
# Closed red upper front and back instead of separated shoulder tabs.
for side, ysign in [('Front',-1),('Back',1)]:
    vs=[(-.141,ysign*.063,1.282),(-.093,ysign*.047,1.38),(-.043,ysign*.043,1.383),(0,ysign*.08,1.336),(.043,ysign*.043,1.383),(.093,ysign*.047,1.38),(.141,ysign*.063,1.282),(.074,ysign*.082,1.278),(0,ysign*.09,1.278),(-.074,ysign*.082,1.278)]
    me=bpy.data.meshes.new('Reimu_Upper_bodice_'+side);me.from_pydata(vs,[],[(0,1,2,3,9),(9,3,8),(8,3,7),(3,4,5,6,7)]);me.update()
    ob=bpy.data.objects.new('Reimu_Upper_bodice_'+side,me);bpy.data.collections['Reimu_Costume'].objects.link(ob);me.materials.append(bpy.data.materials['Reimu_vermilion_cloth'])
    so=ob.modifiers.new('Cloth thickness','SOLIDIFY');so.thickness=.004
for ob in list(bpy.data.collections['Reimu_Costume'].objects):
    if ob.name.startswith(('Reimu_Shoulder_strap_','Reimu_Back_strap_')):
        bpy.data.objects.remove(ob,do_unlink=True)
# Fold relief and a slightly irregular sleeve opening, without moving cuffs.
for side in ('L','R'):
    ob=bpy.data.objects['Reimu_Detached_sleeve_'+side]
    sign=-1 if side=='L' else 1
    for v in ob.data.vertices:
        u=max(0,min(1,(1.28-v.co.z)/.294))
        j=round((v.co.z-0.986)*1000)
        a=math.atan2(v.co.y-.018,v.co.x-sign*(.217+.1*u))
        v.co.y+=.004*math.sin(a*9)*u
        v.co.z+=.012*math.cos(a*2)*u*u
# Darken the materials toward the reference rather than pastel toy colors.
for name,rgb in [('vermilion_cloth',(.32,.012,.022)),('ribbon_red',(.42,.018,.029)),('skin',(.68,.43,.32)),('dark_brown_hair',(.021,.010,.012)),('hair_planes',(.034,.016,.016))]:
    m=bpy.data.materials['Reimu_'+name]
    m.diffuse_color=(*rgb,1)
    m.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(*rgb,1)
scene['iteration']='v002: planar bangs, connected upper bodice, sleeve folds'
scene.camera=bpy.data.objects['Reimu_Front']
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath='D:/神社/shrine/artifacts/reimu_blockout/reimu_8head_v002.blend',check_existing=False)
print(json.dumps({'saved':bpy.data.filepath,'objects':len(scene.objects)},ensure_ascii=False))
for name in ('Front','Side','Back'):
    scene.camera=bpy.data.objects['Reimu_'+name]
    scene.render.filepath='D:/神社/shrine/artifacts/reimu_blockout/'+name.lower()+'.png'
    bpy.ops.render.render(write_still=True)
    print('RENDER_COMPLETE '+name)
scene.camera=bpy.data.objects['Reimu_Front']
