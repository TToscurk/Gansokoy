# Godot 遷移書 —— 混合路線：佈局搬過去、視覺重做

## 為什麼是這條路

網頁版（three.js 全程式生成）的三個痛點：角色的設計感、地圖的排面感、
以及「物件位置不對只能下指令調」的迭代方式。結論是搬到 Godot——但**不是**
把現在的樣子原封不動搬過去（那樣不滿意的東西會原樣跟過去），而是：

- **佈局是資產**：8 張圖的路網、建築配置、傳送點、碰撞手感是長期調出來的，
  這些烤成 `.glb` 底稿（blockout）帶走。
- **視覺重做**：材質、光照、角色、UI 在 Godot 用編輯器與正式資產逐步重做，
  底稿只當比例尺與擺位參考，做一塊換一塊。
- **以後擺東西用編輯器**：物件位置直接在 Godot 編輯器裡拖，不再下指令調。

## 烘焙管線（web → Godot）

```
node tools/export-godot.mjs            # 全部已建成的圖
node tools/export-godot.mjs bamboo     # 只烤指定圖
```

工具做的事：起 `dev-server.mjs` → 無頭 Chromium 逐張開圖 → 從
`window.__godotExport`（GameCore 掛的唯讀口）抓 `world` 群組 →
GLTFExporter 烤成 `.glb`。產物：

| 檔案 | 內容 | 進版控？ |
|---|---|---|
| `godot/blockout/<id>.glb` | 場景幾何 + 烤好的貼圖 | ❌（產物，可重烤；共 300+MB） |
| `godot/data/<id>.meta.json` | 傳送點（含目的地）、遊戲碰撞箱、playSize | ✅ |
| `godot/data/mapRegistry.json` | 全 19 張圖的連通圖（與 web 版同源） | ✅ |

技術細節（改烘焙工具前先讀）：

- **InstancedMesh 會展開合併**：Godot 4.4 不支援 `EXT_mesh_gpu_instancing`，
  會整檔拒收。展開後超過頂點預算（預設 200 萬，`EXPORT_VERT_CAP` 可覆寫）
  就均勻抽稀 —— 花海類的圖密度會打折，反正底稿會被正式植被系統取代。
- **傳送點目的地**寫在工具裡的 `PORTAL_TARGETS` 表（光點建立順序 ↔ 目的地）。
  改地圖傳送點時要同步這張表，數量對不上工具會吵。
- **座標系不用轉**：three / glTF / Godot 都是右手系 y-up，座標原樣通用。
- 烘焙是決定性的：地圖用固定種子的 LCG，重烤結果一致。

## Godot 專案（godot/）

Godot 4.4。第一次打開：用編輯器開 `godot/project.godot`（或
`godot --headless --path godot --import`）讓 `.glb` 匯入，然後直接 F5。

```
godot/
├── project.godot          # 輸入映射（WASD/Shift/Space/F/Ctrl 對齊 web 版）
├── scenes/main.tscn       # 世界根：天空、太陽、玩家、地圖名 UI
├── scenes/player.tscn     # 第三人稱控制器（滑鼠視角、衝刺、跳、飛行）
├── scripts/main.gd        # 世界載入器：載圖、碰撞、傳送點（GameCore 雛形）
├── scripts/player.gd
├── blockout/              # 烤出來的 .glb（gitignore，要自己烤）
└── data/                  # meta json + mapRegistry.json
```

現在就能做的事：從神社出發，走到傳送光柱就會切圖，整個幻想鄉 8 張圖
是通的（連通關係讀 `mapRegistry.json`，跟 web 版同一份資料）。
`godot --path godot -- --map=bamboo` 可直接跳指定圖。

碰撞的雙層設計（`main.gd`）：

1. **大 mesh（XZ 跨度 ≥ 15m）做 trimesh** —— 地形起伏、坡道靠這個。
2. **web 版的遊戲碰撞箱**（`meta.json` 的 box/cylinder）—— 建築、樹、
   竹子的「手感」是 web 版調過的，直接沿用。

## 已知限制（= 視覺重做的起點）

- 貼圖是烤死的 canvas 貼圖，shader（triplanar、LUT 調色、後製鏈）沒跟過來
  —— 本來就打算在 Godot 重做光照與材質。
- NPC、怪、戰鬥、任務、對話、HUD 全部還在 web 版 —— 之後在 Godot 原生重寫，
  不搬程式碼，搬設計。
- 花海圖（sunflower / namelessHill）底稿密度有抽稀。
- 傳送光柱是 `main.gd` 生成的臨時示意（青色圓柱），不是 web 版那顆光球。

## 建議的重做順序

1. **一張圖打樣**（建議香霖堂：最小、有室內外）：在編輯器裡以底稿為比例尺，
   換地形材質、換建築模型、打光 —— 定出「Godot 版的美術基準」。
2. 角色：換掉膠囊，決定角色管線（自製 low-poly / 現成素材 / 委託）。
3. 其餘 7 張圖照基準逐張重做；每張做完就把該圖的 blockout 隱藏或刪掉。
4. 系統重寫：對話 → NPC → 戰鬥 → 任務（順序照依賴關係）。
5. web 版凍結為參考實作，不再加新圖。
