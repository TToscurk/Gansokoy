# CLAUDE.md — Repository Entry Rules

## 核心紅線

## 1. 重用優先
先重用，後新增。
不得建立平行 pipeline，不得擴張無關範圍。

## 2. 視覺專權
只有使用者能給予 `ART_APPROVED`。
Agent 最多只能給予 `ART_REVIEW`，不得自行宣告視覺完成。

## 3. 唯讀保護
`godot/assets/blender/sources/` 全程唯讀。
不得修改、覆寫或重新生成其中內容。

## 4. 禁止空想
不得憑記憶編寫 API、推測場景狀態或虛構驗證結果。

Godot API / engine behavior → 查 `godot-master`。
Project scene / node / transform / resource state → 查 MCP。

## 5. Godot Visual Workflow
- MCP = inspect, measure, debug, verify project state.
- Screenshot = visual evidence, never measurement truth.
- Never guess what MCP can measure.
- Never self-approve subjective visual quality.
- Convert approved visual decisions into measurable constraints when practical.
- Workflow: Inspect → Measure → Modify → Run → Verify → `ART_REVIEW`.
- `ART_APPROVED` requires user approval.
- If MCP is unavailable, state it explicitly.

---

Project: 幻想鄉 / 博麗神社 (Godot 4.7 3D)。主要遊戲專案位於 `godot/`。

## 核心防護 (避免損壞專案)
- **Git LFS 保護**：本專案大量使用 Git LFS。在 Godot 載入前必須確保二進位資產已 pull/checkout 完畢，避免因未解開的 LFS pointer 導致紋理/GLB 損壞並烙印 `valid=false`。
- **編輯器控制**：涉及場景/節點狀態時，以 godot-ai MCP 實況為準，同時僅允許單一實體控制編輯器。
