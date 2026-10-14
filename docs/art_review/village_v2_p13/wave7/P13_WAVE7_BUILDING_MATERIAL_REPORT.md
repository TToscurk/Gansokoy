# P13 WAVE 7 — 町家材質拡張＆視覚クロージャ 報告（ART_REVIEW）

日付：2026-10-14　世界：Village V2　基準：W6 `ce37a40`／`db98a55`（技術有條件接受・ART_REVIEW 維持）
狀態：**ART_REVIEW 提出**。ART_APPROVED は使用者のみ。本輪は第一批 50 棟で止め、次の 50 棟は着手しない。

> 圖の讀み方：下の「自評」は私が畫像解析ツールで見た所見で、使用者の ART 判斷の代わりではない。數字（輝度・件數・gate）は實測。

---

## 0. 結論（先に）

| TASK | 結果 | 備考 |
|---|---|---|
| 1 RoadEdgeBlend | 完成。6 道の `edge_w` を指示どおり變更、CrossStreetMid 不變、幾何／碰撞／RoadBase 不變 | 路面は 7 鏡位すべてで明瞭、差分は路縁にだけ集中 |
| 2 Farmland V 形直邊 | 完成（局部）。**5 頂點**の COLOR.r＋UV2.y だけを変更 | 上方俯瞰では直線の V が消える／TPS では差が小さい |
| 3 EarthBanks 亮度 | 完成。共用材質は EarthBanks 220 件専用と実測で確認 → 複製材質で `ground_k 0.304→0.21` | 田埂 vs 周辺 luma 比 中央値 **1.196 → 1.044**、周辺地面は 85.5→85.5 |
| 4 DrapeFixP13 コスト | 一次比較済。**フレーム差 −0.07…+0.03 ms（雜音以内）**、draw call ±3、overlay 5.8 MB／load 4.6 ms | 視覺改善に対して不均衡ではない → 報告のみ・再構築せず |
| 5 第一批 50 棟 | 完成。主街 39・Pilot 24 と**重複 0**、全て machiya_kit、新規材質 0、新規 geometry 0 | **途中で LOD1/2 屋根の増光を発見し、batch だけ屋根を不覆寫に修正**（§5.4） |
| 6 丘腳社寺 | 盤點のみ。**12 面の灰盒 1 個（18×9×12 m・材質なし）**。施工なし | 正式参考待ち |

主な發見（要判斷）：
1. **K 版アトラスは LOD1/2 の屋根瓦まで ×1.74 に増光する**（batch 實測）。batch は屋根部品を不覆寫にして解消。**R6a Pilot 24 棟は同じ仕組みのまま**（變更せず・§5.4）。
2. **LOD の hysteresis（fade=DISABLED＋margin 4 m）で、テレポート直後は境界帶の物が見えなくなる**（南大門鳥居が 61.7 m で消える）。W7 の變更とは無關・既存の性質（§7.3）。
3. 遠景は **未校正 77 棟（41 %）が殘る**ため、校正済みと混在して「拼貼感」が出る（自評 +1）。

---

## 1. 道路と農田の材質修正（TASK 1–3）

### 1.1 RoadEdgeBlend（TASK 1）
`tools/p13/w6/build_w6_road_edge.gd` の 6 値だけを變更し `gen/road_edge_blend_p13.scn` を再生成（RoadBase は再製作せず、material だけ差替）。

| 道 | edge_w（W6 → W7） |
|---|---|
| FarmPath_2／3／5 | 0.40 → **0.30** |
| EntranceRoad／HillFootStreet／RiverNorthPath | 0.55 → **0.40** |
| CrossStreetMid | 0.55（**不變**・對照） |

他のパラメータ差は 7 道すべて 0（`evidence/edge_w_table.txt`）。`verify_w6_cleanup.gd` の期待値も同步（`--negatives` 付きで 29 PASS／0 FAIL）。
**畫面**：`compare/T1_roads_A_farmpaths_2_3_5.png`、`T1_roads_B_hillfoot_entrance_rivernorth.png`、`T1_roads_C_crossstreetmid_unchanged_control.png`（各列＝BEFORE｜AFTER｜DIFF×4、**同一ハーネス・同一鏡位**、BEFORE は W6 版 overlay を差替えて撮影）。
自評：7 鏡位すべてで路面は明瞭に讀める；差分は路縁の細い帶に集中（路中央・建物・遠景は雜音レベル）；縁は自然な不規則さを保ち直線硬邊にならない；新しい異常なし。路面の「完整さ」の増分は肉眼では小さい（DIFF でようやく確認できる程度）。

### 1.2 FarmlandTerrain の V 形直邊（TASK 2）
- **原因（W7 實測・作業仮説）**：CrossStreetMid の ribbon は道高＋0.10 m の平帯。FarmPath_1 入口（x≈368–372, z≈−34…−32）で P1 地形の台座（66 cm）が ribbon 面と 0–2 cm まで寄り、地形三角形が南縁から約 3 m×1.3 m の楔として露出 → 踏み固め土（暗い赤褐）が街の路面（淺い米黃）に刺さり、2 本の直線で囲まれた V になる。
- **修正**：`FarmJunctionFixP13`（`scripts_p13/farm_junction_fix.gd`・子ノード 0）。RoadBaseP10 が差替えた `Terrain/FarmlandTerrain.mesh` の**複製**に対し、**5 頂點**（x＝366／368／370／372／374, z＝−34）の **COLOR.r と UV2.y だけ**を変更：

  | x | COLOR.r | UV2.y（街の路面重み） |
  |---|--:|--:|
  | 366／374 | 0.35 | 0.55 |
  | 368／370／372 | 0.0 | 1.0 |

  頂點位置・index・法線・UV・UV2.x・COLOR.gba は全 13,703 頂點で不變（gate が RoadBase の mesh と逐頂點比較）。P1 幾何・田塊範囲・農道・水渠高程・地形碰撞は不變。`enabled=false` で RoadBase の mesh に戻る。
- **封存**：RDB 場景 gate が地形 mesh 名 `RoadBase_FarmlandTerrain` を固定要求していたため、**R5a limited reseal**（`verify_village_v2_road_base.gd` の 1 檢查＋ frozen 雜湊 1 件だけ。root に `FarmJunctionFixP13` があり applied>0 のときに限り `FarmJunctionFix_FarmlandTerrain` を許可。歷史 kind `W7_RDB_SCENE_GATE_ACCEPT_JUNCTION_FIX_MESH`）。農田全體の再 bake なし。
- **畫面**：`compare/T2_farm_junction_vwedge.png`（上＝俯瞰×2 の BEFORE｜AFTER｜DIFF×6、下＝TPS）。
  自評：俯瞰では **BEFORE の「^」形の直邊三角形が AFTER で消え**、不規則な草土の境になる；DIFF は路口の橫帶に集中；TPS の目線では差が小さい（楔が薄いため）；新しい方塊・暈・黑斑なし。

### 1.3 P8 EarthBanks 亮度（TASK 3）
- **共用調査**（`evidence/earth_materials.json`＋gate）：元の共用材質（`farmland_p8.scn::ShaderMaterial_ko36i`, `ground_k=0.304`）の使用者は **EarthBanks 220 件ちょうど**、外部の使用者 0 → 「他區域も一緒に變わる」ことはないため、指示に従い實施。
- **方法**：`EarthBankToneP13`（`scripts_p13/earth_bank_tone.gd`・子ノード 0）。材質を**複製**して `ground_k` だけ変更、EarthBanks 220 件の `material_override` にだけ差替。元の共用材質は 0.304 のまま（`enabled=false` で復元を gate が確認）。shader・他の uniform は元と同一。水利の幾何・水面・坡降・碰撞・伏越し・竜骨車・P8 ファイルは不變。
- **値の選定**：目標 0.19 に完全に揃えると畦が草地に溶けるため、**0.21**（0.26→0.21 と 2 回見て決定）。實測（ID パスで畦と周辺地面を分離・26 鏡位）：

  | | BEFORE | AFTER |
  |---|--:|--:|
  | 田埂 luma（中央値） | 101.5 | 89.0 |
  | 周辺地面 luma（中央値） | 85.5 | 85.5 |
  | 田埂／周辺 比（中央値） | **1.196** | **1.044** |

- **畫面**：`compare/T3_earthbanks_brightness.png`（BEFORE｜AFTER｜DIFF×3）。自評：BEFORE は白灰の帶が「貼ってある」ように浮く／AFTER は沈んだ灰褐で周辺と馴染み、輪郭・連續性・紋理は保つ；周辺地面の luma 不變。
- **P8 局部 gate**：P1 保護／P8 local gate／P8 `--seal`／P8 永久反向／P8 田埂・水面擺放稽核 すべて PASS（P8 ファイルは 1 つも變更していない）。FEEDER／ZONE／COST は水理・碰撞・性能を變えていないため未實行。

---

## 2. DrapeFixP13 の一次コスト比較（TASK 4）

通常のゲーム経路（`main.tscn → ReviewStart → village_v2`、實プレイヤー＋TPS、10:00、Forward+、1600×900、vsync off・max_fps 0、`tools/p13/w7/w7_perf.gd`）。各鏡位で ON,OFF,ON,OFF を 1 周（暖機 40＋測定 100 幀の中央値）。多輪負荷試験はしていない。

| 鏡位 | Δ frame ms | Δ GPU ms | Δ CPU ms | Δ draw | Δ 三角形 | 備考（ON の絕對値） |
|---|--:|--:|--:|--:|--:|---|
| 参道（低） | −0.035 | +0.026 | +0.018 | 0 | 0 | 13.5 ms・6.39 M |
| 参道（高） | −0.032 | +0.126 | −0.296 | 0 | 0 | 16.6 ms・8.55 M |
| 水車岸 | +0.032 | −0.002 | +0.001 | +2 | +512 | 10.6 ms・4.56 M |
| 主街 | −0.067 | −0.297 | +0.004 | −3 | −9,145 | 10.9 ms・5.98 M |
| 農道 3 | −0.062 | +0.020 | −0.008 | 0 | 0 | 10.6 ms・3.82 M |

- ON/OFF の run-to-run 雜音は 0.004–0.34 ms で、**差は雜音以內**。DrapeFix は既存 overlay の mesh を**差替える**ので draw call／可視三角形は増えない（40 mesh／194,360 三角形は同時に二重描畫されない）。
- **載入**：overlay ファイル 5.81 MB、`load` 4.6 ms、`apply` 0.31 ms。P1 base 場景載入 gate は 3,947 ms（W6 の 3,856–3,972 ms と同水準）。
- 判定：コストは視覺改善（W6 報告：overlay の地形への沈み 最大 25.6 cm を解消、NorthHill の穿出し 3.25 %→1.19 %）に對して**不均衡ではない**。再構築は不要。生データ `evidence/drapefix_perf.json`。

---

## 3. 第一批 50 棟（TASK 5）

### 3.1 事前確認
`inventory_priority_batches.json` batch1 を、當日の場景から作り直した盤點（`evidence/inventory_187.json`、187 棟）と照合：

| 檢査 | 結果 |
|---|---|
| W2 主街 39 棟と重複 | **0** |
| R6a Pilot 24 棟と重複 | **0** |
| ID の重複 | 0 |
| Kit | 50 棟すべて `machiya_kit`（町家 Kit） |
| 區と用途 | Market＋MixedCommercial 24 棟＝商業（調色盤 A）／ResidentialWest＋ResidentialNE 26 棟＝住宅（調色盤 B） |
| 近鄰の同色 | Pilot∪batch 74 棟の全対で、14 m 內・同區・同組なし |

### 3.2 施工内容
- **材質のみ**。R6a 登記済み 18 變体のうち **14 種**を再利用（新材質 0・新 atlas 0・新 geometry 0・overlay の子ノード 0）。漆喰・木の變体は名簿（`data/village_v2_p13w7_batch1.json`）に建物ごとに記録、基底材質の hash 起點＋近鄰回避で決定的に割當。
- 覆寫は建物ノード全體の surface override：Kit（LOD0／1／2）3,925 面＋Frontage（fr_*）1,571 面＝**5,496 面**。**Kawara（LOD0 屋根瓦）は不校正**。
- 掛載：`AlbedoBatch1P13`（`scripts_p13/albedo_batch.gd`）を `EarthBankToneP13`／`FarmJunctionFixP13` と共に root 末尾に掛載（順序 `RoadEdgeBlendP13 → EarthBankToneP13 → FarmJunctionFixP13 → AlbedoBatch1P13`）。batch は W2 主街 39 棟を含まない。範囲外（Pilot 24＋batch 50 以外）の町家には登記變体の覆寫が 0（gate が全 187 棟で確認・うち主街 36 棟）。

### 3.3 50 棟の ID（全表＝`evidence/batch1_buildings.md`）
- **Market（16）**：MKT_032 034 035 037 038 039 040 041 042 043 049 053 055 058 059 060
- **MixedCommercial（8）**：MXC_009 010 013 014 015 018 019 023
- **ResidentialNE（5）**：RNE_001 002 007 010 012
- **ResidentialWest（21）**：RSW_007 010 017 022 023 027 029 033 034 036 045 046 048 059 071 072 073 074 075 076 077
（`B_P_` 接頭辞省略。道＝CrossStreetMid／CrossStreetSouth／WestAlley／MidLane／HillFootStreet／RiverNorthPath／NELane／NENorth／NESouth／NWLane／WestBankLane／SWLane）

### 3.4 途中で發見・修正した問題（LOD1/2 の屋根）
最初の版は Pilot と同じ仕組み（アトラス → `V2_MachiyaKit_K` を全 LOD）でした。LOD を強制表示して ID パスで部品別に輝度を測ると：

| batch の屋根系 輝度（sRGB luma） | LOD0 | LOD1 | LOD2 |
|---|--:|--:|--:|
| 最初の版の測定：BEFORE | 46.5 | 70.7 | 70.8 |
| 最初の版の測定：AFTER | 55.9 | **122.7**（×1.74） | **122.9**（×1.74） |
| 修正後の測定：BEFORE | 47.1 | 84.3 | 84.4 |
| 修正後の測定：AFTER | 55.8 | **84.8**（×1.01） | **84.9**（×1.01） |

※ 2 回の測定は屋根の部品分類が違う（最初＝`l_rh_t` のみ、修正後＝`l_rh_*` 全部）ので、行をまたいだ比較はせず、**それぞれの BEFORE との比**で見ること。LOD0 の屋根は Wood の部品を含み、變体木で明るくなる分（+9）が出る。

原因：LOD1／2 の屋根 `l_rh_*`（250 部品）は Kawara ではなく**アトラス**で描かれ、`kit_cal.gdshader` が暗部を k_dark 0.75（元は 0.42）にして屋根瓦まで ×1.74 に増光する。結果、遠景で「LOD0 の黑瓦より 2 倍明るい屋根」が壁と同色化した。
**修正**：batch だけ `l_rh_*` を覆寫しない（`albedo_batch.gd` の `skip_prefixes=["l_rh_"]`、200 面）。屋根は未校正アトラスのまま（主街 W2 と同じ仕組み）。壁・木・窓（`l_box_*`／`l_f*`／`l_slab_*`／`l_u_*`）は K 版のまま。gate に反向 N8（屋根に K を入れると FAIL）を追加。
※ 封存済み `albedo_pilot.gd` は變更せず、同じ仕組みの複製 `albedo_batch.gd`＋skip 1 點にした。

---

## 4. LOD0／LOD1／LOD2 材質検査（要求 4）

### 4.1 gate（`verify_w7_cleanup.gd`・61 項 PASS／0 FAIL／反向 8/8）
50 棟 × **建物ノード全體**（Kit の LOD0／1／2 全面＋Frontage）を材質まで逐面で讀み戻し：
- 漆喰・木・石・アトラスが期待どおりの**登記變体**（LOD0／1／2 で同じ變体）
- Kawara 不校正、LOD1／2 の屋根 `l_rh_*` は未校正アトラスのまま、登記變体の `material_override` なし
- overlay の覆寫 5,496／不覆寫 200 面が、名簿から**独立に數えた値**と一致
- LOD0 → LOD1/2 の輝度差（變体 luma と atlas k の差）：漆喰 ≤ 0.08（最大 0.017）、木 ≤ 0.10（最大 0.079）

### 4.2 強制 LOD の實描畫（`compare/T5_LOD_forced_{mkt,rsw,mxc}.png`、上＝BEFORE の L0|L1|L2、下＝AFTER）
全町家を LOD0／1／2 の 1 つだけにして同一鏡位で撮影（距離切替・hysteresis に依存しない）。ID パスで batch の壁系・屋根系を分けて平均（3 鏡位合算、`evidence/lod_color.json`）：

| batch の壁系 luma | LOD0 | LOD1 | LOD2 |
|---|--:|--:|--:|
| BEFORE | 57.7 | 83.0 | 92.3 |
| AFTER | 105.0 | 144.0 | 162.8 |
| 比 L1/L0, L2/L0（BEFORE→AFTER） | | 1.44→1.37 | 1.60→1.55 |

- 3 つの LOD とも **BEFORE より ×1.7–1.8 明るく、LOD 間の比は BEFORE と同等かわずかに小さい**（主街 W2＝1.56／1.87）。「遠距離 LOD が灰色に戻る」現象はない。
- 屋根系：LOD1/2 は BEFORE と同じ暗さ（84.3→84.8）、牆との對比を保つ。
- **未解決の性質（Pilot から継承）**：LOD0 の牆は暖かい米白（R−B ≈ +21）、LOD1/2 は共通アトラスで中性〜やや冷たい灰白（R−B ≈ −6）。切替距離（40 m／110 m）で色相が少し跳ぶ。全建物が 1 枚の共通アトラスを使うため、LOD1/2 には棟ごとの個性が出ない。直すには「調色盤ごとの LOD1/2 アトラス變体」が要り、本輪（新材質なし）の範囲外 → 後続で判斷してください。

---

## 5. 代表的な Before／After（要求 5）

`docs/art_review/village_v2_p13/wave7/compare/`（BEFORE は同一ハーネスの BEFORE 版）：

| ファイル | 内容 | 自評 |
|---|---|---|
| `T5_batch1_A_market_mkt_mid_south_hill.png` | 市集 CrossStreetMid／CrossStreetSouth／丘腳通り | +1：一部が明るい米白へ、暖色の層が増える；近景の影の中の建物は變化が小さい |
| `T5_batch1_B_residential_mid_nw_ne.png` | 西住宅 MidLane／NWLane／東北 NELane | +1：漆喰が明るくなり木構との分離が出る；住宅は素で灰味を保つ、瓦は黑のまま |
| `T5_batch1_C_residential_bank_alley.png` | 西岸 WestBankLane／西窄巷 | +1：上段は變化大、下段はほぼ原狀 |
| `T5_batch1_D_far_views_LOD1_LOD2.png` | 遠景（50–130 m・LOD1/2 主體）3 鏡位 | +1：牆が明るくなり、屋根の對比は保たれる；校正済みと未校正の「拼貼感」が輕〜中度 |
| `T5_LOD_forced_*.png` | §4.2 | — |

全畫面で過曝・螢光・貼圖錯位・突兀な單棟は見つからなかった。

---

## 6. 未校正の建物と丘腳社寺（要求 6）

- **未校正 77 棟**（187 − 主街 39 − Pilot 24〔主街重複 3〕− 第一批 50）：ResidentialWest 48／ResidentialNE 14／MixedCommercial 8／Market 7。ID 一覧＝`evidence/uncorrected_buildings.md`。校正済みは 110 棟（59 %）。
- **構造差異化 backlog**（登記のみ・施工なし、`evidence/structure_differentiation_backlog.md`）：完全に同一形狀の組は **0**。外形枠（型・屋根・幅奥行 ±0.5 m・軒高 ±0.3 m）が 25 m 以內で重なる近鄰ペアが **4 組**（MKT_032–MKT_058、MKT_032–RSW_003、MXC_015–MXC_020、RSW_005–RSW_077；LOD0 の細部は異なる）。
- **丘腳社寺**（`LANDMARK_HILLFOOT_TEMPLE`）：位置 (228, 1.2, −170)、**單一 MeshInstance・12 三角形・18×9×12 m の箱・材質 null・meta `placeholder`**。畫面占有率は丘腳の見渡しで約 1–7 %（鏡位による）。`compare/T6_HillFoot_temple_greybox_status.png`。正式参考畫像が來るまで**何も施工しない**。

---

## 7. Git・封存・gate・技術債（要求 7）

### 7.1 gate（局部のみ・全村長距離実走なし）
最終状態で再實行（`evidence/gates/*.log`）：

| 群 | 結果 |
|---|---|
| W7 gate（61 項）＋反向 8 | PASS |
| W6 gate（TASK 1 の edge_w 含む）＋反向 | PASS |
| R5a：RDB plan＋反向 5／`--scene`／`--seal`、GRD `--seal` | PASS |
| R6a：ALB plan／`--scene`／`--seal`、KITM、Kit gate `--regress`（187 棟）、Kit 反向 4 | PASS |
| P8／P1：P1 保護、P8 local gate、P8 `--seal`、P8 永久反向、P8 擺放稽核、GRD plan＋反向 7、GRD `--scene` | PASS |
| P13 参道：`verify_w4_pilot`、`verify_w5b_integration`、`verify_w5c_transition` | PASS（W7 は参道ファイルを一切觸っていない） |
| `verify_w5a_sample`（歷史的サンプル gate） | 4 FAIL＝W5B で範囲が延びたため G1 範囲檢查が成立しない既存の状態（W5B／W5C gate が現行） |
| TERRAIN gate | 既知の FAIL：P1 base 載入 3,947 ms > 3,000 ms（P12 技術債・不變） |

**本輪で gate を直した點**（いずれも反向テスト付き）：
- RDB 場景 gate：派生地形 mesh 名を許可（R5a limited reseal）。
- Kit gate／KITM K5／ALB 場景 gate：「Pilot 外に覆寫なし」を、**名簿の sha256 が封存 frozen の値と一致するときだけ**名簿の建物にも許可。ALB の「enabled=false → 覆寫全部還原」は batch 分を除外（別 overlay の責任）。
- 名簿が封存と違う／封存がない場合は従来どおり全て FAIL（永久反向 4 は PASS のまま）。

### 7.2 封存（limited reseal・`tools/p13/w7/reseal_limited.py`）
- **R5a**（`data/village_v2_p10r5a_seal.json`）：更新した frozen は `verify_village_v2_road_base.gd` の 1 件のみ。他の 16 件は先に封存時と一致を確認。
- **R6a**（`data/village_v2_p10r6a_seal.json`）：更新 3 件（`verify_village_v2_machiya_kit_gate.gd`／`verify_village_v2_albedo_pilot.gd`／`verify_village_v2_kit_material.gd`）＋名簿 `village_v2_p13w7_batch1.json` を追加。他の 27 件は一致を確認。同じ W7 內の修正は新履歴を足さず `amended` に追記。
- P8 封存は無變更（`--seal` PASS）。Pilot 24 の割當・R6a の登記表・18 變体・`albedo_pilot.gd` も無變更。

### 7.3 既存の性質として見つけたもの（W7 の變更ではない）
1. **LOD hysteresis**：Kit／Hero は `fade_mode=DISABLED` に margin 4 m（LOD0 [0,40]、LOD1 [40,110]；南大門鳥居 [0,60]／[60,160]）。この組合せは**履歴依存**で、テレポート直後は切替帶（±4 m）の物がどの LOD も表示されないことがある。南大門鳥居（カメラから 61.7 m）が、手前から歩いて近づいた W6 の畫像には有るのに、テレポート直後の W7 畫像には無い——**直前に f_000 を經由して f_001 に移ると同じ鏡位で鳥居が出る**ことで確認（`diag/gateseq`）。W7 の overlay を全部止めても（W6 の 2 つも止めても）直接テレポートでは出ない。機構は hysteresis と推定（範囲と margin は實測）。實ゲームでも高速移動／リスポーン直後に起きうるので、P11／P12 の候補。
2. **R6a Pilot 24 棟の LOD1/2 屋根**：同じ K アトラスで `l_rh_*` を覆寫している（読み戻しで 48 面ずつ確認）。設計上 batch の最初の版と同じ増光が起きるが、Pilot の強制 LOD 畫面では屋根は「中深灰藍で LOD0 よりやや淺い」程度で白化は見えない。**變更していない**。Pilot にも同じ除外をかけるなら R6a の限定 reseal が要る → 使用者の判斷。
3. 共通ハーネス（`w7_shots.gd`）に `--swap`（旧版 overlay 差替）・`--lodcycle`（LOD 強制）・`--id` を追加。

### 7.4 技術債・未實行
- P12：TERRAIN 3,947 ms（不變）；P8 COST／FEEDER／ZONE は未實行（水理・碰撞・性能を觸っていない）。
- 全回歸は未實行（指示どおり局部のみ）。
- 未校正 77 棟と LOD1/2 の色相跳び（§4.2）は後続。

### 7.5 Git
- 使用者の **staged 53 項は無變更**（temporary index で commit し、`reset`／`stash`／`push` は使っていない。commit 後は自分の path だけを `git add` して index を HEAD に揃えた）。
- 本地 commit（未 push）：
  - `8908b5f` feat(人間之里V2): P13 W7 町家材質拡張＋道路・農田・田埂の局部材質収尾（111 檔：overlay 3＋生成物＋gate＋ツール＋limited reseal 2＋證據＋比較圖 13〔LFS〕）
  - 本報告の commit（docs）
  - 保持：`ce37a40`／`db98a55`（W6）は變更なし。
  - 前回の W6 から未追跡だった `scripts_p13/*.gd.uid` 4 件（drape_fix／p13_preview_boot／road_edge_blend／sando_pilot_w4）も同梱。
- 未追跡のまま：`wave7/diag/`（診斷畫面 約 400 MB）。コミットするのは `compare/`（LFS）・`evidence/`・本報告・生成物・gate・ツール。

---

## 8. 再現コマンド
```
# gate
godot --headless --path . --script res://tools/p13/w7/verify_w7_cleanup.gd -- --negatives
bash tools/p13/w7/run_w7_local_checks.sh <log> r5a|r6a|w7|p8
# 再生成
godot --headless --path . --script res://tools/p13/w6/build_w6_road_edge.gd
godot --headless --path . --script res://tools/p13/w7/build_w7_earthbank.gd
godot --headless --path . --script res://tools/p13/w7/build_w7_farm_junction.gd
godot --headless --path . --script res://tools/p13/w7/build_w7_batch1.gd
# 撮影（非 headless）
godot --path . --script res://tools/p13/w7/w7_shots.gd -- <out/> <tag> --at=… --free=… [--id] [--lodcycle] [--disable=Name] [--swap=Name=res://x.scn]
godot --path . --resolution 1600x900 --script res://tools/p13/w7/w7_perf.gd -- <out.json>
```
