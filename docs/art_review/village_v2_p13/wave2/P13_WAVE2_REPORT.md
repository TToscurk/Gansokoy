# P13 WAVE 2 — Main Street & Farmstead Art Integration（ART_REVIEW）

狀態：**ART_REVIEW，等待使用者 ART_APPROVAL**。主街 39 棟與農家 A1／A2 已正式整合；其餘 148 棟、土渠、神社、道路未動。

## 1. 主街 39 棟（正式整合，非 overlay）
- 來源：`data/village_v2_p13_mainstreet.json`（`tools/p13/design_mainstreet.py` 生成）＋ `tools/village_v2_p13_mainstreet_lib.gd`。P4 `greybox.json` 不改；全域 `_build_plan()` 權重／seed 不改，計畫 dict 只在 build 期間覆寫、完成後還原。
- 正式生成器 `gen_village_v2.gd` 與 Kit gate 都改用同一個實效紀錄，所以可重現。
- `village_v2.tscn` 是**原位替換** 39 棟的 `Kit`（＋MKT_010 的 Frontage），其他 148 棟節點文字逐行比對 0 差異。W1B 預覽 overlay（ArchPilotP13，793 MeshInstance 的雙份結構）已刪除。
- 39 棟 Kit MeshInstance 3282 → 3392（+110，+3.4 %），LOD0 合計 551,466 三角面；最大單棟 20,212（§14.8 上限 25,000）。
- 用途（以封存 StreetP10 實際店前物件為準）：店 26、大店 6、住居 4、工坊 2、職人家 1；妻入 7 棟（003、010、016、020、030、MXC_004、MXC_006），不機械交錯。
- 空白牆對策（39 棟共通）：上層全開間開窗（取消白壁週期）；20 棟有外露側壁 → 開口型側壁＋懸魚；妻入街側妻面加懸魚。
- 只有 MKT_010 由店改為住居（第一次把 MKT_029／MXC_001 也住居化，P10 R2 構圖 gate 因陳列比例 88 % FAIL，撤回；不放寬 gate）。

## 2. MKT_006 竹籠製作兼販售工坊
- Kit：煙出し、板庇、棟偏後、拿掉暖簾。
- StreetP10 limited correction：`055_sk_teoke`（手桶）→ `055_st_wara`（筵・材料束・編みかけ・腰掛け，碰撞 1.4×1.4×0.9），放在入口左前；`054_st_hiradai_zakka`（笊・籠販售）保留。自檢：MKT_006 以外的節點變化 0。
- vision 判讀：工作區與販售都看得到；「販售」仍比「正在編」強，暗部細節難辨。

## 3. MKT_018 碰撞
- 外觀厨子二階（簷 3.9），碰撞箱高 3.26 → 4.26 m（底不變，頂＝簷 3.9），只改這一棟、共享 shape 先確認唯一引用。
- 相機實測：棟周 8 點 × 12 方向 = 96 次，相機進入建物外殼 0 次。
- 注意：TPS 正面截圖 `06_tps_MKT_018_zushi` 被對街招牌／屋簷擋住（鏡位問題，不是穿入 MKT_018）；實走「足元−地面 最大 1.04 m」是向下射線打到屋簷的量測偏差，未另行驗證。

## 4. 農家 A1／A2（正式，`FarmsteadP13` overlay，root 末尾 1 個）
- A1 (318, 82) 主屋 6.4×9.1 m：茅葺 45°、屋根厚 0.55、軒先小口帶、棟押さえ＋烏おどし；茅葺貼圖＝程序生成 512² 纖維方向 albedo＋normal（`maps/village_v2/farmstead_p13/`）。
- A2 (323, 71) 農具納屋 3.6×5.5 m：板葺＋押縁、開口。
- 碰撞 6：A1 壁、A1 縁、A2 壁、渡し板、農具掛け、薪棚。
- 動線：FarmPath_5 → 渡し板（跨 T0 支線，上面 0.54 m＝水面 0.39＋0.15；水渠與堤不改）→ 踏石 10 → A2 前 → A1 戸口。實走 5/5 段抵達。
- 道具：農具掛け、薪棚、背負い籠。
- vision：茅葺「大致可信」，但葺き段過於整齊、邊角太直，像製品板。

## 5. 驗證
- 實走：主街南→北 7/7、MKT_018 前 2/2、農家 5/5，卡住 0。
- **市集西 (255.9, 7.0) 既有卡滯點**：這次主街實走未卡住，但前一輪探測確認是 StreetP10 既有碰撞，問題仍存在，保留為後續局部通行修正。
- 檢查（皆 0 失敗）：Kit gate `--regress`（187 棟）、GB、STR plan／`--scene`／`--seal`、ENV、MDW、WATER（P12 差異登記仍適用）、HUX／HUSE／ALB `--seal`、ASSET。
- 未跑全量回歸、全村實走、效能量測。

## 6. 封存
- `reseal_w2.py`：只接受本輪兩個檔案的變更（`street_p10.scn`、Kit gate），其他 frozen 不一致即中止。
- frozen 更新：P10 R2、P10 R6a；子封存追從：P10 R4、P10 R4b。全部封存雜湊不一致 0。

## 7. 已知問題（未處理）
- 大型妻壁仍偏空（vision 指出左前景倉庫型山牆）；中遠景主街仍偏平。
- MKT_010 正面仍有店面感（開口多、無庇）。
- 茅葺葺き段過於規則。
- 地面橘色地塊線、遠處灰色無貼圖屋頂（既有，非本輪）。
- F6 預覽場景仍保留為站位跳轉工具（F7），不再掛任何 overlay。

## 8. Git
- 原本 staged 53 項未變；`main.gd`、`yoriichi_character.gd` 未動；不 push。
- 獨立 GPT 代理無法啟動；只參考了 GPT 的事前意見（不用全域 reseal、原位替換、MKT_018 用實測），沒有獨立 ACCEPT。
