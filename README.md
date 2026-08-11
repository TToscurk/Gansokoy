# 幻想鄉緣一計畫

目前正式版本是 **Godot 4.4** 專案，入口位於 `godot/project.godot`。

## 開啟專案

1. 使用 Godot 4.4 開啟 `godot/project.godot`。
2. 從主場景啟動遊戲。

人間之里是原生 Godot 場景：

- 場景：`godot/maps/village/village.tscn`
- 生成入口：`godot/tools/gen_town.gd`
- 責任模組：`godot/tools/town/`

## 專案目錄

| 路徑 | 用途 |
|---|---|
| `godot/` | 現行遊戲、場景、資產及生成工具 |
| `docs/PROJECT_STATE.md` | 每次工作必讀的目前狀態 |
| `docs/ROADMAP.md` | DONE / CURRENT / NEXT / LATER |
| `docs/` | 各子系統正式規格 |
| `docs/archive/` | 歷史文件；只有爭議或考古時才讀 |
| `src/`, `maps/`, `vendor/` | 凍結的 three.js 舊線；目前仍供未原生化地圖匯出 blockout，不能整批刪除 |

## 文件讀取規則

代理應依 `CLAUDE.md`：先讀 `docs/PROJECT_STATE.md`，再只讀本次工作直接相關的
一份正式規格。不要為了「理解專案」掃描整個 `docs/` 或 `docs/archive/`。

舊 three.js 啟動、操作及開發說明已封存於
`docs/archive/web-threejs-readme.md`，不代表現行遊戲入口。
