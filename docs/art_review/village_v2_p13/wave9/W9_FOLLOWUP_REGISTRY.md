# P13 W9 後続登記（ART_APPROVED 済みの項目から出た、後の統合段階で扱う事項）

登録のみ。ここにある項目は、該当の建築が ART_APPROVED になったあとも**解決済みとは扱わない**。着手は使用者の指示または該当段階（相機整合／全域 lighting／P12）まで保留。
最終更新：2026-10-15（W9 Phase 2 三棟 ART_APPROVED の局部結案時に作成。#6–#11 は Phase 3 R1 の ART_REVIEW 提出時に追加。#6 は提出後に数値・方位を更正：Phase 3 R1 報告 §8）。なお、既存の「相機整合一覧」という名前のファイルは見つからなかった（`P11_HANDOFF.md`／`CAMERA_HANDOFF_yoriichi.md` は別 session の交接文書で触れていない）。相機側の窓口が決まったら、この表の #1 を渡す。

| # | 区分 | 項目 | 根拠（実測・出所） | 扱い |
|---|---|---|---|---|
| 1 | **相機整合** | **MKT_029 の原 body 碰撞が可視の前店屋根より高い**ため、SpringArm が屋根の手前で止まる／蔵の上で縮む可能性 | body Shape＝6.994 × 5.766 × 10.92 m・中心 y 2.517（上端 **5.40 m**）。可視の前店の棟は **4.63 m**、庇 3.6 m、蔵の棟 7.40 m。地上の玩家は届かないが相機は未測定 | 美術承認とは別。相機整合で測る（相機は触らない）。footprint／body を変える場合は使用者の事前承認が要る |
| 2 | 動的環境 | RSW_014：鍛造の火光・煙・NPC の作業動画 | 使用者裁定（Phase 2）：後続の動的環境項目、今回は扱わない | 動的環境の段階で |
| 3 | 全域 lighting（P13） | MKT_029 の蔵の白い妻面が 10:00 の全域光で灰青に見え、通常 TPS で蔵棟の辨識が弱い | 使用者裁定：局所の明るさ調整は開かない | 全域 lighting の段階で |
| 4 | 検証の注記 | posts gate の「過大な碰撞」探測は、同棟の別の碰撞箱が近い位置では略過する（成排小物のため）。小物の碰撞箱 18 個のうち、真人短走で停止位置を実測したのは代表 5 個 | `verify_w9r2_posts.gd`／`evidence/phase2_r2_checks.txt` | 必要なら他の箱も実走で測る |
| 5 | P12 | 小物（薪・桶・荷受け台ほか）は L0 のみで、LOD 切替時に 0.2–0.4 m 級の小物が出入りする | `build_w9r2_arch.py` の `Bld.P` は lod==0 のみ | P12 の LOD／最適化で |
| 6 | **相機整合** | **RSW_071 柴棚の前柱（Posts 碰撞、寬 0.14 m・局部高 2.478 m）が、B 巷で SpringArm を 1.21 m 縮める** | 巷中 (235.8, −87.6) で 075 正面（朝北）を向く位置：SpringArm 長 BEFORE **2.75 m**（071 の原 body に当たる）→ AFTER **1.54 m**（`ArchW9R2P13/B_P_RSW_071/Posts`、射線の命中高度 y 3.40 m）。玩家の足元から相機まで 3.48→2.48 m。`arm.collision_mask`＝1、Posts は建築 body と同じ layer。`tools/p13/w9/diag_arm.gd`、`phase3_r1/evidence/springarm_bT3_*.log` | MKT_029 と同類。相機は触らない。選択肢（相機側の窓口と相談）：①相機側で細い柱（<0.2 m）を SpringArm が無視する／margin を下げる ②overlay 側で Posts を SpringArm の mask に入らない layer へ（先に玩家の mask を測る）。柱の碰撞高さを下げる案は、見える柱とずれるので推奨しない |
| 7 | 美術（非阻塞） | MXC_005 の白い蔵が幅 3.0 m の制約で細身（「塔のよう」） | Phase 3 R1 で 2 回調整（幅 2.2→3.0 m、棟 6.9→6.2、腰屋根・石土台・側壁木帶）。視覚モデルの自評は依然「細長い」 | footprint を変えない限りこれ以上は体量で解決しにくい。使用者の判断待ち |
| 8 | 美術（非阻塞） | C：前景の樹が大きく、庭南端から北を見ると主屋を隠す／路肩灌木の形の繰り返し／柴棚の正面が暗い | `phase3_r1/review/C_tps_before_after.jpg` の C-TPS3（自評 3/5） | 樹の縮小は次バッチ、暗さは全域 lighting（P13） |
| 9 | 既存（Phase 3 無関係） | C 区の運河に青い円柱（P8 水利）が目立つ | BEFORE にも同じものがある | P8 の領域。触らない |
| 10 | 検証の注記 | walk gate の B_lane_east（lost 37／max_dy 0.20）、C の lost 1／9／24 は overlay OFF でも同一 | `phase3_r1/evidence/walk_off.json` | 既存の地形の段差・水路。Phase 3 では判定を「ON が OFF より悪くない」に変えた |
| 11 | P12 | `EnrichW9P3` は MeshInstance（非 MultiMesh）。C 区の代表鏡位で GPU +0.35–0.65 ms | `phase3_r1/evidence/perf.json` | 全村へ広げる場合は MultiMesh か LOD |
