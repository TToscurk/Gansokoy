class_name WindSpeciesTable
extends Resource
## Wind V1.2 物種表（res://data/wind/wind_species.tres）。每個物種一份 WindSpeciesProfile；
## 缺的物種用 WindSpeciesProfile.DEFAULTS 補。執行中可用 Wind.set_species_param() 即時調。

@export var profiles: Array[WindSpeciesProfile] = []


func get_profile(name: String) -> WindSpeciesProfile:
	for p in profiles:
		if p != null and p.id == name:
			return p
	return null


static func make_default() -> WindSpeciesTable:
	var t := WindSpeciesTable.new()
	for n: String in WindSpeciesProfile.SPECIES_ORDER:
		t.profiles.append(WindSpeciesProfile.from_defaults(n))
	return t
