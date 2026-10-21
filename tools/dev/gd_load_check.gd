extends SceneTree
## gd_check 的第二意見：在 autoload 已註冊的狀態下 load() 每支腳本。
## `--check-only` 在 autoload 註冊前就結束，所以引用 autoload 單例（StoryFlags、Wind…）的腳本會誤報
## "Identifier not found"；這裡的 _initialize() 發生在 autoload 掛上 root 之後，等同遊戲實際編譯條件。
##
## 注意：Godot 的 load() 在腳本有編譯錯誤時「仍會回傳 Script 物件」（只印 SCRIPT ERROR），
## 所以不能只看 null；必須再檢查 can_instantiate()（編譯失敗的腳本為 false）。
##
## 用法（由 tools/dev/gd_check.py 呼叫）：
##   godot --headless --path godot --script <本檔絕對路徑> -- res://a.gd res://b.gd
## 每支輸出 GDCHK<TAB>PASS|FAIL<TAB>res://path；任何 FAIL → exit 1。

func _initialize() -> void:
	var bad := 0
	for p in OS.get_cmdline_user_args():
		print("GDCHK\tBEGIN\t", p)
		var s = ResourceLoader.load(p, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
		var ok: bool = s != null and s is GDScript and (s as GDScript).can_instantiate()
		if not ok:
			print("GDCHK\tFAIL\t", p)
			bad += 1
		else:
			print("GDCHK\tPASS\t", p)
	quit(1 if bad > 0 else 0)
