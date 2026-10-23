# tools/video_intel — 動畫真值記錄與驗證（Phase 1，CPU only）

| 檔案 | 用途 |
|---|---|
| `validate_animation.py` | 錄製（Godot Movie Maker＋MotionRecorder）並驗證；或對既有資料重新驗證 |
| `validate_animation.sh` | 包裝，優先用 `D:/Tools/video_intel/venv`（numpy、pillow） |
| `run_regression.py` | Phase 1 回歸：基準／三刀連段／相機旋轉／一般移動／壞影片反向案例 |
| `SCHEMA.md` | `godot_motion.v1` 資料結構、座標系、停格三種計數、同步標記 |
| `../../godot/tools/motion_capture/` | `motion_recorder.gd`（逐格記錄元件）、`record_harness.tscn/.gd`（外殼）、`sword_geometry.gd`（刀尖／柄／鍔由網格實測） |

## 指令
```bash
# 錄製＋驗證（約 20–25 s／17 s 片長；--proj-check 會放不受深度遮擋的投影驗證小球，只是畫面標記）
bash tools/video_intel/validate_animation.sh --scene res://characters/yoriichi/v24_isshin/isshin_slash_demo.tscn \
     --output D:/research/video_intel_poc/p1/run1 --scene-args "--tour --no-audio" --proj-check [--cam-sweep 45,2,14]
# 重新驗證既有資料（不重錄）
bash tools/video_intel/validate_animation.sh --input D:/research/video_intel_poc/p1/run1 [--baseline-slog B0/legacy_slog.json]
# 回歸
D:/Tools/video_intel/venv/Scripts/python.exe tools/video_intel/run_regression.py --out D:/research/video_intel_poc/p1/regress
```
結果：資料夾內 `report.json`、`report.md`、`review_sheet.png`。exit 0＝沒有 FAIL、1＝有 FAIL、2＝工具無法執行。
判定 PASS／FAIL／UNVERIFIED／ART_REVIEW；UNVERIFIED 不算通過。

## 限制
- 被測場景需提供 `sk`／`actor`／`combat` 屬性（`isshin_*_demo` 系列都有）；沒有的欄位記 `null` 並列入 `meta.unavailable`。
- 錄影輸出解析度＝視窗大小（本專案 1152×648；`--resolution` 不生效）。
- 腳接觸是運動學推定，不是物理接觸。
- 停格時粒子是否還在動沒有記錄（UNVERIFIED）。
