"""Generate the approved Human Village Phase 2A building-family library.

Usage:
  D:\\Blender\\blender.exe -b -P godot/assets/blender/make_building_families.py -- godot/assets/models

The generator deliberately reuses the production machiya builder for the
Standard Machiya and Small Merchant families. Nagaya and Kura are new complete
systems. Every output keeps the production kit's six shared semantic materials.
"""
import bpy
import importlib.util
import json
import math
import os
import sys


ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = os.path.abspath(ARGV[0] if ARGV else "godot/assets/models")
SOURCE_DIR = os.path.abspath("godot/assets/blender/sources")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

spec = importlib.util.spec_from_file_location("machiya_kit", os.path.join(SCRIPT_DIR, "make_machiya.py"))
kit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kit)


STANDARD_RECIPES = [
    ("family_standard_machiya_01", "machiya_f_a", "right", "lean", "mushiko"),
    ("family_standard_machiya_02", "machiya_f_a", "left", "gable", "mushiko"),
    ("family_standard_machiya_03", "machiya_t_a", "center", "lean", "mushiko"),
    ("family_standard_machiya_04", "machiya_f_n", "right", "gable", "nikai"),
    ("family_standard_machiya_05", "machiya_f_n", "left", "lean", "nikai"),
    ("family_standard_machiya_06", "machiya_t_a", "right", "gable", "mushiko"),
]

NAGAYA_RECIPES = [
    ("family_nagaya_03bay", 3, "none"),
    ("family_nagaya_04bay", 4, "left"),
    ("family_nagaya_05bay", 5, "right"),
]

KURA_RECIPES = [
    ("family_kura_compact", 5.8, 6.5, False),
    ("family_kura_loading", 6.4, 7.4, True),
    ("family_kura_deep", 6.8, 8.8, False),
]

MERCHANT_RECIPES = [
    ("family_small_merchant_01", "machiya_f_s", "left", "compact"),
    ("family_small_merchant_02", "machiya_f_s", "right", "stock"),
    ("family_small_merchant_03", "machiya_f_m", "left", "stock"),
    ("family_small_merchant_04", "machiya_f_m", "right", "display"),
    ("family_small_merchant_05", "machiya_f_s", "center", "display"),
]

PILOT_RECIPES = [
    ("pilot_residence_01", "residence"),
    ("pilot_shop_01", "shop"),
]

SILHOUETTE_RECIPES = [
    ("machiya_pilot_silhouette_quiet_01", "machiya_e_p", "quiet"),
    ("machiya_pilot_silhouette_gable_01", "machiya_e_p", "gable"),
    ("machiya_pilot_silhouette_workshop_01", "machiya_w_a", "workshop"),
]

REPRESENTATIVE_SOURCES = {
    "family_standard_machiya_04",
    "family_nagaya_04bay",
    "family_kura_loading",
    "family_small_merchant_03",
}


def reset_scene():
    kit.clear()
    kit.make_materials()


def add_lattice(b, cx, y, z0, z1, width, bars=6, mat="WOOD"):
    b.box(cx, y, z0, width, 0.08, 0.10, mat)
    b.box(cx, y, z1, width, 0.08, 0.10, mat)
    b.box(cx, y, (z0 + z1) * 0.5, width, 0.07, 0.07, mat)
    for i in range(bars + 1):
        x = cx - width * 0.5 + width * i / bars
        b.box(x, y, (z0 + z1) * 0.5, 0.055, 0.075, z1 - z0, mat)


def roof_ridge_x(b, name, x0, x1, y0, y1, eave_z, ridge_z, mat="KAWARA"):
    """Closed coherent gable roof whose straight ridge runs along X."""
    r_y = (y0 + y1) * 0.5
    b.quad((x0, y0, eave_z), (x1, y0, eave_z),
           (x1, r_y, ridge_z), (x0, r_y, ridge_z), mat)
    b.quad((x0, y1, eave_z), (x0, r_y, ridge_z),
           (x1, r_y, ridge_z), (x1, y1, eave_z), mat)
    b.tri((x0, y0, eave_z), (x0, r_y, ridge_z), (x0, y1, eave_z), mat)
    b.tri((x1, y0, eave_z), (x1, y1, eave_z), (x1, r_y, ridge_z), mat)
    b.box((x0 + x1) * 0.5, r_y, ridge_z + 0.05, x1 - x0 + 0.18, 0.18, 0.16, mat)
    b.box((x0 + x1) * 0.5, y0, eave_z - 0.04, x1 - x0 + 0.12, 0.14, 0.18, "WOOD")
    b.box((x0 + x1) * 0.5, y1, eave_z - 0.04, x1 - x0 + 0.12, 0.14, 0.18, "WOOD")


def roof_ridge_y(b, name, x0, x1, y0, y1, eave_z, ridge_z, mat="KAWARA", end_mat="PLASTER"):
    """Closed coherent gable roof whose straight ridge runs along Y."""
    r_x = (x0 + x1) * 0.5
    b.quad((x0, y0, eave_z), (r_x, y0, ridge_z),
           (r_x, y1, ridge_z), (x0, y1, eave_z), mat)
    b.quad((x1, y0, eave_z), (x1, y1, eave_z),
           (r_x, y1, ridge_z), (r_x, y0, ridge_z), mat)
    b.tri((x0, y0, eave_z), (x1, y0, eave_z), (r_x, y0, ridge_z), end_mat)
    b.tri((x0, y1, eave_z), (r_x, y1, ridge_z), (x1, y1, eave_z), end_mat)
    b.box(r_x, (y0 + y1) * 0.5, ridge_z + 0.05, 0.18, y1 - y0 + 0.18, 0.16, mat)
    b.box(x0, (y0 + y1) * 0.5, eave_z - 0.04, 0.14, y1 - y0 + 0.12, 0.18, "WOOD")
    b.box(x1, (y0 + y1) * 0.5, eave_z - 0.04, 0.14, y1 - y0 + 0.12, 0.18, "WOOD")


def add_residential_entry(b, width, door_x, side):
    if side == "left":
        cx = -width * 0.27
    elif side == "right":
        cx = width * 0.27
    else:
        cx = door_x
    deck_w = min(3.25, width * 0.42)
    b.box(cx, -0.63, 0.34, deck_w, 1.12, 0.18, "WOOD_LT")
    b.box(cx, -1.16, 0.16, deck_w + 0.24, 0.30, 0.22, "STONE")
    for px in (cx - deck_w * 0.46, cx + deck_w * 0.46):
        b.box(px, -1.04, 1.35, 0.13, 0.13, 2.15, "WOOD")
    b.box(cx, -1.04, 2.37, deck_w + 0.30, 0.16, 0.17, "WOOD")
    add_lattice(b, cx, -0.82, 0.55, 2.12, deck_w * 0.88, bars=max(4, int(deck_w / 0.42)))
    kit._hisashi(b, cx, deck_w, 2.55, 0.0, span_over=0.50, proj=1.28)


def add_rear_service(b, width, depth, mode):
    wing_w = min(3.5, width * 0.42)
    cx = -width * 0.5 + wing_w * 0.55 if mode == "lean" else width * 0.5 - wing_w * 0.55
    cy = depth + 1.05
    b.box(cx, cy, 1.42, wing_w, 2.30, 2.55, "PLASTER")
    for px in (cx - wing_w * 0.46, cx + wing_w * 0.46):
        b.box(px, depth + 0.08, 1.45, 0.14, 0.14, 2.40, "WOOD")
    b.box(cx, depth + 0.02, 1.10, wing_w * 0.56, 0.10, 1.35, "WOOD_LT")
    if mode == "gable":
        roof_ridge_y(b, "rear_gable", cx - wing_w * 0.5 - 0.35, cx + wing_w * 0.5 + 0.35,
                     depth - 0.18, depth + 2.35, 2.72, 3.55)
    else:
        b.quad((cx - wing_w * 0.5 - 0.30, depth - 0.28, 2.82),
               (cx + wing_w * 0.5 + 0.30, depth - 0.28, 2.82),
               (cx + wing_w * 0.5 + 0.30, depth + 2.40, 2.42),
               (cx - wing_w * 0.5 - 0.30, depth + 2.40, 2.42), "KAWARA")
        b.box(cx, depth + 2.38, 2.36, wing_w + 0.68, 0.14, 0.16, "WOOD")


def add_upper_residential_treatment(b, width, kind):
    if kind == "nikai":
        z0, z1 = 3.02, 4.18
        for cx in (-width * 0.25, width * 0.25):
            add_lattice(b, cx, -0.13, z0, z1, width * 0.38, bars=6)
            b.box(cx, -0.17, (z0 + z1) * 0.5, width * 0.34, 0.055, z1 - z0 - 0.18, "SHOJI")
    else:
        for cx in (-width * 0.28, 0.0, width * 0.28):
            b.box(cx, -0.13, 2.82, 0.52, 0.08, 0.34, "PLASTER")
            for dx in (-0.16, 0.0, 0.16):
                b.box(cx + dx, -0.19, 2.82, 0.045, 0.07, 0.29, "WOOD")


def build_standard(name, host, entry_side, rear_mode, upper_kind):
    s = kit.spec_of(host)
    b = kit.MB()
    _ridge, door_x, _z_top = kit.machiya(b, s)
    add_residential_entry(b, s["W"], door_x, entry_side)
    add_rear_service(b, s["W"], s["D"], rear_mode)
    add_upper_residential_treatment(b, s["W"], upper_kind)
    return b.build(name)


def build_nagaya(name, dwellings, end_service):
    b = kit.MB()
    bay_w = 4.0
    body_w = dwellings * bay_w
    depth = 7.5
    wall_h = 3.42
    plinth = 0.28
    b.box(0, depth * 0.5, 0.08, body_w + 0.72, depth + 0.72, 0.16, "STONE")
    b.box(0, depth * 0.5, plinth * 0.5, body_w + 0.18, depth + 0.18, plinth, "STONE")
    b.box(0, depth * 0.5, (plinth + wall_h) * 0.5, body_w, depth, wall_h - plinth, "PLASTER")
    for i in range(dwellings + 1):
        x = -body_w * 0.5 + i * bay_w
        b.box(x, 0.08, (plinth + wall_h) * 0.5, 0.16, 0.16, wall_h - plinth, "WOOD")
        b.box(x, depth - 0.08, (plinth + wall_h) * 0.5, 0.16, 0.16, wall_h - plinth, "WOOD")
    b.box(0, 0.02, 1.94, body_w, 0.18, 0.18, "WOOD")
    b.box(0, 0.04, wall_h - 0.12, body_w + 0.12, 0.18, 0.20, "WOOD")
    door_offsets = (-0.78, 0.0, 0.78, 0.0, -0.78)
    for i in range(dwellings):
        bay_c = -body_w * 0.5 + (i + 0.5) * bay_w
        door_c = bay_c + door_offsets[i]
        screen_c = bay_c - door_offsets[i] * 0.52
        b.box(door_c, -0.06, 1.26, 1.18, 0.10, 1.95, "WOOD")
        b.box(door_c, -0.13, 2.28, 1.34, 0.14, 0.16, "WOOD")
        b.box(door_c - 0.34, -0.14, 1.26, 0.07, 0.07, 1.82, "WOOD_LT")
        b.box(door_c + 0.34, -0.14, 1.26, 0.07, 0.07, 1.82, "WOOD_LT")
        # Each household gets the same modest entry roof; door offsets supply
        # controlled variation while the canopy line preserves shared rhythm.
        b.quad((door_c - 0.82, -0.05, 2.48), (door_c + 0.82, -0.05, 2.48),
               (door_c + 0.82, -0.82, 2.31), (door_c - 0.82, -0.82, 2.31), "KAWARA")
        b.box(door_c, -0.82, 2.25, 1.72, 0.12, 0.15, "WOOD")
        add_lattice(b, screen_c, -0.11, 0.52, 1.82, 1.62, bars=5)
        b.box(screen_c, -0.08, 1.15, 1.40, 0.055, 1.10, "SHOJI")
        b.box(bay_c, -0.70, 0.32, bay_w - 0.42, 1.18, 0.18, "WOOD_LT")
        b.box(bay_c, -1.24, 0.15, bay_w - 0.20, 0.30, 0.20, "STONE")
    roof_ridge_x(b, name + "_roof", -body_w * 0.5 - 0.72, body_w * 0.5 + 0.72,
                 -0.72, depth + 0.72, wall_h, 4.82)
    # Shared rear service strip: continuous shelter, repeated partitions.
    b.box(0, depth + 0.78, 1.34, body_w - 0.20, 1.55, 2.30, "WOOD_LT")
    b.quad((-body_w * 0.5 - 0.20, depth - 0.08, 2.72),
           (body_w * 0.5 + 0.20, depth - 0.08, 2.72),
           (body_w * 0.5 + 0.20, depth + 1.72, 2.38),
           (-body_w * 0.5 - 0.20, depth + 1.72, 2.38), "KAWARA")
    for i in range(dwellings + 1):
        x = -body_w * 0.5 + i * bay_w
        b.box(x, depth + 0.72, 1.37, 0.12, 1.35, 2.18, "WOOD")
    if end_service != "none":
        sign = -1 if end_service == "left" else 1
        cx = sign * (body_w * 0.5 + 1.02)
        b.box(cx, depth * 0.58, 1.28, 1.85, 3.10, 2.25, "WOOD_LT")
        b.quad((cx - 1.18, depth * 0.58 - 1.72, 2.64),
               (cx + 1.18, depth * 0.58 - 1.72, 2.64),
               (cx + 1.18, depth * 0.58 + 1.72, 2.28),
               (cx - 1.18, depth * 0.58 + 1.72, 2.28), "KAWARA")
    return b.build(name)


def build_kura(name, width, depth, loading):
    b = kit.MB()
    plinth = 0.46
    wall_h = 4.38
    # Broad stone foot and layered plaster cheeks give the required heavy mass.
    b.box(0, depth * 0.5, 0.15, width + 0.72, depth + 0.72, 0.30, "STONE")
    b.box(0, depth * 0.5, plinth * 0.5, width + 0.22, depth + 0.22, plinth, "STONE")
    b.box(0, depth * 0.5, (plinth + wall_h) * 0.5, width, depth, wall_h - plinth, "PLASTER")
    for sx in (-1, 1):
        b.box(sx * (width * 0.5 - 0.13), depth * 0.5, 2.42, 0.28, depth + 0.10, 3.72, "PLASTER")
    b.box(0, 0.04, 1.52, 2.10, 0.18, 2.45, "WOOD")
    b.box(0, -0.08, 1.52, 1.58, 0.12, 2.06, "WOOD_LT")
    b.box(0, -0.16, 2.78, 2.42, 0.22, 0.26, "WOOD")
    for x in (-0.52, 0.0, 0.52):
        b.box(x, -0.24, 1.52, 0.08, 0.07, 1.90, "WOOD")
    for z in (0.72, 1.34, 1.96):
        b.box(0, -0.24, z, 1.48, 0.07, 0.08, "WOOD")
    # Only two tiny high vents; this must never read as a residence.
    for x in (-width * 0.23, width * 0.23):
        b.box(x, -0.07, 3.48, 0.58, 0.12, 0.46, "WOOD")
        b.box(x, -0.14, 3.48, 0.38, 0.07, 0.26, "SHOJI")
    roof_ridge_y(b, name + "_roof", -width * 0.5 - 0.68, width * 0.5 + 0.68,
                 -0.68, depth + 0.68, wall_h, 5.82)
    b.box(0, -0.71, wall_h + 0.02, width + 0.18, 0.16, 0.20, "WOOD")
    b.box(0, -0.74, 5.02, 0.16, 0.16, 1.12, "WOOD")
    if loading:
        b.box(0, -1.02, 0.43, 3.85, 1.78, 0.22, "WOOD_LT")
        for x in (-1.65, 1.65):
            b.box(x, -1.68, 1.54, 0.15, 0.15, 2.18, "WOOD")
        kit._hisashi(b, 0, 3.65, 2.78, 0.0, span_over=0.55, proj=1.92)
    return b.build(name)


def add_merchant_front(b, width, depth, side, stock_mode):
    if side == "left":
        cx = -width * 0.20
    elif side == "right":
        cx = width * 0.20
    else:
        cx = 0.0
    opening_w = min(4.4, width * 0.60)
    # Dark recessed opening is framed as architecture, not a text or prop cue.
    b.box(cx, -0.13, 1.30, opening_w, 0.09, 2.10, "WOOD")
    b.box(cx, -0.22, 1.28, opening_w - 0.34, 0.06, 1.76, "WOOD_LT")
    for px in (cx - opening_w * 0.5, cx, cx + opening_w * 0.5):
        b.box(px, -1.58, 1.42, 0.16, 0.16, 2.54, "WOOD")
    b.box(cx, -1.58, 2.66, opening_w + 0.55, 0.18, 0.18, "WOOD")
    kit._hisashi(b, cx, opening_w + 0.25, 2.88, 0.0, span_over=0.68, proj=1.82)
    b.box(cx, -1.10, 0.38, opening_w + 0.42, 1.68, 0.24, "WOOD_LT")
    b.box(cx, -1.88, 0.17, opening_w + 0.58, 0.34, 0.22, "STONE")
    # Integrated display/loading rail reads at medium distance.
    b.box(cx, -1.92, 0.82, opening_w + 0.28, 0.20, 0.16, "WOOD")
    for px in (cx - opening_w * 0.43, cx + opening_w * 0.43):
        b.box(px, -1.90, 0.60, 0.13, 0.13, 0.56, "WOOD")
    if stock_mode in ("stock", "display"):
        wing_w = min(3.0, width * 0.36)
        wing_cx = -width * 0.5 + wing_w * 0.5 if side != "left" else width * 0.5 - wing_w * 0.5
        b.box(wing_cx, depth + 0.90, 1.30, wing_w, 2.05, 2.35, "PLASTER")
        b.quad((wing_cx - wing_w * 0.5 - 0.25, depth - 0.18, 2.62),
               (wing_cx + wing_w * 0.5 + 0.25, depth - 0.18, 2.62),
               (wing_cx + wing_w * 0.5 + 0.25, depth + 2.05, 2.28),
               (wing_cx - wing_w * 0.5 - 0.25, depth + 2.05, 2.28), "KAWARA")
        b.box(wing_cx, depth - 0.08, 1.18, wing_w * 0.58, 0.10, 1.28, "WOOD")
    if stock_mode == "display":
        add_lattice(b, -cx * 0.75, -0.16, 0.56, 1.86, min(2.15, width * 0.30), bars=5)


def build_merchant(name, host, side, stock_mode):
    s = kit.spec_of(host)
    b = kit.MB()
    kit.machiya(b, s)
    add_merchant_front(b, s["W"], s["D"], side, stock_mode)
    return b.build(name)


def add_closed_residential_front(b, width, door_x):
    """A quiet, layered frontage: closed screens beside a recessed genkan."""
    genkan_x = -width * 0.27
    # The dark back plane and the screen line are deliberately separated in Y;
    # that small shadow gap reads as a real entrance at player-eye distance.
    b.box(genkan_x, -0.25, 1.28, 1.22, 0.08, 1.98, "WOOD")
    b.box(genkan_x, -0.75, 1.28, 1.02, 0.07, 1.78, "SHOJI")
    for dx in (-0.48, 0.0, 0.48):
        b.box(genkan_x + dx, -0.80, 1.28, 0.055, 0.07, 1.82, "WOOD")
    for z in (0.40, 1.25, 2.16):
        b.box(genkan_x, -0.80, z, 1.04, 0.07, 0.055, "WOOD")

    # Closed rain shutters distinguish the dwelling from an open shop bay.
    shutter_cx = width * 0.21
    shutter_w = min(3.15, width * 0.38)
    b.box(shutter_cx, -0.34, 1.28, shutter_w, 0.09, 1.88, "WOOD_LT")
    for i in range(7):
        x = shutter_cx - shutter_w * 0.5 + shutter_w * (i + 0.5) / 7
        b.box(x, -0.40, 1.28, 0.045, 0.06, 1.82, "WOOD")
    # Two restrained stones remain inside the existing declared frontage bbox.
    for x, y, w in ((genkan_x, -1.13, 0.72), (genkan_x + 0.34, -1.20, 0.58)):
        b.box(x, y, 0.11, w, 0.22, 0.12, "STONE")


def add_shop_identity_front(b, width):
    """Open merchant bay with noren, a projecting sign and display threshold."""
    cx = -width * 0.20
    opening_w = min(4.4, width * 0.60)
    # Five short noren panels leave a readable gap above the display deck.
    panel_w = (opening_w - 0.28) / 5.0
    for i in range(5):
        x = cx - opening_w * 0.5 + 0.14 + panel_w * (i + 0.5)
        b.box(x, -1.66, 2.16, panel_w - 0.06, 0.035, 0.72, "PLASTER")
    b.box(cx, -1.66, 2.55, opening_w + 0.10, 0.06, 0.10, "WOOD")

    # A shallow display shelf keeps the doorway open instead of turning the
    # whole frontage into the dwelling's closed lattice wall.
    display_x = width * 0.27
    display_w = min(1.75, width * 0.25)
    b.box(display_x, -1.70, 0.92, display_w, 0.44, 0.12, "WOOD_LT")
    for px in (display_x - display_w * 0.42, display_x + display_w * 0.42):
        b.box(px, -1.70, 0.56, 0.10, 0.10, 0.68, "WOOD")

    # Plain wooden hanging sign: architecture first, no text dependency.
    sign_x = width * 0.39
    b.box(sign_x, -1.60, 2.23, 0.12, 0.12, 1.02, "WOOD")
    b.box(sign_x, -1.68, 1.89, 0.54, 0.08, 0.72, "WOOD_LT")


def build_pilot(name, role):
    """Build isolated variants for the two player-visible market-front lots."""
    if role == "residence":
        s = kit.spec_of("machiya_f_a")
        s["total_h"] += 0.18
        b = kit.MB()
        _ridge, door_x, _z_top = kit.machiya(b, s)
        add_residential_entry(b, s["W"], door_x, "left")
        add_rear_service(b, s["W"], s["D"], "gable")
        add_upper_residential_treatment(b, s["W"], "mushiko")
        add_closed_residential_front(b, s["W"], door_x)
        return b.build(name)
    if role == "shop":
        s = kit.spec_of("machiya_f_s")
        s["total_h"] += 0.30
        s["pitch"] += 2.0
        b = kit.MB()
        kit.machiya(b, s)
        add_merchant_front(b, s["W"], s["D"], "left", "compact")
        add_shop_identity_front(b, s["W"])
        return b.build(name)
    raise ValueError("unknown Phase 2A pilot role: %s" % role)


def build_silhouette_pilot(name, host, role):
    """Low-frequency Phase 2B variants for fixed pilot lots only."""
    s = kit.spec_of(host)
    if role == "quiet":
        # Background tier: almost no extra height and the original footprint.
        s["total_h"] += 0.10
    elif role == "gable":
        # Secondary tier: one tsuma-facing roof breaks the parallel eave run.
        s["orient"] = "tsuma"
        # Preserve the host's exact 7.94 x 7.88 outer footprint after rotating
        # the roof language; only the massing inside that envelope changes.
        s["W"] += 0.26
        s["D"] -= 0.26
        s["pitch"] = 23.0
        s["total_h"] += 0.42
    elif role == "workshop":
        # Functional tier: a slightly heavier roof mass; the host already owns
        # the only restrained smoke outlet in this market group.
        s["pitch"] += 3.0
        s["total_h"] += 0.42
    else:
        raise ValueError("unknown Phase 2B silhouette role: %s" % role)
    b = kit.MB()
    kit.machiya(b, s)
    return b.build(name)


def export_asset(ob, name):
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(SOURCE_DIR, exist_ok=True)
    if name in REPRESENTATIVE_SOURCES:
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SOURCE_DIR, name + ".blend"))
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB",
                              export_yup=True, export_apply=True, export_materials="EXPORT")
    rep = kit.validate(ob)
    dims = kit.bbox(ob)
    return {
        "name": name,
        "glb": os.path.relpath(path, os.getcwd()).replace("\\", "/"),
        "dimensions": [round(v, 3) for v in dims],
        "faces": rep["faces"],
        "triangles": rep["faces"],
        "materials": len(rep["material_faces"]),
        "material_faces": rep["material_faces"],
        "degenerate": rep["degenerate"],
    }


def generate():
    manifest = []
    jobs = []
    jobs += [(r[0], build_standard, r) for r in STANDARD_RECIPES]
    jobs += [(r[0], build_nagaya, r) for r in NAGAYA_RECIPES]
    jobs += [(r[0], build_kura, r) for r in KURA_RECIPES]
    jobs += [(r[0], build_merchant, r) for r in MERCHANT_RECIPES]
    jobs += [(r[0], build_pilot, r) for r in PILOT_RECIPES]
    jobs += [(r[0], build_silhouette_pilot, r) for r in SILHOUETTE_RECIPES]
    for name, builder, args in jobs:
        reset_scene()
        ob = builder(*args)
        record = export_asset(ob, name)
        assert record["degenerate"] == 0, "%s contains degenerate faces" % name
        manifest.append(record)
        print("FAMILY_ASSET %s faces=%d dims=%s mats=%d" %
              (name, record["faces"], record["dimensions"], record["materials"]))
    manifest_path = os.path.join(SCRIPT_DIR, "building_families_manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as fh:
        json.dump({"recipes": manifest}, fh, indent=2)
    print("WROTE", manifest_path)


if __name__ == "__main__":
    generate()
