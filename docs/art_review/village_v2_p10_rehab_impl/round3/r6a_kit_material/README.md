# P10 R6a ROUND 3 — 町家 Kit 專用亮度校正材質（方案 A，Pilot；ART_REVIEW）

使用者 ROUND 3 §4：方案 A APPROVED FOR IMPLEMENTATION——Kit 專用校正材質、不改全村共用材質庫、保留已核准 24 棟、變體需登記、Kit Gate 原規則不變、本輪不改 187 棟。

## 1. 內容
- 新資產目錄 `godot/assets/village_v2/machiya_kit_cal/`（`machiya_kit/` 的兄弟目錄，不在已封存 P6 Kit 目錄內加檔）：
  - 校正材質 4：`V2_Plaster_K`（0.70）、`V2_Wood_K`（0.75）、`V2_KitStoneTri_K`（0.65）、`V2_MachiyaKit_K`（atlas 色階分類 shader，k 0.75／0.42／0.70）；瓦不校正（照用 `V2_Kawara`）。
  - 區域調色盤變體 14：A 商業（漆喰 4・木 3）、B 住宅（漆喰 4・木 3）。
  - `kit_cal.gdshader`、**變體登記表 `kit_material_variants.json`**（id、檔案、sha256、類別、基底、區域、albedo、飽和度、明度帶、色卡 luma 帶、`allowed_diff`、Pilot 建物 24、保護檔 8 個的 sha256）。
- 數值唯一來源＝`tools/village_v2_albedo_pilot_lib.gd` 的 CAL／KIT_CLASS／PALETTE（第一輪核准值）；生成器 `tools/village_v2_kit_material_lib.gd`。
- `AlbedoPilotP10` 改為外部參照登記材質（不再內嵌複本）；**與核准 r5 的內嵌材質逐屬性比對差 0**（`equivalence_r5_vs_registry.log`）。
  同機位 9 張與第一輪核准圖的像素差：平均 0.05–1.39／255（`pixel_diff_vs_round1.json`；差異來自同期其他 overlay／NPC）。

## 2. 合法變體機制＝gate KITM（`tools/verify_village_v2_kit_material.gd`，`gate_kitm.log`：0 失敗、反向 6/6）
K1 登記表↔檔案 sha256／K2 與基底只差 albedo_color（atlas 只差 k）／K3 飽和 ≤ 0.22・明度帶／K4 與核准 24 棟同值／
K5 場景：187 棟 Kit 子樹中 override 只出現在登記的 Pilot 24 棟、且全是登記變體，其餘 163 棟 0／K6 `_matlib`・P6 Kit 原檔・Kit gate.json／manifest 未變（sha256＋git HEAD）。
反向：登記外 override／登記變體用在 Pilot 外／變體改粗糙度／飽和 0.30／登記 sha 竄改／明度 0.95。
- **P6 Kit Gate 未修改**，仍以「無 override」判 FAIL（Expected Pilot Seal Conflict）。
- 範圍註記：B_* 直下的 P4 灰盒節點（Foundation／Building_Main／Roof…）在 `village_v2.tscn` 內嵌 material_override，屬既存、非 Kit，K5 以 Kit 子樹為範圍（與 Kit Gate 相同）。

## 3. ART_APPROVED 後的正式化（提案，未施工）
1. Kit Gate 合法更新：「無 override」→「override 必須是登記表內變體、只在登記建物、sha 一致、只差 allowed_diff」（更嚴格的白名單，不是放寬）；P6 Kit limited reseal（前後雜湊、反向）。
2. 全村 187 棟套用：以登記變體＋決定性分配（鄰棟 14 m 不同組）——需先取得「最新亮度校正基準」後另行核准。
