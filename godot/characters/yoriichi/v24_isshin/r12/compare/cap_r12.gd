extends "res://characters/yoriichi/v24_isshin/r12/r12_kasha_demo.gd"
## 比較錄影：R12 日之呼吸・火車（sun_kasha）。--vfx12=unified → 統一系統風格化火環；預設 → Blender 火焰 KS12。用法見 vfx_capture.gd。
const Cap = preload("res://characters/yoriichi/v24_isshin/r12/compare/vfx_capture.gd")
var cap

func _ready() -> void:
	super._ready()
	if "--vfx12=unified" in OS.get_cmdline_user_args():
		vfx_variant = UNIFIED
	hud_on = false
	cap = Cap.new(self)

func _process(delta: float) -> void:
	super._process(delta)
	cap.step(delta)

func _on_hit(info: Dictionary) -> void:
	super._on_hit(info)
	cap.hit(info)
