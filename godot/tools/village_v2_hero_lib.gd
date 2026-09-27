extends RefCounted
## 人間之里 V2：Hero／地標新資產的「登記讀取＋放置」共用邏輯（P5 R1 起）。
## 產生器（gen_village_v2.gd _heroes）與 Asset Gate（verify_village_v2_hero_gate.gd）都走這裡——同一套放置，
## 避免「gate 驗的位置」和「場景實際放的位置」不一樣。
##
## 放置規約（asset.json gate_spec.placement）：
##   "greybox"：資產原點＝P4 灰盒 transform（footprint 中心、y＝footprint 最高地面、+z＝正面）。
##              灰盒節點保留（P4 gate 永久讀它），但所有 MeshInstance3D visible＝false、CollisionShape3D disabled。
##              ——灰盒只剩「P4 規格紀錄」，不再提供外觀或碰撞；資產自己接地（禁止墊在灰盒上）。
##   "anchor"： 資產原點＝P0 地標節點原點；placeholder 子節點（例 Torii）的 transform 給旋轉；
##              產生器直接不建 placeholder，gate 在未登記前則隱藏＋停用它。
##              gate_spec.yaw_deg（R3 起）：P0 線框（_wire_box）把 yaw 烘進頂點、節點本身沒旋轉 → 旋轉由這裡給
##              （gate pivot 項另對 layout P0 yaw 驗，不是自報）。
##   gate_spec.also_retire（R3 起）：其他要一起退場的 placeholder 子節點（例 P0 線框的 Footprint 地面框）。
##   gate_spec.instances（R4 水車起）：同一件資產放在多個 P0 地標；每筆覆寫 gate_spec 同名欄位（anchor、yaw_deg…），
##              instances(S) 展開後產生器與 gate 逐筆放置、逐筆驗。
##   "body"（P6 aux 納屋／土藏起）：anchor＝P4 灰盒 StaticBody3D 本身（Districts/<區>/Buildings/S_*）；資產以 identity 掛在它下面
##              （原點＝灰盒原點＝footprint 中心、y＝base_h、+z＝正面）。灰盒節點保留（P4 gate 讀它的位置與 Foundation），
##              灰盒自己的網格隱藏、Shape 停用、collision_layer 0（retire_body）；Hero 子樹不受影響。
## 路徑一律從 registry／asset.json 讀，原始碼不寫資產 res:// 字串（P5 asset reset gate 掃描產生器原始碼）。

const REG := "res://data/village_v2_asset_registry.json"
const GATE_KEYS: Array[String] = ["size", "parcel_fit", "grounding", "materials", "geometry", "pivot_scale",
	"collision", "lod", "performance", "player_screenshot", "f5_f6"]


static func registry() -> Dictionary:
	var r: Variant = JSON.parse_string(FileAccess.get_file_as_string(REG))
	return r if r is Dictionary else {}


## registry v2_assets 中 11 項全 PASS、且 .scn 雜湊與 gate 當時一致的 hero／landmark 資產
static func approved(reg: Dictionary) -> Array:
	var out: Array = []
	for a: Dictionary in reg.get("v2_assets", []):
		if String(a.get("kind", "")) in ["material_library", "kit"]:   # kit（P6 町家 Kit）走 village_v2_machiya_kit_lib.gd
			continue
		var g: Dictionary = a.get("gate", {})
		var ok := true
		for k in GATE_KEYS:
			ok = ok and String(g.get(k, "")) == "PASS"
		var scn := String(a.get("entry", ""))
		if ok and scn != "" and FileAccess.file_exists(scn) \
				and FileAccess.get_sha256(scn) == String(a.get("entry_sha256", "")):
			out.append(a)
	return out


static func spec(asset_json: String) -> Dictionary:
	var s: Variant = JSON.parse_string(FileAccess.get_file_as_string(asset_json))
	return s if s is Dictionary else {}


## gate_spec 依實例展開：沒有 instances → [gate_spec]；有 → 每筆覆寫同名欄位。landmark 預設取 asset.json landmark。
static func instances(S: Dictionary) -> Array:
	var gs: Dictionary = S["gate_spec"]
	var out: Array = []
	for i: Dictionary in gs.get("instances", [{}]):
		var g := gs.duplicate(true)
		g.erase("instances")
		g["landmark"] = String(S.get("landmark", ""))
		for k in i:
			g[k] = i[k]
		out.append(g)
	return out


## 放一件資產到 vroot（VillageV2 根）。回傳 Hero 節點（名為 "Hero"，掛在 anchor 下）；失敗回 null。
## remove_placeholder：true＝anchor 型的 placeholder 直接 free（產生器用）；false＝隱藏＋停用（gate 用）。
## inst：gate_spec.instances 第幾筆（單一放置的資產＝0）。
static func place(vroot: Node3D, S: Dictionary, scene: PackedScene, remove_placeholder: bool, inst := 0) -> Node3D:
	var gs: Dictionary = instances(S)[inst]
	var anchor := vroot.get_node_or_null(String(gs["anchor"])) as Node3D
	if anchor == null:
		push_error("[hero] 找不到 anchor %s" % gs["anchor"])
		return null
	var old := anchor.get_node_or_null("Hero")
	if old != null:
		return old as Node3D   # 已放（產生器烘焙過）
	var body_mode := String(gs["placement"]) == "body"
	var ph := null if body_mode else anchor.get_node_or_null(String(gs["replaces"])) as Node3D
	var xf := Transform3D.IDENTITY
	if body_mode:
		pass   # 資產原點＝灰盒節點原點（identity）
	elif ph != null:
		xf = ph.transform
		if String(gs["placement"]) == "anchor":
			xf.origin = Vector3.ZERO   # 地標原點＝資產原點；placeholder 只給旋轉
	elif String(gs["placement"]) == "greybox":
		push_error("[hero] %s 沒有灰盒節點 %s" % [gs["anchor"], gs["replaces"]])
		return null
	if gs.has("yaw_deg"):
		xf.basis = Basis(Vector3.UP, deg_to_rad(float(gs["yaw_deg"])))
	if gs.has("dy"):
		xf.origin.y += float(gs["dy"])   # 水車：原點＝水渠水面（asset.json 逐點登記；gate 對水面網格實測驗）
	var hero := scene.instantiate() as Node3D
	hero.name = "Hero"
	hero.transform = xf
	hero.set_meta("asset_id", String(S["id"]))
	hero.set_meta("phase", "P5")
	anchor.add_child(hero)
	if body_mode:
		retire_body(anchor)
	if ph != null:
		if String(gs["placement"]) == "anchor" and remove_placeholder:
			anchor.remove_child(ph)
			ph.free()
		else:
			retire(ph)
	for extra: String in gs.get("also_retire", []):
		var e := anchor.get_node_or_null(extra)
		if e == null:
			continue
		if remove_placeholder:
			anchor.remove_child(e)
			e.free()
		else:
			retire(e)
	anchor.set_meta("hero_asset", String(S["id"]))
	return hero


## 灰盒／placeholder 退場：保留節點（P4 gate 讀 Foundation AABB），外觀與碰撞全關。
## 每個 MeshInstance3D 各自 visible＝false：sightline gate 讀的是節點自己的 visible，不是 is_visible_in_tree。
static func retire(n: Node) -> void:
	for c in n.find_children("*", "", true, false) + [n]:
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = false
		elif c is CollisionShape3D:
			(c as CollisionShape3D).disabled = true
		if c is CollisionObject3D:
			(c as CollisionObject3D).collision_layer = 0
	if n is Node3D:
		(n as Node3D).visible = false
	n.set_meta("retired_by_hero", true)


## "body" 放置的灰盒退場：灰盒節點本身與 Hero 子樹保留可見；灰盒自己的網格隱藏、Shape 停用、collision_layer 0。
static func retire_body(body: Node3D) -> void:
	var hero := body.get_node_or_null("Hero")
	for c in body.find_children("*", "", true, false):
		if hero != null and (c == hero or hero.is_ancestor_of(c)):
			continue
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = false
		elif c is CollisionShape3D:
			(c as CollisionShape3D).disabled = true
	if body is CollisionObject3D:
		(body as CollisionObject3D).collision_layer = 0
	body.set_meta("retired_by_hero", true)
