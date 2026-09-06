# CLAUDE.md — Repository Entry Rules

## 核心紅線

核心紅線只有一份權威：repo 根目錄的 `AGENT_CONSTITUTION.md`。

**開工前必讀該檔並遵守**，除非使用者當下的指令明確凌駕某條。
本檔（以及 `.hermes.md`、`AGENTS.md`）一律不得複製紅線條文，
避免副本漏改造成「照哪份走」的歧義。

---

Project: 幻想鄉 / 博麗神社 (Godot 4.7 3D)。主要遊戲專案位於 `godot/`。

## 核心防護 (避免損壞專案)
- **Git LFS 保護**：本專案大量使用 Git LFS。在 Godot 載入前必須確保二進位資產已 pull/checkout 完畢，避免因未解開的 LFS pointer 導致紋理/GLB 損壞並烙印 `valid=false`。
- **編輯器控制**：涉及場景/節點狀態時，以 godot-ai MCP 實況為準，同時僅允許單一實體控制編輯器。
