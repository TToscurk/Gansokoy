# 幻想鄉緣一計畫

目前正式版本是 **Godot 4.7** 專案，入口位於 `godot/project.godot`。

## 開啟專案

1. 使用 Godot 4.7 開啟 `godot/project.godot`。
2. 從主場景啟動遊戲。

人間之里是原生 Godot 場景：

- 場景：`godot/maps/village/village.tscn`（凍結場景，含 `gen/` 已提交產物）
- 舊 170 戶程序生成管線已於 2026-08-25 退役刪除，不再是入口

## 專案目錄

| 路徑 | 用途 |
|---|---|
| `godot/` | 現行遊戲、場景、資產及生成工具 |
| `docs/PROJECT_STATE.md` | 每次工作必讀的目前狀態 |
| `docs/ROADMAP.md` | DONE / CURRENT / NEXT / LATER |
| `docs/` | 各子系統正式規格 |
| `docs/archive/` | 歷史文件；只有爭議或考古時才讀 |
| `src/`, `vendor/`, `tools/*.mjs` | 凍結的 three.js 舊線殘餘（`maps/` 已不存在，此線可能已無法運行）；是否整批移除待使用者裁決 |

## 文件讀取規則

代理應依 `CLAUDE.md`：先讀 `docs/PROJECT_STATE.md`，再只讀本次工作直接相關的
一份正式規格。不要為了「理解專案」掃描整個 `docs/` 或 `docs/archive/`。

舊 three.js 啟動、操作及開發說明已封存於
`docs/archive/web-threejs-readme.md`，不代表現行遊戲入口。
