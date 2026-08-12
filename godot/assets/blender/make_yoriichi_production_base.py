"""YORIICHI_Y02_REBUILD — body and identity silhouette production candidate.

The previous yoriichi_base_prototype is intentionally not imported or edited.
It remains TECH_DUMMY / ART_REJECTED. This generator builds a new large-form
candidate and stops before detail, rigging, animation, UV polish, or gameplay.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


GODOT_ROOT = Path(__file__).resolve().parents[2]
WORKTREE_ROOT = GODOT_ROOT.parent
SOURCE_DIR = GODOT_ROOT / "assets" / "blender" / "sources"
MODEL_DIR = GODOT_ROOT / "assets" / "models"
REVIEW_DIR = WORKTREE_ROOT / "shots2" / "yoriichi_character_rebuild"
BLEND_PATH = SOURCE_DIR / "yoriichi_production_base.blend"
GLB_PATH = MODEL_DIR / "yoriichi_production_base.glb"
MEASURE_PATH = REVIEW_DIR / "measurements.json"

HEIGHT = 1.78
LANDMARKS = {
    "TOP_HEAD": 1.78,
    "CHIN": 1.546,
    "SHOULDER": 1.42,
    "CHEST": 1.28,
    "ELBOW": 1.08,
    "WRIST": 0.80,
    "WAIST": 1.08,
    "CROTCH": 0.93,
    "KNEE": 0.50,
    "ANKLE": 0.10,
    "GROUND": 0.00,
}


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials,
                       bpy.data.cameras, bpy.data.lights, bpy.data.worlds):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def material(name: str, color: tuple[float, float, float, float],
             roughness: float = 0.72, metallic: float = 0.0) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    if bsdf is None:
        nodes.clear()
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
        output = nodes.new("ShaderNodeOutputMaterial")
        mat.node_tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def link_object(obj: bpy.types.Object, collection: bpy.types.Collection,
                mat: bpy.types.Material | None = None,
                smooth: bool = True) -> bpy.types.Object:
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)
    if mat is not None and hasattr(obj.data, "materials"):
        obj.data.materials.append(mat)
    if smooth and obj.type == "MESH":
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    return obj


def mesh_object(name: str, vertices: list[tuple[float, float, float]],
                faces: list[tuple[int, ...]], collection: bpy.types.Collection,
                mat: bpy.types.Material, bevel: float = 0.0) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    link_object(obj, collection, mat)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Edge softness", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
    return obj


def ellipsoid(name: str, center: tuple[float, float, float],
              scale: tuple[float, float, float], collection: bpy.types.Collection,
              mat: bpy.types.Material, segments: int = 40, rings: int = 24) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return link_object(obj, collection, mat)


def loft_z(name: str,
           sections: list[tuple[float, float, float, float, float]],
           collection: bpy.types.Collection, mat: bpy.types.Material,
           segments: int = 32) -> bpy.types.Object:
    """Closed smooth volume from (z, cx, cy, radius_x, radius_y) sections."""
    verts: list[tuple[float, float, float]] = []
    for z, cx, cy, rx, ry in sections:
        for index in range(segments):
            angle = math.tau * index / segments
            verts.append((cx + math.cos(angle) * rx,
                          cy + math.sin(angle) * ry, z))
    faces: list[tuple[int, ...]] = []
    for ring in range(len(sections) - 1):
        start = ring * segments
        nxt = (ring + 1) * segments
        for index in range(segments):
            j = (index + 1) % segments
            faces.append((start + index, start + j, nxt + j, nxt + index))
    faces.append(tuple(reversed(range(segments))))
    last = (len(sections) - 1) * segments
    faces.append(tuple(last + index for index in range(segments)))
    return mesh_object(name, verts, faces, collection, mat)


def tube_path(name: str, points: list[tuple[float, float, float]],
              radii: list[tuple[float, float]], collection: bpy.types.Collection,
              mat: bpy.types.Material, segments: int = 20) -> bpy.types.Object:
    """Tapered curved tube with stable local frames; supports hair and limbs."""
    vectors = [Vector(point) for point in points]
    verts: list[tuple[float, float, float]] = []
    previous_n1: Vector | None = None
    for index, point in enumerate(vectors):
        if index == 0:
            tangent = (vectors[1] - point).normalized()
        elif index == len(vectors) - 1:
            tangent = (point - vectors[index - 1]).normalized()
        else:
            tangent = (vectors[index + 1] - vectors[index - 1]).normalized()
        reference = Vector((0.0, 0.0, 1.0))
        if abs(tangent.dot(reference)) > 0.88:
            reference = Vector((0.0, 1.0, 0.0))
        n1 = tangent.cross(reference).normalized()
        if previous_n1 is not None and n1.dot(previous_n1) < 0.0:
            n1.negate()
        n2 = tangent.cross(n1).normalized()
        previous_n1 = n1.copy()
        rx, ry = radii[index]
        for segment in range(segments):
            angle = math.tau * segment / segments
            vertex = point + n1 * (math.cos(angle) * rx) + n2 * (math.sin(angle) * ry)
            verts.append(tuple(vertex))
    faces: list[tuple[int, ...]] = []
    for ring in range(len(points) - 1):
        start = ring * segments
        nxt = (ring + 1) * segments
        for segment in range(segments):
            j = (segment + 1) % segments
            faces.append((start + segment, start + j, nxt + j, nxt + segment))
    faces.append(tuple(reversed(range(segments))))
    last = (len(points) - 1) * segments
    faces.append(tuple(last + segment for segment in range(segments)))
    return mesh_object(name, verts, faces, collection, mat)


def curved_panel(name: str, levels: list[tuple[float, float, float]],
                 y_center: float, curve_depth: float, thickness: float,
                 collection: bpy.types.Collection, mat: bpy.types.Material,
                 side: str = "both") -> bpy.types.Object:
    """Weighted clothing panel; levels contain (z, inner_x, outer_x)."""
    samples = 7
    front: list[tuple[float, float, float]] = []
    for z, inner_x, outer_x in levels:
        for index in range(samples):
            t = index / (samples - 1)
            x = inner_x + (outer_x - inner_x) * t
            span = abs(outer_x - inner_x)
            normalized = 0.0 if span == 0.0 else (x - (inner_x + outer_x) * 0.5) / span
            y = y_center + curve_depth * (normalized * normalized * 2.0)
            front.append((x, y, z))
    back = [(x, y + thickness, z) for x, y, z in front]
    verts = front + back
    rows = len(levels)
    faces: list[tuple[int, ...]] = []
    layer = rows * samples
    for row in range(rows - 1):
        for col in range(samples - 1):
            a = row * samples + col
            b = a + 1
            c = (row + 1) * samples + col + 1
            d = (row + 1) * samples + col
            faces.append((a, b, c, d))
            faces.append((layer + d, layer + c, layer + b, layer + a))
    # Close all four borders.
    for row in range(rows - 1):
        a, b = row * samples, (row + 1) * samples
        faces.append((a, b, layer + b, layer + a))
        a, b = row * samples + samples - 1, (row + 1) * samples + samples - 1
        faces.append((a, layer + a, layer + b, b))
    for col in range(samples - 1):
        a, b = col, col + 1
        faces.append((a, layer + a, layer + b, b))
        a = (rows - 1) * samples + col
        b = a + 1
        faces.append((a, b, layer + b, layer + a))
    return mesh_object(name, verts, faces, collection, mat, bevel=0.008)


def foot_volume(name: str, x: float, collection: bpy.types.Collection,
                mat: bpy.types.Material) -> bpy.types.Object:
    sections = [
        (-0.19, 0.042, 0.030),
        (-0.14, 0.060, 0.042),
        (-0.05, 0.066, 0.048),
        (0.045, 0.058, 0.044),
        (0.105, 0.048, 0.036),
    ]
    segments = 18
    verts: list[tuple[float, float, float]] = []
    for y, rx, rz in sections:
        for index in range(segments):
            angle = math.tau * index / segments
            verts.append((x + math.cos(angle) * rx, y,
                          0.052 + math.sin(angle) * rz))
    faces: list[tuple[int, ...]] = []
    for ring in range(len(sections) - 1):
        start, nxt = ring * segments, (ring + 1) * segments
        for index in range(segments):
            j = (index + 1) % segments
            faces.append((start + index, start + j, nxt + j, nxt + index))
    faces.append(tuple(reversed(range(segments))))
    last = (len(sections) - 1) * segments
    faces.append(tuple(last + i for i in range(segments)))
    return mesh_object(name, verts, faces, collection, mat)


def build_body(materials: dict[str, bpy.types.Material]) -> bpy.types.Collection:
    body = bpy.data.collections.new("Yoriichi_Production_Body")
    bpy.context.scene.collection.children.link(body)

    foot_volume("PB_Foot_L", -0.090, body, materials["base"])
    foot_volume("PB_Foot_R", 0.090, body, materials["base"])

    tube_path("PB_Leg_L", [(-0.09, 0.015, 0.09), (-0.09, 0.010, 0.50),
                            (-0.105, 0.018, 0.72), (-0.095, 0.020, 0.93)],
              [(0.060, 0.052), (0.072, 0.065), (0.086, 0.078), (0.095, 0.085)],
              body, materials["base"], segments=24)
    tube_path("PB_Leg_R", [(0.09, 0.015, 0.09), (0.09, 0.010, 0.50),
                            (0.105, 0.018, 0.72), (0.095, 0.020, 0.93)],
              [(0.060, 0.052), (0.072, 0.065), (0.086, 0.078), (0.095, 0.085)],
              body, materials["base"], segments=24)

    loft_z("PB_Pelvis", [
        (0.88, 0.0, 0.025, 0.130, 0.085),
        (0.94, 0.0, 0.020, 0.165, 0.100),
        (1.02, 0.0, 0.015, 0.150, 0.092),
        (1.08, 0.0, 0.010, 0.135, 0.082),
    ], body, materials["base"])
    loft_z("PB_Torso", [
        (1.05, 0.0, 0.005, 0.132, 0.082),
        (1.13, 0.0, 0.000, 0.145, 0.088),
        (1.28, 0.0, 0.000, 0.175, 0.100),
        (1.38, 0.0, 0.005, 0.182, 0.102),
        (1.43, 0.0, 0.010, 0.155, 0.088),
    ], body, materials["base"])

    ellipsoid("PB_Shoulder_L", (-0.170, 0.008, 1.375), (0.062, 0.062, 0.070),
              body, materials["base"], 28, 16)
    ellipsoid("PB_Shoulder_R", (0.170, 0.008, 1.375), (0.062, 0.062, 0.070),
              body, materials["base"], 28, 16)

    # Slender relaxed arms with adult hand length.
    tube_path("PB_Arm_L", [(-0.170, 0.010, 1.39), (-0.205, 0.005, 1.25),
                            (-0.215, -0.005, 1.08), (-0.210, -0.020, 0.91),
                            (-0.205, -0.035, 0.80)],
              [(0.055, 0.052), (0.055, 0.050), (0.050, 0.045),
               (0.046, 0.041), (0.042, 0.037)], body, materials["base"], 22)
    tube_path("PB_Arm_R", [(0.170, 0.010, 1.39), (0.205, 0.005, 1.25),
                            (0.215, -0.005, 1.08), (0.210, -0.020, 0.91),
                            (0.205, -0.035, 0.80)],
              [(0.055, 0.052), (0.055, 0.050), (0.050, 0.045),
               (0.046, 0.041), (0.042, 0.037)], body, materials["base"], 22)
    tube_path("PB_Hand_L", [(-0.205, -0.035, 0.80), (-0.204, -0.050, 0.72),
                             (-0.200, -0.055, 0.655)],
              [(0.043, 0.034), (0.050, 0.031), (0.028, 0.020)],
              body, materials["skin"], 20)
    tube_path("PB_Hand_R", [(0.205, -0.035, 0.80), (0.204, -0.050, 0.72),
                             (0.200, -0.055, 0.655)],
              [(0.043, 0.034), (0.050, 0.031), (0.028, 0.020)],
              body, materials["skin"], 20)

    tube_path("PB_Neck", [(0.0, 0.010, 1.40), (0.0, 0.005, 1.555)],
              [(0.058, 0.053), (0.065, 0.058)], body, materials["skin"], 28)
    loft_z("PB_Head", [
        (1.546, 0.0, -0.012, 0.040, 0.046),
        (1.575, 0.0, -0.018, 0.070, 0.070),
        (1.625, 0.0, -0.020, 0.092, 0.090),
        (1.680, 0.0, -0.012, 0.098, 0.096),
        (1.725, 0.0, -0.002, 0.087, 0.090),
        (1.750, 0.0, 0.005, 0.055, 0.064),
    ], body, materials["skin"], segments=40)
    # Modeled sockets and nose bridge, not final eyes or likeness.
    ellipsoid("PB_EyeSocket_L", (-0.042, -0.096, 1.660), (0.031, 0.004, 0.014),
              body, materials["skin_shadow"], 24, 12)
    ellipsoid("PB_EyeSocket_R", (0.042, -0.096, 1.660), (0.031, 0.004, 0.014),
              body, materials["skin_shadow"], 24, 12)
    tube_path("PB_NoseBridge", [(0.0, -0.102, 1.680), (0.0, -0.116, 1.630),
                                 (0.0, -0.118, 1.610)],
              [(0.012, 0.009), (0.014, 0.010), (0.010, 0.008)],
              body, materials["skin"], 16)
    return body


def build_identity(materials: dict[str, bpy.types.Material]) -> bpy.types.Collection:
    identity = bpy.data.collections.new("Yoriichi_Identity_Masses")
    bpy.context.scene.collection.children.link(identity)

    # Hakama: volume increases below the narrow waist, then tapers at calf.
    for side, x in (("L", -0.105), ("R", 0.105)):
        loft_z(f"PC_Hakama_{side}", [
            (0.37, x, 0.015, 0.072, 0.070),
            (0.45, x, 0.020, 0.084, 0.084),
            (0.62, x, 0.025, 0.108, 0.100),
            (0.80, x, 0.025, 0.102, 0.096),
            (0.96, x, 0.020, 0.086, 0.086),
        ], identity, materials["uniform"], segments=30)
        tube_path(f"PC_Wrap_{side}", [(x, 0.012, 0.10), (x, 0.012, 0.36)],
                  [(0.068, 0.060), (0.075, 0.067)], identity,
                  materials["wrap"], 24)

    # Haori panels use curved surfaces and weighted hems instead of boards.
    curved_panel("PC_Haori_Back", [
        (1.42, -0.205, 0.205),
        (1.32, -0.235, 0.235),
        (1.02, -0.250, 0.250),
        (0.70, -0.285, 0.285),
        (0.55, -0.310, 0.310),
    ], 0.055, 0.055, 0.080, identity, materials["haori"])
    tube_path("PC_Haori_Sleeve_L", [(-0.175, 0.010, 1.38), (-0.215, 0.015, 1.22),
                                     (-0.235, 0.000, 1.02), (-0.225, -0.020, 0.87)],
              [(0.060, 0.055), (0.075, 0.064), (0.090, 0.072), (0.080, 0.064)],
              identity, materials["haori_light"], 28)
    tube_path("PC_Haori_Sleeve_R", [(0.175, 0.010, 1.38), (0.215, 0.015, 1.22),
                                     (0.235, 0.000, 1.02), (0.225, -0.020, 0.87)],
              [(0.060, 0.055), (0.075, 0.064), (0.090, 0.072), (0.080, 0.064)],
              identity, materials["haori"], 28)

    # Controlled cap and tied rear volume.
    ellipsoid("PC_Hair_Top", (0.0, 0.018, 1.690), (0.108, 0.102, 0.090),
              identity, materials["hair"], 40, 24)
    ellipsoid("PC_Hair_Rear_Tie", (0.0, 0.105, 1.600), (0.085, 0.060, 0.075),
              identity, materials["hair"], 36, 22)
    # Front fringe and side frame: tapered, curved, overlapping masses.
    tube_path("PC_Hair_Fringe_C", [(-0.010, -0.085, 1.755), (-0.005, -0.112, 1.705),
                                    (-0.018, -0.118, 1.640)],
              [(0.036, 0.025), (0.035, 0.020), (0.006, 0.005)],
              identity, materials["hair_red"], 18)
    tube_path("PC_Hair_Fringe_L", [(-0.060, -0.070, 1.745), (-0.080, -0.105, 1.690),
                                    (-0.092, -0.108, 1.620)],
              [(0.042, 0.025), (0.035, 0.020), (0.006, 0.005)],
              identity, materials["hair"], 18)
    tube_path("PC_Hair_Fringe_R", [(0.060, -0.070, 1.745), (0.080, -0.105, 1.690),
                                    (0.092, -0.108, 1.625)],
              [(0.042, 0.025), (0.035, 0.020), (0.006, 0.005)],
              identity, materials["hair_red"], 18)
    for side, x in (("L", -0.105), ("R", 0.105)):
        sign = -1.0 if x < 0.0 else 1.0
        tube_path(f"PC_Hair_Side_{side}", [(x, 0.000, 1.700),
                                            (x + sign * 0.020, -0.010, 1.535),
                                            (x + sign * 0.012, 0.005, 1.365)],
                  [(0.042, 0.030), (0.035, 0.025), (0.007, 0.006)],
                  identity, materials["hair"], 18)

    tube_path("PC_Hair_Rear_Long_Mass",
              [(0.0, 0.115, 1.620), (0.0, 0.180, 1.410),
               (0.0, 0.220, 1.150), (0.0, 0.180, 0.820)],
              [(0.080, 0.035), (0.125, 0.045), (0.120, 0.042), (0.035, 0.015)],
              identity, materials["hair"], 24)

    cascade_specs = [
        (-0.105, 0.180, 0.88), (-0.055, 0.205, 0.80),
        (0.000, 0.220, 0.76), (0.058, 0.205, 0.82), (0.110, 0.180, 0.90),
    ]
    for index, (x, y, end_z) in enumerate(cascade_specs):
        start_x = x * 0.40
        sway = -0.030 if index % 2 == 0 else 0.035
        tube_path(f"PC_Hair_Cascade_{index:02d}",
                  [(start_x, 0.115, 1.620),
                   (x * 0.70 + sway, y, 1.400),
                   (x - sway, y + 0.025, 1.150),
                   (x + sway * 0.4, y - 0.025, end_z)],
                  [(0.042, 0.022), (0.052, 0.024), (0.044, 0.020), (0.006, 0.004)],
                  identity, materials["hair_red" if index in (1, 4, 6) else "hair"], 18)

    # Adult katana scale and readable left-side diagonal; fittings stay locked.
    tube_path("PC_Sheath", [(-0.185, 0.030, 1.00), (-0.265, 0.055, 0.78),
                             (-0.365, 0.085, 0.50), (-0.465, 0.105, 0.22)],
              [(0.027, 0.027), (0.027, 0.027), (0.025, 0.025), (0.020, 0.020)],
              identity, materials["sheath"], 24)
    tube_path("PC_Handle", [(-0.175, 0.025, 1.00), (-0.130, -0.005, 1.18)],
              [(0.031, 0.031), (0.026, 0.026)], identity, materials["handle"], 22)
    return identity


def build_stage(materials: dict[str, bpy.types.Material]) -> tuple[bpy.types.Collection, list[bpy.types.Object]]:
    stage = bpy.data.collections.new("Review_Stage")
    bpy.context.scene.collection.children.link(stage)
    bpy.ops.mesh.primitive_plane_add(size=5.0, location=(0.0, 0.0, -0.002))
    floor = bpy.context.object
    floor.name = "Review_Floor"
    link_object(floor, stage, materials["floor"], smooth=False)
    guides: list[bpy.types.Object] = []
    for index, (name, z) in enumerate(LANDMARKS.items()):
        if name in {"CHEST", "ELBOW", "WRIST"}:
            continue
        bpy.ops.mesh.primitive_cube_add(location=(0.0, 0.30, z))
        guide = bpy.context.object
        guide.name = f"Guide_{name}"
        guide.scale = (0.62, 0.004, 0.0025 if name not in {"TOP_HEAD", "GROUND"} else 0.005)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        link_object(guide, stage, materials["guide"], smooth=False)
        guide.hide_render = True
        guides.append(guide)
    return stage, guides


def setup_render() -> bpy.types.Object:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.look = "AgX - Medium High Contrast"
    world = bpy.data.worlds.new("Neutral_World")
    world.use_nodes = True
    nodes = world.node_tree.nodes
    background = nodes.get("Background")
    if background is None:
        nodes.clear()
        background = nodes.new("ShaderNodeBackground")
        background.name = "Background"
        output = nodes.new("ShaderNodeOutputWorld")
        world.node_tree.links.new(background.outputs["Background"], output.inputs["Surface"])
    background.inputs["Color"].default_value = (0.055, 0.065, 0.078, 1.0)
    background.inputs["Strength"].default_value = 0.55
    scene.world = world

    for name, light_type, location, energy, size in (
        ("Key", "AREA", (-2.8, -3.8, 4.0), 900, 3.0),
        ("Fill", "AREA", (3.0, -2.2, 2.6), 480, 2.8),
        ("Rim", "AREA", (0.5, 3.2, 3.1), 720, 2.3),
    ):
        data = bpy.data.lights.new(name, light_type)
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        obj = bpy.data.objects.new(name, data)
        scene.collection.objects.link(obj)
        obj.location = location
        obj.rotation_euler = (Vector((0.0, 0.0, 1.0)) - obj.location).to_track_quat("-Z", "Y").to_euler()

    camera_data = bpy.data.cameras.new("Review_Camera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 2.02
    camera = bpy.data.objects.new("Review_Camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    return camera


def aim(camera: bpy.types.Object, location: tuple[float, float, float],
        target: tuple[float, float, float] = (0.0, 0.0, 0.89)) -> None:
    camera.location = location
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


def set_collection_visible(collection: bpy.types.Collection, visible: bool) -> None:
    for obj in collection.all_objects:
        obj.hide_render = not visible


def render(camera: bpy.types.Object, filename: str,
           location: tuple[float, float, float]) -> None:
    aim(camera, location)
    bpy.context.scene.render.filepath = str(REVIEW_DIR / filename)
    bpy.ops.render.render(write_still=True)


def override_silhouette(collections: list[bpy.types.Collection],
                        silhouette: bpy.types.Material) -> dict[str, list[bpy.types.Material]]:
    originals: dict[str, list[bpy.types.Material]] = {}
    for collection in collections:
        for obj in collection.all_objects:
            if obj.type != "MESH":
                continue
            originals[obj.name] = list(obj.data.materials)
            obj.data.materials.clear()
            obj.data.materials.append(silhouette)
    return originals


def restore_materials(collections: list[bpy.types.Collection],
                      originals: dict[str, list[bpy.types.Material]]) -> None:
    for collection in collections:
        for obj in collection.all_objects:
            if obj.name not in originals or obj.type != "MESH":
                continue
            obj.data.materials.clear()
            for mat in originals[obj.name]:
                obj.data.materials.append(mat)


def render_gates(camera: bpy.types.Object, body: bpy.types.Collection,
                 identity: bpy.types.Collection, guides: list[bpy.types.Object],
                 materials: dict[str, bpy.types.Material]) -> None:
    set_collection_visible(body, True)
    set_collection_visible(identity, False)
    for guide in guides:
        guide.hide_render = False
    render(camera, "body_front.png", (0.0, -4.0, 0.89))
    render(camera, "body_side.png", (4.0, 0.0, 0.89))
    for guide in guides:
        guide.hide_render = True
    render(camera, "body_three_quarter.png", (2.8, -2.8, 0.98))
    originals = override_silhouette([body], materials["silhouette"])
    render(camera, "body_silhouette_front.png", (0.0, -4.0, 0.89))
    render(camera, "body_silhouette_side.png", (4.0, 0.0, 0.89))
    restore_materials([body], originals)

    set_collection_visible(identity, True)
    render(camera, "front.png", (0.0, -4.0, 0.89))
    render(camera, "side.png", (4.0, 0.0, 0.89))
    render(camera, "three_quarter.png", (2.8, -2.8, 0.98))
    originals = override_silhouette([body, identity], materials["silhouette"])
    render(camera, "silhouette_front.png", (0.0, -4.0, 0.89))
    render(camera, "silhouette_side.png", (4.0, 0.0, 0.89))
    restore_materials([body, identity], originals)


def export_glb(body: bpy.types.Collection, identity: bpy.types.Collection) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    export_objects = [obj for collection in (body, identity) for obj in collection.all_objects]
    for obj in export_objects:
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = next(obj for obj in export_objects if obj.type == "MESH")
    bpy.ops.export_scene.gltf(filepath=str(GLB_PATH), export_format="GLB",
                              use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT")


def bounds(collections: list[bpy.types.Collection]) -> tuple[Vector, Vector]:
    minimum = Vector((1e9, 1e9, 1e9))
    maximum = Vector((-1e9, -1e9, -1e9))
    for collection in collections:
        for obj in collection.all_objects:
            if obj.type != "MESH":
                continue
            for corner in obj.bound_box:
                point = obj.matrix_world @ Vector(corner)
                for axis in range(3):
                    minimum[axis] = min(minimum[axis], point[axis])
                    maximum[axis] = max(maximum[axis], point[axis])
    return minimum, maximum


def write_measurements(body: bpy.types.Collection, identity: bpy.types.Collection) -> dict[str, object]:
    minimum, maximum = bounds([body, identity])
    mesh_objects = [obj for collection in (body, identity)
                    for obj in collection.all_objects if obj.type == "MESH"]
    triangles = 0
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in mesh_objects:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        triangles += len(mesh.loop_triangles)
        evaluated.to_mesh_clear()
    head_height = LANDMARKS["TOP_HEAD"] - LANDMARKS["CHIN"]
    data = {
        "asset": "Yoriichi Production Base Candidate",
        "technical_status": "TECH_PASS",
        "art_status": "ART_REVIEW",
        "previous_y02": "TECH_DUMMY / ART_REJECTED",
        "target_height_m": HEIGHT,
        "evaluated_bounds_height_m": round(maximum.z - minimum.z, 3),
        "head_ratio": round(HEIGHT / head_height, 2),
        "shoulder_width_m": 0.42,
        "shoulder_width_height_ratio": round(0.42 / HEIGHT, 3),
        "hip_height_m": LANDMARKS["CROTCH"],
        "hip_height_ratio": round(LANDMARKS["CROTCH"] / HEIGHT, 3),
        "knee_height_m": LANDMARKS["KNEE"],
        "knee_height_ratio": round(LANDMARKS["KNEE"] / HEIGHT, 3),
        "landmarks_m": LANDMARKS,
        "mesh_objects": len(mesh_objects),
        "evaluated_triangles": triangles,
        "blender_scale": "1 unit = 1 metre",
        "blender_axes": "+Z up, -Y forward",
        "godot_axes": "+Y up, -Z forward",
        "origin": "between soles at ground level",
        "BODY_PROPORTION_GATE": "ART_REVIEW",
        "IDENTITY_SILHOUETTE_GATE": "ART_REVIEW",
        "detail_lock": True,
        "comparison": {
            "biggest_improvements": [
                "7.61-head adult proportion with explicit landmarks",
                "longer legs, narrower shoulders, smaller adult head and feet",
                "curved hair cascade and readable left-side sheath diagonal",
                "separate unclothed body gate prevents clothing from hiding proportion errors",
            ],
            "remaining_large_form_problems": [
                "torso and shoulder transitions remain generic",
                "haori rear side profile remains provisional",
                "hair cascade needs stronger overlapping mass hierarchy",
                "hakama-to-wrap transition is still abrupt",
                "hands and feet are proportion bases, not production topology",
            ],
        },
        "next_action": "User review of both gates; correct large forms only if rejected",
    }
    MEASURE_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return data


def main() -> None:
    bpy.context.preferences.filepaths.save_version = 0
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    REVIEW_DIR.mkdir(parents=True, exist_ok=True)
    reset_scene()
    materials = {
        "base": material("PB_Base_Suit", (0.055, 0.065, 0.075, 1.0), 0.78),
        "skin": material("PB_Skin_Clay", (0.42, 0.22, 0.15, 1.0), 0.74),
        "skin_shadow": material("PB_Socket_Shadow", (0.18, 0.070, 0.050, 1.0), 0.80),
        "uniform": material("PB_Uniform", (0.022, 0.026, 0.030, 1.0), 0.80),
        "haori": material("PB_Haori_Deep", (0.045, 0.003, 0.005, 1.0), 0.82),
        "haori_light": material("PB_Haori_Light", (0.080, 0.006, 0.009, 1.0), 0.80),
        "hair": material("PB_Hair_BlackRed", (0.010, 0.001, 0.002, 1.0), 0.70),
        "hair_red": material("PB_Hair_RedEdge", (0.035, 0.002, 0.004, 1.0), 0.70),
        "wrap": material("PB_Wrap", (0.38, 0.32, 0.24, 1.0), 0.86),
        "sheath": material("PB_Sheath", (0.008, 0.001, 0.002, 1.0), 0.55),
        "handle": material("PB_Handle", (0.055, 0.012, 0.014, 1.0), 0.65),
        "floor": material("PB_Review_Floor", (0.15, 0.17, 0.19, 1.0), 0.90),
        "guide": material("PB_Landmark_Guide", (0.22, 0.40, 0.55, 1.0), 0.70),
        "silhouette": material("PB_Silhouette", (0.003, 0.003, 0.004, 1.0), 1.0),
    }
    body = build_body(materials)
    identity = build_identity(materials)
    _, guides = build_stage(materials)
    camera = setup_render()
    render_gates(camera, body, identity, guides, materials)
    export_glb(body, identity)
    data = write_measurements(body, identity)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), compress=True)
    print(json.dumps(data, ensure_ascii=False))


if __name__ == "__main__":
    main()
