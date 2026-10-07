# 人間之里 V2 環境資產盤點（P9 R5-4 Existing Asset Environment Pass，2026-10-04；2026-10-05 依分工更新）

- 性質：**唯讀盤點**。沒有修改、移動或重新生成任何資產，也沒有改 sealed source、shader 或原擺放。
- 逐件清單：`environment_asset_audit.csv` 和 `.json`，共 501 列。欄位有 source path、package、type、三角面、材質數、碰撞節點、尺寸（m）、visual style fit、sealed／read-only、授權、適合區域、已使用處、建議重用。
- 縮圖：`sheets/<群>_<n>.jpg`，用 Godot 4.7.2 Forward+ 以 SubViewport 隔離世界實際 render，每格標註名稱、三角面與尺寸。
- 量測工具：`godot/tools/audit_village_v2_env_assets.gd`。
  - `--out=` 量測。
  - `--thumbs=` 縮圖（非 headless）。
  - `--usage=` 列出 `maps/village_v2/gen/*.scn` 實際引用到的 kit mesh。
- UE5／Fab 只引用既有盤點 `../ue5_fab_2026-09-27/`（566 件），沒有重盤。該份的結論是「沒有任何一件能原樣進 Godot」，本輪也不重新下載任何東西。

## 1. 結論

1. **主力是專案自製的 V2 kit**：14 個 kit，LOD0 模組共 236 個，都是 Blender procedural、共用 V2 材質庫、各自帶 LOD1。
   - 本輪要用的 Natural／Rural／Village／Transitional 中尺度物件幾乎都已經有了：藁塚、稲架、農具掛け、大八車、薪棚、天水桶、桶の山、木箱、麻袋、干し竿、柴垣、四つ目垣、木杭、河原石、景石、巨石、蘆、菅、倒木、灌木、笹、飛石、井戸。
   - 這些 kit 分屬已封存的 P7／P9 R1–R4／P10 R1，以及 ART_REVIEW 中的 P10 R2。重用方式是**唯讀參照 mesh `.res`**：source、原擺放、shader 都不動。
2. **舊 kit／外部包（264 件）本輪全部不用**：
   - Quaternius `lowpoly_scene`／`nature`：平塗、玩具調，和 V2 的照片 PBR 不搭。
   - Tripo `market`／`riverbank`：尺寸被正規化成 1.0 m，每件 1–11 萬面。
   - GobKit：3–70 面，尺寸數百 m。
   - `models/`：已判 REJECTED。
   - 以上同類物件 V2 kit 都已經有。
   - 另外有一條硬規則：P5 asset reset gate 規定 V2 場景只能引用白名單或已過 Asset Gate 的資產。舊 kit 必須先過 Asset Gate 才能進場（registry `not_in_scope` 已寫明）。
3. **`missing_environment_assets` 沒有「必要」缺口**。可選項見 §5。依規則不啟用 Meshy／Tripo／Blender 新做。
4. **既有技術債（不是本輪造成，照實記錄）**：
   - `verify_village_v2_asset_reset.gd` 目前有 1 項 FAIL：V2 場景依賴 1,663 個，其中 296 個不在白名單。
   - 原因是 `sky_daynight.gdshader`，加上 P9 R4／P10 的 kit（`street_kit`、`market_kit`、`kiri_kit`…）雖然有各自的 gate，卻沒有登記進 `v2_assets`。
   - 本輪 overlay 參照的 kit 也在這 296 個裡面，所以沒有新增違規**類別**，但違規**件數**會增加。要補登記 registry，或修訂 asset reset gate 的 kit 規則，請使用者裁定。

## 2. 分類摘要（REUSE＝唯讀參照可用）

| 大類 | 小類（代表 id） | 件數 | 適合區 |
|---|---|---:|---|
| Natural | rock：`gk_kei_tall/mid/low/flat`、`rb_bld_a–e` | 9 | 林緣・坡地・水邊・空地の縁 |
| Natural | pebble：`rb_cob_a–c` | 3 | 水邊・路肩 |
| Natural | reed／weed：`wk_reed(_s)`、`wk_sedge`、`wk_iris` | 4 | 溪岸・水渠・井戸端 |
| Natural | shrub／sasa／fern：`shrub_a`、`sasa_a`、`fern_a`、`tsutsuji_a` | 5 | 林緣・後院の隅（躑躅は庭専用） |
| Natural | log／deadwood：`log_a`、`snag_a` | 2 | 林內・林緣 |
| Natural | young tree：`young_sugi`、`young_broad_a/b` | 3 | 林緣の段差 |
| Natural | tree・bamboo：veg_kit 成木 25、bamboo_kit 9 | 34 | ForestP9／BambooP9 封存で配置済み。新植しない |
| Rural | hay／straw：`st_warazuka`、`st_hasa`、`st_wara`、`wk_tawara(3)`、`st_kome_tsumi` | 6 | 農田外緣・農家後場 |
| Rural | cart：`kr_kuruma`、`mk_kuruma_ni` | 2 | 路地・作業場・農道口 |
| Rural | wood pile：`sk_woodpile`、`kr_zaimoku` | 2 | 住宅背面・作業場 |
| Rural | bucket／tub：`sk_tensui`、`sk_teoke`、`tk_okeyama`、`kr_okeyama`、`st_okeya` | 5 | 井戸端・後院・建物の角 |
| Rural | crate／sacks／cargo：`sk_box`、`kr_hakozumi`、`kr_ni`、`ic_hako_*`、`kr_fukuro`、`mk_tsumini` | 8 | 店後・倉儲角 |
| Rural | barrel／jar：`gd_taru(zumi)`、`ic_taru`、`ic_tsubo`、`mk_kame`、`sz_hachi` | 6 | 店後・側院 |
| Rural | fence／stake：`st_shibagaki`、`gk_yotsume`、`gk_sodegaki`、`rb_rail`、`rb_shig`、`rb_pile_a/r` | 7 | 後院・畑の縁・水際 |
| Rural | farm tool：`st_kuwa`、`mk_tenbin`、`kr_houki` | 3 | 農田交界・後院 |
| Village | drying rack：`mk_hoshimono`、`kr_hoshidana`、`sk_hanshi` | 3 | 陽の当たる後院・空地 |
| Village | bench／stool：`sk_bench`、`gd_shogi`、`sz_stool`、`sz_dai` | 5 | 路地・井戸端 |
| Village | sign／lantern／banner | 29 | 店先・巷口（P10 の語彙） |
| Village | well：`st_ido` | 1 | 共同空間 |
| Village | hero-specific（下駄箱・手毬・貸本箱・盛り塩…） | 12 | 各 Hero 周辺のみ。一般住宅には流用しない |
| Transitional | stepping stone：`gk_tobi_a–d`、`gk_nobe_a–c`、`rb_flag_a–d` | 11 | 裏口・水邊への踏み跡 |
| Transitional | edging：`gk_amaochi`、`rb_curb_*`、`rb_cap_*` | 6 | 牆腳・雨落ち |
| Transitional | drainage／frontage：machiya_kit `fr_*` 29 種 | 1 列 | P6 R4 で 187 棟の表に使用済み |
| Commerce | 屋台・棚・平台・幟（`mk_yatai_*`、`st_hiradai_*`、`ic_koya_*`…） | 35 | **P10 専用**。R5-4 では使わない |
| Procedural | MeadowP9 立ち草 9 種、GroundcoverP9 | 2 | 全村に配置済み |

## 3. 舊 kit／外部包の判定（vision 講評＋實測）

| 群 | 件數 | 判定 | 理由 |
|---|---:|---|---|
| `lowpoly_scene`（CC0） | 35 | REWORK | 形は使えるが平塗り・ファセット；V2 に同種あり |
| `nature`（Quaternius CC0） | 68 | REWORK／REJECT | 玩具調の植物・花・松；Pebble_Round 1/3/4 だけ FIT 候補（V2 の `rb_cob`／`gk_kei` で足りる） |
| `market`（Tripo） | 10 | REWORK | 1.0 m 正規化・1.2–2.2 萬面／件；`market_kit`／`street_kit` が後継 |
| `riverbank`（Tripo） | 24 | REWORK | 1.0 m 正規化・1.1–11 萬面；P7 `riverbank_kit` が後継（封存） |
| `landscape`（Tripo r7 樹） | 13 | REWORK | P9 R1 veg_kit が後継。「Tripo 樹は參考のみ・搶救しない」裁定 |
| `_incoming/gobkit_nature` | 41 | REJECT | 極低ポリ・スケール不正 |
| `models/` | 48 | REJECT | 既に REJECTED |
| `shrine/`・`landmark/` | 13 | REFERENCE ONLY | P5 Protected |
| `machiya/` | 7 | REJECT | P5 Asset Reset 封存 |

## 4. Zone classification と cluster vocabulary（Pilot）

| 区 | site（實測） | cluster | 語彙（既存 kit） | 語意 |
|---|---|---|---|---|
| 大型空地 | 市集廣場の北の空地（x 205–240, z −129…−104；南の建物列の北 3 m 帯、鈴奈庵 (248, −6) からは約 100 m 北） | `open_drying` | 干し竿（柿・大根・布）、A 字の干し棚、俵、麻袋、荷車、木箱、材木、腰掛け石 | 空地の縁＝共同の干し場と置き場。中央は抜く |
| 農田→住宅 | 水渠の村側の段（x 311–324, z −62…−45；水車 1 (334.8, −52) の西 16 m、P10 田の縁から ≥ 29 m） | `farm_gate` | 荷を積んだ大八車、俵、天秤棒と籠、手桶、藁塚 1、腰掛け石、田の境の杭 3 | 収穫を運ぶ口。P10 の「稲架＋藁塚＋農具掛け＋柴垣」とは語彙を変える |
| 住宅背面 | 水車 3 (310.6, 58) の西 26–33 m の町家の裏（x 277–285, z 60–66） | `backyard` | 薪棚（壁際）、天水桶（角）、桶の山、木箱、材木、裏口からの飛石 3、干し竿（陽の側） | 裏口の作業場 |
| 水邊 | 西溪の村側の岸（x 179–186, z −58…−52） | `stream_edge` | 巨石 2、蘆叢 2、菅、河原石、舟杭（縄）2、飛石 2、手桶 | 洗い場へ降りる踏み跡 |
| 林緣 | 南林の縁（x 205–217, z 122–130、南門の西） | `forest_edge` | 倒木、景石 2、灌木、笹、切り出した材、薪棚、幼樹 | 村が林を使っている痕跡 |

## 5. missing_environment_assets

- **必要**：なし。既存 kit で 5 区とも cluster が成立した（gate 構造 PASS。美術判定は ART_REVIEW）。
- **可選**（全村擴張で必要と判断されたときのみ。新規生成前に使用者へ申請）：
  - 切り株＋薪割り台（後院の中心物）
  - 路傍の石祠／地蔵（巷口の用途提示）
  - 壁に立て掛けた竹竿の束
  - 洗濯物の物干し（着物）：`mk_hoshimono` は柿・大根・布 3 枚
  - 堆肥の山（農家後場）
  - 小さな畑の畝（家庭菜園）

## 6. 2026-10-05 依分工更新（R5-4 重開）

- 使用者分工：**P9 R5-4＝自然・過渡・空地・林緣・水邊・農田交界與環境 cluster**；**P10＝市集・主街・生活 props・工作區・商業活動・NPC activity anchors**。重疊時 P10 既有配置優先；後院生活 props（薪・桶・箱・曬竿等）交給 P10。
- 重跑量測、縮圖與 usage（kit 數 620 件不變；`maps/village_v2/gen/*.scn` 的參照 505 → 696 件，含 MeadowP9 與 P10 MarketWestP10）。CSV／JSON 新增欄 **`r54_role`**：

| r54_role | 件數 |
|---|---:|
| **R5-4**（景石・巨石・河原石・蘆・菅・花菖蒲・灌木・笹・羊歯・倒木・枯立木・幼樹・筍／竹の落葉・飛石・延段・橋頭鋪石・雨落ち縁石・見切り石・笠石・石橋・四つ目垣・矮欄・しがらみ・木杭） | 49 |
| R5-4 可（柴垣：農田交界の境界のみ；P10 田の縁と同じ場所に重ねない） | 1 |
| P10 優先（藁塚・稲架・藁細工・俵・米俵積み：P10 田の縁 4 か所で使用中） | 6 |
| P10（生活 props・商い・作業：桶・薪棚・箱・籠・樽・甕・荷車・干し竿・腰掛け・看板・提灯・屋台…） | 118 |
| Hero 固有 | 14 |
| P7／P6 構件（護岸・雁木・洗い場・側溝・frontage；R5-4 新規擺放しない） | 13 |
| P9 R1–R3 封存で配置済み（成木・竹；R5-4 新植しない） | 32 |
| 庭専用（躑躅・袖垣） | 2 |
| 舊 kit／外部包（不使用） | 264 |

- **R5-4 語彙では「必要」缺口なし**。可選は §5 のうち路傍の石祠（巷口・村邊の境の目印）だけが R5-4 側に属し、残りは P10 側。
