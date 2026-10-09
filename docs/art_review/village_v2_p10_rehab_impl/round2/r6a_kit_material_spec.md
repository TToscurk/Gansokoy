# P10 R5–R6 ROUND 2 — R6a 町家 Kit 材質規範＋封存相容方案（DRAFT／未施工）

狀態：**提案（文件）**。本輪不改任何 Kit／_matlib／建物，不改 Kit Gate。24 棟 Pilot（`AlbedoPilotP10`）維持第一輪的覆寫方式與色彩設定（使用者已核准方向）。

## 1. 為什麼不能直接全村套用

- 第一輪的做法是 overlay 在執行期對 Pilot 區建物做 surface override（`AlbedoPilotP10`）。
- P6 町家 Kit Asset Gate 的規則是「5 個共享材質、無 override、albedo_k 一致」。全村 187 棟用同一手法 ＝ 187 棟都違規，只能靠放寬 Kit Gate 才能過。
- 使用者裁定：**不要放寬 Kit Gate 來容許任意 override**。所以全村套用必須改成「材質本身就是校正值」，而不是執行期覆寫。

## 2. Kit 材質規範 v2（草案；數值＝第一輪已核准的 Pilot 值）

| 材質（類） | 現況 albedo_color | 規範 v2 | 色卡實測目標（日照垂直面 sRGB luma） | 來源 |
|---|---|---|---|---|
| 漆喰 `V2_Plaster` | 0.42 | **0.70**（實測 0.718） | 0.70–0.85 | `village_v2_albedo_pilot_lib.gd` `CAL`／`TARGET_LUMA` |
| 木 `V2_Wood` | 0.42 | **0.75**（實測 0.413） | 0.35–0.50 | 同上 |
| 瓦 `V2_Kawara` | 0.42 | **0.42（不變）** | 0.25–0.40 | r1 0.58／r2 0.50 高視角屋面讀成淺灰 → 不校正 |
| 基石 `V2_KitStoneTri` | 0.42 | **0.65**（實測 0.522） | 0.50–0.60 | 同上 |
| Kit atlas `V2_MachiyaKit`（LOD1/2） | 0.42 單一 k | **依 atlas 色階分類**：暗（木）k 0.75／中（屋根灰・暖簾）k 0.42／亮（漆喰・障子）k 0.70 | 與 LOD0 同一套對應（40 m LOD 切換不跳亮度） | `KIT_CLASS`、`kit_cal_p10.gdshader` |

街區調色盤（建築差異）：保留第一輪核准的 `PALETTE`（A 商業＝暖白漆喰＋紅殻／飴色木、B 住宅＝灰味漆喰＋風化灰木），飽和度 ≤ 0.22、亮度留在上表目標帶、14 m 內相鄰兩棟不同組。

## 3. 封存相容方案（建議 A；需使用者核准後才施工）

**A（建議）：Kit 專用校正材質＝新資產，不動 _matlib、不放寬 Kit Gate**

1. 新增 Kit 專用材質（不覆寫 `_matlib` 原檔，所以 P5 Hero／P9／P10 其他使用者完全不受影響）：
   `assets/village_v2/machiya_kit/cal/V2_Plaster_K.tres`（0.70）、`V2_Wood_K.tres`（0.75）、`V2_KitStoneTri_K.tres`（0.65）、`V2_MachiyaKit_K`（atlas 色階分類＝把 `kit_cal_p10.gdshader` 的係數烘進 atlas 或做成等價材質）；`V2_Kawara` 照用。
2. 町家 Kit 網格的材質參照改成上述 5 個（仍然 5 個、仍然無 override、albedo_k 在 Kit 內一致）→ **Kit Gate 規則不變**，只需 P6 Kit 的 gate.json／雜湊依正式流程 **limited reseal**（前後雜湊、影響清單、回歸證據）。
3. 調色盤：在 Kit manifest 登錄「變體登記表」（每個變體有 id、luma 帶、飽和度上限），由 `gen_village_v2.gd` 決定性地分配。
   Kit Gate 需要新增一項**更嚴格**的檢查（每個變體都必須在登記表內且在色卡帶內），不是放寬。此項是規格變更，需使用者另外核准。
4. 套用到 187 棟＝重生建物節點（位置／朝向／量體不變）→ 受影響封存：P6（Kit・建物）、引用建物節點的 P10 R2／R1b 場景級 gate（只做存在性與位置檢查者不受影響，需逐項確認）。

**B：只保留 Pilot（現狀）**：24 棟 overlay 覆寫維持為 Pilot；全村不套用；P6 Kit Gate 的 Expected Pilot Seal Conflict 會一直存在。

**C（不建議）：直接改 `_matlib` 的 albedo_k**：會同時改到 P5 Protected Hero、P9／P10 所有共用材質的物件，等於大範圍重封，且違反「Protected 原檔不得覆寫」。

## 4. 本輪狀態

- 未改任何 Kit／_matlib／建物／Kit Gate。
- `AlbedoPilotP10` 與第一輪相同（24 棟），P6 Kit Gate 仍為 **Expected Pilot Seal Conflict**（見回歸分類）。
- 待使用者裁定 A／B（以及 A-3 調色盤變體登記表是否納入 Kit Gate）後才施工。
