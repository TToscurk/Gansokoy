#!/usr/bin/env python3
"""validate_animation — Godot 動畫真值記錄（godot_motion.v1）＋錄影的驗證工具。CPU only。

兩種用法：
  1) 錄製＋驗證：
     python tools/video_intel/validate_animation.py --scene res://characters/yoriichi/v24_isshin/isshin_slash_demo.tscn \
         --output D:/research/video_intel_poc/p1/run1 --scene-args "--tour --no-audio" [--proj-check] [--cam-sweep 40,2,6]
  2) 對既有資料重新驗證：
     python tools/video_intel/validate_animation.py --input D:/research/video_intel_poc/p1/run1 [--baseline-slog X.json]

輸出（寫到資料夾內）：report.json（機器可讀）、report.md（人看）、review_sheet.png（ART_REVIEW 用）。
判定：PASS＝有證據通過；FAIL＝驗證失敗；UNVERIFIED＝缺必要證據（絕不當 PASS）；ART_REVIEW＝需要人工看圖。
exit code：0＝沒有 FAIL；1＝有 FAIL；2＝工具本身無法執行（找不到資料、Godot、ffmpeg）。
資料結構說明：tools/video_intel/SCHEMA.md
"""
import argparse, json, math, os, shlex, subprocess, sys, time
from pathlib import Path

try:
    import numpy as np
except ImportError:
    sys.exit("validate_animation: needs numpy (venv: D:/Tools/video_intel/venv/Scripts/python.exe)")

TOOL_VERSION = "0.1.0"
REPO = Path(__file__).resolve().parents[2]
GODOT_PROJECT = REPO / "godot"
DEFAULT_GODOT = "D:/Godot/Godot_v4.7.2-stable_win64_console.exe"
PASS, FAIL, UNVERIFIED, ART = "PASS", "FAIL", "UNVERIFIED", "ART_REVIEW"


# ------------------------------------------------------------------ helpers
def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, **kw)


def load_jsonl(p):
    out = []
    with open(p, encoding="utf-8") as f:
        for ln in f:
            ln = ln.strip()
            if ln:
                out.append(json.loads(ln))
    return out


def arr(rows, getter, dim=None):
    vals = []
    for r in rows:
        try:
            v = getter(r)
        except (KeyError, TypeError, IndexError):
            v = None
        vals.append(v)
    if dim is None:
        return np.array([np.nan if v is None else float(v) for v in vals])
    return np.array([[np.nan] * dim if v is None else v for v in vals], float)


def stat(x):
    x = np.asarray(x, float)
    x = x[np.isfinite(x)]
    if x.size == 0:
        return None
    return {"n": int(x.size), "min": round(float(x.min()), 6), "median": round(float(np.median(x)), 6),
            "p95": round(float(np.percentile(x, 95)), 6), "max": round(float(x.max()), 6)}


class Report:
    def __init__(self):
        self.checks = []

    def add(self, cid, status, summary, evidence=None, note=""):
        self.checks.append({"id": cid, "status": status, "summary": summary, "evidence": evidence or {}, "note": note})

    def counts(self):
        c = {}
        for k in self.checks:
            c[k["status"]] = c.get(k["status"], 0) + 1
        return c


# ------------------------------------------------------------------ video
def ffprobe(video):
    r = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
             "stream=codec_name,width,height,r_frame_rate,avg_frame_rate,nb_frames", "-of", "json", str(video)])
    if r.returncode != 0:
        return None
    s = json.loads(r.stdout)["streams"][0]
    num, den = s["r_frame_rate"].split("/")
    s["fps"] = float(num) / float(den)
    # packet pts：抓重複時間戳
    r2 = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "packet=pts_time", "-of", "csv=p=0", str(video)])
    pts = [float(x) for x in r2.stdout.decode().split() if x.strip() not in ("", "N/A")]
    s["packet_pts"] = pts
    return s


def read_frames(video, w, h, crop=None, pix="gray"):
    """yield numpy frames (h, w[, 3]) streaming from ffmpeg"""
    vf = []
    if crop:
        cw, ch, cx, cy = crop
        vf = ["-vf", f"crop={cw}:{ch}:{cx}:{cy}"]
        w, h = cw, ch
    ch_n = 1 if pix == "gray" else 3
    cmd = ["ffmpeg", "-v", "error", "-i", str(video), *vf, "-f", "rawvideo", "-pix_fmt", "gray" if pix == "gray" else "rgb24", "-"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    size = w * h * ch_n
    while True:
        buf = p.stdout.read(size)
        if len(buf) < size:
            break
        a = np.frombuffer(buf, np.uint8)
        yield a.reshape(h, w) if ch_n == 1 else a.reshape(h, w, 3)
    p.wait()


def marker_decode_frame(img, meta_marker, scale):
    x0, y0, mw, mh = meta_marker["rect_px"]
    cell = meta_marker["cell_px"]
    cols = meta_marker["cols"]
    nbits = meta_marker["bits"]
    bits = []
    for i in range(nbits):
        cx = (x0 + (i % cols + 0.5) * cell) * scale[0]
        cy = (y0 + (i // cols + 0.5) * cell) * scale[1]
        r = max(1, int(cell * 0.25 * min(scale)))
        patch = img[int(cy) - r:int(cy) + r + 1, int(cx) - r:int(cx) + r + 1]
        bits.append(1 if patch.mean() > 127 else 0)
    if bits[:4] != [1, 0, 1, 1]:
        return None
    v = 0
    for b in bits[4:28]:
        v = (v << 1) | b
    chk = 0
    for b in bits[28:32]:
        chk = (chk << 1) | b
    x = 0
    for k in range(6):
        x ^= (v >> (4 * k)) & 15
    return v if x == chk else None


# ------------------------------------------------------------------ projection
def mat_view(cam):
    c = cam["view_xform"]
    M = np.eye(4)
    M[:3, 0], M[:3, 1], M[:3, 2], M[:3, 3] = c[0], c[1], c[2], c[3]
    return M


def mat_proj(cam):
    return np.array(cam["projection_cols"], float).T  # columns -> matrix


def project(cam, p, W, H):
    v = mat_proj(cam) @ (mat_view(cam) @ np.array([p[0], p[1], p[2], 1.0]))
    if v[3] <= 1e-9:
        return None
    ndc = v[:3] / v[3]
    return np.array([(ndc[0] * 0.5 + 0.5) * W, (1.0 - (ndc[1] * 0.5 + 0.5)) * H])


def blob_centroid(mask, c, rad):
    h, w = mask.shape
    x0, x1 = int(max(0, c[0] - rad)), int(min(w, c[0] + rad + 1))
    y0, y1 = int(max(0, c[1] - rad)), int(min(h, c[1] + rad + 1))
    if x1 <= x0 or y1 <= y0:
        return None, 0
    sub = mask[y0:y1, x0:x1]
    ys, xs = np.nonzero(sub)
    if xs.size < 3:
        return None, int(xs.size)
    return np.array([xs.mean() + x0 + 0.5, ys.mean() + y0 + 0.5]), int(xs.size)


# ------------------------------------------------------------------ main validation
def validate(run_dir: Path, baseline_slog=None, make_sheet=True, baseline_log=None):
    t_start = time.time()
    rep = Report()
    meta_p, frames_p, events_p = run_dir / "meta.json", run_dir / "frames.jsonl", run_dir / "events.jsonl"
    if not meta_p.exists() or not frames_p.exists():
        raise FileNotFoundError(f"{run_dir}: meta.json / frames.jsonl missing")
    meta = json.load(open(meta_p, encoding="utf-8"))
    rows = load_jsonl(frames_p)
    events = load_jsonl(events_p) if events_p.exists() else []
    video = run_dir / "video.avi"
    fps_nominal, fps_source = None, None
    rc_p = run_dir / "record_cmd.json"
    for src, cl in (("meta.cmdline", meta.get("cmdline", [])), ("record_cmd.json", json.load(open(rc_p, encoding="utf-8")).get("cmd", []) if rc_p.exists() else [])):
        for i, a in enumerate(cl):
            if a == "--fixed-fps" and fps_nominal is None:
                fps_nominal, fps_source = float(cl[i + 1]), src
    if fps_nominal is None and rows:
        d = float(np.median([r["delta"] for r in rows[1:]]))
        fps_nominal, fps_source = round(1.0 / d, 6), "derived from median delta (Godot does not expose --fixed-fps to scripts)"
    out = {"tool": "validate_animation", "tool_version": TOOL_VERSION, "run_dir": str(run_dir), "schema": meta.get("schema"),
           "target_scene": meta.get("target_scene"), "rows": len(rows), "events": len(events), "fps_nominal": fps_nominal, "fps_source": fps_source}

    # 1. integrity ---------------------------------------------------
    req = ["id", "frame_drawn", "physics_frame", "t_usec", "delta", "camera", "viewport", "sword", "bones_p_w", "controller", "freeze"]
    missing = {k: sum(1 for r in rows if r.get(k) is None) for k in req}
    missing = {k: v for k, v in missing.items() if v}
    ok_final = meta.get("final") is True and meta.get("rows") == len(rows)
    nonfinite = 0
    for r in rows[:: max(1, len(rows) // 200)]:
        for v in (r.get("bones_p_w") or []):
            if not all(math.isfinite(x) for x in v):
                nonfinite += 1
    st = PASS if ok_final and not missing and nonfinite == 0 else FAIL
    rep.add("data_integrity", st, f"{len(rows)} rows, meta.final={meta.get('final')}, meta.rows={meta.get('rows')}",
            {"rows_missing_field": missing, "nonfinite_bone_samples": nonfinite, "unavailable": meta.get("unavailable", {})},
            "unavailable 欄位依賴的檢查會標 UNVERIFIED")

    # 2. sequence -----------------------------------------------------
    ids = np.array([r["id"] for r in rows])
    fd = np.array([r["frame_drawn"] for r in rows])
    pf = np.array([r["physics_frame"] for r in rows])
    tu = np.array([r["t_usec"] for r in rows])
    dl = np.array([r["delta"] for r in rows])
    psteps = [r.get("physics_steps_since_prev") for r in rows]
    gaps_id = int(np.sum(np.diff(ids) != 1))
    gaps_fd = int(np.sum(np.diff(fd) != 1))
    mono = bool(np.all(np.diff(tu) > 0))
    ph = {}
    for s in psteps[1:]:
        ph[str(s)] = ph.get(str(s), 0) + 1
    dstat = stat(dl[1:])
    delta_ok = fps_nominal is not None and dstat is not None and abs(dstat["max"] - 1 / fps_nominal) < 1e-6 and abs(dstat["min"] - 1 / fps_nominal) < 1e-6
    st = PASS if gaps_id == 0 and gaps_fd == 0 and mono and delta_ok and meta.get("duplicate_pre_draw", 0) == 0 else FAIL
    rep.add("frame_sequence", st, f"id gaps {gaps_id}, frame_drawn gaps {gaps_fd}, t_usec monotonic {mono}, delta {dstat}",
            {"id_range": [int(ids[0]), int(ids[-1])], "frame_drawn_minus_id": sorted(set((fd - ids).tolist()))[:5],
             "physics_steps_per_render_frame_hist": ph, "duplicate_pre_draw": meta.get("duplicate_pre_draw"),
             "physics_ticks_per_second": meta.get("physics_ticks_per_second"), "fixed_fps": fps_nominal,
             "wall_ms_per_frame": stat(np.diff(tu) / 1000.0)})

    # 3. coordinate sanity ---------------------------------------------
    dets, orth, pmis = [], [], []
    for r in rows:
        c = r.get("camera")
        if not c:
            continue
        B = np.array(c["basis_w"], float).T
        dets.append(np.linalg.det(B))
        orth.append(float(np.abs(B.T @ B - np.eye(3)).max()))
        P = mat_proj(c)
        W, H = c["viewport_px"]
        f = 1.0 / math.tan(math.radians(c["fov_deg"]) / 2)
        if c.get("keep_aspect", 1) == 1:   # KEEP_HEIGHT
            exp_x, exp_y = f * H / W, f
        else:
            exp_x, exp_y = f, f * W / H
        pmis.append(max(abs(P[0, 0] - exp_x), abs(P[1, 1] - exp_y)))
    blen = arr(rows, lambda r: r["sword"]["blade_len_m"])
    names = meta.get("main_bones", [])
    seg = [("LeftUpLeg", "LeftLeg"), ("LeftLeg", "LeftFoot"), ("RightUpLeg", "RightLeg"), ("RightLeg", "RightFoot"),
           ("RightArm", "RightForeArm"), ("RightForeArm", "RightHand"), ("LeftArm", "LeftForeArm"), ("LeftForeArm", "LeftHand")]
    ix = {n.replace("mixamorig_", ""): i for i, n in enumerate(names)}
    seg_std = {}
    BP = np.array([r["bones_p_w"] for r in rows], float) if rows and rows[0].get("bones_p_w") else None
    if BP is not None:
        for a, b in seg:
            if a in ix and b in ix:
                L = np.linalg.norm(BP[:, ix[a]] - BP[:, ix[b]], axis=1)
                seg_std[f"{a}-{b}"] = {"mean_m": round(float(L.mean()), 4), "std_mm": round(float(L.std() * 1000), 3), "max_dev_mm": round(float(np.abs(L - L.mean()).max() * 1000), 3)}
    bmax = float(np.nanmax(np.abs(BP))) if BP is not None else None
    ok = (dets and abs(min(dets) - 1) < 1e-3 and abs(max(dets) - 1) < 1e-3 and max(orth) < 1e-3 and max(pmis) < 1e-4
          and np.nanstd(blen) < 1e-4 and bmax is not None and bmax < 500)
    rep.add("coordinates", PASS if ok else FAIL,
            "camera basis orthonormal, projection matches fov/aspect, blade length rigid, bone positions finite & bounded",
            {"camera_det": stat(dets), "camera_orthonormal_err": stat(orth), "projection_vs_fov_err": stat(pmis),
             "blade_len_m": stat(blen), "blade_len_std_m": float(np.nanstd(blen)), "limb_segment_lengths": seg_std, "max_abs_bone_coord_m": bmax},
            "肢段長度只是參考（雙骨 IK 不保證固定長度，鎖骨／手掌 IK 可能拉伸）；不列入判定")

    # 4. blade tip source ----------------------------------------------
    geo = meta.get("blade_geometry", {})
    tip_local = np.array(geo.get("tip_local") or [np.nan] * 3)
    legacy = np.array(meta.get("legacy_tip_local_in_demos", [0, 1.085, 0]))
    tipw = arr(rows, lambda r: r["sword"]["blade_tip_w"], 3)
    hiltw = arr(rows, lambda r: r["sword"]["hilt_w"], 3)
    orgw = arr(rows, lambda r: r["sword"]["node_origin_w"], 3)
    d_tip_org = np.linalg.norm(tipw - orgw, axis=1)
    d_tip_hilt = np.linalg.norm(tipw - hiltw, axis=1)
    ev = {"method": geo.get("method"), "mesh_path": geo.get("mesh_path"), "vertex_count": geo.get("vertex_count"),
          "tip_local_mesh": geo.get("tip_local"), "tip_cluster_verts_within_5mm": geo.get("tip_cluster"),
          "guard_local_mesh": geo.get("guard_local"), "hilt_local_mesh": geo.get("hilt_local"),
          "legacy_TIP_LOCAL": legacy.tolist(), "legacy_minus_true_tip_mesh_local_m": round(float(np.linalg.norm(legacy - tip_local)), 4),
          "tip_to_sword_node_origin_m": stat(d_tip_org), "tip_to_hilt_m": stat(d_tip_hilt)}
    ok = geo.get("ok") and (geo.get("tip_cluster") or 0) > 1 and np.nanmin(d_tip_hilt) > 0.3
    rep.add("blade_tip_source", PASS if ok else FAIL,
            "blade tip = mesh vertex extremum along the blade axis (not the Sword_Hand origin, not a fixed offset)", ev)

    # 4b. legacy slog cross-check (same frames, legacy TIP_LOCAL point) --------------
    slog_p = run_dir / "legacy_slog.json"
    if slog_p.exists():
        S = json.load(open(slog_p, encoding="utf-8"))
        L = S["rows"]
        # align: legacy row j ~ recorder row j+off where controller shot_t and actor x/z match exactly
        rs = [(r["controller"] or {}).get("shot_t") for r in rows]
        best = None
        for off in range(0, min(240, len(rows) - len(L) + 1) if len(rows) >= len(L) else 1):
            m = sum(1 for j in range(0, len(L), 7) if rs[j + off] is not None and abs(round(rs[j + off], 4) - L[j]["shot_t"]) < 1.5e-4)
            if best is None or m > best[1]:
                best = (off, m)
        off = best[0]
        n_checked = len(range(0, len(L), 7))
        # legacy tip_l is actor-local of the TIP_LOCAL point; compute true tip in actor-local for the same rows
        dd = []
        for j in range(len(L)):
            r = rows[j + off]
            a = r.get("actor")
            if not a or not r["sword"].get("blade_tip_w"):
                continue
            q = np.array(a["quat_w"])
            Rm = quat_mat(q)
            loc = Rm.T @ (np.array(r["sword"]["blade_tip_w"]) - np.array(a["pos_w"]))
            dd.append(np.linalg.norm(loc - np.array(L[j]["tip_l"])))
        dd = np.array(dd)
        st = PASS if best[1] == n_checked else FAIL
        rep.add("legacy_log_alignment", st,
                f"demo's own slashlog row j == recorder row j+{off} (shot_t match {best[1]}/{n_checked} sampled rows)",
                {"row_offset": off, "legacy_TIP_LOCAL_point_vs_true_tip_m": stat(dd),
                 "legacy_hitstop_frames_total": S.get("hitstop_frames_total"), "legacy_rows_with_hitstop_gt0": sum(1 for x in L if x["hitstop"] > 0)},
                "舊 slashlog 的 tip_speed／tip_l 用固定偏移 TIP_LOCAL；與真刀尖的距離見 evidence")
        out["legacy_row_offset"] = off

    # 5. hitstop accounting ----------------------------------------------
    hits = [e for e in events if e.get("kind") == "hit_landed"]
    ctrl = [r.get("controller") or {} for r in rows]
    hl = np.array([c.get("hitstop_left") if c.get("hitstop_left") is not None else -1 for c in ctrl])
    ht = np.array([c.get("hitstop_total") if c.get("hitstop_total") is not None else -1 for c in ctrl])
    fz = [r["freeze"] for r in rows]
    cfg = ctrl[-1].get("hitstop_frames_cfg") if ctrl else None
    per_hit = []
    id2row = {r["id"]: i for i, r in enumerate(rows)}
    total_ts0 = total_cnt = total_pose = 0
    for h in hits:
        i = id2row.get(h["id"])
        if i is None:
            continue
        win = []
        for k in range(-1, (cfg or 3) + 3):
            j = i + k
            if 0 <= j < len(rows):
                r = rows[j]
                win.append({"rel": k, "id": r["id"], "hitstop_left": hl[j], "anim_time_scale_zero": fz[j]["anim_time_scale_zero"],
                            "shot_t_unchanged": fz[j]["shot_t_unchanged"], "main_delta_mm": round((r.get("main_delta_max_m") or 0) * 1000, 3),
                            "secondary_delta_mm": round((r.get("secondary_delta_max_m") or 0) * 1000, 2),
                            "tip_speed": None if r["sword"].get("blade_tip_speed") is None else round(r["sword"]["blade_tip_speed"], 2)})
        n_ts0 = sum(1 for w in win if w["anim_time_scale_zero"])
        n_cnt = sum(1 for w in win if w["hitstop_left"] > 0)
        n_pose = sum(1 for w in win if w["main_delta_mm"] < 0.5)
        n_same = sum(1 for w in win if w["shot_t_unchanged"])
        total_ts0 += n_ts0; total_cnt += n_cnt; total_pose += n_pose
        per_hit.append({"hit_id": h["id"], "key": h.get("info", {}).get("key"), "strike": h.get("info", {}).get("strike"),
                        "frames_anim_time_scale_zero": n_ts0, "frames_counter_gt0": n_cnt, "frames_shot_t_unchanged": n_same,
                        "frames_main_pose_frozen": n_pose, "window": win})
    tot_delta = int(ht[-1] - ht[0]) if ht.size and ht[0] >= 0 else None
    consistent = all(p["frames_anim_time_scale_zero"] == cfg and p["frames_shot_t_unchanged"] >= cfg for p in per_hit) and tot_delta == cfg * len(per_hit) if cfg else False
    expl = ("hitstop_total（控制器累計）＝每次命中 hitstop_frames 格；freeze_hit_frame 的招式在命中那一格就凍結並先計 1，"
            "之後 hitstop_left 從 cfg-1 倒數，取樣時已遞減，所以「hitstop_left>0 的列」每次只有 cfg-1 格。"
            "以『動畫時間縮放=0』與『shot_t 不前進』計，每次命中應為 cfg 格。")
    if not hits:
        rep.add("hitstop_accounting", UNVERIFIED, "no hit_landed events in this run")
    else:
        rep.add("hitstop_accounting", PASS if consistent else FAIL,
                f"{len(hits)} hits; cfg {cfg} frames/hit; controller total +{tot_delta}; time-scale-zero frames {total_ts0}; counter>0 rows {total_cnt}; main-pose-frozen frames {total_pose}",
                {"per_hit": per_hit}, expl)
        sec = [w["secondary_delta_mm"] for p in per_hit for w in p["window"] if w["anim_time_scale_zero"]]
        sec_zero = sum(1 for x in sec if x == 0.0)
        en_moves = []
        for p in per_hit:
            for w in p["window"]:
                if w["anim_time_scale_zero"]:
                    j = id2row[w["id"]]
                    if j > 0 and rows[j].get("others") and rows[j - 1].get("others"):
                        en_moves.append(float(np.linalg.norm(np.array(rows[j]["others"]["enemy_child0_local"] or [0, 0, 0]) - np.array(rows[j - 1]["others"]["enemy_child0_local"] or [0, 0, 0]))) * 1000)
        rep.add("hitstop_secondary_motion", ART if sec else UNVERIFIED,
                f"during {len(sec)} animation-frozen frames: spring bones (cloth/hair) moved 0.0 mm in {sec_zero}; target dummy offset moved {stat(en_moves)} mm",
                {"secondary_delta_mm": stat(sec), "frames_secondary_exactly_zero": sec_zero, "dummy_offset_delta_mm": stat(en_moves),
                 "particles": "UNVERIFIED — no particle data recorded"},
                ("實測：停格時布料／頭髮彈簧骨也停住（位移 0.0 mm），與 combat_locomotion.gd 註解「布料／頭髮／IK 仍照常算」不符；"
                 "原因未查證（推測 Skeleton3D 在骨架姿勢不變時沒有跑彈簧骨修改器）。是否要讓布料在停格中繼續動，屬於設計／美術判斷。")
                if sec and sec_zero == len(sec) else
                ("實測：停格時布料／頭髮彈簧骨仍在動。" if sec_zero == 0 else f"實測：{sec_zero}/{len(sec)} 個停格格的彈簧骨位移為 0，其餘仍在動。"))

    # 6. video sync --------------------------------------------------------
    vinfo = ffprobe(video) if video.exists() else None
    mk = meta.get("marker", {})
    if vinfo is None:
        rep.add("video_sync", UNVERIFIED, "no video.avi in run dir (or ffprobe failed)")
    elif not mk.get("enabled"):
        rep.add("video_sync", UNVERIFIED, "sync marker disabled in this run")
    else:
        W, H = int(vinfo["width"]), int(vinfo["height"])
        vw, vh = meta["viewport_size"]
        scale = (W / vw, H / vh)
        x0, y0, mw, mh = mk["rect_px"]
        crop = (int((x0 + mw) * scale[0]) + 4, int((y0 + mh) * scale[1]) + 4, 0, 0)
        # crop from top-left of the marker region: use x 0..x0+mw, y y0..y0+mh (shift coordinates)
        cy0 = int(y0 * scale[1]) - 4
        crop = (int((x0 + mw) * scale[0]) + 4, int(mh * scale[1]) + 8, 0, cy0)
        mkc = dict(mk); mkc["rect_px"] = [x0, y0 - cy0 / scale[1], mw, mh]
        dec = [marker_decode_frame(img, mkc, scale) for img in read_frames(video, W, H, crop=crop)]
        nv = len(dec)
        unread = [k for k, v in enumerate(dec) if v is None]
        vals = [v for v in dec if v is not None]
        dups = [k for k in range(1, nv) if dec[k] is not None and dec[k] == dec[k - 1]]
        drops = []
        for k in range(1, nv):
            if dec[k] is not None and dec[k - 1] is not None and dec[k] - dec[k - 1] > 1:
                drops.append({"video_frame": k, "from_id": dec[k - 1], "to_id": dec[k]})
        offs = sorted(set(v - k for k, v in enumerate(dec) if v is not None))
        rowids = set(int(i) for i in ids)
        not_in_log = [v for v in vals if v not in rowids]
        pts = vinfo["packet_pts"]
        dpts = np.diff(pts) if len(pts) > 1 else np.array([])
        res_ok = (W, H) == (int(vw), int(vh))
        fps_ok = fps_nominal is not None and abs(vinfo["fps"] - fps_nominal) < 1e-6
        ok = not unread and not dups and not drops and len(offs) == 1 and not not_in_log and res_ok and fps_ok
        rep.add("video_sync", PASS if ok else FAIL,
                f"{nv} video frames decoded; id = video_frame + {offs[0] if len(offs) == 1 else offs}; unreadable {len(unread)}, duplicates {len(dups)}, drops {len(drops)}",
                {"video": {"codec": vinfo["codec_name"], "size": [W, H], "fps": vinfo["fps"], "nb_frames": vinfo.get("nb_frames"),
                           "packet_pts_step": stat(dpts)}, "viewport_size": [vw, vh], "resolution_match": res_ok, "fps_match": fps_ok,
                 "id_minus_video_frame": offs[:10], "unreadable_frames": unread[:20], "duplicate_frames": dups[:20], "drops": drops[:20],
                 "ids_not_in_log": not_in_log[:20], "log_rows_without_video_frame": len(rowids - set(vals)),
                 "first_video_frames": dec[:3]})
        out["video_frame_to_id"] = dec

    # 7. projection --------------------------------------------------------
    pts_w = meta.get("proj_points_w") or []
    if vinfo is None or not (pts_w or meta.get("proj_tip_marker")):
        rep.add("camera_projection", UNVERIFIED, "no projection-check markers in this run (use --proj-check)")
    else:
        W, H = int(vinfo["width"]), int(vinfo["height"])
        dec = out.get("video_frame_to_id") or []
        errs_s, errs_t, miss_s, miss_t, godot_math = [], [], 0, 0, []
        out_view = 0
        overlap = 0
        miss_list = []
        under_marker = 0
        mr = meta.get("marker", {}).get("rect_px") if meta.get("marker", {}).get("enabled") else None
        vsz = meta.get("viewport_size") or [W, H]
        def in_marker(q, m=12):
            if not mr:
                return False
            x0, y0, mw, mh = mr[0] * W / vsz[0], mr[1] * H / vsz[1], mr[2] * W / vsz[0], mr[3] * H / vsz[1]
            return x0 - m <= q[0] <= x0 + mw + m and y0 - m <= q[1] <= y0 + mh + m
        EDGE = 15
        cam_move = []
        prev_cam = None
        per_frame = []
        for k, img in enumerate(read_frames(video, W, H, pix="rgb")):
            if k >= len(dec) or dec[k] is None or dec[k] not in id2row:
                continue
            r = rows[id2row[dec[k]]]
            c = r.get("camera")
            if not c:
                continue
            R, G, B = img[..., 0].astype(int), img[..., 1].astype(int), img[..., 2].astype(int)
            mag = (R > 170) & (B > 170) & (G < 110)
            grn = (G > 170) & (R < 110) & (B < 110)
            sx, sy = W / c["viewport_px"][0], H / c["viewport_px"][1]
            proj_all = [project(c, p, *c["viewport_px"]) for p in pts_w]
            proj_all = [None if q is None else q * [sx, sy] for q in proj_all]
            for pi_, pp in enumerate(proj_all):
                if pp is None:
                    out_view += 1
                    continue
                if not (EDGE <= pp[0] < W - EDGE and EDGE <= pp[1] < H - EDGE):
                    out_view += 1          # 投影在畫面外或貼邊（小球被裁切，質心會偏）→不計
                    continue
                if in_marker(pp):
                    under_marker += 1      # 被 2D 同步標記蓋住（CanvasLayer 畫在 3D 之上）→不計
                    continue
                near = [float(np.linalg.norm(pp - q)) for j, q in enumerate(proj_all) if j != pi_ and q is not None]
                rad = min(25.0, 0.45 * min(near)) if near else 25.0
                if rad < 6.0:
                    overlap += 1           # 兩顆同色小球在畫面上太近，無法分辨是哪一顆 → 不計
                    continue
                tw0 = r["sword"].get("blade_tip_px_godot") if (r.get("sword") and meta.get("proj_tip_marker")) else None
                if tw0 is not None and float(np.linalg.norm(pp - np.array(tw0) * [sx, sy])) < 15.0:
                    overlap += 1           # 被刀尖綠球蓋住（兩種小球都不做深度測試，重疊時無法量）→ 不計
                    continue
                cen, n = blob_centroid(mag, pp, rad)
                if cen is None:
                    miss_s += 1
                    if len(miss_list) < 20:
                        miss_list.append({"video_frame": k, "id": r["id"], "point": pi_, "px": [round(float(pp[0]), 1), round(float(pp[1]), 1)]})
                else:
                    errs_s.append(float(np.linalg.norm(cen - pp)))
            tw = r["sword"].get("blade_tip_w") if r.get("sword") else None
            if tw and meta.get("proj_tip_marker"):
                pp = project(c, tw, *c["viewport_px"])
                gp = r["sword"].get("blade_tip_px_godot")
                if pp is not None and gp:
                    godot_math.append(float(np.linalg.norm(pp - np.array(gp))))
                if pp is not None:
                    pp = pp * [sx, sy]
                    if not (EDGE <= pp[0] < W - EDGE and EDGE <= pp[1] < H - EDGE):
                        out_view += 1
                        pp = None
                    elif in_marker(pp):
                        under_marker += 1
                        pp = None
                if pp is not None:
                    cen, n = blob_centroid(grn, pp, 25)
                    if cen is None:
                        miss_t += 1
                    else:
                        e = float(np.linalg.norm(cen - pp))
                        errs_t.append(e)
                        per_frame.append((r["id"], e))
            cp = np.array(c["pos_w"])
            if prev_cam is not None:
                cam_move.append(float(np.linalg.norm(cp - prev_cam)))
            prev_cam = cp
        ss, stt = stat(errs_s), stat(errs_t)
        ok = ss and stt and ss["p95"] <= 2.0 and stt["p95"] <= 2.5 and miss_s == 0 and (stat(godot_math) or {}).get("max", 9) < 0.01
        rep.add("camera_projection", PASS if ok else FAIL,
                f"static markers err px {ss}; blade-tip marker err px {stt}; misses static {miss_s} / tip {miss_t}",
                {"static_err_px": ss, "tip_err_px": stt, "missed_static": miss_s, "missed_tip": miss_t, "skipped_out_of_view_or_edge": out_view, "skipped_ambiguous_overlap": overlap, "skipped_under_sync_marker": under_marker, "missed_static_list": miss_list,
                 "own_matrix_vs_godot_unproject_px": stat(godot_math), "camera_step_m": stat(cam_move),
                 "worst_tip_frames": sorted(per_frame, key=lambda x: -x[1])[:5]},
                "投影＝記錄的 projection_cols × view_xform；與影片中不受深度遮擋的小球質心比較")

    # 8. motion analysis -----------------------------------------------------
    sp = arr(rows, lambda r: r["sword"]["blade_tip_speed"])
    apos = arr(rows, lambda r: r["actor"]["pos_w"], 3)
    dt = dl
    av = np.r_[np.nan, np.linalg.norm(np.diff(apos[:, [0, 2]], axis=0), axis=1) / dt[1:]]
    shot = np.array([np.nan if (c.get("shot_t") is None) else c["shot_t"] for c in ctrl])
    keys = [c.get("shot_key") or "" for c in ctrl]
    rate = np.r_[np.nan, np.diff(shot) / dt[1:]]
    segs = []
    k0 = 0
    for i in range(1, len(rows) + 1):
        if i == len(rows) or keys[i] != keys[k0] or (ctrl[i].get("state_name") != ctrl[k0].get("state_name")):
            if ctrl[k0].get("state_name") == "SHOT":
                rr = rate[k0 + 1:i]
                rr = rr[np.isfinite(rr)]
                segs.append({"key": keys[k0], "id_from": rows[k0]["id"], "id_to": rows[i - 1]["id"], "frames": i - k0,
                             "tip_speed_max": round(float(np.nanmax(sp[k0:i])), 2) if np.isfinite(sp[k0:i]).any() else None,
                             "tip_speed_max_id": int(rows[k0 + int(np.nanargmax(sp[k0:i]))]["id"]) if np.isfinite(sp[k0:i]).any() else None,
                             "root_travel_m": round(float(np.linalg.norm(apos[i - 1, [0, 2]] - apos[k0, [0, 2]])), 3),
                             "anim_rate_hist": {str(round(float(x), 3)): int(np.sum(np.isclose(rr, x))) for x in sorted(set(np.round(rr, 3)))}})
            k0 = i
    feet = {}
    for side in ("Left", "Right"):
        con = [((r.get("feet") or {}).get(side) or {}).get("contact") for r in rows]
        toe = arr(rows, lambda r: r["feet"][side]["toe_w"], 3)
        slides, run_start = [], None
        for i, c in enumerate(con + [False]):
            if c and run_start is None:
                run_start = i
            elif not c and run_start is not None:
                if i - run_start >= 3:
                    d = toe[run_start:i, [0, 2]]
                    slides.append(float(np.linalg.norm(d[-1] - d[0]) * 100))
                run_start = None
        feet[side] = {"contact_frames": int(sum(1 for c in con if c)), "contact_intervals": len(slides),
                      "slide_cm_per_interval": stat(slides)}
    out["motion"] = {"blade_tip_speed_mps": stat(sp), "root_speed_mps": stat(av),
                     "root_total_path_m": round(float(np.nansum(np.linalg.norm(np.diff(apos[:, [0, 2]], axis=0), axis=1))), 3),
                     "shots": segs, "feet": feet,
                     "anim_speed_events": [e for e in events if e.get("kind") == "anim_speed_change"][:50],
                     "hits": [{"id": h["id"], **{k: h.get("info", {}).get(k) for k in ("key", "strike", "shot_t", "tip_speed")}} for h in hits]}
    rep.add("motion_analysis", PASS if np.isfinite(sp).sum() > 0 else UNVERIFIED,
            f"tip speed {stat(sp)}; {len(segs)} shot segments; feet contact L {feet['Left']['contact_frames']} / R {feet['Right']['contact_frames']} frames",
            {}, "腳接觸＝運動學推定（腳趾高度＋水平速度門檻），不是物理接觸；滑步值只代表推定接觸期間的腳趾位移")

    # 9. behaviour unchanged ---------------------------------------------------
    if baseline_log:
        a_ = Path(baseline_log).read_bytes()
        b_p = run_dir / "legacy_log.bin"
        b_ = b_p.read_bytes() if b_p.exists() else b""
        st = PASS if a_ and a_ == b_ else FAIL
        rep.add("behaviour_unchanged", st, f"demo --log binary: baseline {len(a_)} bytes vs recorded-run {len(b_)} bytes; identical {a_ == b_}",
                {"baseline": str(baseline_log), "compared": "every float of the demo's own per-frame log (actor, enemy, sheath, Sword_Hand origin, 84 bones, appended blade columns)"})
    elif baseline_slog:
        A = json.load(open(baseline_slog, encoding="utf-8"))["rows"]
        Bs = json.load(open(slog_p, encoding="utf-8"))["rows"] if slog_p.exists() else []
        keys_cmp = ["t", "state", "shot_t", "hitstop", "tip_speed", "tip_l", "actor", "hp", "key", "dummy"]
        diff = [j for j in range(min(len(A), len(Bs))) if any(A[j].get(k) != Bs[j].get(k) for k in keys_cmp)]
        st = PASS if len(A) == len(Bs) and not diff else FAIL
        rep.add("behaviour_unchanged", st, f"baseline rows {len(A)} vs recorded-run rows {len(Bs)}; differing rows {len(diff)}",
                {"first_diff_rows": diff[:10], "compared_keys": keys_cmp, "baseline": str(baseline_slog)})
    else:
        rep.add("behaviour_unchanged", UNVERIFIED, "no --baseline-slog given (run the demo once without the recorder to compare)")

    # 10. ART_REVIEW sheet --------------------------------------------------------
    sheet = None
    if make_sheet and vinfo is not None and out.get("video_frame_to_id"):
        sheet = make_review_sheet(run_dir, video, vinfo, rows, id2row, out["video_frame_to_id"], hits, meta)
    rep.add("visual_review", ART if sheet else UNVERIFIED,
            "blade-tip / hilt overlay on hit frames — whether the overlay sits on the rendered tip and whether the motion looks right is a human call",
            {"sheet": sheet})

    out["checks"] = rep.checks
    out["status_counts"] = rep.counts()
    out["overall"] = FAIL if any(c["status"] == FAIL for c in rep.checks) else (UNVERIFIED if any(c["status"] == UNVERIFIED for c in rep.checks) else PASS)
    out["validate_seconds"] = round(time.time() - t_start, 1)
    vf = out.pop("video_frame_to_id", None)
    if vf is not None:
        with open(run_dir / "video_frame_map.json", "w", encoding="utf-8") as f:
            json.dump({"video_frame_to_recorder_id": vf}, f)
    json.dump(out, open(run_dir / "report.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=_np_default)
    write_md(run_dir / "report.md", out)
    return out


def _np_default(o):
    if isinstance(o, (np.integer,)):
        return int(o)
    if isinstance(o, (np.floating,)):
        return float(o)
    if isinstance(o, np.ndarray):
        return o.tolist()
    if isinstance(o, np.bool_):
        return bool(o)
    raise TypeError(type(o))


def quat_mat(q):
    x, y, z, w = q / np.linalg.norm(q)
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def make_review_sheet(run_dir, video, vinfo, rows, id2row, vmap, hits, meta):
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        return None
    W, H = int(vinfo["width"]), int(vinfo["height"])
    want_ids = []
    for h in hits[:6]:
        want_ids += [h["id"], h["id"] + 2]
    if not want_ids:
        want_ids = [rows[len(rows) * k // 8]["id"] for k in range(8)]
    want_ids = want_ids[:12]
    id2v = {v: k for k, v in enumerate(vmap) if v is not None}
    tiles = []
    wantv = {id2v[i]: i for i in want_ids if i in id2v}
    for k, img in enumerate(read_frames(video, W, H, pix="rgb")):
        if k not in wantv:
            continue
        rid = wantv[k]
        r = rows[id2row[rid]]
        im = Image.fromarray(img.copy())
        raw = im.copy()
        d = ImageDraw.Draw(im)
        c = r.get("camera")
        tip_xy = None
        for key, col in (("blade_tip_w", (0, 255, 0)), ("hilt_w", (255, 140, 0)), ("node_origin_w", (255, 0, 0))):
            p = r["sword"].get(key)
            if p and c:
                pp = project(c, p, *c["viewport_px"])
                if pp is not None:
                    x, y = pp[0] * W / c["viewport_px"][0], pp[1] * H / c["viewport_px"][1]
                    if key == "blade_tip_w":
                        tip_xy = (x, y)
                    # 十字中間留空，不蓋住投影小球
                    d.line([x - 14, y, x - 5, y], fill=col, width=2); d.line([x + 5, y, x + 14, y], fill=col, width=2)
                    d.line([x, y - 14, x, y - 5], fill=col, width=2); d.line([x, y + 5, x, y + 14], fill=col, width=2)
        if tip_xy:
            zx, zy = int(tip_xy[0]), int(tip_xy[1])
            z = raw.crop((zx - 60, zy - 60, zx + 60, zy + 60)).resize((240, 240), Image.NEAREST)
            im.paste(z, (W - 244, 24))
            d.rectangle([W - 245, 23, W - 3, 265], outline=(0, 255, 0))
        d.rectangle([0, 0, 330, 20], fill=(0, 0, 0))
        hs = (r.get("controller") or {}).get("hitstop_left")
        d.text((4, 4), f"id {rid} video {k} hs {hs} frozen {r['freeze']['anim_time_scale_zero']} tip {r['sword'].get('blade_tip_speed') or 0:.1f} m/s", fill=(255, 255, 255))
        tiles.append(im.resize((W // 2, H // 2)))
    if not tiles:
        return None
    cols = 3
    rows_n = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * W // 2, rows_n * H // 2 + 24), (20, 20, 20))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * W // 2, (i // cols) * H // 2 + 24))
    ImageDraw.Draw(sheet).text((6, 6), "green=blade_tip_w (mesh)  orange=hilt_w  red=Sword_Hand origin (old 'tip_x' column)", fill=(255, 255, 255))
    p = run_dir / "review_sheet.png"
    sheet.save(p)
    return str(p)


def write_md(p, out):
    L = [f"# validate_animation 報告", "", f"- 資料：`{out['run_dir']}`", f"- 場景：`{out.get('target_scene')}`",
         f"- schema：{out.get('schema')}　列數：{out['rows']}　事件：{out['events']}　fps：{out.get('fps_nominal')}",
         f"- **總判定：{out['overall']}**　{out['status_counts']}　（UNVERIFIED 不等於 PASS）", "", "| 檢查 | 判定 | 摘要 |", "|---|---|---|"]
    for c in out["checks"]:
        L.append(f"| {c['id']} | **{c['status']}** | {str(c['summary']).replace('|', '/')} |")
    L += ["", "## 說明與證據摘要", ""]
    for c in out["checks"]:
        L.append(f"### {c['id']} — {c['status']}")
        if c.get("note"):
            L.append(c["note"])
        ev = {k: v for k, v in c["evidence"].items() if k != "per_hit"}
        if ev:
            s = json.dumps(ev, ensure_ascii=False, default=_np_default)
            L.append("```json\n" + (s[:1800] + " …" if len(s) > 1800 else s) + "\n```")
        if "per_hit" in c["evidence"]:
            L.append("| 命中 id | 招式 | 第幾刀 | 時間縮放=0 | shot_t 不動 | 計數器>0 | 主骨凍結 |")
            L.append("|---|---|---|---|---|---|---|")
            for h in c["evidence"]["per_hit"]:
                L.append(f"| {h['hit_id']} | {h['key']} | {h['strike']} | {h['frames_anim_time_scale_zero']} | {h['frames_shot_t_unchanged']} | {h['frames_counter_gt0']} | {h['frames_main_pose_frozen']} |")
        L.append("")
    m = out.get("motion", {})
    if m:
        L += ["## 動作分析", "", f"- 刀尖速度 m/s：{m.get('blade_tip_speed_mps')}", f"- 根速度 m/s：{m.get('root_speed_mps')}　路徑 {m.get('root_total_path_m')} m", ""]
        L.append("| 招式 | id 範圍 | 格數 | 刀尖峰值 m/s | 峰值 id | 根位移 m | 動畫速率分布 |")
        L.append("|---|---|---|---|---|---|---|")
        for s in m.get("shots", []):
            L.append(f"| {s['key']} | {s['id_from']}–{s['id_to']} | {s['frames']} | {s['tip_speed_max']} | {s['tip_speed_max_id']} | {s['root_travel_m']} | {s['anim_rate_hist']} |")
        L.append("")
        L.append(f"- 腳：{json.dumps(m.get('feet'), ensure_ascii=False)}")
    open(p, "w", encoding="utf-8").write("\n".join(L) + "\n")


# ------------------------------------------------------------------ record mode
def godot_bin(explicit):
    g = explicit or os.environ.get("GODOT_BIN") or DEFAULT_GODOT
    r = run([g, "--version"])
    v = r.stdout.decode(errors="replace").strip()
    if r.returncode != 0 or not v.startswith("4.7.2"):
        raise RuntimeError(f"Godot 4.7.2 required, got {g!r}: {v!r}")
    return g, v


def record(scene, out_dir: Path, scene_args, proj_check, cam_sweep, godot, fps=60, no_marker=False):
    g, ver = godot_bin(godot)
    out_dir.mkdir(parents=True, exist_ok=True)
    for f in ("frames.jsonl", "events.jsonl", "meta.json", "video.avi", "report.json"):
        if (out_dir / f).exists():
            (out_dir / f).unlink()
    o = out_dir.as_posix()
    user = [f"--mc-target={scene}", f"--mc-out={o}"]
    if proj_check:
        user.append("--mc-proj-check")
    if cam_sweep:
        user.append(f"--mc-cam-sweep={cam_sweep}")
    if no_marker:
        user.append("--mc-no-marker")
    sa = shlex.split(scene_args or "")
    if "--slashlog=" not in " ".join(sa) and "isshin_slash_demo" in scene:
        sa.append(f"--slashlog={o}/legacy_slog.json")
    cmd = [g, "--path", str(GODOT_PROJECT), "--write-movie", f"{o}/video.avi", "--fixed-fps", str(fps),
           "res://tools/motion_capture/record_harness.tscn", "--", *user, *sa]
    t0 = time.time()
    with open(out_dir / "godot.log", "wb") as lf:
        rc = subprocess.run(cmd, stdout=lf, stderr=subprocess.STDOUT).returncode
    info = {"godot": g, "godot_version": ver, "cmd": cmd, "exit_code": rc, "wall_s": round(time.time() - t0, 1)}
    json.dump(info, open(out_dir / "record_cmd.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return info


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--scene", help="res:// path of the scene to record")
    ap.add_argument("--output", help="output directory for a new recording")
    ap.add_argument("--input", help="re-validate an existing recording directory")
    ap.add_argument("--scene-args", default="", help='arguments passed to the scene, e.g. "--tour --no-audio"')
    ap.add_argument("--proj-check", action="store_true", help="add depth-test-free projection markers (visual only)")
    ap.add_argument("--cam-sweep", default="", help="deg_per_s,start_s,end_s — rotate the scene camera (camera only)")
    ap.add_argument("--no-marker", action="store_true")
    ap.add_argument("--baseline-slog", help="slashlog from a run without the recorder, to prove unchanged behaviour")
    ap.add_argument("--baseline-log", help="isshin_combat_demo --log .bin from a run without the recorder (byte comparison)")
    ap.add_argument("--godot")
    ap.add_argument("--no-sheet", action="store_true")
    a = ap.parse_args()
    try:
        if a.scene:
            if not a.output:
                ap.error("--scene needs --output")
            info = record(a.scene, Path(a.output), a.scene_args, a.proj_check, a.cam_sweep, a.godot, no_marker=a.no_marker)
            print(f"recorded: exit {info['exit_code']} in {info['wall_s']} s")
            run_dir = Path(a.output)
        elif a.input:
            run_dir = Path(a.input)
        else:
            ap.error("need --scene/--output or --input")
        out = validate(run_dir, a.baseline_slog, not a.no_sheet, a.baseline_log)
    except (FileNotFoundError, RuntimeError) as e:
        print(f"validate_animation: ERROR {e}", file=sys.stderr)
        sys.exit(2)
    for c in out["checks"]:
        print(f"{c['status']:<11} {c['id']:<26} {c['summary']}")
    print(f"overall: {out['overall']}  {out['status_counts']}  report: {run_dir / 'report.md'}")
    sys.exit(1 if out["overall"] == FAIL else 0)


if __name__ == "__main__":
    main()
