# noka_b 三階段建築驗證紀錄（P8 散點農舍 第二棟，2026-10-22）

狀態：**ART_REVIEW**（未掛進村莊；FastLane `--dry`，`written=false`）。

- 產生器：`godot/assets/blender/village_v2/build_noka_b.py`（既有 v2_kit；一構件一物件，77 件）
- 連接表：`docs/arch_spatial/examples/noka_b.arch.json`（143 條約束，兩階段共用同一份，未加 stage 欄位）
- 位置（未寫入）：(428.00, 1.24, −61.00)、yaw 90°（正面朝 FarmPath_2）

## 檢查點

| 檢查點 | 構件 | 結果 | 實耗（含 Blender／Godot 啟動） | 快取 |
|---|---|---|---|---|
| 1 骨架 | 36 | PASS 56／FAIL 0／UNKNOWN 88（全部＝「構件不存在」，41 件尚未建） | 1.3 s（計算 0.44 s） | 0／144 |
| 2 屋頂・牆・裝飾（首跑） | 77 | PASS 133／WARN 6／FAIL 11 | 3.1 s（計算 2.24 s） | **55／150**（骨架 55 條全數沿用） |
| 2 工具修正後（VERSION 1.1，快取作廢） | 77 | PASS 134／WARN 6／FAIL 10 | 3.5 s | 0（刻意作廢） |
| 2 局部修正後 | 77 | **PASS 144／0／0／0** | 1.7 s（計算 0.85 s） | **128／143**（只重算 15 條） |
| 2 改材質後 | 77 | PASS 144 | 1.7 s | **143／143**（幾何未變） |
| 3 FastLane `--dry` | — | ground／overlap／access／layout／consistency 全 PASS | 44 s（含重新匯入；GLB 未變時 30 s） | — |
| 3 Visual QA full | — | **405 PASS，最終 PASS** | 74 s（幾何 3.3＋拍攝 9.8＋分析 59.8） | — |

## 發現的問題與處理

| # | 問題 | 層級 | 依據 | 處理 |
|---|---|---|---|---|
| 1 | `Gable_L` 對 `Thatch_L` 報 21.3 mm 穿插（鏡像的 R 側 0.002 mm） | **驗證工具 bug** | 兩者皆封閉、對稱；最近面法線判「外側」；射線逐方向：同一三角形在 1e-7 m 處重報 → 奇偶翻轉 | `arch_spatial.inside()` 視 < 1e-5 m 的重複命中為同一穿越；VERSION 1.1 讓舊快取作廢；Blender 回歸 93/93 |
| 2 | 牆 8 面 SUPPORT 51% < 60% | 宣告量法 | 腰板＋漆喰為一物件，漆喰底面（內部下向面）被當成「底」取樣 | 改用最低帶 `method: lowest, contact_band 0.02`，門檻 0.6 不變 |
| 3 | 建具 2 間「懸空 50 mm」 | 宣告量法 | 建具物件含敷居，障子底坐在自己的敷居上 | 同上 |
| 4 | 沓脱石 × 緣側束石 20 mm 穿插 | 幾何 | Scene Graph：束石有依附（束→緣桁→緣側），沓脱石無 | 移沓脱石（x 0.45–1.35 → 0.25–1.10） |
| 5 | 下屋庇板 × 正面 4 柱 10.9 mm | 幾何 | 板厚沿法線押出，內緣裏面退回柱內 t·sin(a)；支撐者＝棚・下屋桁 | 起點前移 10.9 mm，勾配面不變（仍坐在兩支撐上） |
| 6 | 薪積み × 礎石 S0 30 mm | 幾何 | 礎石支撐 Post_S0→Hari_0… | 移薪（外移 60 mm） |
| 7 | FastLane access 0/23、鏡位全被擋、`--find` 退到水田內 | **驗證工具 bug**（與 HERO 同根因的旁支） | 膠囊實查：4/4 點撞到 `AkyuuNPC/…/SleeveSim/Floor`（AnimatableBody3D，layer 20 無限平面） | `place_building.gd` 四處查詢只認 layer 1＋略過會動的物體 → access 23/23；FastLane 整合測試重跑 |
| 8 | Visual QA 把 FastLane 5 項 PASS 讀成 FAIL | **驗證工具 bug**（P2） | `result.json` 用 `result` 鍵，`placement_rows` 讀 `status`，讀不到預設 FAIL | 改讀 `result`；讀不到＝UNKNOWN |
| 9 | Godot 內整棟白色 | 資產 | 佔位材質靠 prefab 換，快速通道不換 | GLB 改帶實色材質（13 色票，依頂點色分配）；幾何不變（快取 143/143） |

Visual Reviewer（只看截圖）：無懸空／穿插／屋頂錯位；「正面不像朝路」→ 量測反駁（facing 0.0°、入口離 FarmPath_2 路緣 6.82 m）。

## 未解決（美術，非阻斷）

- 茅葺讀不出茅草（平滑實色，沒有 FarmsteadP13 的茅草貼圖）；礎石偏亮；屋根比牆身重（勾配 50°、棟 7.43 m 對本體 8.19 m）。
- 參考圖有、本輪沒做：屋根裏換氣窗、左側下屋、菜園。
