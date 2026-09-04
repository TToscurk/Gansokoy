# CLAUDE.md — Repository Entry Rules

## 核心紅線
1. **重用優先**：先重用後新增；不建平行 pipeline，不擴張無關範圍。
2. **視覺專權**：視覺僅使用者能批准（`ART_APPROVED`）；Agent 至多給予 `ART_REVIEW`。
3. **唯讀保護**：`godot/assets/blender/sources/` 全程唯讀。
4. **禁止空想**：禁止憑記憶寫 API 或推測場景；觸及 Godot 必查 `godot-master`。
5. **Godot Visual Workflow**
   - MCP = inspect, measure, modify, debug, verify.
   - Screenshot = visual evidence, not source of measurements.
   - Never guess a measurable value from screenshots.
   - Never self-approve subjective visual quality.
   - Convert approved visual decisions into measurable constraints when possible.
   - Workflow: Inspect → Measure → Modify → Run → Verify → User approves visuals.
   - If MCP is unavailable, state it.

---

Project: 幻想鄉 / 博麗神社 (Godot 4.7 3D)。主要遊戲專案位於 `godot/`。

## 核心防護 (避免損壞專案)
- **Git LFS 保護**：本專案大量使用 Git LFS。在 Godot 載入前必須確保二進位資產已 pull/checkout 完畢，避免因未解開的 LFS pointer 導致紋理/GLB 損壞並烙印 `valid=false`。
- **編輯器控制**：涉及場景/節點狀態時，以 godot-ai MCP 實況為準，同時僅允許單一實體控制編輯器。
