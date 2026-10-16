# P13 W9 後続登記（ART_APPROVED 済みの項目から出た、後の統合段階で扱う事項）

登録のみ。ここにある項目は、該当の建築が ART_APPROVED になったあとも**解決済みとは扱わない**。着手は使用者の指示または該当段階（相機整合／全域 lighting／P12）まで保留。
最終更新：2026-10-16（Phase 4 R1／R1b ART_APPROVED 局部結案：#9、#16–#21 的狀態更新，新增 #22，新增「Phase 4 結案」「Phase 5 指派」兩段。以下為先前的更新：Phase 4 R1 送 ART_REVIEW：新增 #16–#21，#9 補量測；Phase 3 第一批 ART_APPROVED 局部結案：#6–#9、#12、#15 的狀態更新，新增「Phase 3 第一批 結案」「下一批方向」兩段。以下為先前的更新：Phase 2 三棟 ART_APPROVED 局部結案時建立；#6–#11 於 Phase 3 R1 提交時加入，#6 於提交後更正數值與方位〔Phase 3 R1 報告 §8〕；Phase 3 R2 局部修正提交時更新 #6–#9，新增 #12–#15，R2 報告提交後更正再修訂 #9／#14／#15）。另外，名為「相機整合一覽」的既有檔案找不到（`P11_HANDOFF.md`／`CAMERA_HANDOFF_yoriichi.md` 是別的 session 的交接文件，未動）。相機端窗口確定後，把這張表的 #1 交給對方。

| # | 区分 | 項目 | 根拠（実測・出所） | 扱い |
|---|---|---|---|---|
| 1 | **相機整合** | **MKT_029 の原 body 碰撞が可視の前店屋根より高い**ため、SpringArm が屋根の手前で止まる／蔵の上で縮む可能性 | body Shape＝6.994 × 5.766 × 10.92 m・中心 y 2.517（上端 **5.40 m**）。可視の前店の棟は **4.63 m**、庇 3.6 m、蔵の棟 7.40 m。地上の玩家は届かないが相機は未測定 | 美術承認とは別。相機整合で測る（相機は触らない）。footprint／body を変える場合は使用者の事前承認が要る |
| 2 | 動的環境 | RSW_014：鍛造の火光・煙・NPC の作業動画 | 使用者裁定（Phase 2）：後続の動的環境項目、今回は扱わない | 動的環境の段階で |
| 3 | 全域 lighting（P13） | MKT_029 の蔵の白い妻面が 10:00 の全域光で灰青に見え、通常 TPS で蔵棟の辨識が弱い | 使用者裁定：局所の明るさ調整は開かない | 全域 lighting の段階で |
| 4 | 検証の注記 | posts gate の「過大な碰撞」探測は、同棟の別の碰撞箱が近い位置では略過する（成排小物のため）。小物の碰撞箱 18 個のうち、真人短走で停止位置を実測したのは代表 5 個 | `verify_w9r2_posts.gd`／`evidence/phase2_r2_checks.txt` | 必要なら他の箱も実走で測る |
| 5 | P12 | 小物（薪・桶・荷受け台ほか）は L0 のみで、LOD 切替時に 0.2–0.4 m 級の小物が出入りする | `build_w9r2_arch.py` の `Bld.P` は lod==0 のみ | P12 の LOD／最適化で |
| 6 | **相機整合**（**已核准・結案**；使用者 2026-10-16） | RSW_071 柴棚前柱（Posts 碰撞，寬 0.14 m・局部高 2.478 m）在 B 巷把 SpringArm 縮短 1.21 m（R1） | R1：巷中 (235.8, −87.6) 朝北面向 075 時 SpringArm 長 2.75 m→1.54 m（`ArchW9R2P13/B_P_RSW_071/Posts`，命中高度 y 3.40 m）。**R2b（Phase 3 R2）**：撤掉 3 根庇柱，改為只用腕木的懸挑庇（深 1.15 m；生成器註記 < 1.55 m 不需柱）。全巷 sweep（685 地點×16 方位）縮短 ≥ 0.30 m：R1 250 件（071 造成 188 件）→ **071 造成 0 件**；bT3 臂長 2.752 m＝原場景。真玩家短走（幀可對應的 5 段＝1 102 幀）縮短 ≥ 0.30 m 為 0（反向：放回 R1 的柱，最差 1.22 m）。詳見 `phase3_r2/P13_WAVE9_PHASE3_R2_REPORT.md` §2、`phase3_r2/evidence/gate_arm_sweep.log`・`walk_arm_*.log`；反向案例的失敗史在 `phase3_r2/evidence/GATE_HISTORY.md` | 使用者核准：保留無落地庇柱、由牆面腕木支撐的懸挑設計。SpringArm 已恢復正常，**不再為 bT3 的局部屋簷遮蔽修改全域相機**。未動玩家／相機／main；薪堆的低矮碰撞保留 |
| 7 | 美術（**已核准・結案**；使用者 2026-10-16） | MXC_005 的白蔵被讀成細高的塔 | R1（設計值）：寬 3.0・軒 6.2・棟 7.1 m・長 6.8 m（比店的棟〔設計 6.7 m／實測 6.98 m〕還高）。**R2b**（保存 mesh 實測）：軒 3.35・棟 4.61 m（比店的棟低 2.37 m）・壁寬 3.45・奧行 10.49 m・棟高÷寬 1.34；開口只有門與妻面小窗。`phase3_r2/evidence/gate_p3_kura.log`（6／0；此 gate 的限制見 #15） | 使用者核准：保留目前尺寸，**不再修改 footprint，也不再進行比例搜索**。妻面寬 3.5 m 由敷地決定，屬已知限制，不要求修正 |
| 8 | 美術（**已核准・結案**；使用者 2026-10-16；殘留部分屬 P13） | C：前景樹遮住主屋／路肩灌木輪廓重複／柴棚正面偏暗 | cT4：榎・黑松移到主屋背後樹列，EnrichW9P3 遮住農舍 A1 的比例 37.8 %→0.1 %（ID pass 實測；不含 P9 封存林等原有遮蔽）。cT7：路肩改為 4 群（高度・寬度・種類・間隔皆不同；視覺模型懷疑式目視 3–4／5）。柴棚正面偏暗未處理。`phase3_r2/evidence/ct4_visibility.json` | 使用者核准：保留 cT4／cT7 目前的植被配置，**不再微調灌木間距、葉冠與地被**。殘留皆為已知限制、不要求修正：柴棚正面偏暗→P13 全域 lighting；cT4 農舍 A2 約 49 % 被左前景柴棚（043）遮住；cT4 中央草地偏空；cT7 目視 3–4／5 |
| 9 | **待處理的玩家可見缺陷**（使用者 2026-10-16 指定；P2 既有佔位，與 Phase 3 無關；R1 之前寫「P8 水利」有誤） | C 區運河上顯眼的藍色圓柱 | **`Water/Waterfalls/WATERFALL_F7/Placeholder`**：P2 既有的佔位 MeshInstance3D（CylinderMesh 半徑 0.6 m×高 3.0 m；`StandardMaterial3D` albedo (0.231, 0.336, 0.42)）。父節點 Marker3D `WATERFALL_F7`＝(307, −2.314, 70)，Placeholder 抬高 +1.5 m（`village_v2.tscn` L3558–3568）；`layout_v2.json` L976「跌水（水車旁）」・conf low。cT4 畫面占 0.61 %（ID pass id 7）。BEFORE／R1 皆有。`data/village_v2_p9r44_seal.json` L35 已記載「水車 3 旁 … 藍色 CylinderMesh（P2 既有佔位，非 R4-4）」。同材質同形的 `WATERFALL_B7`（西渠 (142.8, −0.238, 42)・conf medium）也有。**依賴關係（2026-10-16 唯讀查得，未動任何檔案；以下皆讀自磁碟）**：①來源鏈：`layout_v2.json` L974–976 → `tools/gen_village_v2.gd` L1462–1478（Marker3D＋meta label／src／conf；子節點 `Placeholder`＝CylinderMesh 半徑 0.6・高 3.0・`cast_shadow=0`，B7／F7 共用同一個材質；另生 `Debug/Labels/…_Label`「跌水（placeholder）」）→ 烘進 `village_v2.tscn` L3544–3568、L142335／L142345。②**沒有碰撞節點**（只有 MeshInstance3D）；Marker3D 的 meta 沒有消費者。③依名稱引用：`godot/` 內只有上述四處與 `data/village_v2_p9r44_seal.json` L35 的文字註記，**沒有任何 gate／腳本依名稱讀取**。④以型別掃描 `Water` 子樹、會碰到它的回歸項目：P1 protect（`verify_village_v2_p1_protect.gd` L191／L232，**明確跳過 PrimitiveMesh**，不含 Placeholder）；P10 WLF（`verify_village_v2_water_life.gd` L156–176，只取水車 2 輪心 (329.2, 0.0) 4 m 內的水面，F7 距 73 m・B7 距 191 m，不在範圍）；P8 ZONE 實走（`walk_village_v2_farmland.gd` L377，只取名稱含 canal 的網格，不含）；P7 河岸 gate 近景 AABB 掃描（`verify_village_v2_riverbank_gate.gd` L730–748，當一般網格，拿掉只會少一項）。⑤一次性診斷腳本（**不在回歸總表**，已核對 `run_village_v2_regression.sh` 無引用）：P11 R2C `tools/p11r2c/probe_feeder_hydraulics.gd` 曾把 F7 的方塊頂 0.69 列為「候補水源」，報告判定「不是水面」；`survey_village_v2_irrigation.gd`、`audit_village_v2_rehab.gd` 也掃過；P11 R2B `ww.log` 量到 F7 距水車 3 (310.6, 58.0) 12.5 m。⑥封存：沒有任何 seal／data JSON 對 `village_v2.tscn` 本身做 hash（key 型與 record 型兩種格式都查過）；但 `village_v2.tscn` 是 `gen_village_v2.gd` 的產物，改來源＝重生場景並依序重掛全部 overlay。⑦設計意圖：layout「跌水（水車旁）」・conf low；`docs/新人里規劃提案.md` L47：參考圖「三座水車全部架在人工堰的落差上（放大圖可見白色跌水）」→ 這是「此處該有堰的落水」的標記，P2 沒有做成真正的構造。**尚未確認**：整場景級的掃描／計數類 gate（如 MMBAKE、預算、規模統計）有無「精確節點數」斷言（上面只涵蓋明確引用 `Water` 子樹者）；`Debug` 節點在正式（非 ReviewStart）流程是否隱藏（ReviewStart 的 `DEBUG_NODES` 會隱藏它） | **先確認用途與依賴關係，不得未經確認直接改動封存場景**（屬 P2 水利）。列入下一批。處置選項僅供參考、**未決定**：(a) 不動 P2：用 root 直下 overlay（`WaterLifeP10` 的前例）在執行時停用兩個 Placeholder，並同時放置正式的堰落水構造（不是只隱藏）；(b) 改 `gen_village_v2.gd`／layout 並重生場景（影響面最大，需先得你同意，且之後要重掛全部 overlay）。B7 同材質同形，應一併決定 **Phase 4 量測（2026-10-16・實機讀取，`phase4_r1/evidence/taskD_weir_probe.txt`）**：F7 (307.0, 70.0) 渠水面 −1.52 m 沿渠 ±24 m 全平（落差 0），河床 −2.31…−2.47 m；B7 (142.8, 42.0) 水面 0.44→0.16 m／48 m（0.58 %），標記處 0.30 m。兩處在 P8 水面剖面都沒有跌水所需落差；圓柱（底在標記）高出水面 F7 約 2.2 m、B7 約 2.5 m。**物理上說得通的堰＋跌水需改水面剖面（P8，牽涉水車 2 竜骨車取水）→ 待授權；本批未動。** **使用者 2026-10-16（Phase 4 R1 裁定 §4）**：不改 P8 水面、不在平坦水面上做假瀑布、不重生全村、不自行重新設計水車／灌溉；維持為**未解決的玩家可見缺陷**，等另案授權的水系修正。可逆、純視覺且不改水力剖面的替代方案只能另行提案，未經同意不實作；本項不得拖延建築工作。 |
| 10 | 検証の注記 | walk gate の B_lane_east（lost 37／max_dy 0.20）、C の lost 1／9／24 は overlay OFF でも同一 | `phase3_r1/evidence/walk_off.json` | 既存の地形の段差・水路。Phase 3 では判定を「ON が OFF より悪くない」に変えた |
| 11 | P12 | `EnrichW9P3` は MeshInstance（非 MultiMesh）。C 区の代表鏡位で GPU +0.35–0.65 ms | `phase3_r1/evidence/perf.json` | 全村へ広げる場合は MultiMesh か LOD |
| 12 | 相機（資訊） | bT3（075 前巷中）的相機與原場景同位置＝建物前面的平面・高 2.2 m，位於柴棚屋頂（只有視覺、無碰撞）的**下方**；屋簷底板占畫面上緣約 2 成 | `phase3_r2/evidence/gate_p3_view.log`：近景（≤ 1.8 m）071 overlay 遮蔽率 bT3 20.5 %・bT4 0 %（腕木＋斜材版為 31.5 %，提交前已撤） | 不動相機。走向 075 戶口時臂長 1.44 m，把 overlay 關掉的原場景也一樣（原場景建物 body 的既有行為）。使用者 2026-10-16：不再為 bT3 的局部屋簷遮蔽修改全域相機 |
| 13 | 相機（資訊） | 巷西端等處 62／10 960 個樣本（0.57 %）SpringArm 縮短 ≥ 0.30 m（最大 5.1 m）。來源 `EnrichW9P3/Collision`（最差 10 點皆在 073｜074 宅間木戶 `w9_kido` 附近；未特定到哪個碰撞箱） | `phase3_r2/evidence/arm_sweep_R2.json`（R1 的 `arm_sweep_R1.json` 也是同 62 件＝自 R1 起未變） | R1 已核准的配置。相機整合階段再一併處理 |
| 14 | 驗證註記 | cT4 遮蔽 gate 以橢球近似樹冠，且放寬過一次（「入口點須比目標早 0.5 m 以上才算遮」，R2 報告 R-G2；與黑松移位同一次編輯，未單獨量過）。最終 9 %（35 點中 3 點）距上限 10 % 很近。描畫（ID pass）實測 EnrichW9P3 遮住 0.1 % | `w9p3_lib.gd` 的 `crown_r`／`crown_hits`／`ct4_view`；`phase3_r2/P13_WAVE9_PHASE3_R2_REPORT.md` §5 | 之後要改配置時請用 ID pass（`repro/ct4_visibility.py`）確認 |
| 15 | 驗證註記 | R2 新增 gate 的門檻性質：①蔵 gate 只擋 R1 級的塔，R2 初版（棟 5.16 m）也通過；②view gate 的 22 % 在 gate 建立時就寫入，沒有獨立依據（最終實測 20.5 %，餘裕 1.5 點）；③sweep gate 的 N2 判準中途改過（`n_inj > n071`→`NEG_OWNER ≥ 20`），N2 件數 61→186 來自同名注入柱的歸屬問題 | `phase3_r2/evidence/GATE_HISTORY.md`、`phase3_r2/P13_WAVE9_PHASE3_R2_REPORT.md` §5 | 這些 gate 只作回歸防護；「像不像塔」「相機是否被擋」以審圖與真玩家實走為準。使用者 2026-10-16 接受此說明：**不得將 gate PASS 宣稱為美術品質的客觀證明** |
| 16 | Phase 4 R1／R1b（**已核准・結案**；使用者 2026-10-16） | 主街 7 棟（MKT_001／004／005／015、MXC_001／002／004）＋西巷 4 棟（RSW_024／025／026／012）＋中橫街植栽 1 區（東向 80–108 m） | `phase4_r1/P13_WAVE9_PHASE4_R1_REPORT.md`、`phase4_r1b/P13_WAVE9_PHASE4_R1B_REPORT.md` | A 主街 7 棟＝設計方向核准（R1 裁定，不再重新設計、不加裝飾雜物）；C 中橫街植栽＝核准（不再加樹木／灌木）；B 西巷 4 棟＝R1b 修正 B1／B2 後 ART_APPROVED。**不開 R1c**；已批准的 Phase 4 建築不再打磨 |
| 17 | 美術（資訊・下一批候選） | 主街 s≈110–178 m 本批沒有新作（沿街走圖 1／5）；臨街（距路中心線 ≤ 11 m）未改建 15 棟：MKT_002、017、018、003、019、021、022、007（南段 s 27–101）、023、028、014、016、MXC_003、008（MXC_018＝一の鳥居端景，不動） | 報告 §3；greybox＋BUILDERS 名統計 | 下一批由使用者指示選棟。使用者 2026-10-16：Phase 5＝**MKT_023、MKT_028**（中段優先）；MKT_014 與南段 8 棟（002／017／018／003／019／021／022／007）本輪排除，南段 8 棟之後另批。R1 裁定限定詞：s≈110–178 m 沿街走圖仍幾乎未變，**不得宣稱已解決整條主街的重複感** |
| 18 | **相機整合** | 西巷直線段 s 0–50 m、8080 樣本中 150 件（**1.86 %**）SpringArm 縮短 ≥ 0.30 m，全部來自 `EnrichW9P4/Collision`（宅間木戶／板塀）；最差 7.5→1.58 m（(203.76, −67.94)・yaw 270°）。屋根／庇／柱（ArchW9R2P13）造成的縮短為 0。同類 Phase 3＝0.57 %（#13） | `phase4_r1/evidence/gate_summary.txt`；**R1b**：同位置同朝向、只拿掉 EnrichW9P4 碰撞的對照 ray 查出 139／150 件・重い縮み（≥ 2.0 m 且腕 < 3.0 m）81 件全部來自 2 座屋根付き木戸（`w9_kido`，高 2.37 m，離巷軸 1.5 m）。木戸整座移到宅間深處 9.2 m＋若木後退 4.9 m 後：重い縮み 81→**0**、≥ 0.30 m 150→11（全是 025｜026 薪の下屋，最短 3.30 m）；熱點 H1 1.59→7.51 m、H2 1.59→8.50 m（原場景 7.49／8.50 m）。`phase4_r1b/P13_WAVE9_PHASE4_R1B_REPORT.md` §1–2、`phase4_r1b/evidence/lane_arm_R1*.txt`・`arm_hotspots.json` | **已核准・結案**（使用者 2026-10-16）：剩下的 11 件非重度縮短接受。選項 (b)「碰撞箱降到 1.3 m」不採用（碰撞高度未改） |
| 19 | 相機（資訊） | 窄巷中近接 RSW_024／012 的屋簷時，相機在屋簷邊，左上約半幅為深色軒裏（BEFORE 同位置也有、較小；相機座標兩邊相同、屋根無碰撞）。012（簷出 0.75→0.52 m）與 024（壁 3.0→3.5 m、簷出 .55→.50、唐破風縮窄／提高／縮出）已各做針對性修正，沿巷軸接近鏡位暗軒底 3–8 % | `phase4_r1/review/B3*.jpg`、`evidence/vision_self_assessment.md`；R1b 同鏡位相機座標不變（`phase4_r1b/review/B3_c012_eave_R1_R1b.jpg`） | 不再追參數；軒裏偏黑屬全域 lighting／相機整合。使用者 2026-10-16（R1b 裁定）：**保留這個屋簷相機限制**，不為審圖畫面改相機系統 |
| 20 | 驗證註記 | 驗證工具變更：`verify_w9r2.gd` **三角面上限由固定 420,000 改為『平均 15,550 tri／棟 × 棟數』（38 棟＝590,900；實測 556,089，新 11 棟平均 16,078 tri／棟、舊 27 棟 14,046）＝放寬絕對上限，待使用者裁定**，並在場景追加行額度加 Phase 4 的 3 行；`walk_w9r2_real.gd` 加 33 脚資料；`arm_sweep_w9p3.gd` 加 `--lane` 並認得 EnrichW9P4（兩者未改判定門檻）。歩行 47 脚 ON 44 通過；FAIL 3 脚（MKT_004／005／015 壁際 1.3 m 帶）ON／OFF 的停止位置與幀數完全相同（119／46／51 幀），非本批造成，止める物の正體は未特定（店前の既存物と推定） | `phase4_r1/evidence/walk_on.json`、`walk_off.json` | 既知；gate 是回歸防護，不是美術品質證明。使用者 2026-10-16（R1 裁定 §3）：**暫時接受目前幾何量繼續開發，不授權減面**；此上限變更記為**有意的暫定幾何預算修訂，不是優化成果**，通過新上限不能當作效能可接受的證明，之後不得為新增內容反覆調高門檻；下一次整合／優化階段以一致基準與可比鏡位評估實際效能。R1b 後 38 棟 557,173 tri（026 L0 16,932→18,016），上限未改 |
| 21 | 美術（資訊） | 前景既有構件遮住 MKT_004（9 m）的屋頂／二樓、MXC_001（6 m）的入口與部分立面（BEFORE 同樣被遮）；RSW_026 沿巷接近只看到遠處較高的妻面（2／5） | `phase4_r1/review/A2、A5、B2`；R1b 後 RSW_026 近景 3→4／5、巷軸中距 2→3／5、遠距 1→2／5（vision 自評，`phase4_r1b/review/B2_*`） | 使用者 2026-10-16：MKT_004／MXC_001 被遮的鏡位**不需為了截圖重建**，用既有無遮蔽鏡位作建築證據；RSW_026 遠距可讀性有限**不構成再迭代的理由** |
| 22 | **相機整合**（另案；使用者 2026-10-16 指定） | RSW_026 二樓（Kit body 碰撞上緣 2.90 m 以上沒有碰撞）：巷中 TPS 的相機有時進入二樓／出挑的可見體積 | `tools/p13/p4/diag_cam_026.gd`（唯讀）：西巷通行帶 8080 樣本，相機落入「碰撞外的可見體積」——腕 7.5 m：R1 90→R1b 75；腕 8.5 m：100→94。剩下的是 R1 以前就存在的類型，R1b 未新增屋根碰撞。`phase4_r1b/evidence/cam_026_volume_R1_R1b.txt` | 記為獨立的碰撞／相機問題，**不得把美術任務擴大成全域相機系統修改**；相機整合階段處理 |
| 23 | **相機整合**（Phase 5、同 #22 類型） | MKT_023 二階・屋根（Kit body 碰撞上緣 3.90 m 以上、新壁 5.5 m・棟約 8 m）沒有碰撞 | 平地 TPS 相機高約 3.2 m＜3.90 m，通常歩行では当たらない想定；**未取樣** | **未解決的整合問題**（使用者 2026-10-16 Phase 5 裁定）；依 #22 同樣另案，相機／碰撞整合階段處理；Phase 5 不新增屋根碰撞、不改相機 |
| 24 | 驗證註記（Phase 5） | 40 棟 LOD0 593,921 tri：#20 の式（15,550×棟數＝622,000）内だが 38 棟時の絶對值 590,900 を超えた（新 2 棟平均 18,374） | `phase5_r1/evidence/verify_w9r2_excerpt.txt` | 使用者 2026-10-16：**593,921 在既有上限 622,000 內接受，不提高預算公式**（15,550 × 棟數 不變）。Phase 6 R1 後 44 棟 664,328／684,200（公式未改；新 4 棟平均 17,602＞15,550，屋根佔約 90 %，餘裕 19,872）——新增建築的平均高於 15,550 會持續吃掉餘裕，是否接受待使用者裁定。Phase 7 後 46 棟 690,448／715,300（公式未改；新 2 棟 12,342／13,778＝平均 13,060＜15,550，餘裕 24,852） |
| 25 | **相機整合**（Phase 6、同 #22／#23 類型） | MKT_003 的 Kit body 碰撞上緣 3.90 m、新壁 6.25 m；MKT_019 出桁前出 0.40 m 在碰撞箱外（出し桁下端 3.24 m＞立面邊預設 TPS 相機高 3.22 m，但玩家可調俯仰） | `phase6_r1/P13_WAVE9_PHASE6_R1_REPORT.md` §5；**未取樣** | 依 #22／#23 另案；Phase 6 不新增碰撞、不改相機 |
| 26 | **相機整合**（Phase 7、同 #22／#23／#25 類型） | MKT_017 碰撞頂 5.40 m，新壁 5.6 m＋屋根＋本卯建（頂約 9.4 m、妻面外 0.28 m）；MKT_018 碰撞頂 3.90 m，後半本二階壁 5.35 m。牆邊預設 TPS 相機約 3.22 m 高，低於 017 下屋桁（約 3.45 m）、018 垂木尻（約 3.46 m）；調高俯仰時可能進入上層 | `phase7_mcp_pilot/P13_WAVE9_PHASE7_MCP_PILOT_REPORT.md` §6；**未取樣** | 依 #22／#23 另案；Phase 7 不加碰撞、不改相機 |
| 27 | 驗證註記（既有、Phase 7 發現） | `audit_village_v2_placement.gd --selftest`：PASS 201／REVIEW 4／FAIL 2（MXC_007×008 穿插 0.205 m、RSW_074×075 0.040 m、MKT_029×030 0.030 m），selftest 2 項不符（clean、aabbfp）。都是本回沒碰的 body 碰撞；017／018 不在名單內 | `phase7_mcp_pilot/evidence/placement_audit_excerpt.txt` | **未調查**；需先查是哪一輪改了這些 body 碰撞或 audit，再決定修 audit 或修場景 |
| 28 | **玩家可見缺陷**（Phase 8 發現、全村） | 除錯層外露：`Debug`（Label3D 39＝「LANDMARK_SOUTH_GATE」「鈴奈庵（候補）」「跌水（placeholder）」等巨大浮空字、`DistrictOutlines` 7 條）與 `QuestAnchors`（洋紅色 CylinderMesh 8 根） | 只有 `scripts/dev/review_start.gd`（ReviewStart）與 `p13_preview_boot.gd` 會隱藏；`main.gd::load_map` 不隱藏。`--map=village_v2` 實測全部可見（`phase8_village_survey/evidence/debug_visibility_normal_flow.txt`、`review/D_debug_layer_normal_flow.jpg`：4 鏡位中 3 個 vision 判 severe）。獸道 `beast_path.meta.json` 南端 portal 的 target 是 village_v2；目前正式開局 `trail → slice` 尚未接到 V2 | **未處理、需授權**：改 `main.gd`（共享）或 `gen_village_v2.gd`＋重生主場景，並與獸道 session 協調。Phase 8 排名第 1 |
| 29 | 整合（Phase 8） | `EnrichW9P8`（A8 稗田邸西、B8 東北聚落；154 件）已生成，**未掛進 `village_v2.tscn`** | 共享編輯器的 current_scene 是 `village_v2.tscn`，未存檔狀態無法經 MCP 確認，依指令不寫共享場景；AFTER 圖與 gate 都是記憶體內掛載。`phase8_village_survey/P13_WAVE9_PHASE8_VILLAGE_SURVEY_REPORT.md` §8、§10 | 待使用者 ART_REVIEW 裁定與掛載授權；掛載＝`build_w9p8.gd -- --attach`（3 行），刪除即還原 |
| 30 | 美術（資訊・Phase 8） | A8 遠距（X03、K01）只見一團綠、稻置場小道具零碎；B8「整體仍不是有人住的聚落」、PB2 沿路仍空、井戶周圍石材偏淺、吊柿排列規則、PB3 竹垣片孤立；D02／D04 幾乎無變化（畫面佔比 0.8 %／0.3 %） | vision 懷疑式評估（`phase8_village_survey/evidence/vision_notes.md`）、ID pass（`evidence/p8_coverage.txt`） | 已知限制；r1→r2 已用掉一次有理由的修正，不再反覆打磨，等使用者裁定 |
| 31 | 驗證註記（Phase 8） | `verify_w9p8.gd` 的門檻（區域最少件數、雜木林三層、變動係數 0.25、稻置場 < 2 m、portal 6 m、SpringArm 重度＝≥ 2.0 m 且腕 < 3.0 m）是本輪建 gate 時訂的，沒有獨立依據；r1→r2 期間門檻未改。未做真玩家控制器實走、共享編輯器中的掛載 runtime。效能（ON−OFF）ΔGPU +0.11～+0.22 ms、Δdraw calls +86～+222（MeshInstance、非 MultiMesh，同 #11） | `phase8_village_survey/evidence/gate_final.txt`、`GATE_HISTORY.txt`、`perf_p8.txt` | gate 只是回歸防護，**不得當作美術品質的證明**；掛載後若要上線再做實走 |

## Phase 3 第一批 結案（使用者 ART_APPROVED・2026-10-16）

| 範圍 | 裁定 | 記錄位置 |
|---|---|---|
| MXC_005 白蔵／RSW_071 柴棚／C 區 cT4・cT7 植被（R2b） | **ART_APPROVED** | `phase3_r2/P13_WAVE9_PHASE3_R2_REPORT.md` 開頭「最終裁定」 |
| R2 報告更正（gate 執行歷史・判準更動・R-G4 先後） | 已接受 | commit `dc3c764`；`phase3_r2/evidence/GATE_HISTORY.md` |

- 本批正式結案。**不得自行開啟 W9 Phase 3 R2c**；三區不再微調（footprint／比例・全域相機／bT3 屋簷・灌木間距／葉冠／地被）。
- 局部結案：**W9 整體沒有封存**，也沒有 hash 封存檔（W9 沒有這個機制，Phase 1／2 也沒有）；做法同 Phase 2（commit `1fdb647`）：報告開頭追記最終裁定、保留提交時記錄、更新本登記表、不重跑檢查、不 push。
- 已知限制（#6–#15）原樣保留，不要求修正。gate 只是回歸防護，**不得宣稱為美術品質的客觀證明**。
- 引用的既有 commit：`68e1433`（R2 三項局部修正）、`dc3c764`（報告更正）。R1：`0fdea17`、`bce7cf4`。

## 下一批方向（使用者 2026-10-16 裁定）

P13 要擴張到尚未改善的街區，**不回頭反覆打磨已批准的三區**。**下一批必須以大幅提升場景辨識度為目標。** 優先目標：

1. 讓更多建築有不同的屋頂、量體、立面與用途。
2. 改善空曠住宅區與聚落的植被層次。
3. 增加玩家正常 TPS 能明顯看見的場景特色。
4. 清查遠景灰盒與未完成建築。
5. 河道內的 P2 `WATERFALL_F7/Placeholder` 藍色圓柱（登記表 #9）：玩家可見缺陷，先確認用途與依賴關係，不得未經確認改動封存場景。

## Phase 4 結案（使用者 ART_APPROVED・2026-10-16）

| 範圍 | 裁定 | 記錄位置 |
|---|---|---|
| A 主街 7 棟（MKT_001／004／005／015、MXC_001／002／004） | 設計方向核准（R1 裁定），本批不需再設計 | `phase4_r1/P13_WAVE9_PHASE4_R1_REPORT.md` 開頭「最終狀態」 |
| B 西巷 4 棟（RSW_024／025／026／012）＋ B1 SpringArm／B2 RSW_026 | **ART_APPROVED**（R1b 最終裁定） | `phase4_r1b/P13_WAVE9_PHASE4_R1B_REPORT.md` 開頭「最終裁定」 |
| C 中橫街植栽（東向 80–108 m） | 美術方向核准（R1 裁定），保留目前配置 | 同 R1 報告 |
| 幾何預算（590,900） | 暫定接受、不授權減面；記為暫定幾何預算修訂（#20） | 本表 #20 |
| B7／F7 藍色圓柱 | 不改 P8 水面；維持未解決的玩家可見缺陷（#9） | 本表 #9 |

- 本批正式結案。**不開 R1c**；已批准的 Phase 4 建築不再打磨。
- 局部結案：**W9 整體沒有封存**，也沒有 hash 封存檔（同 Phase 1–3 先例）。做法同 Phase 3（`79daa60`）：報告開頭追記最終裁定、保留提交時記錄、更新本登記表、**不重跑檢查、不重拍圖**、不 push。
- 已知限制（#18 的 11 件、#19、#20、#21、#22）原樣保留，不要求修正。gate 只是回歸防護，**不得宣稱為美術品質的客觀證明**。
- 引用的既有 commit：R1 `bd576d7`（內容）・`849ee8f`（文件）；R1b `6e03bce`（內容）・`400d798`（文件）。

## Phase 5 指派（使用者 2026-10-16）

主街中段：**MKT_023**（市集入口的角店）、**MKT_028**（單層住宅）。排除：MKT_014、南段 8 棟、全域相機／控制器修改、全村建築重建。
- MKT_023：做出正常 TPS 走過時讀得到的角地輪廓（屋根、立面、街角性格），不是只加道具；**P10 R2 封存的街道附件（提灯・看板・幟）與其掛點全部保留**，新建築配合既有限制，不改封存內容。
- MKT_028：建立與相鄰商家對比的住宅型；**先從北側拍再決定設計**；優先屋根輪廓、入口配置、整體量體；不做不必要的 footprint／動線變更。
- 沿用可逆的建築 overlay 流程；入口・通行・碰撞行為保持；只做局部結構／碰撞／可逆性／短實走檢查，不做全回歸；結果送 **ART_REVIEW**，不自行核准或封存。
- **Phase 5 R1 已送 ART_REVIEW**（2026-10-16）：`phase5_r1/P13_WAVE9_PHASE5_R1_REPORT.md`。未核准、未封存；新增 #23、#24。

## Phase 5 結案（使用者 ART_APPROVED・2026-10-16）

| 範圍 | 裁定 | 記錄位置 |
|---|---|---|
| MKT_023 市の角の米屋、MKT_028 妻入の仕舞屋 | **ART_APPROVED**；不授權 R2，現行幾何保留 | `phase5_r1/P13_WAVE9_PHASE5_R1_REPORT.md` 開頭「最終裁定」 |
| MKT_023 二階碰撞 | 未解決的整合問題（#23） | 本表 #23 |
| 面數 593,921（40 棟） | 既有上限 622,000 內接受，不提高公式（#24） | 本表 #24 |

- 局部結案，W9 整體未封存、無 hash 封存檔（同 Phase 3／4 先例）。報告開頭追記裁定、保留提交時記錄；**不重跑檢查、不重拍圖**、不 push。
- 引用 commit：`5621397`（內容）・`c83b9c3`（文件）。

## 下一方向：主街建築多樣性（南段，使用者 2026-10-16）

候選 8 棟：MKT_002、MKT_017、MKT_018、MKT_003、MKT_019、MKT_021、MKT_022、MKT_007。實作前先看現況輪廓與正常 TPS 可見度，選出正常遊玩中改善潛力最大的 **4 棟**。
- 優先：屋根輪廓與棟高差、量體比例與立面深度、符合用途的建築性格、TPS 步行路線上的可讀性、街景整體構成（不是單棟裝飾複雜度）。
- 避免：重複的屋根變體、過多道具、改動已核准建築。
- 沿用可逆 overlay 流程；只做實際幾何變更需要的定點檢查。主要成功標準：**玩家走過時明顯感到村落更多樣**。送 ART_REVIEW，不自行核准或封存。
- **Phase 6 R1（主街南段 MKT_019／021／022／003）已送 ART_REVIEW**（2026-10-16）：`phase6_r1/P13_WAVE9_PHASE6_R1_REPORT.md`。未核准、未封存；新增 #25、更新 #24。
- **Phase 7 MCP-first 試行（主街南段 MKT_017／018）已送 ART_REVIEW**（2026-10-16）：`phase7_mcp_pilot/P13_WAVE9_PHASE7_MCP_PILOT_REPORT.md`。未核准、未封存；新增 #26／#27、更新 #24；overlay 新增 `keep_r1`（017 的 R1 杉玉保留顯示）。Phase 6 仍在 ART_REVIEW、幾何未動。

## Phase 8：全村完成度調查（使用者 2026-10-16「Village-Wide Completion Survey」）

- 方向轉為全村的環境完整度與探索體驗；017／018 為使用者接受的現行視覺基準（不再打磨，碰撞限制 #26 保留），**不是 ART_APPROVED 記錄**。
- **已送 ART_REVIEW**（2026-10-16）：`phase8_village_survey/P13_WAVE9_PHASE8_VILLAGE_SURVEY_REPORT.md`。全村評估、灰盒盤點（G1–G7）、注記地圖、五項排序；第一批 A8／B8 overlay `EnrichW9P8` 生成但未掛載（#29）。新增 #28–#31。未核准、未封存、未 push。
- 需要使用者裁定：A8／B8 是否值得掛載；除錯層處理（#28）；丘腳社寺造型方向（TASK E）；主街南段路口・火見櫓前是否開放 P10／P9 封存範圍。
