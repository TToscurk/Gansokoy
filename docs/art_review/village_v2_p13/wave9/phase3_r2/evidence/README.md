# phase3_r2/evidence 索引

全部為 2026-10-15、最終 build（`build_w9r2_arch.py` 的 R2b＋`w9p3_lib.gd` 的 C 區校正後）所取。重現步驟在 `repro/`。
**各新增 gate 的完整執行歷史（含失敗與判準更動）在 `GATE_HISTORY.md`；sweep gate 第一次（失敗）執行的原始輸出在 `history/`。**

| 檔案 | 內容 |
|---|---|
| `GATE_HISTORY.md` | 新增 gate 的所有執行（時刻・通過／失敗・失敗內容・其後的修改）；資料來源＝Hermes session 紀錄的工具回傳 |
| `history/gate_arm_sweep_run1_221517.log` | sweep gate 第一次執行（7 通過／2 失敗）的原始輸出 |
| `gate_r2_main.log`／`gate_r2_posts.log`／`gate_w9_reach.log` | 主 gate 374／0（反向 36／36）・柱 gate 19／0・到達性 NG 0 |
| `gate_p3_environment.log` | Phase 3 環境 gate 50／0（cT4 遮蔽・相機樹冠・cT7 路肩，另有反向 7 件） |
| `gate_p3_kura.log` | MXC_005 蔵的比例 6／0（實測：棟 4.61・店的棟 6.98・壁寬 3.45・奧行 10.49 m） |
| `gate_p3_view.log` | 071 柴棚近景遮蔽（bT3 20.5 %・bT4 0 %）9／0 |
| `gate_arm_sweep.log`／`arm_sweep_R2.json`／`arm_sweep_R1.json` | 全巷 SpringArm sweep：R1＝250 件（071 造成 188）→ R2b＝62 件（071 造成 0）。反向：放回 R1 的柱，縮短 1.21 m |
| `walk_arm_off.*`／`walk_arm_on.*`／`walk_arm_neg.*` | 真玩家短走，每幀記錄 `get_hit_length()`（OFF＝關掉 overlay；ON＝R2b；NEG＝在記憶體中放回 R1 的庇柱）。`.json` 為每幀的臂長與位置 |
| `walk_on.log`／`walk_on.json` | 真玩家 23 段步行（新增：沿庇柱線／走到薪堆前，共 2 段） |
| `ct4_visibility.json`／`idpass_cT4_R1.png`／`idpass_cT4_R2b.png` | cT4 農舍・運河・護岸的可見比例（ID pass ÷ 關掉 EnrichW9P3 的基準） |
| `p3_environment_plan.json`／`build_enrich.log` | EnrichW9P3 最終計畫（79 構件）與 build log |
| `build_arch_chain.log` | R2b 重建那條鏈（Blender→import→prefab→build，`p3_run.sh`）的標準輸出；不含更早的嘗試 |
| `../review/ba_stats.json` | 相機位置比較（A：R1↔R2b；B：原場景↔R2b 與 R1↔R2b；C：R1↔R2b）與 R1↔R2b 的畫素差 |
| `../review/full/` | 主要鏡位 1600×900 圖（BEFORE／R1／AFTER）；`2h`、`2i` 為柴棚外觀（只有 R2b） |

## 注意
- 拍完 RC（cT4／cT7）之後又重 build 過 `enrich_w9p3.scn`，但計畫 JSON（構件 79・dropped 7）與拍攝前的 build 完全一致（`.scn` 位元組是否一致未驗證）。
- 畫素差會被風（植被擺動）推動數％，不能用來判斷有意的變化。
- ID pass 的 `idtable.json`（全節點對照表，數 MB）沒有放進來；可用 `repro/p3_idrun.sh` 重生。

## 重現
```
bash repro/p3_run.sh                  # Blender→import→prefab→build（建築 overlay）
bash repro/p3_final.sh                # 全部 gate 與真玩家步行（SC＝scratch 路徑需自行改）
bash repro/p3_shots.sh RB p3_at_B.txt p3_free_B.txt   # 正式 TPS 拍攝（A／B／C 各一次）
python repro/compose_ba.py <rawdir> <outdir>          # Before／After 審圖表與相機位置比較
bash repro/p3_shots.sh Cid4on p3_at_cid4.txt - --id                         # cT4 的 ID pass（最終）
bash repro/p3_shots.sh Cid2off p3_at_cid4.txt - --id --disable=EnrichW9P3   # 基準（關掉 EnrichW9P3）
bash repro/p3_shots.sh RB2 p3_at_B2.txt p3_free_B2.txt                      # 柴棚外觀（自由視點 2 個，只有 AFTER）
python repro/ct4_visibility.py <rawdir> <out.json> Cid:R1 Cid2on:R2初版 Cid4on:R2b
```
