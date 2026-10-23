# 舊地圖 A 類清理（2026-10-23）

- 清單：`manifest.json`（384 檔、28,483,246 bytes；每筆含路徑、刪除原因、git 追蹤狀態、HEAD blob、首次／最後提交、sha256）。
- 基準 HEAD：`de63c17e7e2aa7f763c6d13f9e3267376fb4ead7`。
- 核准範圍：僅限本清單；不含 slice／trail／shrine／shrine_v2／shrine_v3／village_v2／beast_path／稗田邸／香霖堂地圖本體、共用資產、UNKNOWN 檔、外部資產庫（`D:\資產glb\Gansokoy\village-gen`）。

## 狀態：A 類流程已由使用者取消（2026-10-23），改為整張地圖接管後整批淘汰，見 `地圖接管計畫.md`。本清單僅留作紀錄。

### 取消前的執行前檢查（有 1 項 FAIL，依指示停止，未刪除任何檔案）

| 檢查 | 結果 |
|---|---|
| 384 檔與原始清單一致 | PASS |
| 無其他 session 修改（git status 乾淨、未 staged、sha256 兩次一致、HEAD 未動） | PASS |
| 全部可由 git 還原（384 個 HEAD blob 皆存在本機物件庫、非 LFS、工作樹＝HEAD blob） | PASS |
| 無符號連結／Junction（檔案與每層父目錄） | PASS |
| 不碰 `D:\資產glb\Gansokoy\village-gen`（realpath 全在 repo 內） | PASS |
| 無新增依賴（全專案 7,234 個資源的直接依賴＋UID 反查） | **FAIL：1 檔** |

FAIL 明細：`godot/maps/slice/gen/tree_盆樹.res` 是 `maps/slice/gen/treemm_盆樹.res`（B 類，未核准刪除）的外部 mesh 依賴。
treemm 為壓縮二進位，第一階段的文字掃描看不到這條引用；`ResourceLoader.get_dependencies` 反查才抓到。
`treemm_盆樹.res` 仍被 `tools/audit_tree_y_on_disk.gd`、`audit_village_tree_cost.gd`、`audit_village_tree_ground.gd`、`clear_street_vegetation.gd` 以字串路徑載入。
刪掉 tree_盆樹.res 會讓這些工具載入 treemm 時缺資源。其餘 383 檔反查 0 命中。

## 刪除前基準（未刪除任何檔案時的既有結果，供日後對照）

- 依賴閉包：47 個根場景 missing＝0。
- `--playtest`：trail／slice／shrine／shrine_v2 全 ✓；hieda1f 4 ✗、hieda2f 4 ✗、hieda3f 3 ✗、kourindou 2 ✗、village_v2 3 ✗、beast_path 1 ✗、shrine_v3 1 ✗（傳送點／出生點離地與無環境音，皆為既有問題）。
- `portal_test.gd` PASS、`verify_quest_flow.gd` PASS。
- `verify_story_slice.gd` exit 42（P0 開局被 dev review start 導到 village_v2，既有）。
- `walk_test.gd -- trail` exit 1（南口起點站不下人；combat_encounter.gd／wounded_yokai_event.gd 在 --script 模式編譯失敗，既有）。
- 日誌內 Missing Resource（Failed loading resource／Cannot open file／No loader found）：0。

## 還原

本輪未刪除任何檔案，無需還原。
