# 獸道 S01 R6：入口建築與農村道具（ART_REVIEW，未批准）

日期 2026-10-17。R5 林床不動（地被 13,694 叢、MultiMesh 913、instance 25,709，bake 報告與 R5 逐鍵相同）。
before＝R5 生產狀態；after＝R6。同鏡位、同時刻（hour 10）、1600×900。

## 交付圖
| 檔 | 內容 |
|---|---|
| `1_torii_before_after.jpg` | 鳥居：主路 12 m 第三人稱、右前 3/4 |
| `2_lantern_before_after.jpg` | 石燈籠近景 |
| `3_green_strips_field_before_after.jpg` | 綠長條→耕地：近景、主路視角、`d_wide` |
| `4_entrance_wide_before_after.jpg` | 入口較寬構圖 |
| `5_shadow_fern_sasa_ab.jpg` | 陰影 A/B（左全開、右蕨＋笹不投影） |
| `6_asset_torii_blender.png`／`6_asset_lantern_crops_blender.png` | Blender MCP 資產預覽 |
| `before/h10`、`after/h10` | 原圖各 7 張 |

## 1. Blender 資產（來源：`godot/assets/beast_path/s01_kit/src/build_s01_shrine.py`）
固定 seed、純頂點組裝；只動 `S01_SHRINE` collection，重用 `build_s01_kit.py` 的 MB／tube 工具，舊 kit 沒改。輸出 `s01_kit/glb/`、`src/s01_shrine.blend`、`src/shrine_manifest.json`。

| 資產 | 三角面 | 內容 |
|---|---|---|
| `s01_torii_a` | 1,998 | 明神鳥居木部。柱心距 5.0 m（與舊鳥居相同），笠木頂 5.04 m、總寬 7.32 m；柱徑 0.46→0.40 m、內傾 0.10 m；黑漆反り笠木＋朱島木；貫 3.22–3.52 m 穿柱、出頭與楔；額束（素額，不加字）；黑根卷 |
| `s01_torii_a_base` | 68 | 兩個石台座（0.92 m 見方，埋 0.32 m） |
| `s01_lantern_a` | 1,580 | 春日型石燈籠：基礎→蓮弁卷基壇→竿（中節）→六角中台→火袋（兩面開火口＋其餘四面淺雕）→六角笠（蕨手反り）→請花＋寶珠。地上 2.17 m |
| `s01_crop_daikon`／`_negi`／`_greens` | 518／572／140 | 大根（葉叢＋露出的根肩）、蔥（培土、可見部分偏綠）、小松菜 |

Godot 側新材質（S01 專用，共用 shader 沒改）：`s01k_paint`（收斂朱 sRGB 0.60/0.25/0.17、日曬褪色、小剝落、柱腳泥濺）、`s01k_stone`（淺灰加工花崗岩、雨痕、局部苔）、`s01k_soil`（只讀引用 village_v2 地面陣列的乾土／濕土層）。

## 2. 綠長條是什麼
- **來源**：`tools/beast_path/prop_builder.gd` 的 `_farm_patch()`，POI `farm_patch`（`layout_beast_path.json`，站點 `farm_edge`、`ds 2.0 off 24.0`，地形 `terrace_rect` 平台）。
- **原本幾何**：5 條 19.8×0.3×0.7 m 褐色盒子，各頂一條 18.7×0.06×0.4 m 亮綠盒（Color 0.36/0.50/0.20）——`d_wide` 的平行亮綠條就是這 5 條綠盒。
- **用途**：路段 B01「田緣道」（村外田邊，安全段）的環境敘事——農田，沒有玩法機能、沒有碰撞。是農田的 placeholder，不是無用物件 → **替換**，沒有刪除。
- **替換**：`tools/beast_path/s01_arch.gd field()`——隨地形起伏的土網格，12 條畝（畝距 1.15 m、畝高 0.24 m、平底溝），畝端與田緣不規則；大根／蔥／小松菜按畝種植（同畝同種、偶有缺株，兩條收成後的空畝），共 607 株，外圍畦草。作物不投影、110 m 外隱藏。

## 3. 整合（入口位置不變）
- 只有 S01 三個 POI 加了 `"model"` 欄位（`torii_gate`、`lantern_in_L/R`、`farm_patch`）；`prop_builder.gd` 遇到 `model` 才轉給 `s01_arch.gd`，S02–S04 走原本程式。**拿掉 `model` 欄位＝回到舊道具。**
- 量測（`evidence/placement_probe.txt`，R5 vs R6 同場景讀取）：
  - 鳥居根節點 (-11.99, 1.27, -44.00)、yaw 16.4°，與 R5 相同；兩柱地面 1.25/1.25 m；台座埋 0.32 m。
  - 碰撞：柱圓柱 r 0.26 × 4.45 m＋台座方塊 0.92 m。**地面淨寬 4.08 m（R5 為 4.46 m，台座多占 0.38 m）**；柱間 4.38 m、貫下淨高 3.22 m。
  - 燈籠位置與 yaw 31.5° 不變；碰撞改圓柱 r 0.38 × 2.2 m（R5 方塊 0.6 m）。
  - 森林輸入（`s01_forest_inputs.json`）重生前後逐位元相同 → 腳印／林床佈局沒有被推動。

## 4. 陰影
同一幀依序關閉投影（5 個鏡位，單幀量測，非 benchmark）：

| 關閉投影 | 陰影圖元 | GPU |
|---|---|---|
| 蕨 | −17～−31 % | +0.05～−0.77 ms（多在單幀雜訊內） |
| 蕨＋笹 | −25～−49 % | +0.19～−0.91 ms |
| 再加灌木 | −44～−60 % | −0.18～−1.09 ms |

鏡位 `c66_fwd,s86_fwd,d_tps_f1,e_tps_e,e_close`；例：`e_tps_e` 陰影圖元 4.13M→2.29M、GPU 15.36→14.45 ms。

採用**蕨＋笹不投影**（`s01_dress.json` 兩個 floor 類別 `shadow:false`）；灌木、幼樹、樹、岩、建築保留投影。A/B 圖上林下差異需對照才看得出。
**誠實結論**：陰影圖元砍半，但 GPU 只省不到 1 ms——R5 擴區的 3.4–4.3 ms 主要不在陰影 pass，可能在主 pass 的植被片段／頂點成本。本輪依指示沒有展開效能調查。

## 5. 檢查（只做輕量）
- Blender 匯出 exit 0；generate S01 exit 0；dress bake（非 headless）存後回讀 MultiMesh 零矩陣 0。
- 對 R5 備份（539 檔）逐檔比對：只改 `layout_beast_path.json`、`prop_builder.gd`、`s01_dress.json`、`s01_entrance.tscn`、`gen/s01_dress.scn`、`beast_path.tscn`（只有 unique_id 變動）。S02–S04 場景、地形、原 27 件＋R5 kit 不變。
- 新增檔：`tools/beast_path/{s01_arch.gd,s01_r6_shots.gd}`、`s01_kit/src/{build_s01_shrine.py,s01_shrine.blend,shrine_manifest.json}`、`s01_kit/glb/` 6 個 GLB、`s01_kit/mat/{s01k_paint,s01k_stone,s01k_soil}.gdshader`。
- 還原：R5 備份 `%LOCALAPPDATA%/hermes/backups/beast_path_s01_r5_20261016/RESTORE.md`（R6 新增檔另刪）。

## 已知問題（未修）
- 鳥居柱內傾只有 0.10 m，近看偏直；額束是素額。
- 燈籠火口在 12 m 外不易讀；石面近看偏平滑。
- 耕地遠看仍像一片綠，畝溝要近看才明顯。
- 入口地面：路面在鳥居附近變碎、台座四周沒有土／草的過渡。
- 沒有 commit、沒有升基準、沒有宣告 ART_APPROVED。
