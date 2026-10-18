extends SceneTree
## 產生（或補齊）res://data/wind/wind_species.tres：缺的物種用 WindSpeciesProfile.DEFAULTS。
##   Godot_v4.7.2-stable_win64_console.exe --headless --path godot --script res://tools/wind/wind_species_init.gd [-- --reset]
## 已存在的物種參數不覆寫（除非 --reset）——使用者調過的值會留著。

const PATH := "res://data/wind/wind_species.tres"


func _init() -> void:
	var reset := "--reset" in OS.get_cmdline_user_args()
	var t: WindSpeciesTable = null
	if not reset and ResourceLoader.exists(PATH):
		t = load(PATH) as WindSpeciesTable
	if t == null:
		t = WindSpeciesTable.new()
	var added := 0
	for n: String in WindSpeciesProfile.SPECIES_ORDER:
		if t.get_profile(n) == null:
			t.profiles.append(WindSpeciesProfile.from_defaults(n))
			added += 1
	var err := ResourceSaver.save(t, PATH)
	print("%s %s：%d 物種（新增 %d）" % ["OK" if err == OK else "FAIL", PATH, t.profiles.size(), added])
	quit(0 if err == OK else 1)
