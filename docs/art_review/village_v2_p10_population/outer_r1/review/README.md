# P10 R3e — Outer Village Population Pilot r1（ART_REVIEW）

**狀態：ART_REVIEW（未 ART_APPROVED、未封存；只是 Pilot，是否擴充待使用者決定）。**

## 原則與做法
- 越離開市場核心人越少；核心 39 人（R3b＋R3d，已封存）的密度不複製到外圍。
- 外圍只加 **12 人**：農田 4、水車 2、水渠／橋 2、住宅後巷 3、神社外 1。森林、山腳、偏僻路段**無人**（gate 用區域框擋）。
- 動作只用封存庫：Carry 1（農田的八百屋抱收成木箱）、Talk 2（水車邊、井戶端）、Sit 1（南橋邊縁台的婆婆）、Drink 1（中橋邊一服的娘）；農田不硬套城市動作（稻架旁站著、畦邊短往返 1 人、搬運）。
- 新 overlay `Population/OuterP10`＋`ActivityOuterP10`（`tools/village_v2_population_outer_lib.gd`／`scripts/npc_activity_outer.gd`，繼承封存 overlay）；R3b／R3c／R3d 封存不動（gate 驗雜湊）。不做 crowd system、不做 schedule、不填滿 anchors。

## 人口密度（市場核心 (245,−40) 起算的環，人／1000 m²）
| 環 | 人數 | 密度 |
|---|---|---|
| 0–40 m（市集・主街・裏通り） | 36 | 7.162 |
| 40–90 m（居酒屋・寺子屋・後巷・農田邊・水車） | 11 | 0.539 |
| 90–150 m（丘的畑・南橋・神社外） | 4 | 0.088 |
| 150–260 m（森林・山腳） | 0 | 0 |

示意圖 `population_map.png`（紅＝核心 39、藍＝外圍 12、同心圓＝距市場核心 40／90／150／260 m）。

## 審圖（BEFORE＝核心 39／AFTER＝＋外圍 12；動作相位凍結）
| 圖 | Agent 自評（vision） |
|---|---|
| `R_walk_out_route.jpg`：從市集中心走到田邊／水渠的 5 個 TPS 站點，畫面可見 NPC 7 → 4 → 1 → 1 → 1 | **4/5**：熱鬧 → 安靜 → 稀疏但不空，密度下降明確；比較像「三段式」下降而非五段逐步 |
| `4_farm_mid.jpg` 稻架邊的農人 | 4/5：位置讀得出在田邊工作，稀疏；具體動作在這距離看不出 |
| `5_waterwheel.jpg` 水車邊的兩人 | 4/5：稀疏可信；左邊的人在畫面上和水車輪重疊、右邊的人和樹樁重疊（視覺擁擠，不是穿模） |
| `3_alley_well.jpg` 後巷井戶端的兩人 | 4/5：讀得出井戶端，不是人群；左邊的人離井的柱子很近 |
| `6_canal_south.jpg`／`7_farm_east.jpg`／`8_shrine_torii.jpg` | 各 1–2 人，稀疏 |
| `1_market_core.jpg`／`2_mouth_from_south.jpg` | 核心不變（BEFORE＝AFTER） |

原圖 `../render/`（1920×1080、Forward+、10:00）、可見人數 `../render/route_counts.json`。

## 技術驗證（`godot/tools/verify_village_v2_population_outer.gd`，tag OUTER）
- plan 14 項 0 失敗：人數 10–16 與各區範圍、區域框（森林・山腳不放）、**密度勾配（環密度單調下降）**、**外圍不成群**（6 m 內他人 ≤ 1）、anchor 不重複、職業、歩く人（婆婆 0、≤ 3）、同模型 ≥ 8 m、接地、capsule 對描畫三角形＋碰撞體、往返路、步速、封存 vocabulary、R3d 凍結＋子封存雜湊不變。
- 反向 13/13（count／zone／gradient／sparse／role／walk_rule／twin／body／anchor／path／ground／speed／vocab，各案必打中自己瞄準的項）。
- scene 6 項 0 失敗：掛載順（…EntranceCueP10 → OuterP10 → ActivityOuterP10）、人數 12／51、Activity 5 件、逐格 30 fps（與 R3c 同基準）、8 個審圖鏡位同模型 ≤ 2、歩く人 30 秒。
- 封存交叉（外圍掛載後）：R3d CORE seal、POP・ACT・NPCLIB・MKT・MW・STR・P9F seal、MMBAKE 全部 exit 0（`gate/cross_*.log`）。未重跑完整回歸。

## 界線
- 這是 Pilot：只證明「密度遞減」的語言；外圍的動作仍受封存庫限制（農人沒有真正的農作動作）。
- `population_map.png` 是示意圖（schematic），不是實景截圖。
