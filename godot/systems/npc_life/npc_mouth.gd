extends Node
## 基本嘴型（模型沒有嘴部 blend shape／下顎骨，嘴是畫在身體貼圖上的）：
## 在 HERO「身體」網格的 material_overlay 上，以貼圖 UV 空間畫一個依音量開合的口腔橢圓。
## 畫在臉的表面本身（跟著曲面與骨架），正面、側面都貼在嘴上，不會像平面片那樣偏移。
## 不說話時拿掉 overlay（零額外成本）。嘴的 UV 由 tools/npc_voice/bake_mouth_uv.gd 烘焙進 voices.json。

var _body: MeshInstance3D
var _mat: ShaderMaterial
var _open := 0.0
var _target := 0.0
var _on := false

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;
uniform vec4 anchor_a;        // (u, v, 未用, 未用)
uniform vec4 uvm_a;           // UV 位移 → 臉部公尺：兩欄 (c0x, c0y, c1x, c1y)
uniform vec4 anchor_b;
uniform vec4 uvm_b;
uniform float anchors = 1.0;  // 1 或 2（嘴跨在貼圖接縫上時兩塊）
uniform vec4 anchor_back;     // 嘴是開縫的模型：縫裡露出的頭殼內側（背面）
uniform vec4 uvm_back;
uniform float has_back = 0.0;
uniform vec3 inner_uv = vec3(0.0, 0.0, -1.0);   // 開縫嘴的唇內壁 UV 塊（u, v, 半徑；半徑 < 0＝沒有）
uniform vec2 half_size = vec2(0.009, 0.005);
uniform float open_amt = 0.0;
uniform vec4 inner : source_color = vec4(0.30, 0.06, 0.07, 1.0);
uniform vec4 lip : source_color = vec4(0.55, 0.22, 0.22, 1.0);
void vertex() {
	// 在視空間往鏡頭拉一點（正面、背面都會蓋在原表面上；沿法線推會讓背面被推到後面而被深度測試擋掉）
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz * 0.9997;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
// 到嘴中心的正規化距離（≤ 1 在嘴內）；正面用 a/b 兩塊，背面（開縫嘴縫裡的頭殼內側）用 back
float mouth_r(vec2 uv, bool front) {
	vec2 r2 = vec2(half_size.x * (0.75 + 0.25 * open_amt), max(half_size.y * open_amt, 0.0004));
	if (!front) {
		if (has_back < 0.5) {
			return 9.0;
		}
		vec2 dk = uv - anchor_back.xy;
		return length((uvm_back.xy * dk.x + uvm_back.zw * dk.y) / r2);
	}
	vec2 da = uv - anchor_a.xy;
	float r = length((uvm_a.xy * da.x + uvm_a.zw * da.y) / r2);
	if (anchors > 1.5) {
		vec2 db = uv - anchor_b.xy;
		r = min(r, length((uvm_b.xy * db.x + uvm_b.zw * db.y) / r2));
	}
	return r;
}

void fragment() {
	if (inner_uv.z > 0.0 && distance(UV, inner_uv.xy) < inner_uv.z) {
		// 開縫嘴的唇內壁：說話時塗暗
		ALBEDO = inner.rgb;
		ALPHA = smoothstep(0.06, 0.3, open_amt);
	} else {
		float r = mouth_r(UV, FRONT_FACING);
		if (r > 1.0) {
			discard;
		}
		ALBEDO = mix(inner.rgb, lip.rgb, smoothstep(0.55, 0.95, r));
		ALPHA = 1.0 - smoothstep(0.82, 1.0, r);
	}
}
"""

static var _shader: Shader


## npc_root：角色場景根（含 body_mesh）；vc：voices.json 的 heroes[id]
static func attach(npc_root: Node, vc: Dictionary) -> Node:
	if not vc.has("mouth_uv"):
		return null
	var body := npc_root.find_child(String(vc.get("body_mesh", "身體")), true, false) as MeshInstance3D
	if body == null or body.material_overlay != null:
		return null
	var m: Node = (load("res://systems/npc_life/npc_mouth.gd") as GDScript).new()
	m.name = "Mouth"
	m.call("_setup", body, vc)
	npc_root.add_child(m)
	return m


func _setup(body: MeshInstance3D, vc: Dictionary) -> void:
	_body = body
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.render_priority = 2
	var an: Array = vc.mouth_uv
	var sz: Array = vc.get("mouth_size", [0.016, 0.010])
	for i in mini(an.size(), 2):
		var k := "a" if i == 0 else "b"
		_mat.set_shader_parameter("anchor_" + k, Vector4(an[i][0], an[i][1], 0.0, 0.0))
		_mat.set_shader_parameter("uvm_" + k, Vector4(an[i][2], an[i][3], an[i][4], an[i][5]))
	_mat.set_shader_parameter("anchors", float(mini(an.size(), 2)))
	var bk: Array = vc.get("mouth_uv_back", [])
	if not bk.is_empty():
		_mat.set_shader_parameter("anchor_back", Vector4(bk[0][0], bk[0][1], 0.0, 0.0))
		_mat.set_shader_parameter("uvm_back", Vector4(bk[0][2], bk[0][3], bk[0][4], bk[0][5]))
		_mat.set_shader_parameter("has_back", 1.0)
	var inn: Array = vc.get("mouth_inner", [])
	if inn.size() == 3:
		_mat.set_shader_parameter("inner_uv", Vector3(inn[0], inn[1], inn[2]))
	_mat.set_shader_parameter("half_size", Vector2(float(sz[0]) * 0.5, float(sz[1]) * 0.5))


## 0..1
func set_open(v: float) -> void:
	_target = clampf(v, 0.0, 1.0)


func is_drawing() -> bool:
	return _on


func _process(dt: float) -> void:
	_open = move_toward(_open, _target, 12.0 * dt)
	var want := _open > 0.06
	if want != _on and is_instance_valid(_body):
		_on = want
		_body.material_overlay = _mat if want else null
	if _on:
		_mat.set_shader_parameter("open_amt", _open)
