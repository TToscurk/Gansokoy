# P13 Wave 8 — LOD 材質一致性與可見性修正（ART_REVIEW，未 ART_APPROVED）

2026-10-14。範圍：TASK A 鳥居消失、TASK B 第一批 50 棟 LOD 色、TASK C Pilot 24 檢視、TASK D 剩餘 77 棟名單。
未動 `main.gd`／玩家／相機、水利、神社、農田、道路、Pilot 24 的任何設定；未 reset／stash／push，staged 53 項逐項一致。

---

## A. 鳥居消失：原因與修正

**原因（實測確認，不是推測）**：Kit／Hero／Riverbank 的 LOD 是「首尾相接的 range ＋ margin 4 m ＋ fade DISABLED」。DISABLED 時 margin 變成遲滯（hysteresis），閾值取決於**每個 instance 的「可見」狀態位**：

| 狀態位 | 可見範圍 |
|---|---|
| 1（可見中） | `[begin−margin, end+margin]`（寬） |
| 0（不可見） | `[begin+margin, end−margin]`（窄） |

狀態位初值是 0，且只有通過 layer 與視錐判定的 instance 才會更新。LOD0（end=E）與 LOD1（begin=E）在狀態位 0 時，`[E−4, E+4)` 這 8 m 兩邊都不出現。連續走路時前一級的狀態位仍為 1，所以不空洞（掃描的 mid 情境＝從鄰級走近，OFF 也是 gap 0）；**首次載入、遠距傳送、背向走遠再轉身**時前一級不是鄰級，就整段空洞。南大門 Hero 邊界 60／160 m，W7 消失時相機離門 61.7 m 剛好落在 56–62 m 的洞裡。所以這就是「LOD 遲滯狀態未初始化」。W7 關掉全部 W6／W7 overlay 仍會發生，確認是既有行為，不是 W7 造成。

**修正**：新 overlay `LodGuardP13`（`scripts_p13/lod_guard.gd`，無子節點、不寫資源、不改 Node 屬性、不改 range）。下列情況**只那一幀**把 margin 設為 0 讓 RenderingServer 以嚴格範圍判定，使每個 instance 剛好一級狀態位為 1，描繪後（`frame_post_draw`）還原原 margin：(1) 第一幀 (2) 相機 1 幀移動 ≥ 6 m（傳送）(3) 相機 1 幀轉向 ≥ 35° (4) 距上次累積轉向 ≥ 45° 且間隔 ≥ 1.0 s。之後照原遲滯運作，不會同時出現兩級。

**驗證**

| 項目 | OFF（W7 行為） | ON（W8） |
|---|---|---|
| 正式 main→ReviewStart 真 TPS，同鏡位傳送 5 次（相機離門 61.6 m） | GAP **2／5**（cold 全空） | GAP **0／5** |
| 獨立掃描：南大門 6 情境 × 距離 | 5／6 有洞（56–62 m、156–162 m） | **0** |
| 獨立掃描：MKT_032（Kit 40／110 m 邊界） | near／far／cold／turn 都有洞 | **0** |
| 同一部位兩級同時可見（margin 0 的 47 個距離，4 棟） | — | **0** |

- 對照圖：`compare/A_gate_teleport_before_after.png`（冷啟動／起動直後／通常傳送，左 OFF 右 ON）。OFF 冷啟動時鳥居不見，且近處建築是無細節的白色平牆；ON 都正常（這是看圖觀察，沒有量化）。
- 費用（`w8_lod_sweep` 的 `[W8S]` 行實測，追蹤 18,225 個 instance）：首次掃描 90.2 ms 一次；每次初始化 prime 4.72 ms ＋ restore 7.44 ms。(1)–(3) 很少發生；(4) 已限到 45°／1.0 s。**沒有量過正式遊玩時的長期 frame time**。
- **限制（誠實）**：視錐外的 instance 狀態位任何方法都無法更新（Godot 判定順序）。(4) 只保證「進入視錐的部位在 ≤ 45° 轉向內被修正」；掃描的 turn 情境是用 `--interval0` 診斷選項（間隔 0）跑的，實際遊玩有 1.0 s 間隔。
- 大建築的「部位遷移帶」（掃描記為 double：兩級各 ≥ 50 % 部位同時可見，約 2–6 m 寬）ON／OFF 都有，是各部位 AABB 中心距離不同造成，不是同部位兩級同顯；ON 時固定落在邊界附近。

## B. 第一批 50 棟：LOD0／LOD1／LOD2 色

**方法**：不改幾何、不動封存的 R6a 材質／Pilot runtime。新增 `lod_cal_p13/` 共 21 個 LOD 材質（L1 13、L2 6、屋頂 LR 2）＋ shader `kit_cal_lod.gdshader`（封存 K shader 副本＋牆／屋頂乘數），共用原 Kit atlas，只覆寫 50 棟的 LOD1／LOD2 atlas surface（`LodCalBatch1P13`）。
擬合流程：LOD0 材質解析 albedo（線性、三角面積加權）→ 按部件分群（`w8_lod_fit_build.py`）→ 先少量代表建築（市集／西住宅／丘腳通り 3 鏡位，LOD0／1／2 強制 + ID pass 分群組量）→ 修一次整體 gain → 一次套到 50 棟。屋頂只校亮度不校色相（LOD0 屋頂畫素含暖色木簷，LOD1／2 只有瓦，連色相一起對會染橘）。

**結果（同鏡位強制 LOD，逐棟，各 LOD ≥ 2000 px 才算）**

| | W7 BEFORE L1／L0 | W8 AFTER L1／L0 | W7 L2／L0 | W8 L2／L0 |
|---|---|---|---|---|
| 牆（8 棟） | 中位 1.20（0.95–1.64） | **0.98**（0.92–1.07） | 中位 1.74（1.37–2.42） | **1.15**（0.86–1.33） |
| 屋頂（6 棟） | 中位 1.48（1.28–1.67） | **1.05**（0.86–1.11） | 中位 1.49 | **1.05** |

- 落在 0.80–1.25：牆 0 → **6／8**；屋頂 0 → **6／6**。
- 圖：`compare/B_lod_same_view_{mkt,rsw,mxc}.png`（上 BEFORE、下 AFTER，LOD0／1／2）。看圖：沒有整棟變白、沒有破圖；AFTER 的 LOD2 牆面比 LOD0 更均一、略偏冷灰（細節減少造成）。
- **未達標處**：牆的 L2／L0 仍有 3 棟偏亮（B_P_MXC_014 1.33、MXC_013 1.29、RSW_075 1.21，都是深色牆）；市集 B_P_MKT_035 偏暗（L1 0.92、L2 0.86）。屋頂**亮度**對齊了，但西住宅 LOD1／2 屋頂**偏藍**（warmth L0 +0.001 → −0.098），這是 LOD0 屋頂畫素含暖色木簷的量測副作用，沒有再追。
- **樣本限制**：3 個取景點只有 8 棟牆、6 棟屋頂同時滿足三級 LOD 都 ≥ 2000 px。其他 42 棟套用同一套擬合，但**沒有逐棟實測**。
- 依「不為少量像素差異反覆重拍」，到此停止，沒有再迭代 gain。

## C. Pilot 24（未改動；檢視結果）

用同一套強制 LOD 量測（3 個以 Pilot 為主的取景點，`compare/C_pilot_lod_unchanged.png`）：

| 群 | 牆 L1／L0 | 牆 L2／L0 | 屋頂 L1／L0 |
|---|---|---|---|
| Pilot 24 | 1.18 | 1.41 | 1.52 |
| 主街 39 | 1.22 | 1.34 | 1.51 |

看圖：LOD1／LOD2 牆面明顯變白變亮，木構細節消失，**LOD0→LOD1 的跳變肉眼明顯**；屋頂轉為較均一的深灰。**Pilot 24 與主街 39 的 LOD 跳色是真實存在的**（W8 的 LOD 材質只套到第一批 50 棟）。
這是強制 LOD 取景，不是正常遊玩視角的證據；依你的指示**沒有重設屋頂亮度、沒有重新封存 Pilot**。要不要把同一套 LOD 校色延伸到 Pilot 24＋主街 39，請你裁定（見文末）。

## D. 剩餘 77 棟施工名單（只盤點，未施工）

`evidence/remaining77_worklist.md／.json`：187 − 主街 39 − R6a Pilot 21（與主街重疊 3）− W7 第一批 50 ＝ 77；列出 id、區、用途、道路、型、屋根、可見度、TPS ≥ 3000 px 次數、最大 px、神社可見、批次（W6 優先序 batch2／batch3）、是否在 W7 結構差異化候補。順序＝批次 → TPS 次數 → 最大 px。

## 封存與 gate

- 限定 reseal：`data/village_v2_p10r6a_seal.json` 只更新 2 個 verifier（Kit gate、KITM）並新增 24 個 W8 凍結檔（LOD registry／shader／21 材質／W8 manifest），其餘 31 件雜湊不變（`reseal_limited.py r6a --check`：frozen 55、不一致 0）。Pilot 的 R6a 材質、Pilot runtime 未動。
- Kit gate／KITM 改成「封存的 W8 registry sha 吻合才合法」的 scope-aware 例外，新增永久反向：KIT `material_w8_badsha`、`material_w8_unfrozen`，KITM N7（共 7／7）。

| Gate | 結果 |
|---|---|
| ALB plan／--scene／--seal | PASS ×3 |
| KITM（反向 7／7） | PASS |
| KIT --regress（187）＋反向 6 案（含 W8 2 案） | PASS ＋ 6／6 |
| W8 gate（40 項 ＋ 反向 9／9） | PASS |
| W7 gate ＋ 反向（W8 overlay 停用後驗 W7 責任區） | PASS |
| W6 gate ＋ 反向 | PASS |
| LOD 掃描 OFF／ON ＋ 判定（ON gap 0、OFF 能偵測）＋ 同部位雙顯 0 | PASS ×4 |
| R5a RDB plan／--scene／--seal、GRD --seal | PASS ×4 |
| P8 地形保護／local／--seal／--negative／田埂稽核／GRD plan／GRD --scene | PASS ×7 |

log 在 `evidence/gates/`。**沒有跑**：全回歸、全村實走、P12 TERRAIN（>3000 ms 既有技術債）。

## 需要你裁定

1. **Pilot 24＋主街 39 的 LOD 色**：實測牆 1.18–1.41×、屋頂 1.5×。是否延伸 W8 的 LOD 校色（純 LOD1／2 overlay，不碰 LOD0 與已封存的 Pilot 材質；Pilot 的 reseal 只會是 registry 新增）？
2. W8 B 的殘餘（3 棟深色牆 L2 偏亮、1 棟市集偏暗、西住宅屋頂偏藍）是否可接受，或再做一輪針對性 gain。
3. 剩餘 77 棟是否在 LOD 流程穩定後開工（本輪未動）。

STOP，等待 ART APPROVAL。
