#!/usr/bin/env python3
"""validate_animation 回歸測試（Phase 1）。依序錄製並驗證：
  B0  isshin_slash_demo 直接跑（無 recorder）→ 基準 slashlog（證明 recorder 不改行為）
  B1  isshin_combat_demo 直接跑（無 recorder）→ 基準 --log
  R1  slash demo + recorder + 投影小球：靜止、三刀連段、高速揮刀、命中停格、斬後左移
  R2  同 R1 + 相機旋轉（cam_yaw_extra 45°/s，2–14 s）
  R3  isshin_combat_demo --tour（一般移動、轉身、閃避）+ recorder + 舊 --log（驗證附加欄位、與 B1 逐位元相同）
  N1  反向案例：把 R1 影片刪掉一格、重複一格 → 驗證器必須抓到
usage: python tools/video_intel/run_regression.py --out D:/research/video_intel_poc/p1/regress [--only B0,B1,R1,...] [--skip-record]
"""
import argparse, json, subprocess, sys, time
from pathlib import Path
import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import validate_animation as va

SLASH = "res://characters/yoriichi/v24_isshin/isshin_slash_demo.tscn"
COMBAT = "res://characters/yoriichi/v24_isshin/isshin_combat_demo.tscn"


def baseline(out: Path, scene=None, extra=None):
    g, ver = va.godot_bin(None)
    out.mkdir(parents=True, exist_ok=True)
    o = out.as_posix()
    cmd = [g, "--path", str(va.GODOT_PROJECT), "--write-movie", f"{o}/video.avi", "--fixed-fps", "60", scene or SLASH, "--",
           *(extra if extra is not None else ["--tour", "--no-audio", f"--slashlog={o}/legacy_slog.json"])]
    t0 = time.time()
    with open(out / "godot.log", "wb") as lf:
        rc = subprocess.run(cmd, stdout=lf, stderr=subprocess.STDOUT).returncode
    json.dump({"cmd": cmd, "exit_code": rc, "wall_s": round(time.time() - t0, 1)}, open(out / "record_cmd.json", "w"), indent=1)
    return rc


def damage_video(src: Path, dst_dir: Path, drop=300, dup=500):
    """copy a run's data; rebuild the MJPEG video without frame `drop` and with frame `dup` doubled (JPEG payloads copied, no re-encode)"""
    dst_dir.mkdir(parents=True, exist_ok=True)
    for f in ("meta.json", "frames.jsonl", "events.jsonl", "record_cmd.json"):
        if (src / f).exists():
            (dst_dir / f).write_bytes((src / f).read_bytes())
    tmp = dst_dir / "frames_tmp"
    seqd = dst_dir / "frames_seq"
    tmp.mkdir(exist_ok=True)
    seqd.mkdir(exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(src / "video.avi"), "-c:v", "copy", "-f", "image2", str(tmp / "f_%05d.jpg")], check=True)
    files = sorted(tmp.glob("f_*.jpg"))
    seq = []
    for k, f in enumerate(files):
        if k == drop:
            continue
        seq.append(f)
        if k == dup:
            seq.append(f)
    for i, f in enumerate(seq):          # 依序重新編號，image2 以固定 60 fps 讀入（不經 concat 的時間換算）
        (seqd / f"s_{i:05d}.jpg").write_bytes(f.read_bytes())
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-framerate", "60", "-i", str(seqd / "s_%05d.jpg"), "-c:v", "copy",
                    str(dst_dir / "video.avi")], check=True)
    for d_ in (tmp, seqd):
        for f in d_.glob("*.jpg"):
            f.unlink()
        d_.rmdir()
    return {"dropped_video_frame": drop, "duplicated_video_frame": dup, "frames_in": len(files), "frames_out": len(seq)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="B0,B1,R1,R2,R3,N1")
    ap.add_argument("--skip-record", action="store_true")
    a = ap.parse_args()
    root = Path(a.out)
    only = a.only.split(",")
    summary = {}
    if "B0" in only and not a.skip_record:
        summary["B0"] = {"exit_code": baseline(root / "B0_baseline")}
    if "B1" in only and not a.skip_record:
        b1 = root / "B1_combat_baseline"
        summary["B1"] = {"exit_code": baseline(b1, COMBAT, ["--tour", f"--log={(b1 / 'legacy_log').as_posix()}"])}
    specs = {"R1": (SLASH, "--tour --no-audio", True, ""), "R2": (SLASH, "--tour --no-audio", True, "45,2,14"),
             "R3": (COMBAT, f"--tour --log={(root / 'R3_combat' / 'legacy_log').as_posix()}", True, "")}
    names = {"R1": "R1_slash", "R2": "R2_slash_camsweep", "R3": "R3_combat"}
    base = root / "B0_baseline" / "legacy_slog.json"
    for k in ("R1", "R2", "R3"):
        if k not in only:
            continue
        scene, args, proj, sweep = specs[k]
        d = root / names[k]
        if not a.skip_record:
            info = va.record(scene, d, args, proj, sweep, None)
            print(k, "recorded", info["exit_code"], info["wall_s"], "s", flush=True)
        b1log = root / "B1_combat_baseline" / "legacy_log.bin"
        r = va.validate(d, str(base) if (scene == SLASH and base.exists()) else None, True,
                        str(b1log) if (scene == COMBAT and b1log.exists()) else None)
        summary[k] = {"overall": r["overall"], "counts": r["status_counts"], "checks": {c["id"]: c["status"] for c in r["checks"]},
                      "validate_s": r["validate_seconds"]}
        print(k, r["overall"], summary[k]["checks"], flush=True)
    if "R3" in only:
        d = root / "R3_combat"
        m = json.load(open(d / "legacy_log.json", encoding="utf-8"))
        raw = np.fromfile(d / "legacy_log.bin", dtype=np.float32)[: m["rows"] * m["width"]].reshape(m["rows"], m["width"])
        ci = {c: i for i, c in enumerate(m["cols"])}
        ei = {c: m["extra_offset"] + i for i, c in enumerate(m["extra_cols"])}
        rows = va.load_jsonl(d / "frames.jsonl")
        lt = raw[:, [ei["blade_tip_x"], ei["blade_tip_y"], ei["blade_tip_z"]]]
        rt = np.array([r["sword"]["blade_tip_w"] for r in rows])
        org = np.array([r["sword"]["node_origin_w"] for r in rows])
        best = min(range(0, 200), key=lambda off: float(np.abs(rt[off:off + 200] - lt[:200]).max()))
        n = min(len(lt), len(rt) - best)
        e_tip = np.abs(rt[best:best + n] - lt[:n]).max()
        e_old = np.abs(org[best:best + n] - raw[:n, [ci["tip_x"], ci["tip_y"], ci["tip_z"]]]).max()
        dist_old_true = np.linalg.norm(raw[:n, [ci["tip_x"], ci["tip_y"], ci["tip_z"]]] - lt[:n], axis=1)
        b1 = root / "B1_combat_baseline" / "legacy_log.bin"
        same = None
        if b1.exists():
            braw = np.fromfile(b1, dtype=np.float32)
            same = {"baseline_floats": int(braw.size), "recorded_floats": int(raw.size),
                    "identical_bytes": bool(braw.size == raw.size and braw.tobytes() == raw.tobytes())}
            if braw.size == raw.size:
                dd = np.abs(braw.astype(np.float64) - raw.ravel().astype(np.float64))
                same["max_abs_diff_ignoring_nan"] = float(np.nanmax(dd))
        summary["R3_behaviour_unchanged_vs_B1"] = same
        summary["R3_legacy_log"] = {"row_offset": best, "rows": int(n), "blade_tip_max_abs_diff_vs_recorder_m": float(e_tip),
                                    "old_tip_col_vs_sword_origin_max_abs_diff_m": float(e_old),
                                    "old_tip_col_to_true_tip_m": {"min": float(dist_old_true.min()), "max": float(dist_old_true.max())},
                                    "extra_cols": m["extra_cols"], "col_notes_present": "col_notes" in m}
        print("R3 legacy log", summary["R3_legacy_log"], "vs B1", same, flush=True)
    if "N1" in only:
        d = root / "N1_damaged_video"
        info = damage_video(root / "R1_slash", d)
        r = va.validate(d, None, make_sheet=False)
        vs = next(c for c in r["checks"] if c["id"] == "video_sync")
        ev = vs["evidence"]
        exp_drop = [{"video_frame": info["dropped_video_frame"], "from_id": info["dropped_video_frame"] - 1, "to_id": info["dropped_video_frame"] + 1}]
        exp_dup = [info["duplicated_video_frame"]]          # 原第 dup 格在刪格後位於 dup-1，重複的那一格在 dup
        ok = vs["status"] == "FAIL" and ev["drops"] == exp_drop and ev["duplicate_frames"] == exp_dup
        summary["N1"] = {"damage": info, "video_sync": vs["status"], "drops": ev["drops"], "duplicates": ev["duplicate_frames"],
                         "expected_drops": exp_drop, "expected_duplicates": exp_dup,
                         "negative_test": "PASS (exactly the injected defects)" if ok else "FAIL (detection differs from injected defects)"}
        print("N1", summary["N1"], flush=True)
    json.dump(summary, open(root / "regression_summary.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=va._np_default)


if __name__ == "__main__":
    main()
