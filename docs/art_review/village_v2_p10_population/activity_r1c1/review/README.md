# P10 R3c.1 Readability Pass — ART_REVIEW（等待使用者裁定）

Agent 只到 ART_REVIEW；**未授 ART_APPROVED、不 seal、不進 R3d**。範圍照 2026-10-07 裁定：只做 Sit／Carry／Talk 的遠距可讀性。人口 16 不變；R3b baseline 的位置、朝向、模式、patrol 都沒動，只改私有 overlay `godot/scripts/npc_activity_overlay.gd` 的指派和道具。NPCLIB、P9、市場封存不動。W3 Drink（B1＋新杯握持）保留。

## 根因（基線量測 `../readability_baseline.json`，六類審圖鏡位）
R3c 的 Sit／Carry／Talk 放在審圖鏡位看不到的人身上：
- Carry M4：29–43 m、27–39 px，全被攤位擋住。
- Sit M5：被棚架擋，而且床几太低。
- Talk W1／W2：不在任何畫面內。

## 改了什麼
| 類別 | R3c | R3c.1 | 審圖鏡位實測 |
|---|---|---|---|
| Sit | M5 瀬戸物＋床几 | **W4 藥草婆婆**，Mixamo「Sitting Talking」，坐在既有 Kit 的紅毛氈縁台 `ms_endai_mousen`（長縮到 1.2 m、深 0.34 m、座高 0.285 m） | 裏通り 9.6 m／121 px，5 條射線全部看得到 |
| Carry | M4 魚販（被擋） | **S2 八百屋**，Mixamo「Box Idle」，雙手捧木箱面向客人 | 主街 19.3 m／59 px |
| Talk | M2／W1／W2 | M2、W1、W2 不變；**新增 S3 藥草婆婆**，Mixamo「Talking（Finding Something Funny）」，對著 S2 說話 | 主街 19.7 m／57 px |
| — | M4、M5 | 回到 R3b 原本的站立待機 | — |

- 新動作由 Mixamo 下載（skin false、30 fps、arm-space 沿用各 NPC 的值），烘焙和接地沿用封存的 pipeline。沒有手 key。下載紀錄在 `../candidates/*_download.json`。
- 八百屋 `yaoya_m01` 和 `chonin_m01` 原本沒有 Mixamo 角色，這次用 NPCLIB 的匯出腳本上傳（貼圖縮到 1024）。chonin 最後沒用到。
- 試過但淘汰：
  - S4 魚販邊走邊搬（Mixamo Holding Walk）：重定向後雙手在腰側、不在身前，木箱一定穿過骨盆（實測 13 cm）。
  - S4 改用 Shopping Bag Walk：步幅速度 0.92 m/s，對不上 patrol 的 1.32 m/s，要快 44% 才不滑腳。
  - 結論：R3b 的 patrol 速度不改，所以本輪沒有「邊走邊搬」。

## 接觸實測（`../contact_final.json`，CPU 蒙皮全身頂點、每格）
- **Carry S2**：木箱內部沒有任何身體頂點（容許 4 mm 貼合）；最差的一格，手離箱子 1.2 cm。
- **Sit W4**：臀腿與座面接觸 −0.1～−0.9 cm（壓入不到 1 cm），沒有身體穿過座面；縁台後緣離店前台階 2 cm。

## Technical（同一版本）
- `verify_p10_activity.gd`：plan 9／scene 19／negatives 29 全 PASS，exit 0（`../gate/`）。
- gate 調整：
  - 指派數 7→8。
  - 木箱檢查改為依 `crate_forward／up／inset` 算手的預期位置。
  - 座椅腳的接地改為取「地形碰撞」和「可見地面」兩者較高者：裏通り地面比 TerrainCollision 高 0.15 m，R3b 也是用可見地面讓 NPC 接地。
- R3b `--seal` 0 失敗、NPCLIB `--seal` 0 失敗。

## 審圖檔
- `1_…`–`6_…_R3b_vs_R3c1.jpg`：同鏡位六類靜態對照（左 activity off／右 on）。
- `motion_*_R3b_vs_R3c1.gif`：同鏡位 6 秒動態（4 fps），左 R3b、右 R3c.1，裁到活動角色附近並放大。**遠距的可讀性主要靠動作，請以 GIF 為主。**
- 原圖：`../population/`（PNG 1920×1080）、`../motion/`（JPG）。

## 直說的界線
- **Sit**：在 10 m 審圖鏡位一眼就看得出是坐著，是本輪最明顯的進步。
- **Carry＋Talk（主街 19 m）**：
  - 靜態截圖還是弱，角色只有 59 px，木箱太小。
  - 看動態時讀得出「捧著貨＋對方比手勢」的互動，但不是一眼就懂。
  - 縁台座高 0.285 m 比一般縁台（約 0.40 m）低，因為 Mixamo 坐姿配這位婆婆的腿長就是這個高度。
- **沒改到的**：W1／W2 的對話仍在審圖鏡位外；1 號鏡位的 M2 沿用原本的 talk_general（twohands 版遠看反而比較不明顯，已比較過）。
