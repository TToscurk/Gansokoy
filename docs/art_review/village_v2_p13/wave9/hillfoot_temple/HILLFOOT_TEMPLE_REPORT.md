# 丘腳社寺：使用者模型掛上地圖＋建築碰撞（ART_REVIEW，未批准）

> 使用者 2026-10-17 指示：「D:\資產glb\丘腳社寺 請將這個模組加入到地圖上並添加相符的建築碰撞」。
> 走既有的 P5 Hero 管線（龍神像同法），取代 `LANDMARK_HILLFOOT_TEMPLE` 的 P0 灰盒（18 × 9 × 12 m）。美術狀態：**ART_REVIEW**。

## 1. 放了什麼

| 項目 | 值 |
|---|---|
| 來源 | Tripo 模型 92,902 面、單材質、4096² 底色；原樣複製為 `godot/assets/village_v2/hillfoot_temple/src/hillfoot_temple_source.glb` |
| 縮放 | 等比 ×12.277：總高 **9.00 m**（＝P0 上限），腳印 **12.0 × 11.4 m**（P0 18 × 12 以內） |
| 位置 | P0 地標原點 (228, 1.20, −170)，yaw 0，正面朝南（丘腳街）；台基下沉 0.08 m（整地面 1.20） |
| LOD | 57,975／19,492／5,596 面（社殿上限 60,000；33.6 %／9.7 %），距離 0／45／130／700 m |
| 材質 | `V2_HillfootTemple.tres`（2048² 底色、VRAM 壓縮、albedo_k 0.42）。底色只做線性等比增益 ×1.61（平均亮度 0.121 → 0.192，對齊材質庫木／瓦／石平均），不改色相 |

## 2. 碰撞（8 個，box／convex／cylinder）

| 名稱 | 涵蓋 |
|---|---|
| Kidan | 石積台基（頂 1.47 m） |
| Hall | 社殿本體＋緣＋向拝柱線（前面 z 2.80；賽錢箱、格子戶在內） |
| Steps | 石段斜面 35.3°，通過各段段鼻；可以走上石段頂 |
| FrontL／FrontR | 石段兩側的袖石＋前燈籠，左前角石；右側含高札 |
| LanternL／LanternR／LanternR2 | 台基旁三座石燈籠（r 0.74 m） |

石段用 LOD0 實測：5 段踏面 0.28／0.52／0.76／1.00／1.23 → 台基 1.47 m，每階 ≤ 0.28 m。
建置時以 gate 同一套周邊射線自檢：2,494 條射線，可見網格比碰撞突出 > 0.15 m 的有 0 條。

## 3. 驗證

- **Hero Asset Gate 11／11 PASS**（`evidence/hero_gate_headless.log`、`hero_gate_render.log`；`gate.json`）。
  - 已登記進 `village_v2_asset_registry.json`（`build_village_v2_asset_registry.py` 產生，只新增這一筆，status ART_REVIEW）。
  - `-- --all` 21 件全部重驗：0 失敗。
- **gate 擴充**：`verify_village_v2_hero_gate.gd` 新增「多段石段」入口檢查。原本只認單一踏石，門檻仍是每階 ≤ 0.30 m，沒有放寬。
  - 反向案例：只給 2 段時，最大一階 0.95 m → FAIL。
  - 其他資產沒有 `steps` 欄位，行為不變。
- **真輸入實走**（`evidence/real_walk.json`，正式 `main.tscn --map=village_v2`，磁碟場景）：
  - A：從丘腳街出發，繞過四目垣，走上石段。在社殿向拝柱線前停住（局部 z 3.11），接地沒有中斷。
  - B：下石段回前庭，沒有卡住。
  - C：在石段前方橫走 15.8 m，沒有被擋，也沒有看不見的障礙。
  - D：繞社殿西、後、東一圈，沒有卡住。
  - E：朝台基西牆直走，在局部 x −5.37 被擋住（可見石積約 −4.9），沒有穿進去。
- **擺放稽核**：`LANDMARK_HILLFOOT_TEMPLE/Hero` PASS（基礎埋深 0.10 m）。
- **Asset reset**：場景依賴 2,070 → 2,073，新增 3 個都在登記內。違規仍是收尾前就有的 137 個 w9_kit。

## 4. 已知問題

1. **石段上腳底離可見踏面 0.08–0.30 m**（平均約 0.19 m）。斜面碰撞在段鼻處貼合，在每段踏面後緣差一個蹴上高。若把斜面往下壓，gate 的突出檢查會 FAIL（下段蹴上會穿進身體），所以維持現狀。
2. **石段頂轉身往下走時，相機被社殿擋住**：SpringArm 最短 1.65 m。其餘路段最短 7.66 m。
3. **正面的四目垣斷片**（`Props/EnvironmentP9/edge/E082_fence_frag`）橫在石段正前方 1.4–2.6 m，玩家要繞過去。這屬於 EnvironmentP9 的內容，**沒有動**，請裁定是否移開。
4. 正面簷下偏暗：原始貼圖本身陰影重，再乘全村共用 albedo_k 0.42。
5. 擺放稽核另有 22 個 REVIEW（NO_COLLISION_PROXY）。全部是市場／MXC／RSW 的灰盒單位，與丘腳社寺無關。推測來自另一個 session 的 `eb0afba`（W9 FIX 22 棟碰撞替換）；本輪沒有改那些檔案。

## 5. 改動的檔案

- 新增：`tools/build_village_v2_hillfoot_temple_tex.py`、`godot/assets/blender/village_v2/build_hillfoot_temple.py`、`godot/assets/village_v2/hillfoot_temple/`、`godot/tools/p13/w9/mount_hillfoot_temple.py`
- 修改：
  - `godot/maps/village_v2/village_v2.tscn`：ext_resource +1、anchor meta +1、Block 三節點＋3 個 sub_resource 換成 Hero 實例，與產生器 `_heroes()` 對已登記資產的輸出相同；`evidence/scene_diff.txt`。
  - `godot/data/village_v2_asset_registry.json`：+1 筆。
  - `godot/tools/verify_village_v2_hero_gate.gd`：多段石段檢查。
- 寫入前確認：沒有開 Godot 編輯器；場景與收尾提交版逐位元相同。

## 6. 檔案

- `review/hillfoot_before_after.jpg`：BEFORE（灰盒，記憶體內重建外觀）／AFTER，丘腳街南、西、東與前庭 4 個鏡位。
- `review/hero_gate_player_shots.jpg`：gate 玩家視角 4 張＋F6。
- `review/steps_top_tps.png`：石段頂 TPS 鏡頭。
- `evidence/`：gate、稽核、asset reset 的 log，實走 JSON，場景差分，gate 修改差分；`repro/` 收實走與截圖腳本。
