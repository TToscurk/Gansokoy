# phase3_r2/evidence の索引

すべて 2026-10-15、最終の build（`build_w9r2_arch.py` の R2b＋`w9p3_lib.gd` の C 較正後）で取った。再現手順は `repro/`。

| ファイル | 内容 |
|---|---|
| `gate_r2_main.log`／`gate_r2_posts.log`／`gate_w9_reach.log` | 主 gate 374／0（反向 36／36）・posts 19／0・到達性 NG 0 |
| `gate_p3_environment.log` | Phase 3 環境 gate 50／0（cT4 の遮蔽・相機の樹冠・cT7 の路肩＋反向 7 を追加） |
| `gate_p3_kura.log` | MXC_005 の蔵の比例 6／0（実測：棟 4.61・店の棟 6.98・壁幅 3.45・奥行 10.49 m） |
| `gate_p3_view.log` | 071 柴棚の近景遮蔽（bT3 20.5 %・bT4 0 %）9／0 |
| `gate_arm_sweep.log`／`arm_sweep_R2.json`／`arm_sweep_R1.json` | 巷全体の SpringArm sweep：R1＝250 件（071 起因 188）→ R2b＝62 件（071 起因 0）。反向で R1 の柱を戻すと 1.21 m |
| `walk_arm_off.*`／`walk_arm_on.*`／`walk_arm_neg.*` | 真玩家の短走で毎フレームの `get_hit_length()` を記録（OFF＝overlay 無し、ON＝R2b、NEG＝R1 の庇柱をメモリ内で戻した反向）。`.json` に全フレームの臂長と位置 |
| `walk_on.log`／`walk_on.json` | 既存の 23 脚の真玩家歩行（庇柱の線・薪の前で止まる、の 2 脚を追加） |
| `ct4_visibility.json`／`idpass_cT4_R1.png`／`idpass_cT4_R2b.png` | cT4 の農舎・運河・護岸の見える割合（ID パス÷EnrichW9P3 を外した基準） |
| `p3_environment_plan.json`／`build_enrich.log` | EnrichW9P3 の最終計画（79 構件）と build ログ |
| `build_arch_chain.log` | Blender→import→prefab→build の鎖（`p3_run.sh`）の標準出力 |
| `../review/full/` | 主要鏡位の 1600×900 画像（BEFORE／R1／AFTER）。`2h`・`2i` は柴棚の外観（R2b のみ） |
| `../review/ba_stats.json` | 相機位置の比較（A：R1↔R2b・B：元の場景↔R2b と R1↔R2b・C：R1↔R2b）と、R1↔R2b の画素差 |

## 注意
- RC（cT4／cT7）の撮影後に `enrich_w9p3.scn` を再 build したが、計画 JSON（構件 79・dropped 7）は撮影前の build と完全に一致した（`.scn` のバイト一致は未検証）。
- 画素差は風（植被の揺れ）で数％動く。意図した変化の判断には使わない。
- ID パスの `idtable.json`（全ノードの対応表、数 MB）はここに入れていない。`repro/p3_idrun.sh` で再生成できる。

## 再現
```
bash repro/p3_run.sh                  # Blender→import→prefab→build（アーチ overlay）
bash repro/p3_final.sh                # 全 gate・真玩家歩行（SC＝scratch のパスを書き換える）
bash repro/p3_shots.sh RB p3_at_B.txt p3_free_B.txt   # 正式 TPS の撮影（A／B／C 各々）
python repro/compose_ba.py <rawdir> <outdir>          # Before／After の審圖シートと相機比較
bash repro/p3_shots.sh Cid4on p3_at_cid4.txt - --id                         # cT4 の ID パス（最終）
bash repro/p3_shots.sh Cid2off p3_at_cid4.txt - --id --disable=EnrichW9P3   # 基準（EnrichW9P3 無し）
bash repro/p3_shots.sh RB2 p3_at_B2.txt p3_free_B2.txt                        # 柴棚の外観（自由視点 2・AFTER のみ）
python repro/ct4_visibility.py <rawdir> <out.json> Cid:R1 Cid2on:R2初版 Cid4on:R2b
```
