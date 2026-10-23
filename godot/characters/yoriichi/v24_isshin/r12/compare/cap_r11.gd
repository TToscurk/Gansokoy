extends "res://characters/yoriichi/v24_isshin/fire_research_v2/sun_fire_hekira_demo.gd"
## 比較錄影：R11 碧羅天（R11 動作）＋R11 原版 Blender 火焰（HK11_R10），不改 R11 任何檔案。用法見 vfx_capture.gd。
const Cap = preload("res://characters/yoriichi/v24_isshin/r12/compare/vfx_capture.gd")
var cap

func _ready() -> void:
	super._ready()
	vfx_variant = _old_variant
	fire.clear()
	hud_on = false
	cap = Cap.new(self)

func _process(delta: float) -> void:
	super._process(delta)
	cap.step(delta)

func _on_hit(info: Dictionary) -> void:
	super._on_hit(info)
	cap.hit(info)

func _update_cam(snap: bool) -> void:
	ThirdCam.update(self, snap)

const ThirdCam = preload("res://characters/yoriichi/v24_isshin/r12/third_person_cam.gd")
