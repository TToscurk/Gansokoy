"""Generate three standalone Human Village building proofs.

Usage: D:\\Blender\\blender.exe -b -P godot/assets/blender/make_building_asset_proof.py -- godot/assets/models
"""
import bpy
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_compat as BC   # shader nodes by TYPE, not by (localized) name

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(ARGV[0] if ARGV else "godot/assets/models")
SOURCE_OUT = os.path.abspath("godot/assets/blender/sources")
ONLY = set(ARGV[1:])

# Material names are a contract, not labels. `gen_lib.semantic_mesh()` maps a
# surface to the project's PBR set by NAME PREFIX over
# WOOD_LT / WOOD / PLASTER / STONE / KAWARA / SHOJI.
# These were previously named "WOOD_LIGHT" and "PAPER": the first collapsed
# into the plain WOOD bucket (prefix match) and the second matched nothing at
# all, so the light timber and the shoji lost their identity on the way into
# Godot. EARTH has no semantic slot and deliberately keeps the glb material.
MATS = {
    "WOOD": ((0.11, 0.075, 0.045, 1), 0.84),
    "WOOD_LT": ((0.28, 0.18, 0.09, 1), 0.82),
    "PLASTER": ((0.72, 0.67, 0.56, 1), 0.92),
    "KAWARA": ((0.12, 0.15, 0.18, 1), 0.68),
    "EARTH": ((0.30, 0.20, 0.12, 1), 0.94),
    "SHOJI": ((0.82, 0.77, 0.64, 1), 0.94),
}

def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

def materials():
    for name, (color, rough) in MATS.items():
        mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = BC.principled(mat)
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = rough

def box(name, loc, scale, mat="WOOD"):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    ob = bpy.context.object
    ob.name = name
    ob.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.append(bpy.data.materials[mat])
    return ob

def cyl(name, loc, radius, depth, mat="WOOD", vertices=12, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot)
    ob = bpy.context.object; ob.name = name; ob.data.materials.append(bpy.data.materials[mat]); return ob

def gable_roof(name, w, d, eave_z, rise, y=0, mat="KAWARA", over=0.65):
    verts = [(-w/2-over,-d/2-over,eave_z),(w/2+over,-d/2-over,eave_z),(0,-d/2-over,eave_z+rise),
             (-w/2-over,d/2+over,eave_z),(w/2+over,d/2+over,eave_z),(0,d/2+over,eave_z+rise)]
    faces = [(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)]
    me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.materials.append(bpy.data.materials[mat])
    ob=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(ob); return ob

def gable_roof_at(name, cx, cy, w, d, eave_z, rise, mat="KAWARA", over=.65):
    """Closed, centered gable volume with straight ridge and matched eaves."""
    x0, x1 = cx-w/2-over, cx+w/2+over
    y0, y1 = cy-d/2-over, cy+d/2+over
    ridge = (cx, eave_z+rise)
    verts = [(x0,y0,eave_z),(x1,y0,eave_z),(ridge[0],y0,ridge[1]),
             (x0,y1,eave_z),(x1,y1,eave_z),(ridge[0],y1,ridge[1])]
    faces = [(0,2,1),(3,4,5),(0,3,5,2),(2,5,4,1),(0,1,4,3)]
    me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.materials.append(bpy.data.materials[mat])
    ob=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(ob); return ob

def hip_roof(name, w, d, eave_z, rise, mat="KAWARA", over=0.7, ridge=0.35):
    x=w/2+over; y=d/2+over
    verts=[(-x,-y,eave_z),(x,-y,eave_z),(x,y,eave_z),(-x,y,eave_z),(-ridge,-y*.55,eave_z+rise),(ridge,-y*.55,eave_z+rise),(ridge,y*.55,eave_z+rise),(-ridge,y*.55,eave_z+rise)]
    faces=[(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]
    me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.materials.append(bpy.data.materials[mat])
    ob=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(ob); return ob

def posts(prefix, xs, y, z, h, thick=.16, mat="WOOD"):
    for i,x in enumerate(xs): box(f"{prefix}_post_{i}",(x,y,z+h/2),(thick,thick,h),mat)

def lattice(prefix, x0, x1, y, z0, z1, count):
    for i in range(count):
        x=x0+(x1-x0)*i/max(1,count-1); box(f"{prefix}_lat_{i}",(x,y,(z0+z1)/2),(.065,.07,z1-z0),"WOOD")
    for i,z in enumerate((z0,z1,(z0+z1)/2)): box(f"{prefix}_rail_{i}",((x0+x1)/2,y,z),(x1-x0,.075,.07),"WOOD")

def barrel(name,x,y,z,scale=1):
    cyl(name,(x,y,z),.48*scale,.9*scale,"WOOD_LT",16)
    for dz in (-.32,.32): cyl(name+"_band"+str(dz),(x,y,z+dz*scale),.50*scale,.06*scale,"WOOD",16)

def build_sake():
    # Broad, low merchant house: hipped main roof, deep continuous shop canopy, attached kura wing.
    box("sake_plinth",(0,0,.18),(12.2,8.0,.36),"EARTH")
    box("sake_body",(0,.2,1.75),(11.4,7.2,3.2),"PLASTER")
    posts("sake",[-5.35,-3.5,-1.6,.2,2.1,4.0,5.35],-3.44,.35,2.75)
    lattice("sake_left",-5.1,-2.0,-3.51,.65,2.45,11)
    lattice("sake_right",1.4,5.05,-3.51,.65,2.45,12)
    box("sake_entry",(-.55,-3.53,1.48),(1.65,.12,2.25),"WOOD_LT")
    hip_roof("sake_main_hip",11.8,7.5,3.45,1.88)
    box("sake_canopy",(0,-4.02,2.55),(12.0,1.55,.16),"KAWARA")
    posts("sake_canopy",[-5.4,0,5.4],-4.55,.25,2.25,.13)
    # Architectural business cue: integrated cask loading bay and cedar-ball bracket.
    box("sake_loading_frame",(-4.3,-4.02,1.2),(2.35,.35,2.15),"WOOD")
    barrel("sake_cask_a",-4.65,-4.38,.82,1.05); barrel("sake_cask_b",-3.65,-4.38,.72,.85)
    cyl("sake_sugidama",(3.85,-4.38,2.55),.48,.75,"EARTH",16,rot=(math.pi/2,0,0))
    # Phase 2A hero frontage: the broad open bay gets a readable noren rhythm,
    # while the cedar ball and cask bay remain the sake-shop-specific cues.
    for i, x in enumerate((-1.28, -.82, -.36, .10)):
        box(f"sake_noren_{i}",(x,-4.43,2.18),(.38,.035,.82),"PLASTER")
    box("sake_noren_rail",(-.59,-4.43,2.63),(1.95,.07,.11),"WOOD")
    box("sake_sign_bracket",(2.72,-4.34,2.56),(.12,.12,1.10),"WOOD")
    box("sake_sign_board",(2.72,-4.43,2.18),(.62,.07,.78),"WOOD_LT")
    box("sake_threshold",(-.58,-4.48,.30),(2.15,.48,.16),"WOOD_LT")
    box("sake_kura",(4.55,2.3,2.25),(3.0,3.0,4.15),"PLASTER")
    gable_roof("sake_kura_roof",3.2,3.2,4.3,1.16,y=2.3)
    # Phase 2B hero tier: one low brewing smoke monitor.  It is deliberately
    # smaller than the attached kura and remains part of the roof mass, never
    # a tower or universal shop motif.
    box("sake_smoke_monitor",(1.65,.85,4.86),(1.75,1.90,.52),"PLASTER")
    gable_roof_at("sake_smoke_monitor_roof",1.65,.85,1.95,2.10,5.12,.52,over=.30)
    lattice("sake_side",-5.76,-5.76,-.2,.8,2.2,3)  # side relief rhythm

def build_inn():
    # Tall deep hatago: two-storey front block, projecting gallery, stepped rear wing and entry porch.
    box("inn_plinth",(0,.3,.2),(8.8,11.2,.4),"EARTH")
    box("inn_body",(0,.4,2.75),(8.2,10.3,5.1),"PLASTER")
    gable_roof("inn_main_roof",8.5,10.7,5.25,2.24)
    posts("inn_front",[-3.75,-2.5,-1.2,1.1,2.4,3.75],-4.78,.4,2.55)
    lattice("inn_shop",-3.55,-1.5,-4.87,.7,2.5,8)
    box("inn_recess",(0,-4.93,1.5),(1.75,.2,2.45),"WOOD_LT")
    lattice("inn_room",1.35,3.55,-4.87,.7,2.5,8)
    # Strong inn cue: continuous second-floor guest gallery with rhythmic room screens.
    box("inn_gallery_deck",(0,-5.25,3.45),(8.7,1.25,.18),"WOOD")
    posts("inn_gallery",[-3.75,-2.5,-1.25,0,1.25,2.5,3.75],-5.65,3.45,1.62,.12)
    box("inn_gallery_top",(0,-5.65,5.05),(8.4,.15,.14),"WOOD")
    for i,x in enumerate([-3.1,-1.55,0,1.55,3.1]):
        box(f"inn_shoji_{i}",(x,-4.84,4.22),(1.25,.10,1.35),"SHOJI")
        lattice(f"inn_upper_{i}",x-.56,x+.56,-4.91,3.6,4.85,4)
    box("inn_entry_roof",(0,-5.72,2.72),(2.65,1.75,.16),"KAWARA")
    posts("inn_entry",[-1.05,1.05],-6.3,.25,2.45,.15)
    # Side-wall veranda and rain-shutter rhythm make the long depth legible.
    box("inn_side_walk",(4.45,.6,1.05),(1.1,8.3,.18),"WOOD_LT")
    posts("inn_side",[4.25,4.25],-2.8,.35,2.4,.15)
    for y in (-2.6,-1.0,.6,2.2,3.8): box("inn_side_shutter",(4.14,y,1.65),(.12,1.05,1.7),"WOOD")
    box("inn_rear_wing",(-2.4,5.25,2.0),(3.4,2.7,3.6),"PLASTER")
    hip_roof("inn_rear_hip",3.6,2.9,3.75,1.0)

def build_workshop():
    # Asymmetric compound: tall street-facing work hall plus low storage lean-to.
    box("work_plinth",(0,.2,.18),(10.4,8.6,.36),"EARTH")
    box("work_hall",(-1.55,.1,2.15),(6.7,7.8,3.95),"WOOD_LT")
    # Street-facing gable gives a silhouette unlike the two eave-front merchants.
    gable_roof_at("work_gable",-1.55,.1,6.9,8.1,4.1,2.25)
    # Straight ridge, matched eave fascias, and a framed plaster front gable.
    box("work_ridge_cap",(-1.55,.1,6.39),(.22,9.55,.20),"KAWARA")
    box("work_eave_left",(-5.65,.1,4.08),(.16,9.55,.22),"WOOD")
    box("work_eave_right",(2.55,.1,4.08),(.16,9.55,.22),"WOOD")
    gable_roof_at("work_front_gable_panel",-1.55,-4.03,5.95,.04,4.08,1.92,"PLASTER",0)
    box("work_gable_tie",(-1.55,-4.20,4.10),(6.15,.18,.18),"WOOD")
    box("work_gable_king_post",(-1.55,-4.20,5.18),(.18,.18,2.05),"WOOD")
    box("work_lean_body",(3.45,.8,1.55),(3.1,6.3,2.75),"PLASTER")
    box("work_lean_roof",(3.55,.65,3.15),(3.65,7.0,.18),"KAWARA")
    posts("work_front",[-4.55,-2.9,-1.25,.4,1.72],-3.72,.32,3.25,.18)
    # Strong workshop cue: full-height open work portal, beam crane and timber rack.
    box("work_open_dark",(-1.65,-3.78,1.82),(3.0,.16,2.9),"EARTH")
    box("work_portal_top",(-1.65,-3.94,3.18),(3.25,.22,.24),"WOOD")
    box("work_crane_beam",(-1.55,-4.55,3.1),(3.8,.18,.2),"WOOD")
    posts("work_crane",[-3.25,.15],-4.55,.25,2.85,.16)
    cyl("work_hoist",(-1.55,-4.58,2.15),.18,1.25,"WOOD",12)
    lattice("work_front_side",.45,1.55,-3.82,.7,2.75,5)
    for i,z in enumerate((.65,1.25,1.85)): box(f"work_rack_{i}",(3.55,-3.65,z),(2.8,.55,.13),"WOOD")
    for i,x in enumerate((2.55,3.55,4.55)): cyl(f"work_log_{i}",(x,-3.9,.55),.24,2.2,"WOOD_LT",10,rot=(math.pi/2,0,0))
    # Clerestory smoke monitor makes the upper silhouette unmistakable.
    box("work_monitor",(-1.55,.45,5.05),(2.25,2.5,1.05),"PLASTER")
    gable_roof_at("work_monitor_roof",-1.55,.45,2.5,2.8,5.55,.72,over=.40)
    box("work_monitor_ridge",(-1.55,.45,6.31),(.16,3.60,.16),"KAWARA")
    box("work_vent",(-1.55,-.86,5.05),(1.4,.10,.55),"EARTH")
    for y in (-2.2,0,2.2): box("work_side_brace",(-5.0,y,2.0),(.14,1.25,2.8),"WOOD")
    # Restrained functional detail: framed rear service doors and high daylight screens.
    posts("work_rear",[-4.55,-3.0,-1.45,.1,1.65],3.86,.35,3.20,.16)
    box("work_rear_lintel",(-1.45,3.88,3.25),(6.35,.18,.20),"WOOD")
    for i,x in enumerate((-3.75,-2.20,-.65,.90)):
        box(f"work_rear_screen_{i}",(x,3.91,2.55),(1.15,.10,.72),"SHOJI")
        box(f"work_rear_screen_sill_{i}",(x,3.96,2.16),(1.25,.14,.14),"WOOD")

def export_asset(name, builder):
    """Build, JOIN INTO ONE OBJECT, export, and report the measured bbox.

    ⚠ The join is the whole point of this function, not tidiness.
    This script used to export every loose primitive as its own glTF node.
    Blender was happy and `measure_building_asset_proof.py` reported the right
    dimensions, because it aggregates *all* mesh objects after re-import.
    But the engine does not: `gen_lib.semantic_mesh()` / `prop_mesh()` walk the
    imported scene, take the FIRST MeshInstance3D they meet, and stop. So each
    of these three buildings arrived in Godot as one arbitrary sub-part —
    a smoke vent (1.40 m), a lattice rail (1.12 m), a cedar ball (0.96 m) —
    while `PHASE5A_FAMILIES` still declared 9–13 m footprints. OBB checks and
    collision boxes are built from that table, so every static gate passed and
    Phase 5A shipped three invisible buildings with invisible colliders.
    Every other exporter in this kit (`make_machiya.py`, `make_building_
    families.py`) hands `export_scene.gltf` a single joined object. So does
    this one now. `tools/asset_dims_check.gd` is the gate that keeps it true.
    """
    clear(); materials(); builder()
    meshes=[o for o in bpy.context.scene.objects if o.type=="MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes: o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob=bpy.context.view_layer.objects.active
    ob.name=name
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    assert len([o for o in bpy.context.scene.objects if o.type=="MESH"])==1, \
        "%s did not collapse to a single mesh object" % name
    os.makedirs(SOURCE_OUT,exist_ok=True); os.makedirs(OUT,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SOURCE_OUT,name+".blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,name+".glb"),use_selection=True,export_format="GLB",export_yup=True,export_apply=True,export_materials="EXPORT")
    vs=[v.co for v in ob.data.vertices]
    dx=max(v.x for v in vs)-min(v.x for v in vs)
    dy=max(v.y for v in vs)-min(v.y for v in vs)
    dz=max(v.z for v in vs)-min(v.z for v in vs)
    # Blender (x, y, z) with export_yup -> Godot (x, z, -y): w = dx, h = dz, d = dy
    print("PROOF_ASSET %s w=%.3f h=%.3f d=%.3f faces=%d mats=%d" %
          (name, dx, dz, dy, len(ob.data.polygons), len(ob.data.materials)))

for asset,builder in (("asset_proof_sake_shop",build_sake),("asset_proof_hatago",build_inn),("asset_proof_workshop",build_workshop)):
    if not ONLY or asset in ONLY:
        export_asset(asset,builder)
