"""Build and review-render the Yoriichi Character Track 01 prototype.

ART_FAST scope: one coherent, unrigged character prototype with large readable
forms.  This script owns the source geometry so the asset remains reproducible.

Scale contract:
    Blender: metres, +Z up, -Y forward, origin between the soles at ground level.
    Godot/glTF: metres, +Y up, -Z forward after standard glTF axis conversion.
    Visual height: 1.78 m; current gameplay capsule reference: 1.70 m.
"""

from __future__ import annotations

import json
import math
import os
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "assets" / "blender" / "sources"
MODEL_DIR = ROOT / "assets" / "models"
SHOT_DIR = ROOT.parent / "shots2" / "yoriichi_character_track_01"
BLEND_PATH = SOURCE_DIR / "yoriichi_base_prototype.blend"
GLB_PATH = MODEL_DIR / "yoriichi_base_prototype.glb"
MEASURE_PATH = SHOT_DIR / "measurements.json"

CHARACTER_HEIGHT_M = 1.78
PLAYER_CAPSULE_HEIGHT_M = 1.70
FORWARD_BLENDER = "-Y"
UP_BLENDER = "+Z"


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials,
                       bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def make_material(name: str, rgba: tuple[float, float, float, float],
                  roughness: float = 0.6, metallic: float = 0.0) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = rgba
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf is None:
        material.node_tree.nodes.clear()
        bsdf = material.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
        output = material.node_tree.nodes.new("ShaderNodeOutputMaterial")
        material.node_tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return material


def assign_material(obj: bpy.types.Object, material: bpy.types.Material) -> None:
    if obj.data and hasattr(obj.data, "materials"):
        obj.data.materials.append(material)


def finish_object(obj: bpy.types.Object, collection: bpy.types.Collection,
                  material: bpy.types.Material | None = None,
                  bevel: float = 0.0) -> bpy.types.Object:
    for existing in list(obj.users_collection):
        existing.objects.unlink(obj)
    collection.objects.link(obj)
    if material is not None:
        assign_material(obj, material)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Soft bevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
    return obj


def cube(name: str, location: tuple[float, float, float],
         scale: tuple[float, float, float], collection: bpy.types.Collection,
         material: bpy.types.Material, bevel: float = 0.015,
         rotation: tuple[float, float, float] = (0.0, 0.0, 0.0)) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_object(obj, collection, material, bevel)


def sphere(name: str, location: tuple[float, float, float],
           scale: tuple[float, float, float], collection: bpy.types.Collection,
           material: bpy.types.Material, segments: int = 32,
           rings: int = 20) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.shade_smooth()
    return finish_object(obj, collection, material)


def cylinder_between(name: str, start: tuple[float, float, float],
                     end: tuple[float, float, float], radius: float,
                     collection: bpy.types.Collection, material: bpy.types.Material,
                     vertices: int = 24, bevel: float = 0.006) -> bpy.types.Object:
    a, b = Vector(start), Vector(end)
    delta = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius,
                                       depth=delta.length, location=(a + b) * 0.5)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Z", "Y")
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.shade_smooth()
    return finish_object(obj, collection, material, bevel)


def tapered_between(name: str, start: tuple[float, float, float],
                    end: tuple[float, float, float], radius_a: float, radius_b: float,
                    collection: bpy.types.Collection, material: bpy.types.Material,
                    vertices: int = 24, bevel: float = 0.004) -> bpy.types.Object:
    a, b = Vector(start), Vector(end)
    delta = b - a
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius_a, radius2=radius_b,
                                   depth=delta.length, location=(a + b) * 0.5)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Z", "Y")
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.shade_smooth()
    return finish_object(obj, collection, material, bevel)


def prism(name: str, points_xz: list[tuple[float, float]], y_front: float,
          depth: float, collection: bpy.types.Collection,
          material: bpy.types.Material, bevel: float = 0.008) -> bpy.types.Object:
    """Extrude a closed X/Z polygon toward +Y; winding is intentionally closed."""
    count = len(points_xz)
    verts = [(x, y_front, z) for x, z in points_xz]
    verts += [(x, y_front + depth, z) for x, z in points_xz]
    faces: list[tuple[int, ...]] = []
    faces.append(tuple(reversed(range(count))))
    faces.append(tuple(range(count, count * 2)))
    for index in range(count):
        next_index = (index + 1) % count
        faces.append((index, next_index, count + next_index, count + index))
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    assign_material(obj, material)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Soft bevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
    return obj


def curve_line(name: str, points: list[tuple[float, float, float]], radius: float,
               collection: bpy.types.Collection, material: bpy.types.Material) -> bpy.types.Object:
    curve = bpy.data.curves.new(name=f"{name}_curve", type="CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 3
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, coordinate in zip(spline.bezier_points, points):
        point.co = coordinate
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    assign_material(obj, material)
    return obj


def add_hanafuda(name: str, x: float, collection: bpy.types.Collection,
                 materials: dict[str, bpy.types.Material]) -> None:
    side = -1.0 if x < 0.0 else 1.0
    y = -0.015
    cube(f"{name}_hook", (x, y, 1.555), (0.006, 0.006, 0.025), collection,
         materials["metal"], bevel=0.003)
    cube(f"{name}_plate", (x, y, 1.495), (0.026, 0.009, 0.050), collection,
         materials["earring_cream"], bevel=0.006,
         rotation=(0.0, 0.0, math.radians(side * 2.0)))
    cube(f"{name}_top_red", (x, y - 0.010, 1.524), (0.020, 0.003, 0.015), collection,
         materials["mark"], bevel=0.002)
    sphere(f"{name}_sun", (x, y - 0.014, 1.493), (0.012, 0.003, 0.012), collection,
           materials["mark"], segments=16, rings=8)
    prism(f"{name}_rays", [(x - 0.018, 1.485), (x + 0.018, 1.485),
                            (x + 0.012, 1.459), (x - 0.012, 1.459)],
          y - 0.015, 0.004, collection, materials["earring_dark"], bevel=0.001)


def build_character() -> tuple[bpy.types.Collection, dict[str, bpy.types.Material]]:
    character = bpy.data.collections.new("Yoriichi_Base_Prototype")
    bpy.context.scene.collection.children.link(character)

    materials = {
        "skin": make_material("Y_Skin", (0.48, 0.24, 0.16, 1.0), 0.72),
        "skin_shadow": make_material("Y_Skin_Shadow", (0.24, 0.10, 0.07, 1.0), 0.75),
        "uniform": make_material("Y_Uniform", (0.035, 0.045, 0.050, 1.0), 0.72),
        "uniform_edge": make_material("Y_Uniform_Edge", (0.12, 0.14, 0.14, 1.0), 0.66),
        "haori": make_material("Y_Haori_Red", (0.055, 0.004, 0.006, 1.0), 0.76),
        "haori_light": make_material("Y_Haori_Highlight", (0.095, 0.007, 0.010, 1.0), 0.73),
        "lining": make_material("Y_Haori_Lining", (0.025, 0.002, 0.003, 1.0), 0.78),
        "hair": make_material("Y_Hair_RedBlack", (0.055, 0.010, 0.012, 1.0), 0.58),
        "hair_red": make_material("Y_Hair_RedEdge", (0.16, 0.015, 0.018, 1.0), 0.62),
        "eyes": make_material("Y_Eyes", (0.30, 0.055, 0.045, 1.0), 0.42),
        "white": make_material("Y_EyeWhite", (0.82, 0.74, 0.64, 1.0), 0.70),
        "mark": make_material("Y_Flame_Mark", (0.46, 0.035, 0.025, 1.0), 0.60),
        "belt": make_material("Y_Belt", (0.20, 0.12, 0.075, 1.0), 0.78),
        "wrap": make_material("Y_Leg_Wrap", (0.42, 0.36, 0.28, 1.0), 0.82),
        "sheath": make_material("Y_Sheath", (0.030, 0.003, 0.005, 1.0), 0.46),
        "metal": make_material("Y_Metal", (0.32, 0.30, 0.27, 1.0), 0.28, 0.65),
        "gold": make_material("Y_Gold", (0.48, 0.27, 0.06, 1.0), 0.34, 0.55),
        "earring_cream": make_material("Y_Hanafuda_Cream", (0.78, 0.69, 0.52, 1.0), 0.72),
        "earring_dark": make_material("Y_Hanafuda_Dark", (0.075, 0.045, 0.035, 1.0), 0.65),
    }

    # Feet, legs and layered uniform. Proportions prioritize a tall, lean read.
    sphere("Y_Foot_L", (-0.090, -0.045, 0.060), (0.068, 0.130, 0.048), character,
           materials["sheath"], segments=24, rings=12)
    sphere("Y_Foot_R", (0.090, -0.045, 0.060), (0.068, 0.130, 0.048), character,
           materials["sheath"], segments=24, rings=12)
    tapered_between("Y_LowerLeg_L", (-0.095, 0.015, 0.12), (-0.090, 0.005, 0.55),
                    0.066, 0.078, character, materials["uniform"])
    tapered_between("Y_LowerLeg_R", (0.095, 0.015, 0.12), (0.090, 0.005, 0.55),
                    0.066, 0.078, character, materials["uniform"])
    tapered_between("Y_UpperLeg_L", (-0.090, 0.005, 0.54), (-0.080, 0.010, 0.92),
                    0.082, 0.098, character, materials["uniform"])
    tapered_between("Y_UpperLeg_R", (0.090, 0.005, 0.54), (0.080, 0.010, 0.92),
                    0.082, 0.098, character, materials["uniform"])
    cube("Y_Pelvis", (0.0, 0.015, 0.91), (0.175, 0.095, 0.125), character,
         materials["uniform"], bevel=0.045)
    prism("Y_Hakama_L", [(-0.178, 0.940), (-0.010, 0.940), (-0.035, 0.470),
                           (-0.125, 0.430), (-0.185, 0.570)],
          -0.105, 0.205, character, materials["uniform"], bevel=0.025)
    prism("Y_Hakama_R", [(0.010, 0.940), (0.178, 0.940), (0.185, 0.570),
                           (0.125, 0.430), (0.035, 0.470)],
          -0.105, 0.205, character, materials["uniform"], bevel=0.025)
    tapered_between("Y_Wrap_L", (-0.095, -0.010, 0.115), (-0.095, -0.005, 0.405),
                    0.069, 0.073, character, materials["wrap"], vertices=24, bevel=0.004)
    tapered_between("Y_Wrap_R", (0.095, -0.010, 0.115), (0.095, -0.005, 0.405),
                    0.069, 0.073, character, materials["wrap"], vertices=24, bevel=0.004)
    for side, x in (("L", -0.095), ("R", 0.095)):
        for index, z in enumerate((0.17, 0.24, 0.31, 0.38)):
            cylinder_between(f"Y_WrapBand_{side}_{index}", (x, -0.010, z - 0.006),
                             (x, -0.010, z + 0.006), 0.075, character,
                             materials["earring_cream"], vertices=24, bevel=0.002)
    prism("Y_Torso", [(-0.205, 1.27), (0.205, 1.27), (0.155, 0.93), (-0.155, 0.93)],
          -0.090, 0.190, character, materials["uniform"], bevel=0.035)
    cube("Y_Uniform_Collar_L", (-0.055, -0.105, 1.285), (0.055, 0.018, 0.028), character,
         materials["uniform_edge"], bevel=0.008,
         rotation=(0.0, math.radians(-12.0), math.radians(-20.0)))
    cube("Y_Uniform_Collar_R", (0.055, -0.105, 1.285), (0.055, 0.018, 0.028), character,
         materials["uniform_edge"], bevel=0.008,
         rotation=(0.0, math.radians(12.0), math.radians(20.0)))
    for z in (1.20, 1.10, 1.00):
        sphere(f"Y_Uniform_Button_{z:.2f}", (0.0, -0.105, z), (0.014, 0.007, 0.014),
               character, materials["metal"], segments=16, rings=8)

    # Belt reads as a clean horizontal counterpoint to the sheath diagonal.
    cube("Y_Belt", (0.0, 0.0, 0.94), (0.205, 0.112, 0.032), character,
         materials["belt"], bevel=0.008)
    cube("Y_Belt_Buckle", (0.0, -0.118, 0.94), (0.035, 0.012, 0.035), character,
         materials["gold"], bevel=0.006)

    # Relaxed arms: almost straight, with no action-pose exaggeration.
    tapered_between("Y_UpperArm_L", (-0.195, 0.010, 1.23), (-0.235, -0.005, 0.98),
                    0.070, 0.058, character, materials["uniform"])
    tapered_between("Y_Forearm_L", (-0.235, -0.005, 0.98), (-0.225, -0.055, 0.76),
                    0.058, 0.046, character, materials["uniform"])
    sphere("Y_Hand_L", (-0.225, -0.060, 0.70), (0.050, 0.040, 0.075), character,
           materials["skin"], segments=24, rings=14)
    tapered_between("Y_UpperArm_R", (0.195, 0.010, 1.23), (0.235, -0.005, 0.98),
                    0.070, 0.058, character, materials["uniform"])
    tapered_between("Y_Forearm_R", (0.235, -0.005, 0.98), (0.225, -0.055, 0.76),
                    0.058, 0.046, character, materials["uniform"])
    sphere("Y_Hand_R", (0.225, -0.060, 0.70), (0.050, 0.040, 0.075), character,
           materials["skin"], segments=24, rings=14)

    # Neck and face. Facial features stay graphic and deliberately restrained.
    cylinder_between("Y_Neck", (0.0, 0.015, 1.27), (0.0, 0.015, 1.43), 0.070,
                     character, materials["skin"], vertices=32, bevel=0.004)
    sphere("Y_Head", (0.0, -0.015, 1.565), (0.112, 0.101, 0.145), character,
           materials["skin"], segments=40, rings=24)
    prism("Y_Nose", [(-0.012, 1.585), (0.012, 1.585), (0.018, 1.525), (-0.018, 1.525)],
          -0.122, 0.025, character, materials["skin_shadow"], bevel=0.004)
    cube("Y_EyeWhite_L", (-0.045, -0.112, 1.595), (0.031, 0.006, 0.010), character,
         materials["white"], bevel=0.005,
         rotation=(0.0, 0.0, math.radians(-4.0)))
    cube("Y_EyeWhite_R", (0.045, -0.112, 1.595), (0.031, 0.006, 0.010), character,
         materials["white"], bevel=0.005,
         rotation=(0.0, 0.0, math.radians(4.0)))
    sphere("Y_Iris_L", (-0.045, -0.121, 1.594), (0.010, 0.004, 0.010), character,
           materials["eyes"], segments=16, rings=8)
    sphere("Y_Iris_R", (0.045, -0.121, 1.594), (0.010, 0.004, 0.010), character,
           materials["eyes"], segments=16, rings=8)
    cube("Y_Brow_L", (-0.046, -0.120, 1.625), (0.037, 0.004, 0.006), character,
         materials["hair"], bevel=0.003,
         rotation=(0.0, 0.0, math.radians(-7.0)))
    cube("Y_Brow_R", (0.046, -0.120, 1.625), (0.037, 0.004, 0.006), character,
         materials["hair"], bevel=0.003,
         rotation=(0.0, 0.0, math.radians(7.0)))
    curve_line("Y_Mouth", [(-0.026, -0.121, 1.505), (0.0, -0.124, 1.505),
                            (0.026, -0.121, 1.505)], 0.0035, character,
               materials["skin_shadow"])

    # Flame-like birthmark, large enough to read before facial polish.
    curve_line("Y_Mark_Main", [(-0.062, -0.119, 1.685), (-0.078, -0.123, 1.655),
                                (-0.068, -0.124, 1.620), (-0.083, -0.117, 1.594)],
               0.008, character, materials["mark"])
    curve_line("Y_Mark_Flame_A", [(-0.066, -0.120, 1.665), (-0.040, -0.124, 1.649),
                                   (-0.050, -0.124, 1.628)], 0.006, character,
               materials["mark"])
    curve_line("Y_Mark_Flame_B", [(-0.075, -0.118, 1.646), (-0.094, -0.112, 1.626),
                                   (-0.090, -0.112, 1.605)], 0.0055, character,
               materials["mark"])

    # Hair: a few deliberate masses, not strand noise.
    sphere("Y_Hair_Cap", (0.0, 0.003, 1.650), (0.126, 0.113, 0.143), character,
           materials["hair"], segments=32, rings=20)
    prism("Y_Fringe_Center", [(-0.035, 1.745), (0.035, 1.745), (0.020, 1.620),
                               (-0.010, 1.574), (-0.045, 1.642)],
          -0.128, 0.028, character, materials["hair"], bevel=0.006)
    prism("Y_Fringe_Left", [(-0.102, 1.716), (-0.030, 1.748), (-0.050, 1.615),
                             (-0.112, 1.555), (-0.118, 1.642)],
          -0.120, 0.030, character, materials["hair_red"], bevel=0.006)
    prism("Y_Fringe_Right", [(0.030, 1.748), (0.105, 1.714), (0.116, 1.625),
                              (0.086, 1.548), (0.047, 1.626)],
          -0.120, 0.030, character, materials["hair"], bevel=0.006)
    sphere("Y_Hair_BackMass", (0.0, 0.070, 1.445), (0.145, 0.105, 0.300), character,
           materials["hair"], segments=32, rings=20)
    cube("Y_Hair_Tie", (0.0, 0.103, 1.360), (0.105, 0.085, 0.034), character,
         materials["hair_red"], bevel=0.025)
    prism("Y_Hair_Tail_L", [(-0.120, 1.390), (-0.020, 1.395), (-0.032, 1.010),
                             (-0.092, 0.915), (-0.145, 1.090)],
          0.030, 0.115, character, materials["hair"], bevel=0.010)
    prism("Y_Hair_Tail_R", [(0.020, 1.395), (0.120, 1.390), (0.145, 1.090),
                             (0.092, 0.915), (0.032, 1.010)],
          0.030, 0.115, character, materials["hair_red"], bevel=0.010)
    prism("Y_Hair_Tail_Outer_L", [(-0.110, 1.385), (-0.052, 1.365), (-0.095, 1.105),
                                   (-0.185, 0.955), (-0.162, 1.235)],
          0.075, 0.070, character, materials["hair"], bevel=0.008)
    prism("Y_Hair_Tail_Outer_R", [(0.052, 1.365), (0.110, 1.385), (0.162, 1.235),
                                   (0.185, 0.955), (0.095, 1.105)],
          0.075, 0.070, character, materials["hair_red"], bevel=0.008)
    prism("Y_SideLock_L", [(-0.125, 1.670), (-0.095, 1.650), (-0.102, 1.350),
                            (-0.143, 1.275), (-0.158, 1.510)],
          -0.020, 0.050, character, materials["hair"], bevel=0.007)
    prism("Y_SideLock_R", [(0.095, 1.650), (0.125, 1.670), (0.158, 1.510),
                            (0.143, 1.275), (0.102, 1.350)],
          -0.020, 0.050, character, materials["hair"], bevel=0.007)

    add_hanafuda("Y_Hanafuda_L", -0.138, character, materials)
    add_hanafuda("Y_Hanafuda_R", 0.138, character, materials)

    # Haori construction: thick back mass, separate front panels and sleeves.
    prism("Y_Haori_Back", [(-0.215, 1.285), (0.215, 1.285), (0.255, 0.600),
                            (0.050, 0.550), (0.0, 0.625), (-0.050, 0.550),
                            (-0.255, 0.600)],
          0.075, 0.055, character, materials["haori"], bevel=0.015)
    prism("Y_Haori_Front_L", [(-0.205, 1.270), (-0.018, 1.285), (-0.050, 0.610),
                               (-0.225, 0.565), (-0.250, 0.870)],
          -0.120, 0.052, character, materials["haori_light"], bevel=0.013)
    prism("Y_Haori_Front_R", [(0.018, 1.285), (0.205, 1.270), (0.250, 0.870),
                               (0.225, 0.565), (0.050, 0.610)],
          -0.120, 0.052, character, materials["haori"], bevel=0.013)
    tapered_between("Y_Haori_Sleeve_L", (-0.205, 0.010, 1.235),
                    (-0.255, -0.005, 0.885), 0.095, 0.112,
                    character, materials["haori_light"], vertices=20, bevel=0.010)
    tapered_between("Y_Haori_Sleeve_R", (0.205, 0.010, 1.235),
                    (0.255, -0.005, 0.885), 0.095, 0.112,
                    character, materials["haori"], vertices=20, bevel=0.010)
    cube("Y_Haori_Shoulder_L", (-0.190, 0.010, 1.245), (0.082, 0.105, 0.062),
         character, materials["haori_light"], bevel=0.045,
         rotation=(0.0, math.radians(-6.0), math.radians(-8.0)))
    cube("Y_Haori_Shoulder_R", (0.190, 0.010, 1.245), (0.082, 0.105, 0.062),
         character, materials["haori"], bevel=0.045,
         rotation=(0.0, math.radians(6.0), math.radians(8.0)))
    cube("Y_Haori_Lapel_L", (-0.092, -0.150, 1.160), (0.042, 0.018, 0.175),
         character, materials["lining"], bevel=0.010,
         rotation=(0.0, math.radians(-4.0), math.radians(-15.0)))
    cube("Y_Haori_Lapel_R", (0.092, -0.150, 1.160), (0.042, 0.018, 0.175),
         character, materials["lining"], bevel=0.010,
         rotation=(0.0, math.radians(4.0), math.radians(15.0)))

    # Sheathed Nichirin sword: unmistakable secondary diagonal at the left hip.
    sheath_start = (-0.185, 0.025, 0.970)
    sheath_end = (-0.455, 0.090, 0.245)
    cylinder_between("Y_Sheath", sheath_start, sheath_end, 0.027, character,
                     materials["sheath"], vertices=24, bevel=0.004)
    cylinder_between("Y_Sheath_Rim", (-0.180, 0.024, 0.985), (-0.198, 0.030, 0.935),
                     0.034, character, materials["gold"], vertices=24, bevel=0.003)
    cylinder_between("Y_Sheath_End", (-0.448, 0.088, 0.264), (-0.462, 0.093, 0.225),
                     0.031, character, materials["gold"], vertices=24, bevel=0.003)
    cylinder_between("Y_Sword_Handle", (-0.170, 0.020, 1.000),
                     (-0.105, -0.010, 1.205), 0.026, character,
                     materials["belt"], vertices=20, bevel=0.004)
    cylinder_between("Y_Sword_Pommel", (-0.102, -0.012, 1.213),
                     (-0.088, -0.017, 1.252), 0.030, character,
                     materials["gold"], vertices=20, bevel=0.003)
    cylinder_between("Y_Sword_Guard", (-0.162, 0.018, 0.990),
                     (-0.176, 0.023, 0.948), 0.050, character,
                     materials["gold"], vertices=16, bevel=0.003)

    # Ground contact remains exactly Z=0 via a tiny sole layer.
    cube("Y_Sole_L", (-0.090, -0.045, 0.012), (0.068, 0.128, 0.012), character,
         materials["belt"], bevel=0.008)
    cube("Y_Sole_R", (0.090, -0.045, 0.012), (0.068, 0.128, 0.012), character,
         materials["belt"], bevel=0.008)

    return character, materials


def character_bounds(collection: bpy.types.Collection) -> tuple[Vector, Vector]:
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    for obj in collection.all_objects:
        if obj.type not in {"MESH", "CURVE"}:
            continue
        for corner in obj.bound_box:
            world_corner = obj.matrix_world @ Vector(corner)
            mins.x = min(mins.x, world_corner.x)
            mins.y = min(mins.y, world_corner.y)
            mins.z = min(mins.z, world_corner.z)
            maxs.x = max(maxs.x, world_corner.x)
            maxs.y = max(maxs.y, world_corner.y)
            maxs.z = max(maxs.z, world_corner.z)
    return mins, maxs


def add_review_stage(materials: dict[str, bpy.types.Material]) -> bpy.types.Collection:
    stage = bpy.data.collections.new("Review_Stage")
    bpy.context.scene.collection.children.link(stage)
    floor_mat = make_material("Review_Floor", (0.14, 0.16, 0.18, 1.0), 0.88)
    cube("Review_Floor", (0.0, 0.0, -0.035), (2.1, 2.1, 0.035), stage,
         floor_mat, bevel=0.0)

    # A restrained 1.70 m capsule proxy appears only in the scale shot.
    proxy_mat = make_material("Player_Capsule_Reference", (0.24, 0.40, 0.48, 1.0), 0.65)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12,
                                       location=(0.65, 0.0, 0.85))
    proxy = bpy.context.object
    proxy.name = "Player_Capsule_1_70m"
    proxy.scale = (0.45, 0.45, 0.85)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    finish_object(proxy, stage, proxy_mat)
    proxy.hide_render = True

    # 1 m ruler for the scale-contract image.
    ruler = cube("Scale_Ruler_1m", (-0.62, 0.10, 0.50), (0.012, 0.012, 0.50),
                 stage, materials["earring_cream"], bevel=0.003)
    ruler.hide_render = True
    for index in range(5):
        tick = cube(f"Scale_Tick_{index}", (-0.59, 0.095, index * 0.25),
                    (0.04 if index in (0, 4) else 0.026, 0.010, 0.006), stage,
                    materials["earring_cream"], bevel=0.002)
        tick.hide_render = True
    return stage


def setup_render() -> bpy.types.Object:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.look = "AgX - Medium High Contrast"

    world = bpy.data.worlds.new("Neutral_World")
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    if background is None:
        world.node_tree.nodes.clear()
        background = world.node_tree.nodes.new("ShaderNodeBackground")
        background.name = "Background"
        output = world.node_tree.nodes.new("ShaderNodeOutputWorld")
        world.node_tree.links.new(background.outputs["Background"], output.inputs["Surface"])
    background.inputs["Color"].default_value = (0.055, 0.065, 0.080, 1.0)
    background.inputs["Strength"].default_value = 0.50
    scene.world = world

    key_data = bpy.data.lights.new("Key_Light", "AREA")
    key_data.energy = 950
    key_data.shape = "DISK"
    key_data.size = 3.0
    key = bpy.data.objects.new("Key_Light", key_data)
    scene.collection.objects.link(key)
    key.location = (-2.6, -3.8, 4.2)
    key.rotation_euler = (math.radians(28), 0.0, math.radians(-34))

    fill_data = bpy.data.lights.new("Fill_Light", "AREA")
    fill_data.energy = 520
    fill_data.size = 2.4
    fill = bpy.data.objects.new("Fill_Light", fill_data)
    scene.collection.objects.link(fill)
    fill.location = (3.2, -1.8, 2.5)
    fill.rotation_euler = (math.radians(58), 0.0, math.radians(55))

    rim_data = bpy.data.lights.new("Rim_Light", "AREA")
    rim_data.energy = 780
    rim_data.size = 2.0
    rim = bpy.data.objects.new("Rim_Light", rim_data)
    scene.collection.objects.link(rim)
    rim.location = (0.5, 3.2, 3.0)
    rim.rotation_euler = (math.radians(-42), 0.0, math.radians(168))

    camera_data = bpy.data.cameras.new("Review_Camera")
    camera_data.lens = 58
    camera = bpy.data.objects.new("Review_Camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    return camera


def aim_camera(camera: bpy.types.Object, location: tuple[float, float, float],
               target: tuple[float, float, float] = (0.0, 0.0, 0.90)) -> None:
    camera.location = location
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


def render_view(camera: bpy.types.Object, filename: str,
                location: tuple[float, float, float], stage: bpy.types.Collection,
                show_scale: bool = False) -> None:
    for obj in stage.all_objects:
        if obj.name.startswith("Player_Capsule") or obj.name.startswith("Scale_"):
            obj.hide_render = not show_scale
    aim_camera(camera, location)
    bpy.context.scene.render.filepath = str(SHOT_DIR / filename)
    bpy.ops.render.render(write_still=True)


def render_silhouette(camera: bpy.types.Object, character: bpy.types.Collection,
                      stage: bpy.types.Collection) -> None:
    scene = bpy.context.scene
    silhouette = make_material("Silhouette_Black", (0.005, 0.005, 0.006, 1.0), 1.0)
    originals: dict[str, list[bpy.types.Material]] = {}
    for obj in character.all_objects:
        if obj.type not in {"MESH", "CURVE"} or not hasattr(obj.data, "materials"):
            continue
        originals[obj.name] = list(obj.data.materials)
        obj.data.materials.clear()
        obj.data.materials.append(silhouette)
    old_world = scene.world.node_tree.nodes["Background"].inputs["Color"].default_value[:]
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.82, 0.82, 0.78, 1.0)
    for obj in stage.all_objects:
        obj.hide_render = obj.name != "Review_Floor"
    aim_camera(camera, (2.75, -3.35, 1.25))
    scene.render.filepath = str(SHOT_DIR / "silhouette.png")
    bpy.ops.render.render(write_still=True)
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = old_world
    for obj in character.all_objects:
        if obj.name not in originals:
            continue
        obj.data.materials.clear()
        for material in originals[obj.name]:
            obj.data.materials.append(material)


def export_glb(character: bpy.types.Collection) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in character.all_objects:
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = next(obj for obj in character.all_objects if obj.type == "MESH")
    bpy.ops.export_scene.gltf(filepath=str(GLB_PATH), export_format="GLB",
                              use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT")


def write_measurements(character: bpy.types.Collection) -> dict[str, object]:
    minimum, maximum = character_bounds(character)
    mesh_objects = [obj for obj in character.all_objects if obj.type == "MESH"]
    curve_objects = [obj for obj in character.all_objects if obj.type == "CURVE"]
    triangle_count = 0
    for obj in mesh_objects:
        depsgraph = bpy.context.evaluated_depsgraph_get()
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        triangle_count += len(mesh.loop_triangles)
        evaluated.to_mesh_clear()
    data = {
        "asset": "Yoriichi Base Prototype",
        "status": "ART_REVIEW",
        "visual_height_m": round(maximum.z - minimum.z, 3),
        "target_height_m": CHARACTER_HEIGHT_M,
        "player_capsule_reference_m": PLAYER_CAPSULE_HEIGHT_M,
        "bounds_min_m": [round(value, 4) for value in minimum],
        "bounds_max_m": [round(value, 4) for value in maximum],
        "mesh_objects": len(mesh_objects),
        "curve_objects": len(curve_objects),
        "evaluated_triangles": triangle_count,
        "blender_scale": "1 unit = 1 metre",
        "blender_forward": FORWARD_BLENDER,
        "blender_up": UP_BLENDER,
        "godot_forward": "-Z",
        "godot_up": "+Y",
        "origin": "between soles at ground level",
    }
    MEASURE_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return data


def main() -> None:
    bpy.context.preferences.filepaths.save_version = 0
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    SHOT_DIR.mkdir(parents=True, exist_ok=True)
    reset_scene()
    character, materials = build_character()
    stage = add_review_stage(materials)
    camera = setup_render()

    render_view(camera, "front.png", (0.0, -4.25, 1.04), stage)
    render_view(camera, "three_quarter.png", (2.75, -3.35, 1.18), stage)
    render_view(camera, "side.png", (4.20, 0.0, 1.04), stage)
    render_view(camera, "back.png", (0.0, 4.25, 1.04), stage)
    render_view(camera, "game_scale.png", (0.0, -4.65, 1.04), stage, show_scale=True)
    render_silhouette(camera, character, stage)

    export_glb(character)
    data = write_measurements(character)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), compress=True)
    print(json.dumps(data, ensure_ascii=False))


if __name__ == "__main__":
    main()
