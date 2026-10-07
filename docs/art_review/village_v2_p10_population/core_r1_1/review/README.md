# P10 R3d r1.1 — Market South Entrance Cue（ART_REVIEW）

**狀態：ART_REVIEW（未 ART_APPROVED、未封存）。** 使用者裁定：R3d r1 核心人口配置接受、不重做 39 人布局；只補南側市集入口。R2 不重開、封存的主街 props 不動。

## 改了什麼（人數仍 39）
- **R3d 的 3 人**（入口附近，只改位置／朝向／往返路線；動作沿用已核准 vocabulary）：
  - C6 魚販（買い物客）：往返路線改成 **南の主街 → 辻 → 市の口**（往＝進市集、返＝出市集），長 19.5 m。
  - C11 布屋（呼び込み、Talk）：從辻的角移到 **口の東、幟の脇**，面向辻（迎著從主街來的客人），不擋通道。
  - C12 八百屋（木箱、Carry）：移到 **口のすぐ内側**，面向中橫街＝抱著貨正要出來。
  - 三人方向不同（西北／東南／南）、位置錯開不成一列。
- **入口 cue 2 件**：口的兩側（間隔 10.7 m）各立一支既有 market_kit 的小幟「市」（`mk_nobori_ichi`，竿 4 m・布 0.45 × 1.8 m），布面朝東南（主街的辻）；新 overlay `Population/EntranceCueP10`（`gen/entrance_cue_p10.tscn`，`tools/village_v2_entrance_cue_lib.gd`）。沒有新資產、沒有大招牌、沒有箭頭。
- 其他區域（市集 16 的其餘人、Market West 8、寺子屋 3、鯢吞亭 2）、R3b／R3c 封存、NPC Library 不動。

## 審圖（只重拍入口）
| 圖 | 內容 | Agent 自評（vision） |
|---|---|---|
| `6_mouth_from_south_r1_vs_r1_1.jpg` | 南側主街 → 市集入口 TPS，左 r1／右 r1.1 | **3/5 → 4/5**：兩支小幟讓缺口讀成「指定的入口」，人分散在入口周圍、不成一列、不擋路；小幟低調不像 UI。殘留：這距離「市」字本身看不清、個別人的進出方向在靜態圖不完全確定 |
| `10_mouth_close_r1_vs_r1_1.jpg` | 更近的入口 TPS，左 r1／右 r1.1 | **4/5**：入口標記與人流增強、無阻擋／浮空／穿模；呼び込み與其他站著的人在這距離區別不大 |
| `11_mouth_motion_r1_1.gif`（＋`_sheet.jpg`） | 7 秒動態走訪（玩家實際輸入走向入口、NPC 照常動作；r1 對照 `11_mouth_motion_r1.gif`） | **4/5**：有人走向入口、有人在入口、有人往外走；沒有滑步／浮空／突然出現。「從門檻跨進／跨出」在取樣格間不完全明確 |

依裁定（達到 4/5 即停）不再 polish。原圖：`r1_state/`（r1）、`r1_1/`（r1.1），1920×1080、Forward+、10:00。

## 技術驗證（`godot/tools/verify_village_v2_population_core.gd`，tag CORE）
- plan 14 項 0 失敗（新增「入口 cue」：≤ 2 件・既有 Kit mesh・接地・不在道路上・不撞建物／攤位／人／往返路・口的通道 ≥ 8 m）。
- 反向 13/13（新增 `cue`：把幟移到中橫街中央 → 只 FAIL「cue」）。
- scene 9 項 0 失敗（掛載順 PopulationP10 → ActivityP10 → CoreP10 → ActivityCoreP10 → EntranceCueP10、cue 2 件、逐格 30 fps 等）。
- 封存交叉（r1.1 掛載後）：POP seal／scene、ACT seal／scene、NPCLIB・MKT・MW・STR・P9F seal、MMBAKE、TXT 全部 exit 0（`gate/cross_*.log`）。未重跑完整 96 群組回歸。
