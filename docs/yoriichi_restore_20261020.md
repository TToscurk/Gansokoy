# 緣一：取消 R7／R8，恢復原始版本——清理報告（2026-10-20）

## 1. R7 開工前版本來源
- 基準：`work/yoriichi_r7/backup_pre_r7_attacks_20261018/`（R7 攻擊重製開工前的正式檔與動畫雜湊）。
- 逐檔比對結果：正式場景、原始戰鬥動畫（v24/anims、anims_r4、r5、r6、r61）、R5–R6.2 控制器、`sun_breathing.gd`、`r62_grip_ik.gd` 全部與基準**相同**。
- 唯一差異：`yoriichi_character.gd` 刀手判定由膠囊改為同尺寸膠囊網格凸包（11 行，2026-10-19 03:51）。原因是專案已改用 Jolt Physics，Jolt 膠囊不支援非等比縮放；這是物理引擎相容修正，不是 R7 戰鬥改動，**保留**。
- 正式主遊戲（`main.tscn` → `player_yoriichi.tscn` → `yoriichi_character.gd`）與 `combat_arena.tscn` 從未引用 R7／R8 候選。正式控制器與動畫不需要回退。

## 2. 跑酷
全部在正式控制器 `yoriichi_character.gd`，R7 期間未修改（除上述刀手判定）。
實測功能：走跑、衝刺、跑步急轉、一般跳＋落地、二段空翻、踩牆跳、空中攀上矮牆（Mantle）、地面蹬牆跑上高牆（Wall Run）、高處落下翻滾（LandRoll）、攀爬／落地後恢復操作、拔刀狀態下移動與跳躍。
基準測試 `godot/tools/yoriichi_restore/test_parkour_baseline.gd`：清理前 12/12、清理後 12/12，**逐項數值完全相同**（跑 2.66 m/s、衝刺 7.0 m/s、跳高 1.75 m、滯空 50 格、Mantle 落點 y=1.2、Wall Run 落點 y=2.6、踩牆跳 vy 7.9）。

## 3. 已隔離（退出現役，未刪除）
搬到 `godot/_quarantine_r7_r8_20261020/`（有 `.gdignore`，Godot 不掃描），原路徑結構保留，可直接搬回：
- 候選場景：`player_yoriichi_r7.tscn`、`player_yoriichi_r7k.tscn`、`player_yoriichi_r8.tscn`
- 候選控制器：`yoriichi_character_r7.gd`（含十三型循環）、`yoriichi_character_r8.gd`
- 候選動畫：`v24/anims_r7/`（含 form13 派生）、`v24_r7/`（REF09 MX、圓舞右鍵、Running Jump 素材）、`v24_r8/`
- 工具與測試：`tools/yoriichi_r7/`、`tools/yoriichi_r8/`
`work/yoriichi_r7`、`work/yoriichi_r8`、`docs/yoriichi_r7`、`docs/yoriichi_r8` 本來就在 Godot 專案外，原地保留。

## 4. 原始戰鬥（`test_original_combat.gd`，10/10）
正式控制器、拔刀、左鍵普攻（Attack_Combo，木樁命中 1 次）、右鍵重斬（Heavy_Cut）、Shift 閃避、F 格擋、日之呼吸壹之型（正式型表）、收刀；正式角色未載入任何 R7／R8 動畫。

## 5. 場景與依賴（`test_scene_loads.gd`，0 失敗）
main 開機、load_map 神社／獸道／人間之里 V2／slice、敵人 samurai／wolf／訓練木樁、combat_arena 全部載入成功，Player 皆為正式控制器；log 中沒有任何 R7／R8 路徑錯誤（只有引擎結束時的 RID 洩漏提示，與本次無關）。Godot 重新匯入沒有缺檔錯誤。

## 6. 備份
`D:/神社_archive/yoriichi_r7_r8_cancel_20261020/`（2.7 GB，專案外）：R7／R8 全部動畫、腳本、Blender 工作檔、Mixamo 素材與 provenance、十三型控制器與測試、影片與文件、清理前正式檔、`git status --porcelain`（1512 行）、`git log`。`SHA256_project_copy.txt` 977 檔：備份內 0 不符、與清理前原檔 0 不符。

## 7. 已刪除（2026-10-20 使用者同意）
- `work/yoriichi_r7`（654 檔）、`work/yoriichi_r8`（15 檔）、`docs/yoriichi_r7`（28 檔）、`docs/yoriichi_r8`（2 檔）已刪除。刪前確認外部備份逐檔數量相符、SHA256 977 檔 0 不符；這四個資料夾不在 Git 追蹤內，現役專案無任何引用。
- 要找回：從 `D:/神社_archive/yoriichi_r7_r8_cancel_20261020/project_copy/` 複製回原路徑。

## 8. 待確認
- `godot/_quarantine_r7_r8_20261020/`（Godot 不掃描）仍保留，是否也刪由使用者決定。
- 正式檔在 Git 中為未提交修改（R7 之前就存在），未提交、未還原。
