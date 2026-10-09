# P10 R5–R6 ROUND 2 — ART_REVIEW

**狀態：ART_REVIEW（ROUND 2），未 ART_APPROVED、未封存、未重新封存任何受影響階段。**
使用者 2026-10-09「P10 R5–R6 — ART_DIRECTION ROUND 2」。起點 HEAD `b502dbc`。本輪只動三個需整改的 Pilot（R5b 水車 2、R6b 參道、R5a 道路 base）；R5c／R4c 不再迭代；R6a 只交材質規範與封存相容方案（文件）。

## 0. 一頁結論

| 工作包 | ROUND 1（使用者） | ROUND 2 做了什麼 | Agent 自評（vision，**不是 ART 判定**） | 技術 gate |
|---|---|---|---|---|
| **R5b 水車 2** | 西 2/5、東／高 3/5 | 安並式柄杓（輪郭の外へ張り出す）、水の見せ方（柄杓の中の水・滴り・注ぎ・跳ね・樋の流れ）、架台を古い暗い木＋筋交い、**P8 落とし樋の木部 17 件を輪と同じ明度（runtime）**、**根因修正：手作り方塊が裏返し（巻き順）** | 西 TPS 3、東 TPS 3、東 8 m 3–4、高 3；**白い縦材＝消えた** | plan 10＋反向 10/10、build 表裏 0／2724、scene 11 |
| **R6b 參道** | 下り 2/5（石段は基礎として核准） | **根因修正：石段の法線が裏向き＝踏面に日が当たらず暗い青**；踊り場 3（s 50／62.6／75.6、盛土 ≤ 1.09 m）＋丘の肩の長い段 13＝最長 44 段で休む；幅 2.4 m；1 枚石中心・不揃いの鼻先・面取り・ひび・苔の低い袖石；兩脇の土の帯を隠す | 下り 3、頂上から下り 3、踊り場から下り 2、上り 5 m 3、上り踊り場 4、中段（視線の終点）4 | plan＋反向 8/8、リズム gate、表裏 0／6468、scene 6；實走 上下 阻塞 0；**P9 R4-2 封存 gate と衝突（§6）** |
| **R5a 道路 base 重生 Pilot** | 部分通過（田格の除去は受理） | 3 本 416 m を地形なり（元は地形＋0.10 m の平板）・幅 0.52–0.82×・蛇行・区間別の使われ方（轍／中央草／路肩草／砂利）で再生；元 .res 不変 | 5–6 m 3、8–10 m 4、10 m 3、高 3–4 | plan＋反向 5/5、build（元 .res 雜湊不變）、scene 7；GroundPilot 補丁 7 段・反向 7/7 |
| R6a 建築亮度 | ART_APPROVED（24 棟 Pilot） | 施工なし。Kit 材質規範＋封存相容方案（`round2/r6a_kit_material_spec.md`） | — | Kit Gate 不放寬 |
| R5c／R4c | ART_APPROVED（Pilot） | 不再迭代、成果保留 | — | 回歸で確認 |

**主要視角 4/5 には三包とも未到達**（水車 3、參道下り 3、道路近距 3）。停止規則に従い、本輪はここで止めて裁定を仰ぐ。

## 1. 本輪で見つけた根因（三包に共通しない、個別の実測）

1. **手作り網格の表裏（R5b・R6b、第一輪からの不具合）**：Godot は時計回りが表。
   - R6b：踏面の明示法線が下向き → 日光ゼロ・空の環境光だけ → 下り視点の画素 RGB 16/39/61（同じ場所の土 98/92/72）。第一輪の「偏深色」の主因。
   - R5b：方塊（柄杓・受け樋・架台・杭）の外側の面が裏＝間引かれ、奥の内側の面が外向き法線で照らされる → 柱が空の色の青灰に光る、柄杓が平たい。
   - 修正＋**永久 gate「表裏」**（明示法線と表が逆の三角形 0、反向で旧い巻き順の四角を必ず検出）。
2. **P8 落とし樋の木部が頂点色なし**＝水車の輪の 1.6 倍明るい → 支柱・樋が淡色の縦材。表示切替（WaterFX／架台／P5 LOD0）で白い縦材の出どころを特定。
3. **道路**：`_ribbon` は左右 2 点の平板を「道の高さ＋0.10 m」に置く（実測 +0.100、最大 +0.172）、幅一定・定規の直線。

## 2. R5b 水車 2（`round2/r5b_water/README.md`）
- 使用者の 5 項目：①水輪の取水＝柄杓が水に浸かる（最下点が水面 −0.2 m 以下）・輪の下の泡　②柄杓の提升＝上り側の柄杓の中の水・水から出たばかりの柄杓の滴り　③受水槽へ倒入＝輪頂を越えた柄杓の口から東へ落ちる注ぎ＋受け樋の跳ね　④合理坡度＝受け樋 50 mm 下がり → P8 樋頭（Δy 0.014 m）→ P8 落とし樋の流れ　⑤白色豎向構造＝樋頭架台（P8 樋頭の枕木を下から支える柱 2＋頭貫・腰貫・筋交い）。今は古い暗い木で、vision は東西 TPS とも「淡い縦材なし」。
- 残る：輪頂の受け渡し（柄杓→受け樋）は小さく、主な TPS 角度では架構と重なる → 4/5 未達。選択肢：(a) 現状で可／(b) 受け樋の樋口を東の通路から見えるよう延ばす（P8 樋頭不変）／(c) 純動力へ戻し P8 高架出水を撤去（P8 limited reseal）。**水車 1／3 は未着手**。

## 3. R6b 參道（`round2/r6b_shrine/README.md`）
- 186 段は高低差 32.8 m と蹴上 0.17–0.19 m で決まる（段数を減らすには蹴上 > 0.20）→ 一本の帯をリズムで解いた：普通段 169（蹴上 0.135–0.197、踏面 0.25–0.45）＋丘の肩（11–24°＝地形の根拠のある休み）の長い段 13＋30° 一定坂の踊り場 3（參道が 16° 曲がる s 62.6 を含む）。燈籠は 3 対のまま。
- 實走（正式 main.tscn・実入力・既存 TPS 相機）：上り 69.6 m／19.9 s、下り 90.1 m／23.9 s、阻塞 0、接地 100 %。**下りの ARM_PULL 1→5**（背後の斜坡に SpringArm が縮む、穿模ではない）。
- 残る：下り視点 3/5（鼻先が直線的・きれい過ぎ、下りでは踊り場が平らな台に見えやすい）。

## 4. R5a 道路 base 重生 Pilot（`round2/r5a_road/README.md`）
- 対象＝FarmPath_1（160 m）・FarmPath_4（216 m）・南橫街の橋より東（町の区間は元の三角形 150 を逐字）。
- 依存：道に碰撞なし（歩行＝P1 地形）、NPC 0 人（不搬）、P8＝元の路幅の中だけ、P9 地被／立ち草＝路幅内の株 0・浮き 0、P7 橋の切れ目を保持、元の road_*.res 雜湊不變。
- 残る：細くした分、地形自身の「道の土」塗り（P7）が直線の帯で残る（**推定**、切り分け撮影は未実施）→ P7 地形重みか pilot shader へのマスクが必要＝次の一手（提案）。轍の対・中央草がまだ弱い。

## 5. R6a／R5c／R4c
- R6a：`round2/r6a_kit_material_spec.md`——Kit 専用の校正材質を新資産で作り（_matlib 不変＝P5 Protected・P9・P10 へ波及なし）、Kit 網格の参照を差し替えて P6 Kit Gate のルールはそのまま（5 材質・override なし）→ P6 limited reseal。調色盤は「変体登記表」を Kit Gate に**厳しく**足す案（要裁定）。本輪は施工なし。
- R5c：変更なし。R4c：変更なし（A2 の位置と st_hasa_v2 は R4／R4b snapshot の limited reseal 待ち＝ART_APPROVED 後）。

## 6. 回歸（`round2/regression/`）

**第一輪の第 10 項＝19-point walk**（Newly Introduced、一の鳥居の柱台で膠囊が 0.50 m 浮く → 柱台ガードで修正済み `2f617cd`）。10 項すべての分類と證據は `round2/regression/CLASSIFICATION.md`。

**ROUND 2 全量 130 項（128＋RDB 2）：121 PASS／9 FAIL**（`full_regression.log`、約 85 分）

| 分類 | 項目 | 説明 |
|---|---|---|
| Pre-existing Failure（3） | terrain gate（base 載入 3707 ms ＞ 3000）、P5 asset reset（違規 421）、P9 R4-3 寺子屋周邊場景級（R3d C20 巡回） | P10 FINAL 基準と同じ。P8 runtime budget は今回 **PASS**（もともと「UNRESOLVED CLEAN BENCHMARK」の不安定項目） |
| Expected Pilot Seal Conflict（5） | P6 町家 Kit Gate（AlbedoPilotP10）、R4 HUSE 場景級＋封存、R4b HUX 場景級＋封存（PropFixP10：A2 1 件の位置） | 第一輪と同じ内容（ROUND 2 は Albedo／PropFix を変えていない）。第一輪の `proof_pilots_off.log` で 2 overlay を外すと全 PASS を確認済み |
| **Newly Introduced（1）** | **P9 R4-2 神社周邊 場景級**：封存 gate の「參道＋前庭膠囊（地形＋0.55 m から上）」179 点中 40 点が `RampCollision` に当たる | ROUND 2 の**盛土の踊り場**で、踊り場手前の斜坡碰撞が地形より最大 1.09 m 上にある（踏面の上を歩く設計）。證明：ShrineApproachP10 を外すと 179 点 被擋 0＝PASS（`proof_r6b_off_p9r42.log`、tscn は sha256 一致で復元）。実際の玩家實走は阻塞 0。**舊 gate は修改していない** |

ROUND 2 の gate（WLF／SAN／GRD／RDB の plan＋場景級、R5c／R6a／R4c）、19-point walk はすべて PASS。

P9 R4-2 の扱い（要裁定）：
- (1) 踊り場を採用し、P9 R4-2 の實走プローブを「歩ける面の上（最上面）」に移す封存遷移（P9 R4-2 limited reseal、使用者の承認後）。gate の意図＝「參道が歩ける・ふさがれていない」は変わらない。
- (2) 30° 坂の盛土の踊り場をやめ、丘の肩の長い段だけ残す（斜坡が地形に沿い P9 R4-2 は元のまま通る；下り視点のリズムは弱くなる）。

本輪で見つけた別の不具合（修正済み）：ShrineApproachP10／WaterLifeP10 は掛載ノードに `enabled=false` を書いて読み込むと `_ready` が apply を呼ばず、石段・斜坡碰撞・架台が残っていた（第一輪から）。`_ready` で常に `apply(enabled)` に修正、場景級 gate 再実行 PASS、上の證明で enabled=false の読み込みが効くことも確認。

## 7. 效能（`round2/perf/`、Forward+、GTX 1070、1600×900、10:00、15 機位 × 2 回）
- 本輪で変えた 4 overlay（GroundPilot／WaterLife／ShrineApproach／RoadBase）の ON−OFF：**−0.00〜+0.41 ms**（最大 `perf_r4c_hasa` +0.41、參道 `perf_san_steps` +0.29、田の高視角 +0.17）。
- 全 7 overlay の ON：參道機位 **14.09 ms**（第一輪 14.27 ms、追跡継続）、田の高視角 11.60（第一輪 11.56）、朝外の機位は第一輪と同等（R5c 林帯＋Vista の分）。

## 8. 封存依存への影響（すべて runtime／overlay、封存ファイル改動 0）
| 封存 | 本輪の影響 | 状態 |
|---|---|---|
| P1 地形・碰撞 | なし（石段は地形の上、道は地形を射線で読むだけ） | — |
| P3 道路（road_*.res） | RoadBaseP10 が 3 本の mesh を runtime 差し替え；ファイル雜湊不變（`47c5492e…`／`f46ba82e…`／`7f4e607d…`） | 要裁定（全村適用＝D3） |
| P3 參道 ribbon（HillApproach） | ShrineApproachP10 が石段範囲を全幅で隠す（cut_hw 2.6、第一輪 1.63） | runtime |
| P5 水車 2（Protected） | 柄杓を轉子の子として runtime 掛け；資產不變 | runtime |
| P5 sando_torii | 一の鳥居として instance（第一輪と同じ） | — |
| P6 町家 Kit | AlbedoPilotP10（第一輪のまま）→ Kit Gate＝Expected Pilot Seal Conflict | 方案＝R6a 文書 |
| P7 ground.gdshader | 雜湊不變；pilot shader（補丁 7 段目＝UV2.y ≥ 1 の再生道だけ） | runtime |
| P7 橋 | 南橫街の切れ目（橋）を保持 | — |
| P8 落とし樋（WaterSupply） | **木部 17 件の material_override（runtime、ファイル不變、enabled=false で元へ）** | 新規・要裁定 |
| P8 田・水路 | 道は元の路幅の中 | — |
| P9 地被／立ち草 | 道の路幅内の株 0（浮き 0） | — |
| **P9 R4-2 鎮守之森（場景級 gate）** | **盛土の踊り場の斜坡碰撞が、封存 gate の「地形＋0.55 m の膠囊實走」に 40／179 点当たる**（ShrineApproachP10 を外すと PASS） | **Newly Introduced・要裁定**（§6） |
| P10 R4／R4b | PropFixP10（第一輪のまま）→ HUSE／HUX＝Expected Pilot Seal Conflict | ART_APPROVED 後 limited reseal |
| NPC 51・Population | 不搬（石段・鳥居柱・再生道との干渉 0） | — |
| `village_v2.tscn` | ＋3 行（RoadBaseP10 掛載） | — |

## 9. コミット（push なし、使用者の staged 53 件は触らない）
（下に記入）

## 10. 裁定をお願いしたいこと
1. R5b：(a) 現状／(b) 受け樋の樋口を見せる／(c) 純動力へ戻す（P8 高架出水撤去＝P8 limited reseal）のどれで進めるか。P8 落とし樋木部の runtime 明度合わせを認めるか。
2. R6b：下り視点 3/5 の現状で石段の方向性を認めるか（次の一手＝鼻先の欠け・不揃いの踏石高さ等）。**盛土の踊り場**を残して P9 R4-2 の實走プローブを最上面へ移す封存遷移を認めるか、踊り場をやめて丘の肩だけにするか（§6）。下りの ARM_PULL 増加の扱い（相機は別件として記録）。
3. R5a：道路 base 再生の方向を認めるか。残る「直線の土の帯」に P7 地形重み（limited）または pilot shader マスクのどちらで進めるか。
4. R6a：Kit 材質規範 方案 A／B、調色盤の変体登記表を Kit Gate に入れるか。
5. 回歸の Expected Pilot Seal Conflict（P6 Kit／R4 HUSE／R4b HUX）を、どの段階で合法的に封存遷移するか。

**STOP。ART 裁定待ち。**
