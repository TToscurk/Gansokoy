# 剩餘 77 棟町家 — 下一批施工名單（盤点のみ・W8 では施工しない）

出所：W7 の未校正 77 棟（187 − 主街 39 − R6a Pilot 21 − W7 第一批 50）。順序＝W6 の優先度（batch2＝TPS で顕著・神社から見える／batch3＝顕著でない）の中で、TPS 3000 px 以上の鏡位数 → 最大画素数。

- 批次：{'batch2': 61, 'batch3': 16}
- 区：{'ResidentialWest': 48, 'ResidentialNE': 14, 'Market': 7, 'MixedCommercial': 8}
- 可見度ティア：{'A': 61, 'B': 12, 'C': 4}
- 道路：{'NWBranch': 5, 'NELane': 6, 'CrossStreetMid': 3, 'CrossStreetSouth': 7, 'HillFootStreet': 8, 'NWLane': 8, 'NESouth': 8, 'WestBankLane': 22, 'WestAlley': 5, 'SWLane': 4, 'RiverNorthPath': 1}

## 前提（W8 で整ったもの）

1. LOD1／LOD2 の色は『LOD0 の材質を決めた後に』擬合する（`w8_albedo_probe.gd` → `w8_lod_fit_build.py`）。順序＝先に W7 方式で LOD0 の 18 変体を割り当て → その LOD0 を基準に LOD1／2 の調色盤を擬合。
2. 屋根 l_rh_* は LOD 材質の roof 種別（LOD0 の瓦に合わせた乗数）。W7 の『不覆寫』は W8 で置き換わった。
3. 新しい材質ファイルは `maps/village_v2/lod_cal_p13/` に追加（既存の登記表は封存のまま）。W9 で LOD 材質を増やすときは W8 と同じ限定 reseal（`tools/p13/w8/reseal_limited.py`）を 1 回。
4. 本表の `structure_backlog=true` は W7 の『同じ外形枠で細部だけ違う近隣』候補。材質だけの施工では直らない（構造差異化は別工程）。

## 一覧（施工順）

| # | id | 区 | 用途 | 道路 | 型 | 屋根 | 可見 | n≥3000px | 最大px | 神社から | 批次 | 構造候補 |
|---|----|----|------|------|----|------|------|----------|--------|----------|------|----------|
| 1 | B_P_RSW_041 | ResidentialWest | 住宅（西区） | NWBranch | 厨子二階 | tsuma | A | 2 | 508370 |  | batch2 |  |
| 2 | B_P_RNE_009 | ResidentialNE | 住宅（北東区） | NELane | 平屋 | tsuma | A | 2 | 453024 |  | batch2 |  |
| 3 | B_P_MKT_036 | Market | 商業（市集區の町家列） | CrossStreetMid | 平屋 | hira | A | 2 | 346159 |  | batch2 |  |
| 4 | B_P_MKT_052 | Market | 商業（市集區の町家列） | CrossStreetSouth | 厨子二階 | tsuma | A | 2 | 294762 |  | batch2 |  |
| 5 | B_P_MXC_011 | MixedCommercial | 商業・混在（丘脚通り） | HillFootStreet | 平屋 | hira | A | 2 | 265210 |  | batch2 |  |
| 6 | B_P_MXC_012 | MixedCommercial | 商業・混在（丘脚通り） | HillFootStreet | 厨子二階 | hira | A | 2 | 248379 |  | batch2 |  |
| 7 | B_P_RSW_008 | ResidentialWest | 住宅（西区） | HillFootStreet | 平屋 | hira | A | 2 | 212182 |  | batch2 |  |
| 8 | B_P_RSW_006 | ResidentialWest | 住宅（西区） | CrossStreetSouth | 厨子二階 | hira | A | 2 | 176158 |  | batch2 |  |
| 9 | B_P_RSW_028 | ResidentialWest | 住宅（西区） | NWLane | 平屋 | hira | A | 2 | 156832 |  | batch2 |  |
| 10 | B_P_RNE_016 | ResidentialNE | 住宅（北東区） | NESouth | 平屋 | hira | A | 2 | 150782 |  | batch2 |  |
| 11 | B_P_RSW_001 | ResidentialWest | 住宅（西区） | CrossStreetMid | 平屋 | hira | A | 2 | 88165 |  | batch2 |  |
| 12 | B_P_RSW_037 | ResidentialWest | 住宅（西区） | NWLane | 平屋 | hira | A | 2 | 61290 |  | batch2 |  |
| 13 | B_P_RSW_040 | ResidentialWest | 住宅（西区） | NWBranch | 平屋 | hira | A | 2 | 48653 |  | batch2 |  |
| 14 | B_P_RSW_032 | ResidentialWest | 住宅（西区） | NWLane | 平屋 | tsuma | A | 2 | 28432 |  | batch2 |  |
| 15 | B_P_MKT_051 | Market | 商業（市集區の町家列） | CrossStreetSouth | 平屋 | hira | A | 2 | 21274 |  | batch2 |  |
| 16 | B_P_MXC_020 | MixedCommercial | 商業・混在（丘脚通り） | HillFootStreet | 厨子二階 | tsuma | A | 2 | 17131 |  | batch2 | ● |
| 17 | B_P_RSW_047 | ResidentialWest | 住宅（西区） | WestBankLane | 平屋 | tsuma | A | 2 | 13735 |  | batch2 |  |
| 18 | B_P_RNE_013 | ResidentialNE | 住宅（北東区） | NESouth | 厨子二階 | hira | A | 2 | 9990 |  | batch2 |  |
| 19 | B_P_MXC_022 | MixedCommercial | 商業・混在（丘脚通り） | HillFootStreet | 厨子二階 | hira | A | 2 | 7379 |  | batch2 |  |
| 20 | B_P_RNE_003 | ResidentialNE | 住宅（北東区） | NELane | 厨子二階 | hira | A | 2 | 7104 |  | batch2 |  |
| 21 | B_P_RSW_062 | ResidentialWest | 住宅（西区） | WestBankLane | 厨子二階 | hira | A | 2 | 7033 |  | batch2 |  |
| 22 | B_P_MKT_047 | Market | 商業（市集區の町家列） | CrossStreetSouth | 總二階 | hira | A | 2 | 6913 |  | batch2 |  |
| 23 | B_P_RSW_030 | ResidentialWest | 住宅（西区） | NWLane | 平屋 | hira | A | 2 | 5732 |  | batch2 |  |
| 24 | B_P_RSW_018 | ResidentialWest | 住宅（西区） | WestAlley | 平屋 | tsuma | A | 2 | 4706 |  | batch2 |  |
| 25 | B_P_RSW_031 | ResidentialWest | 住宅（西区） | NWLane | 厨子二階 | hira | A | 2 | 3893 |  | batch2 |  |
| 26 | B_P_RSW_055 | ResidentialWest | 住宅（西区） | WestBankLane | 厨子二階 | hira | A | 1 | 473637 |  | batch2 |  |
| 27 | B_P_RSW_069 | ResidentialWest | 住宅（西区） | WestBankLane | 厨子二階 | hira | A | 1 | 454265 |  | batch2 |  |
| 28 | B_P_RNE_005 | ResidentialNE | 住宅（北東区） | NELane | 平屋 | tsuma | A | 1 | 453628 |  | batch2 |  |
| 29 | B_P_RSW_078 | ResidentialWest | 住宅（西区） | SWLane | 平屋 | hira | A | 1 | 369047 |  | batch2 |  |
| 30 | B_P_RSW_064 | ResidentialWest | 住宅（西区） | WestBankLane | 平屋 | hira | A | 1 | 340952 |  | batch2 |  |
| 31 | B_P_RSW_050 | ResidentialWest | 住宅（西区） | WestBankLane | 平屋 | tsuma | A | 1 | 317579 |  | batch2 |  |
| 32 | B_P_RNE_011 | ResidentialNE | 住宅（北東区） | NESouth | 平屋 | tsuma | A | 1 | 298867 |  | batch2 |  |
| 33 | B_P_RSW_020 | ResidentialWest | 住宅（西区） | WestAlley | 厨子二階 | tsuma | A | 1 | 280017 |  | batch2 |  |
| 34 | B_P_RSW_060 | ResidentialWest | 住宅（西区） | WestBankLane | 平屋 | hira | A | 1 | 142732 |  | batch2 |  |
| 35 | B_P_RSW_021 | ResidentialWest | 住宅（西区） | WestAlley | 平屋 | hira | A | 1 | 139627 |  | batch2 |  |
| 36 | B_P_RSW_009 | ResidentialWest | 住宅（西区） | WestAlley | 平屋 | tsuma | A | 1 | 106821 |  | batch2 |  |
| 37 | B_P_RSW_081 | ResidentialWest | 住宅（西区） | SWLane | 平屋 | tsuma | A | 1 | 86362 |  | batch2 |  |
| 38 | B_P_RSW_079 | ResidentialWest | 住宅（西区） | SWLane | 平屋 | hira | A | 1 | 85621 |  | batch2 |  |
| 39 | B_P_RSW_051 | ResidentialWest | 住宅（西区） | WestBankLane | 平屋 | hira | A | 1 | 80449 |  | batch2 |  |
| 40 | B_P_RSW_065 | ResidentialWest | 住宅（西区） | WestBankLane | 平屋 | tsuma | A | 1 | 69549 |  | batch2 |  |
| 41 | B_P_MXC_024 | MixedCommercial | 商業・混在（丘脚通り） | RiverNorthPath | 平屋 | hira | A | 1 | 56121 |  | batch2 |  |
| 42 | B_P_RSW_042 | ResidentialWest | 住宅（西区） | NWBranch | 平屋 | hira | A | 1 | 52717 |  | batch2 |  |
| 43 | B_P_RSW_066 | ResidentialWest | 住宅（西区） | WestBankLane | 厨子二階 | hira | A | 1 | 29588 |  | batch2 |  |
| 44 | B_P_MKT_048 | Market | 商業（市集區の町家列） | CrossStreetSouth | 平屋 | tsuma | A | 1 | 27071 |  | batch2 |  |
| 45 | B_P_RSW_070 | ResidentialWest | 住宅（西区） | WestBankLane | 平屋 | hira | A | 1 | 25715 |  | batch2 |  |
| 46 | B_P_RSW_061 | ResidentialWest | 住宅（西区） | WestBankLane | 平屋 | hira | A | 1 | 23647 |  | batch2 |  |
| 47 | B_P_RSW_056 | ResidentialWest | 住宅（西区） | WestBankLane | 平屋 | tsuma | A | 1 | 23010 |  | batch2 |  |
| 48 | B_P_RSW_080 | ResidentialWest | 住宅（西区） | SWLane | 厨子二階 | hira | A | 1 | 22571 |  | batch2 |  |
| 49 | B_P_RNE_006 | ResidentialNE | 住宅（北東区） | NELane | 厨子二階 | hira | A | 1 | 19411 |  | batch2 |  |
| 50 | B_P_RSW_052 | ResidentialWest | 住宅（西区） | WestBankLane | 厨子二階 | hira | A | 1 | 13277 |  | batch2 |  |
| 51 | B_P_RNE_017 | ResidentialNE | 住宅（北東区） | NESouth | 厨子二階 | hira | A | 1 | 13184 |  | batch2 |  |
| 52 | B_P_RSW_043 | ResidentialWest | 住宅（西区） | NWBranch | 平屋 | hira | A | 1 | 11370 |  | batch2 |  |
| 53 | B_P_RSW_035 | ResidentialWest | 住宅（西区） | NWLane | 平屋 | hira | A | 1 | 10078 |  | batch2 |  |
| 54 | B_P_MXC_017 | MixedCommercial | 商業・混在（丘脚通り） | HillFootStreet | 厨子二階 | hira | A | 1 | 9137 |  | batch2 |  |
| 55 | B_P_MKT_054 | Market | 商業（市集區の町家列） | CrossStreetSouth | 平屋 | hira | A | 1 | 8585 |  | batch2 |  |
| 56 | B_P_MXC_021 | MixedCommercial | 商業・混在（丘脚通り） | HillFootStreet | 平屋 | hira | A | 1 | 7031 |  | batch2 |  |
| 57 | B_P_RSW_005 | ResidentialWest | 住宅（西区） | CrossStreetSouth | 平屋 | tsuma | A | 1 | 6598 |  | batch2 | ● |
| 58 | B_P_RNE_014 | ResidentialNE | 住宅（北東区） | NESouth | 平屋 | tsuma | A | 1 | 6487 |  | batch2 |  |
| 59 | B_P_MKT_033 | Market | 商業（市集區の町家列） | CrossStreetMid | 平屋 | hira | A | 1 | 5862 |  | batch2 |  |
| 60 | B_P_RSW_058 | ResidentialWest | 住宅（西区） | WestBankLane | 平屋 | hira | A | 1 | 5280 |  | batch2 |  |
| 61 | B_P_RSW_044 | ResidentialWest | 住宅（西区） | NWBranch | 平屋 | hira | A | 1 | 3718 |  | batch2 |  |
| 62 | B_P_RNE_008 | ResidentialNE | 住宅（北東区） | NELane | 平屋 | hira | B | 0 | 2954 |  | batch3 |  |
| 63 | B_P_RSW_019 | ResidentialWest | 住宅（西区） | WestAlley | 平屋 | hira | B | 0 | 2672 |  | batch3 |  |
| 64 | B_P_RSW_057 | ResidentialWest | 住宅（西区） | WestBankLane | 平屋 | hira | B | 0 | 1958 |  | batch3 |  |
| 65 | B_P_RSW_067 | ResidentialWest | 住宅（西区） | WestBankLane | 平屋 | hira | B | 0 | 1864 |  | batch3 |  |
| 66 | B_P_RNE_015 | ResidentialNE | 住宅（北東区） | NESouth | 平屋 | hira | B | 0 | 1840 |  | batch3 |  |
| 67 | B_P_RSW_053 | ResidentialWest | 住宅（西区） | WestBankLane | 平屋 | hira | B | 0 | 1825 |  | batch3 |  |
| 68 | B_P_RSW_054 | ResidentialWest | 住宅（西区） | WestBankLane | 平屋 | tsuma | B | 0 | 1681 |  | batch3 |  |
| 69 | B_P_MXC_016 | MixedCommercial | 商業・混在（丘脚通り） | HillFootStreet | 平屋 | hira | B | 0 | 1494 |  | batch3 |  |
| 70 | B_P_RSW_063 | ResidentialWest | 住宅（西区） | WestBankLane | 平屋 | tsuma | B | 0 | 1450 |  | batch3 |  |
| 71 | B_P_RSW_038 | ResidentialWest | 住宅（西区） | NWLane | 厨子二階 | tsuma | B | 0 | 1183 |  | batch3 |  |
| 72 | B_P_RSW_068 | ResidentialWest | 住宅（西区） | WestBankLane | 平屋 | tsuma | B | 0 | 946 |  | batch3 |  |
| 73 | B_P_RNE_004 | ResidentialNE | 住宅（北東区） | NELane | 平屋 | hira | B | 0 | 519 |  | batch3 |  |
| 74 | B_P_RNE_018 | ResidentialNE | 住宅（北東区） | NESouth | 平屋 | tsuma | C | 0 | 103 |  | batch3 |  |
| 75 | B_P_RNE_019 | ResidentialNE | 住宅（北東区） | NESouth | 平屋 | hira | C | 0 | 94 |  | batch3 |  |
| 76 | B_P_RSW_049 | ResidentialWest | 住宅（西区） | WestBankLane | 平屋 | hira | C | 0 | 38 |  | batch3 |  |
| 77 | B_P_RSW_039 | ResidentialWest | 住宅（西区） | NWLane | 平屋 | hira | C | 0 | 0 |  | batch3 |  |

## 区別の小計

- **ResidentialWest**（48）：RSW_041, RSW_008, RSW_006, RSW_028, RSW_001, RSW_037, RSW_040, RSW_032, RSW_047, RSW_062, RSW_030, RSW_018, RSW_031, RSW_055, RSW_069, RSW_078, RSW_064, RSW_050, RSW_020, RSW_060, RSW_021, RSW_009, RSW_081, RSW_079, RSW_051, RSW_065, RSW_042, RSW_066, RSW_070, RSW_061, RSW_056, RSW_080, RSW_052, RSW_043, RSW_035, RSW_005, RSW_058, RSW_044, RSW_019, RSW_057, RSW_067, RSW_053, RSW_054, RSW_063, RSW_038, RSW_068, RSW_049, RSW_039
- **ResidentialNE**（14）：RNE_009, RNE_016, RNE_013, RNE_003, RNE_005, RNE_011, RNE_006, RNE_017, RNE_014, RNE_008, RNE_015, RNE_004, RNE_018, RNE_019
- **Market**（7）：MKT_036, MKT_052, MKT_051, MKT_047, MKT_048, MKT_054, MKT_033
- **MixedCommercial**（8）：MXC_011, MXC_012, MXC_020, MXC_022, MXC_024, MXC_017, MXC_021, MXC_016
