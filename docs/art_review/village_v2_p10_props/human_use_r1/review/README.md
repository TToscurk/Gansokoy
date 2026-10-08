# P10 R4 Human-Use / Ambient Life Pilot — ART_REVIEW

狀態：**ART_APPROVED・SEALED**（使用者 2026-10-08：Pilot A／B／C 全部通過；封存 `godot/data/village_v2_p10r4_seal.json`＋snapshot `village_v2_p10r4_snapshot.json`，`verify_village_v2_human_use.gd -- --seal`）。以下為送審時的紀錄（ART_REVIEW r4），內容未改。
`art_revision`＝P10 R4 Human-Use Pilot r4（ART_REVIEW）。overlay＝`HumanUseP10`（`gen/human_use_p10.scn`，掛在 village_v2 root 直下、緊接 `Props` 之後）。
不放進 `Props` 的原因：已封存的 R3b scene gate 以「完全一致」檢查 `Props` 子節點（Market→Street→MarketWest→Environment），放進去會讓該封存 gate FAIL；依「不重開任何 Population seal」改掛 root。若要回到 `Props` 底下，需使用者同意把該 gate 改成順序檢查並 reseal R3b。

## 這一輪做了什麼

把 NPC 全部藏起來後，場景本身要留下「有人長期在這裡生活、工作」的痕跡。不加 NPC、不動 R3b／R3d／R3e 封存人口、不開 schedule／對話、不重開 P8／P9、不改道路／建築／Market。

| Pilot | 位置 | cluster |
|---|---|---|
| **A 農田** | Bridge_03 過橋後的田側（R3e 農家 O1／O3／O8 的田） | A1 稻架列（田緣）・A2 脫穀／風選作業場（FarmPath_4 旁）・A3 田口（FarmPath_1×4 辻：農具掛＋載貨大八車＋一服） |
| **B 住宅後院** | MidLane 南、町家 4 戶的後院（市集北側，無 Hero） | B1 堆柴戶（MKT_030）・B2 內職戶（MKT_029，藁細工）・B3 有小孩的家（MKT_028，洗衣＋玩具）・B4 乾淨戶（RSW_072，隱居：掃帚・水甕・緣台・盆栽） |
| **C 水邊** | 北水車（村側岸）＋Bridge_03 北詰 | C1 羽根板修理（作業台・替板・梯子・道具箱・繩）・C2 搬來搗米的貨（貼著 R4-4 的臼與俵）・C3 水渠邊洗衣曬布 |

共 10 cluster、50 件。每件都帶 `who`／`why`／`anchor`（節點 meta `hu_who`／`hu_why`／`hu_anchor`），完整清單見 `gate/plan.json`。

## 資產：重用優先，只補缺件

- 重用既有 Kit 41 件（82 %）：street_kit（稲架・藁塚・農具掛け・藁細工・大工作業場）、market_kit（干し竿・甕・荷車）、school_kit（薪棚・手桶・天水桶・縁台・道具箱・輪回し・手毬・草履）、tower_kit（梯子・縄）、kiri_kit（只用汎用品：箒・縄・板材・大八車・桶・箱・菰包み；茸／奇石等 Hero 固有品由 gate 拒絕）、suzu_kit（腰掛け・鉢植え）、waterside_kit（俵）。
- 新增 `humanuse_kit` **6 件**（既有 Kit 裡真的沒有的生活語彙）：千歯扱き `hu_senba`、唐箕 `hu_tomi`、籾干し筵 `hu_momiboshi`、洗濯盥 `hu_tarai`、薪割り台 `hu_makiwari`、背負い籠（稲束）`hu_seoikago`。LOD0 278–450△、LOD1 各一；材質只用 V2_Wood＋ST_Street（無新 atlas）。生成：`godot/assets/blender/village_v2/build_humanuse_kit.py`。

## 審圖檔

`review/`（同一 TPS 機位三欄：**BEFORE**＝HU 關・NPC 開／**AFTER**＝HU＋NPC＝實際遊戲／**NPC OFF**＝只有 HU）

| 檔 | 內容 |
|---|---|
| `A_tps_near_5-10m.jpg` | A1／A2／A3，玩家到 cluster 約 6–9 m（鏡頭再後 3.6 m） |
| `A_tps_mid_10-15m_high_npc.jpg` | A_mid（橋東端→A1，約 14 m）・A_mid2（辻→A2，約 15 m）・A_high（高視角）・A_npc（村側橋頭，O8 入鏡） |
| `B_tps_near_5-10m.jpg` | B_near（B1–B3，約 8.5 m）・B_near2（B3，約 8.6 m）・B4_near（約 7.4 m） |
| `B_tps_mid_10-15m_high_npc.jpg` | B_mid（MidLane→後院，約 16 m）・B_high・B_npc（井戶端 O9／O10 入鏡） |
| `C_tps_near_5-10m.jpg` | C1_near（約 7 m）・C1_side（側面，背景是草地）・C3_near（約 7.4 m） |
| `C_tps_mid_10-15m_high_npc.jpg` | C_mid（約 17 m）・C_high・C_npc（沿岸望水車，O5／O6 入鏡） |
| `{A,B,C}_top_before_after.jpg` | 真上正射（12 px/m）BEFORE／AFTER |

原圖 `render/<view>_{before,after,npcoff}.png`；機位 `godot/tools/shot_p10_human_use_views.json`；撮影 `godot/tools/shot_p10_human_use.gd`（非 headless、Forward+、10:00）。

## Gate（同一版本，tag HUSE）

- plan 14 項＋反向 16＋build 回讀 3：`gate/plan_negatives_build.log`（MeadowP9 規劃株以同 seed 重算，不用快取）
- scene 11 項（root 直下 Props 之次・Props 子節點維持封存清單・個別節點・MultiMesh／Marker3D 0・Population 不變・**擺放驗證**：50 件 × 3×3 下射 ray 450 本 FLOATING 0、最大埋入 0.118 m；碰撞箱 39 個 collide_shape 貫通 0；float／clash 反向都抓到）：`gate/scene.log`
- 封存交叉回歸：`gate/regression_subset.log`（root 掛載後的 scene／seal／ENV plan／MMBAKE／PLACE／HUSE）。先前掛在 `Props` 底下跑的 47 項見 `gate/regression_subset_mount_under_props.log`（45/47：POP scene 因 Props 完全一致 FAIL → 已改掛 root；CORE scene 見下）。
- **既有問題（不是 R4 造成）**：R3d 的 `verify_village_v2_population_core.gd --scene` 要求 Population 總數＝39（R3b 16＋R3d 23），R3e 外圍 12 人掛上後是 51 → 自 R3e 掛載起就 FAIL。R3e 封存時只跑了各 `--seal`，沒跑 CORE scene，所以沒抓到。修正要改封存的 R3d gate（例如改成只數 R3b＋R3d 節點）並 reseal R3d，需使用者同意，本輪未動。

## 自評（vision，NPC OFF 可讀性 1–5，誠實列出）

| 視角 | 分 | 弱點 |
|---|---|---|
| A1_near | 3 | 稻架列讀得出，但只是田緣一處，小件看不見 |
| A2_near | 4 | 兩張籾干し筵連成作業床後最清楚；兩張筵之間有接縫 |
| A3_near | 3 | 載貨大八車最清楚；蓑、俵當座位、繩讀不出 |
| A_high | 4 | 田緣稻架／路旁作業場／田口的依附關係清楚 |
| B_near | 4 | 藁塚（材料）＋洗衣把戶別分開 |
| B_near2／B4_near | 3 | 盆栽、水甕、掃帚太小；乾淨戶本來就東西少 |
| C1_near／C1_side | 4 | 修理點成一組；道具箱、繩太小 |
| C3_near | 4 | 洗衣曬布最清楚 |
| C_mid | 3 | 15 m 時小件融進水車暗部 |
| C_high | 3–4 | 三組分得開 |
| C_npc | 4 | 實際遊戲鏡頭，NPC 關掉仍讀得出「有人用」 |

BEFORE→AFTER 在 5–10 m 屬明顯變化（尤其 A2、B_near、C3、C_npc）；10–15 m 的 C_mid、B_near2 只是中等變化。

## 已知限制（記錄、未處理）

- 田埂反覆踩踏的地面痕跡：地面層是 P9 R5 封存的 Macro Ground，本輪沒碰；A2 改用兩張筵當作業床。
- 小件（繩、蓑、手毬、草履）在 10 m 以上讀不出，只當近景點綴；主要可讀性靠中型輪廓。
- A3 的載貨大八車重用 market_kit 的 `mk_kuruma_ni`（俵＋南瓜＋籠）。
- NPC 沒和道具互動（不新增 NPC 或動作）。

## 下一步

STOP，等使用者裁定。若三個 Pilot 都通過，再訂全村 Human-Use Expansion 規則；若判 FAIL，不進入 batch。

## 使用者裁定（2026-10-08）

- **ART_APPROVED**：A 農田（脫穀、曬穀、搬運形成完整工作流程）／B 住宅後巷（四戶不同生活習慣，沒有平均堆雜物）／C 水岸（水車維修、米俵搬運、洗衣形成具體用水關係）。
- Non-blocking：B 側面可讀性較弱、C 在 15 m 約 3/5。未來擴張以玩家常走的方向優先安排主要生活物件，不必每個角度都磨到 5/5。
- 值得保留的是 10 個有用途的工作群組，不是 50 件的數量。
- 掛載：維持 root 直下、Props 之次（獨立 overlay，不為節點分類 reseal R3b）。
- R3d 人數檢查＝驗證器設計錯誤 → 已修成 scope-aware（R3d 39／R3e 12／村 51，R3d 單獨仍驗 39；多一人／少一人／身份重複反向），R3d／R3e limited reseal（`reseal_history` 記前後雜湊）。
- 全村擴張規則：不平均加道具；農田依生產與運輸動線、住宅依每戶差異、水岸依水源用途；核心商業區已有大量 P10 Props，不再重複堆放。
