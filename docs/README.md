# docs —— 哪份文件管什麼

**先讀這兩份**（專案記憶的入口，2026-08-08 建立）：

| 文件 | 管什麼 | 什麼時候更新 |
|---|---|---|
| **PROJECT_STATE.md** | 「現在做到哪裡」—— 目前 Phase／已核准基線／建築 kit 現況／村圖現況／已知風險／不可重開的決定。新任務的第一入口 | 專案狀態實質變動時 |
| **ROADMAP.md** | DONE / CURRENT / NEXT / LATER，只有狀態不放細節 | 排程狀態變動時 |

永久工作規則在 repo root 的 `CLAUDE.md` 與 `.claude/rules/`，不在 docs/。

**主題文件**（subsystem source of truth）—— 一個主題一份，動工前只查跟任務相關的那一份，不要翻 archive。

| 文件 | 管什麼 | 什麼時候更新 |
|---|---|---|
| **machiya-production-kit.md** | 町家 Architecture Kit 現行規格（Blender→GLB→Godot、模組、材質與驗證契約） | kit 的規格或模組變動時 |
| **ningen-no-sato.md** | 人間之里的**現況與規則總結**（管線／座標約定／不可違反的規則／復發性病症目錄／檢查工具能力邊界／未結項目）—— 要動村圖之前先讀這份 | 村圖的事實或規則變動時 |
| **village-art-direction.md** | 人間之里的美術規格（風格／尺度／色彩／工序）——「這樣好不好看」的唯一依據 | 使用者定案新方向時 |
| **domain-model.md** | 產生器的現行領域詞彙、模組邊界與 ADR 摘要 | 加新概念、跨模組不變量或新 ADR 時 |
| **godot-migration.md** | Godot 環境的事實（烘焙管線、project.godot 規則、指令） | 踩到新的環境坑時 |
| **border-vistas.md** | 每張圖的地平線該看到什麼（幻想鄉方位考據） | 開新地圖時 |
| **hieda-estate-features.md** | 稗田邸現行規格（完整院落、庭園、三層內裝、portal 與驗證） | 稗田邸相關變動時 |

人間之里的逐輪工作紀錄已移至 `archive/ningen-no-sato-redesign.md` 與
`archive/ningen-no-sato-production-history-2026-08-10.md`。日常工作只讀
`ningen-no-sato.md`。

## 歸檔規則

設計書「做完」就搬進 `archive/`（用 `git mv`，歷史還在）。
判斷標準：**內容已經活在程式碼或別的活文件裡，再讀一次不會改變任何決定。**

three.js 時代（`src/`）的計畫書全部在 archive —— 那條線已凍結，
Godot 版不吃那些檔案。
