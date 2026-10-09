# P10 R5–R6 ROUND 3 — 全量回歸與失敗分類

全量回歸 **132 項**（ROUND 2 的 130 項＋新 gate 2：KITM、SWALK）：**121 PASS／11 FAIL**（`full_regression.log`，約 90 分）。
**沒有修改任何舊 Gate**（P5／P6／P8／P9 R4-2／R4／R4b 的驗證器與封存檔皆未改）；ROUND 3 只新增 KITM／SWALK 兩項，並更新 RDB／WLF 兩行的說明文字。

| # | 項目 | 分類 | 證據／說明 |
|---|---|---|---|
| 1 | terrain gate | Pre-existing | base 載入 3528 ms ＞ 3000（P10 FINAL 起同項；P12）。FarmlandTerrain 的頂點色修正不影響此 gate 的其他檢查（只有這一行 FAIL） |
| 2 | P5 asset reset gate | Pre-existing（數量 421 → **440**，+19 已對帳） | 增加的 19＝`machiya_kit_cal` 的 18 個登記材質＋`kit_cal.gdshader`（`proof_p5_asset_plus19.log`：AlbedoPilotP10 的依存清單）。P5 白名單不擴充；登錄屬 ART_APPROVED 後的合法更新 |
| 3 | P6 町家 Kit Gate | Expected Pilot Seal Conflict | AlbedoPilotP10 的 override（現在全部是登記變體；KITM 證明只在 Pilot 24 棟）。Kit Gate「無 override」規則未放寬 |
| 4 | **P8 取水水路淨空（FEEDER）** | **Expected Pilot Seal Conflict（ROUND 3 新增）** | WaterLifeP10 在 runtime 隱藏水車 2 高架落とし樋（可視 6／碰撞 3）。FEEDER 把 WaterSupply 下所有 MeshInstance 當作可見（不看 `is_visible_in_tree`）→ 隱藏的 Support 柱 4 根被判「可見但無碰撞」。實際遊戲中這 4 根柱不可見。證明：移除 WaterLifeP10 → FEEDER 全 PASS（`proof_wlf_off_feeder.log`；village_v2.tscn sha256 還原一致 4e041a74…）。正式解＝P8 limited correction（見 `../r5b_water/README.md`） |
| 5 | P8 runtime budget | Pre-existing（不穩定） | 第一輪 FAIL、ROUND 2 PASS、ROUND 3 FAIL；P10 FINAL 起即為 PRELIMINARY／UNRESOLVED CLEAN BENCHMARK，不當作改善或惡化 |
| 6 | P9 R4-2 神社周邊 場景級 | Newly Introduced（ROUND 2 起，未變） | 盛土踊り場的斜坡碰撞 × 封存 gate 的「地形基準」膠囊：179 點中 40 點。SWALK（最上面可行走面基準）同路線被擋 0。舊 gate 未修改；ART_APPROVED 後才做 limited verifier correction／reseal |
| 7 | P9 R4-3 寺子屋周邊 場景級 | Pre-existing | R3d C20 巡回（跨層） |
| 8 | R4 HUSE 場景級 | Expected Pilot Seal Conflict | PropFixP10 A2 1 件（未變） |
| 9 | R4 HUSE 封存 | Expected Pilot Seal Conflict | 同上 |
| 10 | R4b HUX 場景級 | Expected Pilot Seal Conflict | 同上 |
| 11 | R4b HUX 封存 | Expected Pilot Seal Conflict | 同上 |

合計：Pre-existing 4（含不穩定的 P8 runtime budget）／Expected Pilot Seal Conflict 6（ROUND 3 新增 P8 FEEDER 1）／Newly Introduced 1（P9 R4-2，ROUND 2 起）。
本輪新 gate：KITM ✓、SWALK ✓、RDB plan／scene ✓（ROUND 3 版）、WLF plan／scene ✓（ROUND 3 版）、SAN plan／scene ✓、19-point walk ✓、MMBAKE ✓。
