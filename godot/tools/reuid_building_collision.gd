extends SceneTree
## 把 uid://di8l4d0vl7a2p 烙印進 building_collision.scn 的檔頭。
## 4.7 的 import 掃描不讀 .uid sidecar（實測無效），只有 ResourceSaver
## 重存時寫進 binary 檔頭的 resource UID 才會進 uid_cache.bin。
const TARGET := "res://maps/slice/gen/building_collision.scn"
const WANT := "uid://di8l4d0vl7a2p"

func _init() -> void:
	var res: Resource = ResourceLoader.load(TARGET, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res == null:
		print("[REUID] FAIL load")
		quit(1)
		return
	print("[REUID] before=", res.resource_uid)
	res.resource_uid = WANT
	var err := ResourceSaver.save(res, TARGET)
	print("[REUID] save err=", err, " after=", res.resource_uid)
	# 重新以忽略快取載入，確認檔頭真的寫进去了
	var again: Resource = ResourceLoader.load(TARGET, "", ResourceLoader.CACHE_MODE_IGNORE)
	print("[REUID] reread=", again.resource_uid)
	quit(0 if String(again.resource_uid) == WANT else 2)
