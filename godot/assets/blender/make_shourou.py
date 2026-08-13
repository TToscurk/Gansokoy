# 鐘楼（袴腰鐘楼）—— BUILDING_PRODUCTION_01
#
#   blender -b -P assets/blender/make_shourou.py -- <outdir> [--render <dir>]
#
# 本通南端の視線終点に立つ landmark。町家 production kit と**同じ規約**で
# 生成する（語意材質・繞序・原点・-y 正面）ので、`make_machiya.py` から
# MB / make_materials / validate / bbox / gbox / export を借りる。屋根は
# `roof_lib.irimoya_roof()` —— 寺子屋・火見櫓・格の高い店で使い回す前提の
# 共用サブシステムで、ここがその最初の利用者。
#
# ══════════════════════════════════════════════════════════════════════
# 袴腰鐘楼の構成（下から）
# ══════════════════════════════════════════════════════════════════════
#   石垣基壇 1.50   —— 勾配のついた石積み。鐘楼が「地面に置いてある」のでは
#                      なく「土から生えている」ように見えるかどうかは、この
#                      **батter（緩やかな傾き）**だけで決まる。垂直な箱にすると
#                      とたんに置物になる。
#   袴腰    2.66   —— 下広がりの漆喰の裾。この建物の名前そのもの。50m から
#                      見て鐘楼と判るのは、実はこの**台形**であって鐘ではない。
#   縁・高欄 0.82  —— 人が上がる床がある、という情報。これが無いと塔になる。
#   鐘室    3.03   —— 四本の通し柱＋貫＋頭貫＋桁。**開いている**ことが要件で、
#                      壁は一枚も無い。
#   入母屋  2.33   —— 深い出簷。軒先は鐘の肩より下まで下りてくる（＝鐘は
#                      軒の下の影の中にある）。これが鐘楼の見え方の正解。
#
# ⚠ 梵鐘の材質は **STONE** を当てている。語意材質は六種で固定（増やすなと
#   規約にある）ので、青銅に一番近いのは中間グレーの STONE —— KAWARA は
#   暗すぎて、軒の影の中で鐘が消える。可読性を採った取捨で、考証ではない。
import bpy
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib.util as _ilu

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load(mod):
    spec = _ilu.spec_from_file_location(mod, os.path.join(_HERE, mod + ".py"))
    m = _ilu.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


mm = _load("make_machiya")
RL = _load("roof_lib")

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = ARGV[0] if ARGV else "godot/assets/models"
RENDER_DIR = ARGV[ARGV.index("--render") + 1] if "--render" in ARGV else None

# ══════════════════════════════════════════════════════════════════════
# 寸法 —— 原点は**正面（-y 側）の地面**、x が面寬方向（町家と同じ規約）
# ══════════════════════════════════════════════════════════════════════
BASE_W = 6.50          # 石垣基壇の一辺（＝この模組の footprint）
CY = BASE_W / 2.0      # 奥行き中心。正面が y=0 なので中心は y=3.25

BASE_H = 1.50          # 石垣
BATTER = 0.22          # 石垣の勾配（片側の後退量）
COPE_Z = BASE_H + 0.14  # 葛石の上端

HAKAMA_TOP = 4.30      # 袴腰の上端＝縁の下端
# ⚠ 袴腰の裾は**葛石より内側**でなければならない。最初の版は裾 3.15 で
# 葛石 3.15・石垣天 3.03 より外に出ており、正面から石垣が一切見えず、
# 下半分が白い台形一枚に潰れていた（仕様の「石垣基壇 1.5m」が消えた）。
# 石の上に漆喰が載っている、と読ませるには段差が要る。
HAKAMA_HW0 = 2.90      # 袴腰の裾（下）半幅
HAKAMA_HW1 = 2.275     # 袴腰の肩（上）半幅＝鐘室の半幅

DECK_Z0, DECK_Z1 = HAKAMA_TOP, HAKAMA_TOP + 0.22
DECK_HW = 2.95         # 縁は袴腰より 0.675 張り出す
RAIL_HW = 2.80
RAIL_TOP = DECK_Z1 + 0.82

POST_C = 2.115         # 通し柱の芯（断面 0.32 → 外面が 2.275 に揃う）
POST_R = 0.16
NUKI_Z = 5.42          # 腰貫（高欄のすぐ上）
KASHIRA_Z = 7.35       # 頭貫
PLATE_TOP = 7.75       # 桁の上端＝**屋根の壁面基準**（規約：桁天は壁天と面一）
PLATE_R = 0.11

BEAM_Z = 7.05          # 梵鐘を吊る梁
BELL_TOP = 6.80        # 鐘身の天（この上に竜頭）
BELL_BOT = 4.95        # 口縁。縁から 0.43 浮く

PITCH = math.radians(38.0)
OVERHANG = 1.35
GABLE_AT = 0.55


def _ring(cy, z, r, n):
    return [(r * math.cos(k * math.tau / n), cy + r * math.sin(k * math.tau / n), z)
            for k in range(n)]


def _tube(bld, cy, prof, mat, n=12, cap=True):
    """回転体（梵鐘）。リングは反時計回り、面は下→上 —— frustum4 と同じ向き。"""
    rings = [_ring(cy, z, r, n) for (z, r) in prof]
    for a, b in zip(rings, rings[1:]):
        for k in range(n):
            k2 = (k + 1) % n
            bld.quad(a[k], a[k2], b[k2], b[k], mat)
    if cap:
        top = rings[-1]
        for k in range(1, n - 1):
            bld.tri(top[0], top[k], top[k + 1], mat)


def _stone_base(bld):
    """石垣基壇：勾配のついた石積み ＋ 葛石。"""
    RL.frustum4(bld, 0.0, CY, 0.0, BASE_H,
                BASE_W / 2, BASE_W / 2,
                BASE_W / 2 - BATTER, BASE_W / 2 - BATTER, "STONE")
    # 葛石（天端の縁石）—— 石垣と袴腰の間に一本入れると、二つの材が
    # 「積み替わった」と読める。無いと漆喰が石から直接生えて見える。
    bld.box(0, CY, BASE_H + 0.07, 6.30, 6.30, 0.14, "STONE")


def _hakama(bld):
    """袴腰：下広がりの漆喰の裾 ＋ 隅の木の押さえ ＋ 裾の水切り板。"""
    RL.frustum4(bld, 0.0, CY, COPE_Z, HAKAMA_TOP,
                HAKAMA_HW0, HAKAMA_HW0, HAKAMA_HW1, HAKAMA_HW1, "PLASTER")
    # 裾の水切り（板）——漆喰の下端は必ず板で切る。地面からの跳ね返りで
    # 漆喰が最初に傷むのがここなので、実物も必ず板が回っている。
    bld.box(0, CY, COPE_Z + 0.08, HAKAMA_HW0 * 2 + 0.12, HAKAMA_HW0 * 2 + 0.12,
            0.16, "WOOD_LT")
    for sx in (1, -1):
        for sy in (1, -1):
            RL.beam(bld, (sx * HAKAMA_HW0, CY + sy * HAKAMA_HW0, COPE_Z),
                    (sx * HAKAMA_HW1, CY + sy * HAKAMA_HW1, HAKAMA_TOP),
                    0.095, "WOOD")


def _engawa(bld):
    """縁（張り出した床）＋ 腕木 ＋ 高欄。"""
    # 腕木（縁を受ける斜めの木）—— 張り出した床の下に何も無いと浮いて見える
    hk = lambda z: HAKAMA_HW0 + (HAKAMA_HW1 - HAKAMA_HW0) * \
        (z - COPE_Z) / (HAKAMA_TOP - COPE_Z)
    for sy in (1, -1):
        for x in (-2.05, -0.85, 0.85, 2.05):
            RL.beam(bld, (x, CY + sy * hk(3.86), 3.86),
                    (x, CY + sy * (DECK_HW - 0.10), DECK_Z0 - 0.02),
                    0.075, "WOOD")
    for sx in (1, -1):
        for y in (-2.05, -0.85, 0.85, 2.05):
            RL.beam(bld, (sx * hk(3.86), CY + y, 3.86),
                    (sx * (DECK_HW - 0.10), CY + y, DECK_Z0 - 0.02),
                    0.075, "WOOD")
    # 床板
    bld.box(0, CY, (DECK_Z0 + DECK_Z1) / 2, DECK_HW * 2, DECK_HW * 2,
            DECK_Z1 - DECK_Z0, "WOOD", top="WOOD_LT")
    # 縁框（床の外周を締める）
    for sy in (1, -1):
        RL.beam(bld, (-DECK_HW, CY + sy * DECK_HW, DECK_Z1 - 0.06),
                (DECK_HW, CY + sy * DECK_HW, DECK_Z1 - 0.06), 0.065, "WOOD")
    for sx in (1, -1):
        RL.beam(bld, (sx * DECK_HW, CY - DECK_HW, DECK_Z1 - 0.06),
                (sx * DECK_HW, CY + DECK_HW, DECK_Z1 - 0.06), 0.065, "WOOD")
    # 高欄：親柱四本 ＋ 各面に二本の中柱、上下二段の横木
    xs = (-RAIL_HW, -0.95, 0.95, RAIL_HW)
    for sy in (1, -1):
        for x in xs:
            RL.beam(bld, (x, CY + sy * RAIL_HW, DECK_Z1),
                    (x, CY + sy * RAIL_HW, RAIL_TOP), 0.068, "WOOD")
        for z, r in ((RAIL_TOP - 0.04, 0.062), (DECK_Z1 + 0.34, 0.046)):
            RL.beam(bld, (-RAIL_HW, CY + sy * RAIL_HW, z),
                    (RAIL_HW, CY + sy * RAIL_HW, z), r, "WOOD")
    for sx in (1, -1):
        for y in (-0.95, 0.95):
            RL.beam(bld, (sx * RAIL_HW, CY + y, DECK_Z1),
                    (sx * RAIL_HW, CY + y, RAIL_TOP), 0.068, "WOOD")
        for z, r in ((RAIL_TOP - 0.04, 0.062), (DECK_Z1 + 0.34, 0.046)):
            RL.beam(bld, (sx * RAIL_HW, CY - RAIL_HW, z),
                    (sx * RAIL_HW, CY + RAIL_HW, z), r, "WOOD")
    # 擬宝珠（四隅）—— 主橋と同じ語彙。村の「格のある構築物」の印。
    for sx in (1, -1):
        for sy in (1, -1):
            bld.box(sx * RAIL_HW, CY + sy * RAIL_HW, RAIL_TOP + 0.11,
                    0.17, 0.17, 0.22, "WOOD")


def _frame(bld):
    """鐘室の軸組：通し柱 → 腰貫 → 頭貫 → 斗 → 桁。壁は無い。"""
    for sx in (1, -1):
        for sy in (1, -1):
            RL.beam(bld, (sx * POST_C, CY + sy * POST_C, HAKAMA_TOP - 0.30),
                    (sx * POST_C, CY + sy * POST_C, PLATE_TOP - 0.10),
                    POST_R, "WOOD")
    for z, r in ((NUKI_Z, 0.085), (KASHIRA_Z, 0.115)):
        for sy in (1, -1):
            RL.beam(bld, (-POST_C, CY + sy * POST_C, z),
                    (POST_C, CY + sy * POST_C, z), r, "WOOD")
        for sx in (1, -1):
            RL.beam(bld, (sx * POST_C, CY - POST_C, z),
                    (sx * POST_C, CY + POST_C, z), r, "WOOD")
    # 舟肘木（柱頭の受け）
    for sx in (1, -1):
        for sy in (1, -1):
            bld.box(sx * POST_C, CY + sy * POST_C, PLATE_TOP - 0.32,
                    0.46, 0.46, 0.17, "WOOD")
    # 桁：**上端が壁天基準 7.75 に面一**（規約。上に伸ばすと屋根面を破る）
    for sy in (1, -1):
        RL.beam(bld, (-POST_C - 0.16, CY + sy * POST_C, PLATE_TOP - PLATE_R),
                (POST_C + 0.16, CY + sy * POST_C, PLATE_TOP - PLATE_R),
                PLATE_R, "WOOD")
    for sx in (1, -1):
        RL.beam(bld, (sx * POST_C, CY - POST_C - 0.16, PLATE_TOP - PLATE_R),
                (sx * POST_C, CY + POST_C + 0.16, PLATE_TOP - PLATE_R),
                PLATE_R, "WOOD")


def _bell(bld):
    """梵鐘 ＋ 吊る梁 ＋ 撞木。"""
    RL.beam(bld, (-POST_C, CY, BEAM_Z), (POST_C, CY, BEAM_Z), 0.16, "WOOD")
    prof = [(BELL_BOT, 0.630), (BELL_BOT + 0.11, 0.615), (5.95, 0.585),
            (6.42, 0.555), (6.62, 0.500), (6.72, 0.340), (BELL_TOP, 0.200)]
    _tube(bld, CY, prof, "STONE")
    # 上帯・下帯（鐘身を三段に割る横の線。無いと灰色の壺に見える）
    for z in (5.62, 6.16):
        _tube(bld, CY, [(z, 0.612), (z + 0.085, 0.610)], "STONE", cap=False)
    bld.box(0, CY, BELL_TOP + 0.10, 0.24, 0.38, 0.20, "STONE")   # 竜頭
    # 撞木：正面（-y）側から鐘を撞く。吊木から二本の縄で吊る。
    RL.beam(bld, (0, CY - 2.30, 5.95), (0, CY - 0.95, 5.95), 0.105, "WOOD")
    RL.beam(bld, (0, CY - POST_C, 7.12), (0, CY - 0.90, 7.12), 0.075, "WOOD")
    for y in (CY - 2.05, CY - 1.05):
        RL.beam(bld, (0, y, 7.08), (0, y, 5.95), 0.032, "WOOD")


def build(name="tower_bell_p"):
    b = mm.MB()
    _stone_base(b)
    _hakama(b)
    _engawa(b)
    _frame(b)
    _bell(b)
    roof = RL.irimoya_roof(b, 0.0, CY, PLATE_TOP, HAKAMA_HW1 * 2, HAKAMA_HW1 * 2,
                           PITCH, overhang=OVERHANG, thick=0.18,
                           gable_at=GABLE_AT)
    ob = b.build(name)
    return ob, roof


VIEWS = [
    # 50m の剪影が要件なので、まずそれ。近景は後。
    ("00_silhouette_50m", (-18.0, -44.0, 9.0), (0.0, CY, 4.6)),
    ("01_front", (0.0, -26.0, 7.0), (0.0, CY, 5.0)),
    ("02_three_quarter", (-17.0, -19.0, 8.6), (0.0, CY, 4.8)),
    ("03_bell_stage", (-4.5, -12.5, 7.2), (0.0, CY, 6.0)),
    ("04_eave_up", (-3.0, -7.0, 2.2), (0.0, CY, 8.2)),
]


def render(ob, out_dir):
    import mathutils
    os.makedirs(out_dir, exist_ok=True)
    sc = mm._neutral_stage(ground_at=(0, CY), ground_size=200)
    cam = mm._camera(sc, lens=50.0)
    for nm, pos, tgt in VIEWS:
        cam.location = mathutils.Vector(pos)
        mm._look_at(cam, tgt)
        sc.render.filepath = os.path.join(out_dir, nm + ".png")
        bpy.ops.render.render(write_still=True)
        print("rendered %s" % sc.render.filepath)


if __name__ == "__main__":
    mm.clear()
    mm.make_materials()
    ob, roof = build()
    rep = mm.validate(ob)
    bb = mm.bbox(ob)
    gb = mm.gbox(ob)
    print("── 鐘楼 BUILDING_PRODUCTION_01 ──")
    print("  faces %d / verts %d" % (rep["faces"], rep["verts"]))
    print("  degenerate %d / loose %d / non-manifold-edges %d"
          % (rep["degenerate"], rep["loose_verts"], rep["non_manifold_edges"]))
    print("  materials %d 種 %s" % (len(rep["material_faces"]),
                                    rep["material_faces"]))
    print("  fw %.2f  fd %.2f  h %.2f" % bb)
    print("  gbox %s" % gb)
    print("  棟 %.2f / 軒 %.2f / 妻壁基 %.2f / 棟半長 %.2f"
          % (roof["ridge_z"], roof["eave_z"], roof["gable_z"], roof["gable_x"]))
    assert rep["degenerate"] == 0, "退化面あり：%s" % rep
    assert len(rep["material_faces"]) >= 4, "語意材質が塌れた：%s" % rep
    assert 9.5 <= bb[2] <= 11.0, "総高 %.2f が仕様 9.5~11.0 の外" % bb[2]
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR, exist_ok=True)
    print("exported %s" % mm.export(ob, "tower_bell_p"))
    if RENDER_DIR:
        render(ob, RENDER_DIR)
    print("done")
