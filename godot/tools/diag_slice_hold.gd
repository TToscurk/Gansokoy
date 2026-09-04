extends SceneTree
## 正確歸因：Godot 的 ResourceCache 是弱參考 —— 前一次載入的結果一旦被
## 釋放就會離開快取，所以「先冷載一次再熱載一次」量到的其實還是冷載。
##
##   Godot --headless --path godot --script tools/diag_slice_hold.gd
##
## 這裡改成 **抓住相依資源的參考不放**，讓它們確實留在快取裡，再量 slice
## 本身。這樣才分得出「文字解析」與「相依載入」各佔多少。

const SRC := "res://maps/slice/slice.tscn"

var _held: Array = []   # 關鍵：不放手，資源才會留在快取


func _init() -> void:
	_run.call_deferred()


func _ms(a: int, b: int) -> float:
	return float(b - a) / 1000.0


func _run() -> void:
	# 1) 完全冷：什麼都沒抓住
	var t0 := Time.get_ticks_usec()
	var cold := ResourceLoader.load(SRC, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var t_cold := _ms(t0, Time.get_ticks_usec())
	cold = null
	print("[HOLD] 完全冷載 slice.tscn            %9.1f ms" % t_cold)

	# 2) 先把 87 個相依全部載進來並抓住
	var deps := ResourceLoader.get_dependencies(SRC)
	t0 = Time.get_ticks_usec()
	for d in deps:
		var p := _dep_path(String(d))
		if p != "" and ResourceLoader.exists(p):
			var r := ResourceLoader.load(p)
			if r != null:
				_held.append(r)
	var t_deps := _ms(t0, Time.get_ticks_usec())
	print("[HOLD] 預載並持有 %d 個相依           %9.1f ms" % [_held.size(), t_deps])

	# 3) 相依已在快取（且被持有），再量 slice 自己
	t0 = Time.get_ticks_usec()
	var warm := ResourceLoader.load(SRC, "", ResourceLoader.CACHE_MODE_IGNORE)
	var t_warm := _ms(t0, Time.get_ticks_usec())
	print("[HOLD] 相依已快取時解析 slice.tscn    %9.1f ms" % t_warm)
	print("[HOLD] → 相依佔 %.1f ms（%.0f%%），自身文字解析佔 %.1f ms（%.0f%%）" % [
		t_cold - t_warm, (t_cold - t_warm) / t_cold * 100.0,
		t_warm, t_warm / t_cold * 100.0])

	# 4) 逐個相依排名（此時全部已在快取，量的是「純重新解析自己」）
	print("[HOLD] --- 相依冷載入排名（各自 DEEP 冷載，抓住不放）---")
	_held.clear()
	var rows: Array = []
	for d in deps:
		var p := _dep_path(String(d))
		if p == "" or not ResourceLoader.exists(p):
			continue
		var s := Time.get_ticks_usec()
		var r := ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var dt := _ms(s, Time.get_ticks_usec())
		if r != null:
			_held.append(r)   # 抓住，後面的相依才不會重複冷載
		rows.append({"p": p, "ms": dt})
	rows.sort_custom(func(a, b): return a["ms"] > b["ms"])
	var i := 0
	var sum := 0.0
	for r in rows:
		sum += r["ms"]
	for r in rows:
		if i >= 15:
			break
		print("[HOLD]   %8.1f ms  %s" % [r["ms"], r["p"]])
		i += 1
	print("[HOLD]   相依加總 %.1f ms（無重複，因為載過的都持有）" % sum)

	warm = null
	print("[HOLD] done")
	quit(0)


func _dep_path(raw: String) -> String:
	var parts := raw.split("::")
	var chosen := ""
	for p in parts:
		if p.begins_with("res://") or p.begins_with("uid://"):
			chosen = p
	return chosen
