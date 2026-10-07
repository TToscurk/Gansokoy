# P10 R3d — Village Core Population Expansion r1（ART_REVIEW）

**狀態：ART_REVIEW（Agent 只到 ART_REVIEW；未 ART_APPROVED、未封存、未做 Outer Village）。**

## 這輪做了什麼
- 人口 16 → **39**（R3b 封存 16 人不動＋R3d 新增 23 人），新 overlay `Population/CoreP10`（`gen/population_core_p10.tscn`）＋活動 `Population/ActivityCoreP10`（`scripts/npc_activity_core.gd`，繼承封存的 R3c overlay，只換對象與指派）。
- 區域：主市集 16、主街 10、Market West 8、鯢吞亭門前 2、寺子屋前庭 3。市集最密、主街次之、裏通り／居酒屋／寺子屋更疏；不擴到農田／河岸／森林（gate 以區域框檢查）。
- 動作只用 R3c／R3c.1 已封存的 vocabulary（gate 逐筆比對封存的 type／NPC／clip／slot／options）：Talk 6、Carry 1、Drink 1、Sit 1、YouthShortStep 1；其餘 Idle、Walk 往返（新增 2 人）。
- 南側「市」的導引（R2 non-blocking 交辦）：市の口 的呼び込み（布屋、Talk）、從主街往市の口 往返的買い物客（魚販）、在口抱著木箱的八百屋（Carry）、口內原有的跑腿少年。

## 審圖圖（同鏡位 BEFORE＝已核准 R3b＋R3c 16 人／AFTER＝R3d 39 人；動作相位凍結，只切換 R3d 的顯示）
| 圖 | 內容 | Agent 自評（vision，誠實） |
|---|---|---|
| `1_market_tps.jpg` | 市集 TPS 8.5 m | — |
| `2_market_west_tps.jpg` | 裏通り TPS 4.5 m | — |
| `3_main_street_tps.jpg` | 主街 TPS 8.5 m | 3/5：人多了、沒有明顯錯位；但多數人是站著／路過，交易／交談／工作的動作在這距離不易讀 |
| `4_market_high.jpg` | 市集高視角 13 m | 3/5（第一版 2/5 → 加了廣場中央的立ち話二人組）：看得到中央的交談，但人仍小、前景空地大 |
| `5_walk_through.jpg` | 正式 Player 輸入＋碰撞實走 6 格 | — |
| `6_mouth_from_south.jpg` | 主街南側看市の口（新鏡位） | 3/5：口附近有人，但還不是「明顯往市集流入／聚集」；主街右側的人同樣吸睛 |
| `7_mouth_from_north.jpg` | 主街北側看市の口（新鏡位） | — |
| `8_izakaya.jpg` | 鯢吞亭門前（新鏡位） | 3/5：門前有兩人；這個鏡位玩家角色擋住一部分、杯子在這距離看不清 |
| `9_terakoya.jpg` | 寺子屋前庭（新鏡位） | 3/5（第一版 2/5 → 從暗色玄關前移到明亮的院子）：縁台上的婆婆＋站著的母親可讀；小孩和玩家角色在畫面重疊，「接小孩」的敘事不夠明確 |

原圖 `../render/`（1920×1080、Forward+、10:00）。

## 技術驗證（`godot/tools/verify_village_v2_population_core.gd`，tag CORE）
- plan 13 項 0 失敗：人數 30–40／區域與密度順序／核心區範圍／anchor（不與 R3b 及彼此重複）／職業對位／歩く人規則（婆婆 0、少年 ≤ 2）／同模型 ≥ 8 m（新增分相關）／構圖（小群 ≥ 4、單獨 ≥ 6、最近距離變異係數 ≥ 0.5）／接地 ±3 cm／身體 capsule 對描畫三角形＋碰撞體／往返路／步速＝clip 足速（滑 ≤ 3 %）／Activity＝封存 vocabulary／封存檔只讀。
- 反向 12/12：各案只打中自己瞄準的項。
- scene（非 headless、Forward+）9 項 0 失敗：掛載順 PopulationP10→ActivityP10→CoreP10→ActivityCoreP10、人數 23／39、Activity 10 件在播承認 clip、道具貼在身上（木箱↔雙手、杯↔左手、縁台↔腰）、縁台與木箱不撞攤位／建物、**逐格（30 fps、clip 全長，與 R3c 同基準：clip／道具有效、腳 rest 誤差 < 1.2 cm、道具不進描畫三角形、木箱／縁台吃入 < 2 cm、縁台四腳著地 < 5.5 cm）**、9 個審圖鏡位同模型 ≤ 2、歩く人 30 秒移動＋折返（XZ ≤ 5 cm、Y ≤ 3 cm）。
- 封存交叉（R3d 掛載後）：POP seal／scene、ACT seal／scene／negatives、NPCLIB・MKT・MW・STR・P9F seal、MMBAKE、TXT 全部 exit 0（`../gate/cross_*.log`）。未重跑完整 96 群組回歸。

## 界線（不宣稱的事）
- capsule／描畫三角形／碰撞體檢查不是逐一動畫手掌／衣物頂點對所有道具的穿模認證。
- 這輪 vision 自評全部約 3/5：比 R3b 明顯熱鬧，但「交易・交談・工作」的可讀性仍受遠距與既有 vocabulary（只有 5 類動作、大多數模型只有 Idle／Walk）限制。
- 南側「市」：有改善但未達「明顯流入」；是否需要小型 entrance-cue pass，待使用者判斷（依 R2 裁定，不重開 R2）。
