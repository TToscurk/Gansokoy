extends Node
## 物理步驅動器：在 SoftBody3D 之前執行（process_physics_priority 低者先跑）
var cb: Callable
func _physics_process(_d: float) -> void:
	if cb.is_valid(): cb.call()
