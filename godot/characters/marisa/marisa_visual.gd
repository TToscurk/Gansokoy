extends "res://characters/keine/keine_visual.gd"
## 魔理莎專用的見た目ルート：繼承慧音版（idle 變奏＋淡入切換），再多掛一張「額外動作表」。
## extra_clips：{ 動作名: res 路徑 }，啟動時加進 AnimationPlayer 的預設庫，之後用 play_clip(&"動作名") 切換
## （npc_casual_actor.gd 的閒逛／閒聊動作從這裡取）。共用的 keine_visual.gd／npc_visual.gd 不改。

@export var extra_clips := {}


func _ready() -> void:
	super._ready()
	var lib := player.get_animation_library(&"")
	for k in extra_clips:
		var a := load(String(extra_clips[k])) as Animation
		if a == null:
			push_warning("[Marisa] 找不到動作 %s" % extra_clips[k])
			continue
		lib.add_animation(StringName(k), a)
