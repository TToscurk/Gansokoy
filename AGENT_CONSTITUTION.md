# 幻想鄉緣一計畫：Production Constitution

> 2026-08-29 使用者審定。細節規格以 `.claude/rules/` 與各 skill 為權威，本文件只留原則。

**目標**：最短時間做出玩家**看得見、走得到、可展示**的提升。
基線＝現行 `village.tscn` 地標區；20% 修舊／80% 新美術。內部整潔不算進度。

**紅線**

1. 先重用後新增；不建平行 pipeline 或第二套資料來源。
2. 沒有阻塞不重構核心；不順手擴張範圍、不過度工程。
3. 視覺只有使用者能批准（`ART_APPROVED`）；agent 至多 `ART_REVIEW`。
4. `godot/assets/blender/sources/` 唯讀。

**證據優先**

- 場景／節點／資源狀態：先用 godot-ai MCP 查實況，不讀檔名或文件推測。
  逾時不等於失敗——先 `editor_state` 確認再重試；同時只允許一個 AI 控編輯器。
- **工具責任與證據邊界**：
  - **Graphify**＝文件、程式架構、依賴與歷史決策的查詢索引。`graphify-out/graph.json`
    存在時，專案內容／架構問題先載入 `graphify` skill 並查圖，再按需要回到原始文件或原始碼複核；
    Graphify 的 `INFERRED`／`AMBIGUOUS` 關係不是事實，也不得裁決場景、資源、幾何或視覺。
  - **godot-ai MCP**＝編輯器內場景、節點、資源、匯入與 runtime 狀態的實況權威；
    Graphify、檔名、`.tscn`／`.tres` 文字與記憶都不能取代它。
  - **Blender MCP／`asset_probe.py`**＝mesh／GLB 頂點、原點、尺度、行走面與幾何狀態的實況權威；
    截圖、AABB、檔名與文字描述都不能取代頂點量測。
  - **GDToolkit**＝GDScript 的 lint、format 與 complexity 靜態檢查；不能取代 Godot 4.7
    實際載入、解析、執行、場景驗證或截圖驗收。只使用專案既有檢查，不為了符合本條另建 pipeline。
- **資產進場管線**：Meshy RAW → Blender 整理／頂點量測 → GLB → Godot 匯入 →
  prototype → render → Human Art Review → `ART_APPROVED` 後 rollout。不得跳步；
  `godot/assets/blender/sources/` 全程唯讀，未批准不得大量灌入。
- 結構驗證用 MCP 查詢；**視覺驗收才截圖**，一律 shotlist 固定機位。
  渲染問題（剔除、繞線、摩爾紋、光照）只有截圖抓得到。
- **資產幾何一律用頂點量測裁決，不用 AABB 推定，更不用截圖判讀。**
  跑 `godot/tools/asset_probe.py`（Blender MCP 直讀 GLB 頂點）確認：
  原點在幾何中心還是底部（**Meshy 資產多為置中，但有例外**），
  以及行走面的真實落差（AABB 全高含底部凹陷與頂部凸脊，用它算 scale 會錯）。
  低解析度截圖交給 vision 判斷模型形狀會產出完全錯誤的描述，不得作為證據。
  新資產進場前先量，擺放後再用「模型底 + position.y × scale = 目標面」複驗。
- Skill 按需載入，一次一個 reference（路由見 CLAUDE.md 的 skill 清單）。
- **強制**：任何觸及 Godot 的工作（場景／節點／資源、GDScript、生成器、匯入、
  material／shader、驗證腳本）開工前，必須先載入 `godot-master` skill，
  再依其路由讀取所需的單一 reference。不得憑記憶寫 Godot 4.7 API。
  **每一次修改都適用**，不因同一輪對話先前已載入過而豁免：改動前重新確認
  該次工作對應的 reference，跨領域（材質→shader→世界建構）時逐一載入對應項。

**流程**

- 製作場景內的地形、或做村落／區域規劃前，先參考概念圖 `docs/reference/人間之里概念圖/`：
  **基準＝`村落農村概念俯視.png`**（使用者裁決 2026-08-30；搭配
  `村落農村概念俯視區域分隔.png` 看分區），其餘（住商地區、住宅概念圖、
  河童重工＋人間之里）為輔助參考。
  **圖是權威，文字轉錄不是。**`docs/village-concept-reference.md` 只是索引，
  與圖衝突時一律以圖為準；不得引用該文件的字句去否定圖上讀到的內容。
  以資料夾內**現存檔案**為準；檔案被移除即代表該參考作廢，不得引用不存在的圖。
- prototype → render → **Human Art Review** → rollout，不可跳步；未批准不得大量灌入。
- 日常改動跑 Fast 檢查（既有檢查，不重寫）；整合／世界生成變更才跑 Full regression。
- 三距離審：50m 量體 → 20m 街道節奏 → 5m 細節；不得用 5m 掩蓋 50m 失敗。

**行為**

- 已批准方向自主做到底，不要微批准；只在動地標、村莊結構、已核准美術方向、
  玩法／世界觀、或無回滾的破壞性操作前停下來問。
- 先給結論與證據，再說內部工作；方向有問題就以證據提更小更正確的替代方案。

---

# English Version

> User-ratified 2026-08-29. Detailed specs live in `.claude/rules/` and the
> project skills — those are authoritative; this document is principles only.

**Goal**: Deliver player-**visible, walkable, showable** improvements in the
shortest time. Baseline = the current `village.tscn` landmark area;
20% repair / 80% new art. Internal tidiness does not count as progress.

**Red lines**

1. Reuse before adding; never build a parallel pipeline or a second data source.
2. No core refactors unless actually blocked; no scope creep, no over-engineering.
3. Only the user approves visuals (`ART_APPROVED`); an agent reaches `ART_REVIEW` at most.
4. `godot/assets/blender/sources/` is read-only.

**Evidence first**

- Scene / node / resource state: query the godot-ai MCP for ground truth —
  never infer from filenames, docs, or memory. A timeout is not a failure:
  confirm via `editor_state`, then retry. Only one AI drives the editor at a time.
- **Tool responsibilities and evidence boundaries**:
  - **Graphify** is a query index for documents, code architecture, dependencies,
    and historical decisions. When `graphify-out/graph.json` exists, project-content
    and architecture questions load the `graphify` skill and query the graph first,
    then verify against original documents or source as needed. Graphify
    `INFERRED` / `AMBIGUOUS` edges are not facts and cannot settle scene, resource,
    geometry, or visual truth.
  - **godot-ai MCP** is authoritative for live editor scenes, nodes, resources,
    imports, and runtime state. Graphify, filenames, `.tscn` / `.tres` text, and
    memory cannot replace it.
  - **Blender MCP / `asset_probe.py`** is authoritative for mesh / GLB vertices,
    origins, scale, walkable surfaces, and geometry state. Screenshots, AABBs,
    filenames, and prose cannot replace vertex measurement.
  - **GDToolkit** provides static GDScript linting, formatting, and complexity
    checks. It does not replace Godot 4.7 loading, parsing, execution, scene
    validation, or screenshot review. Use only existing project checks; do not
    create a parallel pipeline merely to satisfy this rule.
- **Asset intake pipeline**: Meshy RAW → Blender cleanup / vertex measurement →
  GLB → Godot import → prototype → render → Human Art Review → rollout only after
  `ART_APPROVED`. No stage may be skipped; `godot/assets/blender/sources/` remains
  read-only throughout, and unapproved work must not be mass-deployed.
- Structural checks go through MCP queries; **screenshots are for visual
  acceptance only**, always from fixed shotlist cameras. Render-side defects
  (culling, winding, moiré, lighting) are catchable ONLY in screenshots.
- **Asset geometry is settled by vertex measurement — never by AABB inference,
  and never by reading a screenshot.** Run `godot/tools/asset_probe.py`
  (Blender MCP, reads GLB vertices directly) to establish whether the origin
  sits at the geometric centre or the base (**Meshy exports are usually
  centred, but there are exceptions**), and the real walkable rise (an AABB's
  full height includes base hollows and top ridges — sizing `scale` from it is
  wrong). Handing a low-resolution screenshot to vision for shape judgement
  produces confidently wrong descriptions and is not admissible evidence.
  Measure before placing; after placing, re-verify that
  `model_bottom + position.y × scale` lands on the intended surface.
- Load skills on demand, one reference at a time (routing: see the skill list in CLAUDE.md).
- **Mandatory**: before any Godot-touching work (scenes / nodes / resources,
  GDScript, generators, import, materials / shaders, validation scripts), load
  the `godot-master` skill first, then follow its routing to the one reference
  the task needs. Never write Godot 4.7 API from memory.
  **This applies to every single change** — having loaded it earlier in the same
  session grants no exemption. Re-confirm the reference that matches the change
  at hand, and when work spans domains (materials → shaders → world building),
  load each corresponding reference in turn.

**Process**

- Before building in-scene terrain or planning village/area layout, first review
  the concept art in `docs/reference/人間之里概念圖/`. **The baseline is
  `村落農村概念俯視.png`** (user ruling 2026-08-30; use
  `村落農村概念俯視區域分隔.png` for its zoning breakdown); the other sheets
  (`住商地區`, `住宅概念圖`, `河童重工+人間之里`) are supporting references.
  **The image is authoritative; the text transcription is not.**
  `docs/village-concept-reference.md` is an index only — where it conflicts with
  the image, the image wins, and its wording must never be used to overrule what
  the image actually shows.
  The **files actually present in that folder** are the authority — a removed
  sheet is a retired reference and must not be cited.
- prototype → render → **Human Art Review** → rollout, no skipping; nothing
  unapproved gets mass-deployed.
- Day-to-day changes run Fast checks (existing checks, never rewritten);
  integration / world-generation changes run the Full regression.
- Three-distance review: 50m massing → 20m street rhythm → 5m detail;
  never use 5m detail to hide a 50m failure.

**Behavior**

- Once a direction is approved, execute autonomously to completion — no
  micro-approvals. Stop and ask only before: moving a major landmark, changing
  village structure, changing approved art direction, changing gameplay /
  worldbuilding, or any destructive action without a safe rollback.
- Lead with conclusions and evidence, then internals; if the direction is
  wrong, propose a smaller, more correct alternative backed by evidence.
