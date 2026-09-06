extends Node3D
## 水車自轉。模型軸=局部 Z（實測 bbox [1.0, 1.0, 0.331]，中心在原點），
## 生成器已把軸轉向跨流方向，繞局部 Z 旋轉即是正確的水車轉動。
## 真實水車很慢：每分鐘 3~8 轉，太快會讀成風車。

@export var rpm: float = 3.5

func _process(delta: float) -> void:
	rotate_object_local(Vector3(0.0, 0.0, 1.0), rpm * TAU / 60.0 * delta)
