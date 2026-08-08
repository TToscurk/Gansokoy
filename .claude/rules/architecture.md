# Rule: Architecture Production (Blender → GLB → Godot)

Full specification: `docs/machiya-production-kit.md`. This file is the
short list of constraints that must not be violated.

## Module contract

- Coordinates: front faces **−y**, origin at the **front face at ground
  level**, x is the frontage direction. Blender `(x, y, z)` → Godot
  `(x, z, −y)`. The origin is *not* the centre of the volume — code that
  assumes it is has broken the ground layer twice.
- `godot/assets/blender/make_town.py` is the **single writer** of
  `godot/data/town_modules.json`. Sizes (W / D / total height / pitch) live
  in its `MACHIYA` table; composition lives in `make_machiya.py`'s `SPECS`.
  When the two disagree, the table wins.
- `fw` / `fd` / `h` are measured from the actual bbox, never from
  parameters, and include roof overhang. Use `fw` (not W) for spacing.

## Real construction, not blockout

- 真壁造: erect the frame (土台→柱→貫→内法長押→桁), then fill plaster
  panels **between** posts, recessed 25 mm. Never a white box with wood
  strips glued outside.
- Roofs are assemblies (野地 / 軒裏 / 垂木 / 鼻隠し / 破風板 / 懸魚 / 棟 /
  瓦), not a single sloped plane. Eaves and hisashi are complete components,
  never a horizontal cube protruding from a wall.
- The plate (桁) top must be **flush with** the wall-top datum; growing it
  upward pierces the roof plane.

## Semantic materials

- Six names are a contract: `WOOD`, `WOOD_LT`, `PLASTER`, `STONE`,
  `KAWARA`, `SHOJI`. Blender material → one glTF primitive → one Godot
  surface → `gen_lib.semantic_mesh()` maps by name prefix.
- A variant may legitimately use fewer than six (the workshop has no
  shoji). The assert is: **≥4 per module, union across the kit = 6** — it
  exists to catch identity collapsing to one surface, not to force usage.

## Variation rules ("same culture, different families")

- Constant across the kit (human scale): 内法高 1.85, post 150, 貫 105,
  長押 130, 腰板, 犬走り, materials, plaster filling method, tile method.
- Variable (family scale): frontage, total height, mezzanine type, bay
  composition, 平入/妻入, hisashi, 卯建/煙出し, pitch.
- **Fake variation is forbidden**: scaling or rotating one mesh does not
  count. 妻入り rotates the roof's *generation coordinate system* only —
  the frame, façade and hisashi still generate facing the street, and the
  height budget changes span from depth to frontage.
- Any vertex transform must be a **rotation with positive determinant**.
  A mirror flips winding; Blender renders double-sided so it looks fine
  there and vanishes in Godot.
- Do not aim for "every building different" — repeated standard houses are
  what makes a settlement read as one culture.

## Do not touch without instruction

`machiya_f_a` geometry (approved, 2834 faces), the four legacy blockouts
still used by the village's 169 houses, and the village layout itself.
