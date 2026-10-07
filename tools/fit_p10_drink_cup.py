"""R3c W3 Drink — fit the tea-cup grip in the left hand (prop placement only; the Mixamo clip is untouched).

Input: per-frame skinned vertices around the hand in LeftHand-bone space + mouth / world-up / body-forward
in the same space (godot/tools/probe_p10_drink_dump.gd).
Cup = the overlay's lathed yunomi: outer radius 0.027 at the foot → 0.036 at the rim, height 0.072,
rim lip mid-radius 0.0325. The cup is rotationally symmetric, so its pose in the hand is
  axis u (unit, hand space)  +  foot centre o = palm(LeftMiddleProximal) + (dx, dy, dz).

Stage 1 (orientation only): u must be near-upright while the cup is held low (tilt ≤ 20°) and, at the
sip, lean toward the face (35–75° from vertical, top toward the face) — a cup fixed to the old axis
(-hand.x) ends upside-down at the sip.
Stage 2 (position): near rim edge ≤ 1.5 cm from the lips at the sip; no face / sleeve / torso vertex
inside the cup; finger skin may press ≤ 4 mm into the wall (grip contact) but the cup must not float
(> 8 mm from every finger).
Usage: uv run --with numpy python tools/fit_p10_drink_cup.py <dump.json> [<out.json>]
"""
import json, math, sys
import numpy as np

REG = ['face_head', 'hand_L', 'arm_sleeve_L', 'torso', 'other']
H, R0, R1, RIM, TOL = 0.072, 0.027, 0.036, 0.0325, 0.003


def load(path):
    d = json.load(open(path, encoding='utf-8'))
    fr = []
    for f in d['frames']:
        p = np.array(f['pts'], dtype=np.float64).reshape(-1, 4)
        fr.append({'t': f['t'], 'palm': np.array(f['palm_h']), 'mouth': np.array(f['mouth_h']),
                   'up': np.array(f['up_h']), 'fwd': np.array(f['fwd_h']), 'P': p[:, :3], 'reg': p[:, 3].astype(int)})
    return d, fr


def basis(u):
    u = u / np.linalg.norm(u)
    ref = np.array([0.0, 0.0, 1.0]) if abs(u[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    x = np.cross(u, ref); x /= np.linalg.norm(x)
    z = np.cross(x, u)
    return np.stack([x, u, z], axis=1)   # columns = cup X, Y(up), Z in hand space


def ang(a, b):
    return math.degrees(math.acos(max(-1.0, min(1.0, float(a @ b / np.linalg.norm(a) / np.linalg.norm(b))))))


def rim_to(q):
    """distance from a cup-local point to the rim lip circle"""
    rho = math.hypot(q[0], q[2])
    return math.hypot(rho - RIM, q[1] - H)


def evaluate(frames, u, off):
    B = basis(u)
    res = {'inside_frames': [0]*5, 'inside_depth': [0.0]*5, 'float_frames': 0, 'max_float': -1.0}
    for f in frames:
        o = f['palm'] + off
        q = (f['P'] - o) @ B
        rr = np.hypot(q[:, 0], q[:, 2])
        rad = R0 + (R1 - R0) * np.clip(q[:, 1] / H, 0, 1)
        band = (q[:, 1] > 0.004) & (q[:, 1] < H - 0.004)
        dep = np.where(band, rad - TOL - rr, -1)
        reg = f['reg']
        for r in range(5):
            m = reg == r
            if not m.any():
                continue
            dm = float(dep[m].max())
            if dm > (0.004 if r == 1 else 0.0):
                res['inside_frames'][r] += 1
            res['inside_depth'][r] = max(res['inside_depth'][r], max(dm, 0.0))
        hm = (reg == 1) & band
        gap = float((rr[hm] - rad[hm]).min()) if hm.any() else 1.0
        if gap > 0.008:
            res['float_frames'] += 1
        res['max_float'] = max(res['max_float'], gap)
    return res


def main():
    d, frames = load(sys.argv[1])
    dist = np.array([np.linalg.norm(f['mouth'] - f['palm']) for f in frames])
    hold = [i for i in range(len(frames)) if dist[i] > 0.30]
    sip = int(np.argmin(dist))
    near = [i for i in range(len(frames)) if dist[i] < dist[sip] + 0.03]   # the whole sip window
    print('frames', len(frames), 'hold', len(hold), 'sip t=%.2f' % frames[sip]['t'], 'sip window', len(near))
    # ---- stage 1: orientation
    n = 4000
    k = np.arange(n) + 0.5
    phi = np.arccos(1 - 2 * k / n); th = math.pi * (1 + 5 ** 0.5) * k
    dirs = np.stack([np.cos(th) * np.sin(phi), np.sin(th) * np.sin(phi), np.cos(phi)], axis=1)
    cand = []
    for u in dirs:
        ht = max(ang(u, frames[i]['up']) for i in hold)
        s = frames[sip]
        st = ang(u, s['up'])
        tf = float(u @ -s['fwd'])
        pen = max(0, ht - 20) * 5 + max(0, 35 - st) * 2 + max(0, st - 75) * 2 + max(0, 0.3 - tf) * 100
        cand.append((pen, ht, st, tf, u))
    cand.sort(key=lambda c: c[0])
    ox = np.array([-1.0, 0, 0])
    print('old axis -hand.x: hold tilt %.1f sip tilt %.1f toward-face %.2f' % (
        max(ang(ox, frames[i]['up']) for i in hold), ang(ox, frames[sip]['up']), float(ox @ -frames[sip]['fwd'])))
    for c in cand[:5]:
        print('axis pen %.1f hold-tilt %.1f sip-tilt %.1f toward-face %.2f u=%s' % (c[0], c[1], c[2], c[3], np.round(c[4], 3)))
    # ---- stage 2: position for the best few axes (frames subsampled ×2, full sip window kept)
    sub = sorted(set(range(0, len(frames), 2)) | set(near))
    fs = [frames[i] for i in sub]
    out = []
    for pen, ht, st, tf, u in cand[:6]:
        B = basis(u)
        for dx in np.arange(-0.02, 0.101, 0.01):
            for dy in np.arange(-0.06, 0.041, 0.01):
                for dz in np.arange(-0.02, 0.101, 0.01):
                    off = np.array([dx, dy, dz])
                    rm = min(rim_to((frames[i]['mouth'] - (frames[i]['palm'] + off)) @ B) for i in near)
                    if rm > 0.015:
                        continue
                    r = evaluate(fs, u, off)
                    bad = (r['inside_frames'][0] + r['inside_frames'][2] + r['inside_frames'][3] + r['inside_frames'][4]) * 10 \
                        + r['inside_frames'][1] * 2 + r['float_frames'] * 2
                    sc = bad + pen + rm * 200 + max(0, r['inside_depth'][1] - 0.004) * 2000
                    out.append((sc, [round(float(x), 3) for x in off], [round(float(x), 4) for x in u], round(rm, 4), ht, st, tf, r))
    out.sort(key=lambda o: o[0])
    for o in out[:10]:
        print(round(o[0], 2), 'off', o[1], 'u', o[2], 'rim-lip %.3f' % o[3], 'hold %.1f sip %.1f tf %.2f' % (o[4], o[5], o[6]), json.dumps(o[7]))
    if len(sys.argv) > 2:
        json.dump({'clip': d['clip'], 'sip_t': frames[sip]['t'],
                   'top': [{'score': o[0], 'offset': o[1], 'axis': o[2], 'rim_lip_m': o[3], 'hold_tilt_deg': o[4],
                            'sip_tilt_deg': o[5], 'toward_face': o[6], 'result': o[7]} for o in out[:20]]},
                  open(sys.argv[2], 'w', encoding='utf-8'), indent=1)


main()
