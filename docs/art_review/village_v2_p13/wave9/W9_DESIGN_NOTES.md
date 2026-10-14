# P13 W9 — 設計メモ（作業用・compaction 対策）

## 方針（使用者 2026-10-14 授權）
第一輪＝3 区の完成した変化：①住宅側巷（WestBankLane）②主街南段／市の入口（MainStreet z 80..−10）③村外の農家（FarmsteadP13 周辺）。
STOP は第一輪後。全村拡張しない。丘腳社寺は盤点＋方向案＋切替プレビューのみ（灰盒は置換しない）。

## 現況観察（正式 TPS・survey/ の 12 枚、vision）
- 住宅巷：町家が長方体の連続、門前は裸、宅間は裸土の隙間。生活痕跡は主街交点に集中。R4／R4b の生活 props は全部「後院」＝巷から見えない。
- 主街：店の用途が遠距離で読めない（酒の旗以外）。紅提灯・桶・盆の同款繰り返し。招牌弱い。
- 農家：茅葺主屋 A1（318,82）＋納屋 A2（323,71）。屋前に生活過渡なし、草地は均質、田埂は直線。

## 既存の使えるもの（重用）
kr_kago／kr_houki／sk_woodpile／kr_zaimoku／hu_makiwari／hx_hatake／st_shibagaki／gk_yotsume／mk_kame／mk_hoshimono／st_hasa／st_kuwa／sz_hachi／sk_teoke／tk_okeyama；
veg：shrub_a／fern_a／sasa_a／young_broad_a,b／young_sugi（LOD0..3）。ms_kido_*（市集西の木戸）・ms_tsuri_*（吊るし）は店向けで住宅巷には大きい。

## 新規 w9_kit（22 構件、11,030 tri、材質は V2_Wood／V2_Kawara／ST_Street だけ）
板塀 a/b・建仁寺垣・木戸・下屋（薪／農具）・軒下の干し柿／唐辛子・簾・植木棚・朝顔棚・地蔵・祠・杉玉・傘干し台・草鞋掛け・笊吊り棚・案山子・野花 4 種。
Blender：assets/blender/village_v2/build_w9_kit.py → tools/p13/w9/w9_kit_prefab.gd（封存の machiya_kit_prefab.gd は不触、R4／R4b seal に雜湊あり）。
審圖：docs/art_review/village_v2_p13/wave9/kit/（kit_all.png）。要改善：杉玉（球輪郭が崩れる）・草鞋（板に見える）・笊（緑の扇形）・農具小屋（農具が読めない）・唐辛子（淡色が目立つ）。

## 町家 Kit 局部座標（実測）
x＝幅（±w/2）、z＝奥行（前面＝+d/2、外壁面 +0.05）、y 原点＝node、床面（基壇上端）＝ +0.32、軒下端 hiraya 2.73／zushi 3.9、庇 fb_ 2.70–2.90、犬矢来 iy z+0.28 まで。
bay_kind：plain（0.9 m の無地壁）／koshi／koshir／koshib（格子）／door／mado／amado／shop_*。bay_x は境界（n+1 個）。door_w 1.64–1.8。
WestBankLane：道 x≈135–138（R 3 m）、F 1.25 m、町家 2 列 11 m 奥行、宅間 2.3–5.9 m。

## 主街南段の店（P13 W2 data/village_p13_mainstreet.json）
酒屋 MKT_012／017、履物屋 002／026、竹籠工房 006、荒物屋 011／019、薬屋 007／013、茶屋 009／014／022、飯屋 003／027、豆腐屋 020、油屋 016／024、菓子屋 031、住居 010／018／028。
店用途の「遠距離で読める目印」＝杉玉（酒）・草鞋（履物）・笊（竹籠／荒物）・傘（空き「店」）・簾（茶屋／飯屋）。

## 注意（機構）
- HU.top_h は F（店先帯）を含まない → 壁際の物は F を含めて接地。
- HU.why の frontage／building／door 判定は壁付けの物に厳しすぎる → W9 は独自 why（mode 付き）。
- 出力は root 直下 overlay `EnrichW9P13`（HumanUseExpansionP10 の流儀、MultiMesh なし）。FarmsteadP13 等の root overlay を占有に加える。
- staged53 は $TMPDIR/staged53_w9.txt、不 reset／stash／push。
