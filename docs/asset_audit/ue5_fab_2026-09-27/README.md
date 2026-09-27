# UE5／Fab 既有資產重用盤點（Existing Asset Reuse Audit）

- 日期：2026-09-27　性質：**唯讀盤點**（UE 編輯器未啟動；未搬、刪、改任何 UE／Fab 原檔；未做 UE 匯出）
- 範圍：`D:/TOUHOU`（專案 Content＋RawAssets）＋ Epic Launcher VaultCache（`C:/ProgramData/Epic/EpicGamesLauncher/VaultCache`，8 個已下載包）＋ Fab 圖書館本機快取 `FabLibrary/listings_v1.db`
- 逐件清單：`inventory_ue_static_meshes.csv`（566 個 StaticMesh，每列含來源／授權／格式／面數／LOD／材質數／貼圖／碰撞／Nanite／尺寸／判定／建議階段）
- 縮圖：`sheets/`（UE 內嵌縮圖＋Blender 實際匯入渲染）

## 1. 結論（一句話）

**沒有任何一件 UE／Fab 資產能「原樣」進 Godot；授權乾淨且風格吻合、值得轉的只有 CC-BY 原始檔（FBX／OBJ）中的少數幾件。P7–P10 主力仍是專案內既有 kit ＋ Poly Haven CC0 材質管線。**

| 判定 | 件數（StaticMesh） | 說明 |
|---|---|---|
| USE AS-IS | 0 | `.uasset` 不直接進 Godot；RawAssets 原檔也都要清理 |
| REWORK（授權乾淨、可轉） | 見 §4（CC-BY 原始檔 4 組） | 走 UE/Fab 原檔 → Blender → GLB → Asset Gate |
| REWORK 候選（需 UE 匯出，暫不做） | 103 | 皆有更便宜的專案內替代；需要時另建 UE 工作副本匯出 |
| REFERENCE ONLY | 227 | 風格不合／Hero 類（V2 已有核准版）／遠景 |
| REJECT | 107 | 歐式建築、現代物件、奇幻道具、PS1 風格 |
| 授權不明→不使用 | 17＋90 | Cicitoon 內含 Megascans／SpeedTree／第三方貼圖；FabTrial/Props（otsuga1）listing 未確認 |

## 2. 來源與授權（全部實讀）

授權依據：Fab listing API（`https://www.fab.com/i/listings/<uuid>`）與 Fab EULA 摘要（`https://www.fab.com/eula`，本次重抓）。EULA 摘要原文要點：Standard License「Use the assets with any compatible tools (usage is not limited to Unreal Engine)」、Personal／Professional 兩層權利相同、不得單獨轉售／免費再散布；「Reference-Only tier will only grant you access to the content in form of a referenced asset, not its source format」；CC-BY 須具名。

| 包 | 作者 | 授權 | 格式 | 位置 | 檔數／StaticMesh | 備註 |
|---|---|---|---|---|---|---|
| Cicitoon Japanese-style Room V1.0 | MrCici | Fab Standard | UE `.uasset` | VaultCache | 544／175 | **包內混有第三方內容**：Megascans（`veniffjdb` 石燈籠、`vlskbcz`、`wdipfjw`、`sk0kh0g`；`SM_Jap`）、SpeedTree `.st` 來源植物 16 件、`SpanishCourtyard` 貼圖 → 整包視為**授權不明、不使用**（見 §6 問題 1） |
| Stylized Environment Pack | Forge of Fantasy | CC-BY | UE | VaultCache | 522／52 | 手繪亮色風，金黃木色；與 V2 照片型材質衝突 |
| FabTrial（D:/TOUHOU/Content） | 多位 | CC-BY（Props/otsuga1 對應 listing 未確認） | UE＋RawAssets 原檔 | TOUHOU | 311／201 | 植物／樹 kit、石徑掃描、林道掃描、石像掃描、鳥居、社殿、PS1 城 |
| Sharur's Normandy Village + PCG Plants | Sharur | Fab Standard | UE（92/105 Nanite） | VaultCache（已自 TOUHOU 移除） | 498／105 | 歐式廢墟；草／灌木／碎石可抽，但需 UE 匯出＋Nanite 降面 |
| [FREE] Mountain Tops | Arghanion's Puzzlebox | Fab Standard | UE（14/14 Nanite） | VaultCache | 80／14 | 冰島地質遠山 |
| Pine Tree Pack (Imposter) | Next Spring | CC-BY | UE | VaultCache | 36／11 | octahedral imposter，需重寫 shader |
| Tileable Pine Forest Road | Serkan CINAR | CC-BY | UE（4K×3） | VaultCache | 6／1 | 林道 tileable 材質 |
| RPG - Crafting & Environment VFX | VRhinoFX | Fab Standard | UE（Niagara 22） | VaultCache | 81／7 | 奇幻鍛造／藥水／魔法陣 |
| Electric Dreams Env | Epic Games | Personal/Professional，**listing 明寫「UE-Only Content - Licensed for Use Only with Unreal Engine-based Products」** | UE | VaultCache | 未盤點網格 | **REJECT（授權：UE 專用）**，含 311 個音訊 uasset 亦不可用 |

量測方法：直接解析 `.uasset` 標頭的 Asset Registry tags（Triangles／LODs／Materials／CollisionPrims／NaniteEnabled／ApproxSize／Dimensions）；材質→貼圖鏈由套件內 `/Game/...` 參照解析。UE 內嵌縮圖為 **BGRA**，初版判讀把棕木看成青藍，已 R/B 對調後重判（`sheets/` 為校正版）。

## 3. 逐類候選（依使用者清單）

欄位：來源／授權／格式／類型／LOD0 面數／材質／貼圖／LOD／Collision／尺寸（m）／適合 V2／判定／建議階段。

### 3.1 樹、竹、灌木、草、花

| 候選 | 來源／授權 | 格式 | 面數 | 材質／貼圖 | LOD／Col | 尺寸 | 適合 V2 | 判定 | 階段 |
|---|---|---|---|---|---|---|---|---|---|
| S_Tree_A–J（10 株闊葉） | Vegetation Stylized Kit（Lux Art Studios）／CC-BY | FBX＋blend（RawAssets） | 2,200–3,116 | 2／**本機缺貼圖**（`T_Leafs_01A.psd`、`T_Trunk_D.png` 全碟搜尋無） | 1／無 | 3.9–11.2 × 至 14.6 | 輪廓可（欅／楓／櫻候選） | REFERENCE ONLY（缺貼圖；專案 `landscape/` 已有 r7 樹） | P9 備援 |
| S_Bush_A–D、S_Fern_A–D、S_Flowers_E/F、S_Clovers_A/B、S_Grass | 同上 | 同上 | 170–4,170 | 缺貼圖 | 1／無 | 0.3–3.0 | 部分可（蕨偏大） | REFERENCE ONLY | P9 備援 |
| S_Cattail_A／B（蒲） | 同上 | 同上 | 834／320 | 缺貼圖 | 1／無 | 0.5–0.8 × 1.0–1.1 | 可（河岸） | REWORK 候選（只取幾何、自製材質） | P7 |
| SM_Grass／GrassTall_00A–02A | Normandy／Fab Standard | UE（Nanite） | 502–731 | 4K | 1／有 | 0.6–1.2 × ~0.7 | 中性可用 | REWORK 候選（需 UE 匯出；專案 `nature/` 已有 CC0 草） | P7／P9 |
| SM_PlantTypeA/B/C | Normandy | UE（Nanite） | 3,962–9,283 | 4K | 1／有 | 1.4–2.9 | A/B 可；C 紅紫偏觀賞 | REWORK 候選 | P9 |
| 黑松 01/02、Pine_TreeTall、Japanese_Bush、草花 16 件 | Cicitoon | UE（SpeedTree） | 至 170k | — | — | — | 黑松 01 最好 | **授權不明→不使用** | — |
| Bush1–3、Tree1–3 | Stylized Env／CC-BY | UE | 11–22k | 4K | 4／有 | 3–6 | 手繪亮綠，衝突 | REFERENCE ONLY | — |
| SM_Imposter（松） | Pine Imposter／CC-BY | UE | 8 | 2K | 1 | — | 遠景想法 | REFERENCE ONLY | P12 |
| 竹 | — | — | — | — | — | — | **UE／Fab 內無竹子資產** | — | P9 另做 |

### 3.2 岩石、河石、護岸石、踏石

| 候選 | 來源／授權 | 格式 | 面數 | 貼圖 | 尺寸 | 判定 | 階段 |
|---|---|---|---|---|---|---|---|
| Rocky Stone Path Scan（23 個岩地模組＋2 片底板） | PersScans／CC-BY | FBX＋blend＋4K albedo/normal/roughness/ao（本機齊全） | 13,517–35,139／模組（共 448,320；25 物件、3 材質；無 LOD、無 collision） | 4K | 模組 2.3–8.4 m、起伏 0.31–0.88 m | **REWORK（採用，限岩地補丁）**：實測每個模組是**一整片連續開放曲面**（連通分量 1–3、邊界邊 320–735），是「土中嵌石」的地面，不是可分離的單顆石 → 用途限 P7 粗石徑／河岸邊緣補丁（減面至 2–4k、4K→1K、色調對齊 V2_Stone）。**單顆踏石／飛石不從此抽**（需切割＋封底＋重 UV，手工量大）→ 改 Blender 自建 | P7 |
| GroundStone 01–06、Stone_Big 01–03、RockSculpted、SmallStone | Cicitoon | UE | 1.8k–8.3k | 2K | 0.17–1.15 | 品質好但**授權不明→不使用** | — |
| StoneCluster Round／Pond／Wall | Cicitoon | UE | 30k–145k | 2K | 3.6–6.0 | 觀光庭園圓環石組＋授權不明 | — |
| SM_LS_Rock_00A–03A | Normandy | UE（Nanite） | 2.5k–3.9k | 4K | 6.4–18.4 | REWORK 候選（北丘露岩） | P9 |
| SM_Stone_00A–04A、Rubbish、RubblePile | Normandy | UE | 0.8k–8.5k | 4K | 0.1–2.5 | 小石可；碎石堆＝破敗感 | P7 備援／REFERENCE |
| LargeRock、SingleRock、Stone1–3 | Stylized Env | UE | 96–476 | 4K 手繪 | 0.2–8.5 | REFERENCE ONLY（手繪） | — |
| StoneWall／OldWall 系列 | Normandy／Stylized | UE | 6–17k | 4K | ~3 | REJECT（歐式砌法） | — |

### 3.3 土地／泥土／碎石／石板／苔 材質

| 候選 | 來源／授權 | 解析度 | 判定 | 階段 |
|---|---|---|---|---|
| Forest trail path 掃描 | Punttulanbro／CC-BY，FBX＋2×8K（本機齊全）；Blender 實測 1 物件、1,413,393 面、2 材質、6.77×2.91×0.81 m、無 LOD、無 collision（Nanite 級，不原樣搬進 Godot，只當烘貼圖來源） | 8K | REWORK 候選：可烘 tileable 林道土；**P7 預設仍用 Poly Haven CC0 管線**（`build_village_v2_textures.py`，已有 sha256 溯源） | P7 備援 |
| Tileable Pine Forest Road | Serkan CINAR／CC-BY，UE | 4K×3 | REWORK 候選（需 UE 匯出） | P7 備援 |
| T_LC_Ground*（Dry／GrassGravel／GrassMoss／GrassSoil／Mossy／RockyRoad／SoilExcavated） | Normandy／Fab Standard，UE | 4K | REFERENCE ONLY：寫實歐式地表，與 Poly Haven 同類、無額外價值且需 UE 匯出 | — |

### 3.4 木橋、木樁、木欄杆、圍籬

| 候選 | 來源／授權 | 面數 | 尺寸 | 判定 | 階段 |
|---|---|---|---|---|---|
| Old/Dry Bamboo Bridge | Pikas／CC-BY，FBX＋貼圖（spec/gloss，檔名與 FBX 引用不一致需重連） | 35,004 | 20.17×2.33×2.10 | REFERENCE ONLY（P2/P3 橋位已定；長 20 m 無對應位置） | P8 備援 |
| Fence_Var1–3、BridgeCol、Staircase、Plank、Pole | Stylized Env | 92–6,440 | — | REFERENCE ONLY（金黃手繪木、X 撐西式） | — |
| SM_HW_Plank_00A–08A | Normandy | 732–824 | 1.1–4.0 長 | REWORK 候選（材木堆） | P10 備援 |
| Ryokan_Railing_03、LiangTing | Cicitoon | 588／2,184 | 4.0／5.0 | 授權不明；亭為中式 | — |

### 3.5 木桶、木箱、籃、甕、麻袋、柴堆／農具、手推車、板車／市集攤位／家具

| 候選 | 來源／授權 | 判定 | 說明 |
|---|---|---|---|
| BarrelTris、WineBarrel | Stylized Env | REJECT | 西式鐵箍桶／酒桶（需日式樽，另做） |
| CrateLarge、Logpile、Log1–3、Campfire | Stylized Env | REFERENCE ONLY | 手繪金黃木；柴堆輪廓可參考 |
| otsuga1 室內 kit（書、層架、矮櫃、坐墊） | FabTrial RawAssets，listing 未確認 | 授權待確認→不使用 | 86 物件、3,041,328 面、49 材質、外框 299.4×299.4×11.5 m、每本書 67,584 面、尺度疑似 ×10 |
| 農具、手推車、板車、市集攤位、布棚 | — | — | **UE／Fab 內無合用資產** → 用專案 `market/`（屋台絲綢／蔬果／陶瓷攤、平台攤、雜物堆木桶／瓢盆／草捆、水井、旗子）＋自建 |

### 3.6 燈籠、招牌、旗幟、布料／水岸農田灌溉小件

| 候選 | 來源／授權 | 判定 | 說明 |
|---|---|---|---|
| Ryokan_Lantern_Ground_02、Fenglin（風鈴）、Clothes_drying_pole、茶具 | Cicitoon | 授權不明→不使用 | 形狀簡單，P10 以 Blender 自建 |
| 石燈籠（Megascans veniffjdb） | Cicitoon | 不使用 | Megascans 內容 |
| SM_Props_Lantern_02A | Normandy | REJECT | 西式煤油燈 |
| 水岸／農田／灌溉 | — | — | UE／Fab 內無；專案 `riverbank/` 已有 24 件（水田一格、畦道、稻作株、田泵水口、木樋支撐棚架、分水閘門、木構水門、石造堰檻、洗物石段、親水階梯、濱水平台、塊石疊砌牆、mooring_post…） |

### 3.7 石像（掃描）

| 候選 | 來源／授權 | 面數／貼圖 | 尺寸 | 判定 | 階段 |
|---|---|---|---|---|---|
| Jizo statue in Kyoto | Paul Griswold／CC-BY，OBJ | 149,512／8K | 0.48×0.48×0.51 | REWORK 候選（減面 ≤6k、1K，削掉底部碎石裙） | P10（路旁地藏，需構圖依據才放） |
| Kitsune statue in Nagoya | 同上 | 144,987／8K | 0.76×0.89×1.59 | REFERENCE ONLY（放狐像＝稻荷社設定，屬劇情／設定決定） | — |
| Nakasendo shrine statue | 同上 | 314,969／8K | 1.46×1.30×0.86 | REFERENCE ONLY（含大片地面與植物碎片） | — |
| Otagi Nenbutsu-ji statue | 同上 | 363,227／8K | 0.75×0.70×0.82 | REFERENCE ONLY（羅漢群為現代作品） | — |

### 3.8 VFX 與音效

| 類別 | 內容 | 判定 |
|---|---|---|
| Niagara（28 個） | RPG VFX 22（鍛造火星、坩堝蒸氣、魔法陣、藥水、寶箱）、Normandy 5（DustMotes、StormClouds、StormDust）、Stylized 1（FallingLeafs） | 全部 REFERENCE ONLY：Niagara 無法移植，P13 以 Godot GPUParticles3D 重做（煙、蒸氣、落葉、塵、水花、螢火蟲） |
| 音效 | 8 個已安裝包音訊 **0 件**；Electric Dreams 311 件為 UE 專用授權 | 不可用；沿用專案 `godot/assets/audio/`（63 檔：蟲鳴日夜、鳥、蛙、貓頭鷹、各地面腳步、水花…）與 `docs/audio_sources.md` |

## 4. 採用清單（授權乾淨、風格可、不需 UE 匯出）

| # | 資產 | 授權義務 | 管線 | 階段 |
|---|---|---|---|---|
| A1 | Rocky Stone Path Scan → 岩地補丁模組 3–5 種（河岸邊緣、林道粗石段） | CC-BY：credits 具名 PersScans | FBX → Blender（減面 2–4k、邊緣下沉、烘法線、1K）→ GLB → Asset Gate | P7 |
| A2 | Vegetation Stylized Kit：S_Cattail_A/B 幾何 | CC-BY：Lux Art Studios | 幾何＋自製葉材 → GLB → Gate；若自建蘆葦更好則不用 | P7 |
| A3 | Forest trail path 掃描 → tileable 林道土（備援） | CC-BY：Punttulanbro | 僅在 Poly Haven CC0 無合適時才烘 | P7 備援 |
| A4 | Jizo 掃描 → 路旁地藏（選用） | CC-BY：Paul Griswold | 減面＋去底裙 | P10 選用 |

UE `.uasset` 只含的候選（Normandy 草／灌木／露岩、TileableForestRoad、Stylized 岩）：暫不匯出。需要時「另建 V2 工作副本 UE 專案」再用 UnrealEditor-Cmd 匯出 FBX／PNG，原 VaultCache 與 D:/TOUHOU 不動。

## 5. 對接各階段（實際施工主力）

| 階段 | 主力 | UE／Fab 補位 |
|---|---|---|
| P7 地面／河岸 | Poly Haven CC0 材質管線（`build_village_v2_textures.py`、`_matlib`）；專案 `riverbank/`、`nature/`（Quaternius CC0） | A1 岩地補丁、A2 蒲、A3 備援 |
| P8 農地 | 專案 `riverbank/`（水田、畦道、稻作株、田泵水口、木樋…） | 無 |
| P9 林帶／庭園 | 專案 `landscape/`（r7 松／楓／櫻／杉／針葉／竹垣）、`nature/`；飛石／庭石 Blender 自建 | Normandy 露岩（需匯出時） |
| P10 市集／生活／Hero dressing | 專案 `market/`＋Blender 自建（樽、箱、籠、燈籠、風鈴、茶具、看板、暖簾） | A4 地藏（選用） |
| P13 VFX／音 | Godot GPUParticles3D 自建；專案 audio 63 檔 | Niagara 僅參考 |

## 6. 待使用者確認（不阻塞施工）

1. **Cicitoon Japanese-style Room**：listing 授權為 Fab Standard（可跨工具），但包內混有 Megascans、SpeedTree 與 `SpanishCourtyard` 第三方內容，無法證明其中石組／燈籠／茶具是作者自有。依規則「不確定就標記、不要使用」，目前全包不用。若你確認可用，最值得轉的是 GroundStone 01–06（飛石，1.8k–8.3k 面、2K）。
2. **FabTrial/Props（otsuga1.fbx）**：`D:/TOUHOU/LICENSES.md` 標為「疑似」Japanese-Style Room（TheTohru，CC-BY），未確認 → 不使用。

## 7. CC-BY credits（採用時必須加入專案 credits）

- "Rocky Stone Path Scan" by PersScans, CC-BY — https://www.fab.com/listings/85333ece-52d0-418c-a555-5a7b906af638
- "Vegetation Stylized Kit" by Lux Art Studios, CC-BY — https://www.fab.com/listings/52498d47-a865-4e7e-a7ec-6a3fcbe9e5f3
- "Forest trail path" by Punttulanbro, CC-BY — https://www.fab.com/listings/6a93b773-099b-4c66-b92f-697013b2ecab
- "Jizo statue in Kyoto - MTSU Animation" by Paul Griswold, CC-BY — https://www.fab.com/listings/25504e2e-d977-4e11-8feb-113c666742ea

（只列實際採用者；未採用不列。）
