# P10 R4b Human-Use Expansion Batch 1 — A/B FINAL（2026-10-08）

**狀態：A 農田・B 住宅＝ART_APPROVED・SEALED（A/B FINAL）／C 水岸＝ART_REJECTED（正式配置から除去）。** 封存 `godot/data/village_v2_p10r4b_seal.json`。

## 最終裁定（使用者 2026-10-08「P10 R4b Batch 1 — Final Art Decision」）
- A Farmland：ART_APPROVED／B Residential：ART_APPROVED／C Waterside：ART_REJECTED。
- 中距離 2/5 の 4 群（XA2 農具置き場・XA5 一服・XB2 桶直し・XB5 漬物）：ACCEPTED / NON-BLOCKING（secondary ambient detail）。
- 第四次の美術反復なし。A/B 10 群の位置・用途・物件配置は変更しない；評分のために物件を足さない。
- C 3 群（XC1 洗菜・XC2 換橋板・XC3 清淤）は正式生成から除去。理由（封存に記録）：
  > Three iterations failed to establish readable waterside activities. Existing R4 Pilot C already provides sufficient waterside human-use evidence. Additional expansion was removed to preserve natural negative space.
- C の設計は `village_v2_human_use_exp_lib.gd::rejected_c()` に rejected candidate として記録だけ残す（正式の design／plan／bake は出力しない）。XC3 専用の新規 `hx_doroage` も kit に残すが配置しない。曬漁網・曬布架などの代替は足さない。R4 Pilot C（封存）は不変。

## 正式構成（C 除去後の実測）
- **10 群 40 件**（A 農田 5 群 22 件・B 住宅 5 群 18 件、C 0）；重用 37／40（93 %）、新規の配置は `hx_hatake`×2・`hx_daikon_kake`×1。
- 計画 40 件＝承認時 r3 の A/B 40 件と完全一致（id・zone・cluster・anchor・who・why・位置・朝向；`gate/plan_final.json` vs `gate/plan_r3.json`）。
- 再撮影（A/B 31 視點×3 状態、`gate/ab_final_vs_r3.json`）：BEFORE（擴張なし）の差＝run 間の揺れ（風・NPC idle）を基準にすると、超過は XA4_oroshi high 0.20 %・near 0.11 %（背景の XC3 が消えた所、XA4 の荷車と荷の山は不変）と XB3_hatake near 0.05 %（植え込みの揺れ）だけ。
- scene（`gate/scene_final.log`）11 項 PASS：Props → HumanUseP10 → HumanUseExpansionP10・正式構成 10 群／C 0／ZoneC なし・R4 の 50 件 snapshot ≤ 1 cm・Population 51・接地 360 ray（FLOATING 0、最大埋まり 0.110 m）・貫通 0・float／clash 反向。
- plan（`gate/plan_final.log`）：正式構成・計画＝封存 snapshot・MeadowP9 株 0・禁區・非均一・自然の岸ほか＋反向 19（rejected_c() を戻す／hx_doroage を置く／B を 1 群減らす を含む）。
- 以下の「範圍」以降は **r3 審圖時の記録**（13 群 53 件、C を含む）。`render/XC*`・`review/XC*`・`review/zoneC_*` は rejected candidates として封存に記録。`review/npc_on_off.jpg`・`review/distribution.jpg` は r3 の記録（C を含む）。

---

# （記録）r3 ART_REVIEW（2026-10-08）

## 範圍
- 新 overlay：場景 root 直下 `HumanUseExpansionP10`（`HumanUseP10` の次）＝`godot/maps/village_v2/gen/human_use_exp_p10.scn`
  - generator：`godot/tools/village_v2_human_use_exp_lib.gd`（R4 封存 lib を只讀で使い、禁區を追加）
  - gate：`godot/tools/verify_village_v2_human_use_exp.gd`（tag HUX：plan 13 項＋反向 16＋build 回讀＋scene 10 項）
  - 撮影：`godot/tools/shot_p10_human_use_exp.gd`＋`shot_p10_human_use_exp_views.json`（41 視點）、シート `tools/sheet_p10_r4b.py`
- 13 群・53 件（A 農田 5・B 住宅 5・C 水岸 3）。NPC・人口路線・anchors・P8／P9・R4 の 50 件は不変。

## 群（誰が・何をしている所か）
| 群 | 依附 | 中身 | 用途 |
|---|---|---|---|
| XA1_shukka | FarmPath_2×4 の辻 | 積みかけの大八車・次の 3 俵・俵の台・縄 | 出荷：俵を車に積む途中 |
| XA2_teire | FarmPath_1×5 の辻 | 農具掛け 2・馬の作業台・柄の材・腰掛け | 組の農具置き場と柄の付け替え |
| XA3_hasa | FarmPath_4 東の田の北縁 | 稲架 3 架の列・柴垣・藁塚 | 稲干し |
| XA4_oroshi | Bridge_04 田側の橋詰め | 空の大八車・降ろした荷の山・背負い籠・菰包み | 村から運んで降ろした所 |
| XA5_yasumi | FarmPath_2×5 の辻 | 藁塚・縁台・下ろした背負い籠・手桶 | 田の合間の一服 |
| XB1_some | RSW_048 の裏 | 反物の掛け（藍・絣）・盥・甕・腰掛け | 染め物の内職 |
| XB2_okeya | RSW_051 の裏 | 桶屋の作業場・直し待ちの盥・直した手桶の台・道具箱 | 近所の桶・盥の直し |
| XB3_hatake | RNE_005 の裏 | 畝 2（大根・葱・青菜）・柴垣 | 家庭菜園 |
| XB4_nizukuri | RNE_003 の裏 | 荷積み・半分積んだ大八車・菰包み・縄 | 荷造り（出荷か引っ越し） |
| XB5_tsukemono | RSW_033 の裏 | 大根干し・漬物樽の筵・腰掛け | 冬の漬物（沢庵） |
| XC1_araimono | 北の雁木石段 | 泥付きの箱と籠 → 盥 → 洗った野菜の筵 | 野菜洗い |
| XC2_hashi | Bridge_05 東の橋詰め | 馬の作業台・新しい橋板・外した古板・梯子・縄 | 橋板の張り替え |
| XC3_suiro | 南の水車の下手の東岸 | 泥上げの山（鋤）・土嚢 2・熊手の掛け・手桶の台 | 水路の泥上げ |

## 資產（新規 vs 重用）
- 53 件中 **49 件（92 %）が既存 Kit の重用**：street_kit 15・kiri_kit 12（汎用品のみ許可制）・market_kit 7・humanuse_kit（R4）4・school 3・suzu 3・tower 3・mise 1・waterside 1。
- **新規 `humanuse_exp_kit`（缺件 3 種、材質は V2_Wood／ST_Street だけ、新 atlas なし）**：
  - `hx_hatake` 家庭菜園の畝（714△）— 住宅の「小型家庭菜園」に該当する物が既存に無い
  - `hx_daikon_kake` 大根干し（732△）— `mk_hoshimono` は布の干し竿で、大根には使えない（r1 で誤用 → 修正）
  - `hx_doroage` 泥上げの山（110△）— 水路を手入れした「理由」が見える物が既存に無い
- 桶・箱・籠・箒・縄は新規に作っていない。

## 審圖（render/ 125 枚、review/ シート）
- `review/<群>.jpg`：行＝near（相機→群 5–10 m）／mid（10–15 m）／high（俯瞰）、列＝BEFORE（擴張なし）／AFTER（NPC あり＝実際の遊戲）／NPC OFF
- `review/zone{A,B,C}_overview_npcoff.jpg`（near）・`zone{A,B,C}_overview_mid_npcoff.jpg`（mid）：區の中の重複・平均化を見る
- `review/npc_on_off.jpg`：NPC が実際に立つ所から（A＝XA4、C＝XC3；外圍の O7 が手前に座る）
- `review/distribution.jpg`：村の真上 3 px/m、R4（青）と R4b（橙）
- 距離の定義：**相機から群の中心まで**（R4 の「玩家から」より 3.6 m 近い側＝厳しめ）

## 自己評価（vision、NPC OFF；判定は使用者）
| 群 | 5–10 m | 10–15 m | 所見 |
|---|---|---|---|
| XA1 出荷 | 3 | 3 | 積んだ車は読めるが「積み込み途中」は弱い |
| XA2 農具置き場 | 3 | **2** | near は農具置き場、mid は小さな暗い塊 |
| XA3 稲架 | **5** | **5** | 一番強い |
| XA4 降ろした荷 | 3 | 4 | 車と荷の山は読める |
| XA5 一服 | 3 | **2** | 藁塚は読めるが、縁台が日陰の休み場に見えない |
| XB1 染め物 | 4 | 4 | 布の掛けが強い（染めか洗濯かは曖昧） |
| XB2 桶直し | 3 | **2** | 低く暗い；「直し」より「桶の置き場」 |
| XB3 菜園 | 5 | 3 | near は一目で畑 |
| XB4 荷造り | 5 | 4 | 大八車が強い |
| XB5 漬物 | 4 | **2** | 大根干しは near で読める、mid は細い；相機の右に壁 |
| XC1 野菜洗い | **2** | **2** | 「水辺の荷」止まり |
| XC2 橋板張り替え | **2** | **2** | 「橋のそばの大工仕事」止まり（橋そのものは封存で触れない） |
| XC3 泥上げ | **2** | **1** | 水車と橋に負ける；泥の山が暗い塊 |

**率直な判定**
- A 農田・B 住宅：主要群（XA3・XA4・XB1・XB3・XB4）は 5–10 m で明確、10–15 m でも輪郭が残る。XA2・XA5・XB2・XB5 は mid で 2＝「静かな次要群」としてなら成立、主要群としては弱い。
- **C 水岸：基準未達。** 3 回の構成変更（r1→r3、泥上げの新規 1 件含む）でも mid 1–2。水車・橋・石垣の大きな輪郭に対して、低い作業物が負ける。R4 Pilot C（水車の修理・洗濯）は 4 だったが、そこは干した布と梯子という高い輪郭があった。
- 重複：住宅 5 戸の組成類似度 最大 0.17（gate ≤ 0.34）、vision も「コピペの戸なし」。R4 の脫穀一式の再利用なし。
- 過密：なし（13 群は辻・裏・岸の具体的な場所に一つずつ、核心商業區には 0）。XA4 と XC3 が約 20 m で一番近い（橋と水車の別の用途）。
- 用途不明：XC1・XC2・XC3（上記）、XB2 の mid。
- NPC：R4b の件から一番近い NPC まで 16.7 m、群の中心からは 20–195 m（外圍人口が意図的に疎）。だから大半の視點で AFTER と NPC OFF はほぼ同じ。住宅 5 戸は 60 m 以内に NPC なし（人口は封存で動かさない）。

## 技術 gate（同じ版）
- plan 13 項 PASS・反向 16 PASS・build 回讀（53 件・MeshInstance 106・碰撞 44・MultiMesh 0・Marker3D 0）
- scene 10 項 PASS：root 掛載順・Props の子は封存どおり・R4 の 50 件 snapshot 位置 ≤ 1 cm・Population 51 不変・接地 477 ray（53 件×9、FLOATING 0、最大埋まり 0.110 m）・貫通 0・float／clash 反向
- 禁區：R4 の全禁區＋核心商業區（市場中心 r 45 m・P10 構件 +4 m）＋R4 の 50 件 +0.5 m・Pilot 区 +3 m；MeadowP9 株 0；EnvironmentP9 錨から ≥ 12.7 m；NPC の立ち位置から ≥ 16.7 m
- 接地＝見えている最上面（地形・路面・P4 院子・P8・封存 overlay の地面 decal の max）
- 自然の岸：水面の縁 460 格のうち R4＋R4b の生活痕跡から 6 m 以内 11 格（2 %）
- R4 HUSE `--scene`／`--seal` 0 失敗（擴張を掛けた状態）・回歸 subset：`gate/regression_subset.log`

## 未決（r3 時点）→ 使用者裁定で解決
1. C 水岸 3 群 → ART_REJECTED・除去（上の最終裁定）。
2. XA2・XA5・XB2・XB5 の mid 2 → ACCEPTED / NON-BLOCKING。
