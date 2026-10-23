"""P4 六情境量化摘要（讀回歸資料夾，不重錄）。"""
import json, sys, math
from pathlib import Path
import numpy as np
root = Path(sys.argv[1])
def rows(d): return [json.loads(l) for l in open(root / d / "frames.jsonl", encoding="utf-8")]
def evs(d): return [json.loads(l) for l in open(root / d / "events.jsonl", encoding="utf-8")]
out = {}
R1 = rows("R1_slash")
first_atk = next(i for i, r in enumerate(R1) if r["controller"] and r["controller"]["is_attack"])
st = R1[:first_atk]
p = np.array([r["actor"]["pos_w"] for r in st])
out["1_stationary"] = {"source": "R1_slash ids 0..%d (before first attack)" % (first_atk - 1), "frames": len(st),
    "root_disp_max_m": float(np.linalg.norm(p - p[0], axis=1).max()),
    "tip_speed_max_mps": max(r["sword"]["blade_tip_speed"] or 0 for r in st),
    "main_bone_delta_max_mm": max(r["main_delta_max_m"] for r in st[1:]) * 1000,
    "feet_contact_both_frames": sum(1 for r in st if r["feet"]["Left"]["contact"] and r["feet"]["Right"]["contact"])}
R3 = rows("R3_combat")
p = np.array([r["actor"]["pos_w"] for r in R3]); dt = np.array([r["delta"] for r in R3])
sp = np.r_[0, np.linalg.norm(np.diff(p[:, [0, 2]], axis=0), axis=1) / dt[1:]]
mv = sp > 0.3
labels = {}
for r, m in zip(R3, mv):
    if m: labels[r["controller"]["label"]] = labels.get(r["controller"]["label"], 0) + 1
out["2_locomotion"] = {"source": "R3_combat (isshin_combat_demo --tour)", "frames": len(R3), "moving_frames(>0.3 m/s)": int(mv.sum()),
    "root_speed_mps": {"median_moving": float(np.median(sp[mv])), "p95": float(np.percentile(sp[mv], 95)), "max": float(sp.max())},
    "path_length_m": float(np.linalg.norm(np.diff(p[:, [0, 2]], axis=0), axis=1).sum()), "moving_labels": labels,
    "feet_contact_frames": {s: sum(1 for r in R3 if r["feet"][s]["contact"]) for s in ("Left", "Right")},
    "foot_slide_note": "see R3 report motion_analysis (kinematic contact)"}
hits = [e for e in evs("R1_slash") if e["kind"] == "hit_landed"]
segs = {}
for r in R1:
    c = r["controller"]
    if c and c["is_attack"]:
        segs.setdefault(c["shot_key"] + "#" + str(c["state"]), []).append(r)
out["3_three_slash_combo"] = {"hits": [(e["id"], e["info"]["key"], e["info"]["strike"]) for e in hits],
    "combos": "3 × (strike 0,1,2)", "strike_ids_complete": [e["info"]["strike"] for e in hits] == [0, 1, 2] * 3}
spd = np.array([r["sword"]["blade_tip_speed"] or 0 for r in R1])
out["4_fast_slash"] = {"true_tip_speed_mps": {"max": float(spd.max()), "frames_over_20": int((spd > 20).sum()), "frames_over_40": int((spd > 40).sum())},
    "max_per_frame_tip_travel_m": float(spd.max() / 60), "tip_marker_projection": "see R1 camera_projection blade-tip err (marker drawn at recorded tip every frame)"}
fz = [r for r in R1 if r["freeze"]["anim_time_scale_zero"]]
out["5_hit_hitstop"] = {"hits": len(hits), "anim_frozen_frames": len(fz), "counter_gt0_rows": sum(1 for r in R1 if r["freeze"]["hitstop_counter_active"]),
    "main_pose_frozen_frames": sum(1 for r in R1 if r["freeze"]["main_pose_frozen"]),
    "frozen_ids_per_hit": [[r["id"] for r in fz if h["id"] <= r["id"] < h["id"] + 6] for h in hits]}
R2 = rows("R2_slash_camsweep")
yaw = [math.degrees(math.atan2(r["camera"]["basis_w"][2][0], r["camera"]["basis_w"][2][2])) for r in R2]
dy = np.diff(np.unwrap(np.radians(yaw)))
out["6_camera_rotation"] = {"source": "R2 (--cam-sweep 45,2,14) + R3 follow camera", "R2_total_cam_yaw_deg": float(np.degrees(np.abs(dy).sum())),
    "R2_cam_yaw_rate_deg_s_max": float(np.degrees(np.abs(dy)).max() * 60),
    "R3_cam_travel_m": float(np.linalg.norm(np.diff(np.array([r["camera"]["pos_w"] for r in R3]), axis=0), axis=1).sum())}
json.dump(out, open(root / "scenarios.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(json.dumps(out, ensure_ascii=False, indent=1))
