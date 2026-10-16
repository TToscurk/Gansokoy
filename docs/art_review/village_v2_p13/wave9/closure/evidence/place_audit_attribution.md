# 場景擺放／碰撞稽核（audit_village_v2_placement.gd）收尾時的 FAIL 調查與修正

## 現象
回歸總表 PLACE（--selftest）在收尾掛載後：clean PASS 192／REVIEW 6／FAIL 9（207 單位），selftest 2 項不符（clean、aabbfp）。
Phase 7 時已是 PASS 201／REVIEW 4／FAIL 2、selftest 2 項不符（登記表 #27「未調查」）。

## 原因（實測）
`_narrow_phase()` 以 `collide_shape` 查 A 的 shape 時，只 exclude「單位＋地形＋邊界」，不 exclude overlay 的道具／構件碰撞。
A 的 shape 碰到第三者，接觸就被記成「A × B 穿插」。用 `intersect_shape`（只排除 A 自己與地形）逐對列出實際接觸對象：

| 報告的對 | 舊報告深度 | A 的 shape 實際碰到的碰撞體（收尾後） | 收尾前（未掛 EnrichW9P8） |
|---|---|---|---|
| B_P_RNE_002 × 003 | 0.062 FAIL | EnrichW9P8/Collision | 無 |
| B_P_RNE_003 × 004 | 0.062 FAIL | EnrichW9P8/Collision | 無 |
| B_P_RNE_005 × 006 | 0.066 FAIL | EnrichW9P8/Collision | 無 |
| B_P_RNE_016 × 017 | 0.057 FAIL | EnrichW9P8/Collision | 無 |
| B_P_RNE_011 × 012 | 0.026 REVIEW | EnrichW9P8/Collision | 無 |
| B_P_MXC_007 × 008 | 0.205 FAIL | ArchW9R2P13/B_P_MXC_007/Posts | 同（既有） |
| B_P_MKT_029 × 030 | 0.030 REVIEW | ArchW9R2P13/B_P_MKT_029/Posts | 同（既有） |
| B_P_RSW_074 × 075 | 0.040 REVIEW | ArchW9R2P13/B_P_RSW_074/Posts | 同（既有） |

→ 沒有一對是兩棟建物彼此穿插。新增的 RNE 5 對是 EnrichW9P8 貼牆的棚／構件碰撞與宅的灰盒碰撞接觸（深度 0.026–0.066 m，Phase 8 的貼牆設計）；
MXC／MKT／RSW 3 對（#27）是 W9 R2 自己的柱。

## 修正
`_narrow_phase()` 的 exclude 改為「場景中 B 以外的全部 CollisionObject3D」。門檻（PEN_REVIEW 0.02 m 等）不變，只修正接觸的歸屬。

## 修正後
- clean：PASS 207／REVIEW 0／FAIL 0（207 單位）
- 反向／對照 5 案全部符合：float→FAIL、sink→FAIL、clash→兩者 FAIL（穿插 3.210 m）、aabbfp→兩者 PASS（舊版此案不符）、noproxy→REVIEW
- selftest 0 項不符（`place_selftest_after_fix.log`）

## 仍需知道的
EnrichW9P8 有構件碰撞與 RNE 宅的灰盒碰撞重疊 0.026–0.066 m（貼牆）。走路實測不受影響（26 段 0 卡住）；這個稽核本來就只涵蓋建物單位，overlay 道具由 verify_w9p8.gd（43 PASS）負責。
