extends RefCounted
class_name AudioBuses
## 執行期建立音效匯流排。
##
## 專案沒有 default_bus_layout.tres（全部走 Master）—— ambience.gd 早就在
## 執行期自己補了一條 "Ambience"，這裡照同一個做法補 "SFX" 與 "Wildlife"，
## 不強迫使用者去編輯器開匯流排面板、也不必新增資源檔。
##
## 為什麼不讓遊戲音效直接走 Master：Master 應該只留給最終限幅。
## 全部塞進 Master 的話，之後要做音量選單就沒有辦法分類調整
## （音樂／音效／環境各自一條才調得動）。

const SFX := &"SFX"
const WILDLIFE := &"Wildlife"


## 確保匯流排存在，回傳可直接指派給 AudioStreamPlayer.bus 的名字。
## 拿不到（例如 AudioServer 還沒就緒）就退回 Master，絕不讓聲音消失。
static func ensure(bus_name: StringName, send_to: StringName = &"Master") -> StringName:
	if AudioServer.get_bus_index(bus_name) != -1:
		return bus_name
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, String(bus_name))
	AudioServer.set_bus_send(idx, String(send_to))
	if AudioServer.get_bus_index(bus_name) == -1:
		return &"Master"
	return bus_name


static func sfx() -> StringName:
	return ensure(SFX)


## 野生動物（鳥鳴／蛙／水花）獨立一條，掛在 SFX 底下 ——
## 這樣之後要單獨壓低「環境生物」而不動打擊音，只要調這條。
static func wildlife() -> StringName:
	ensure(SFX)
	return ensure(WILDLIFE, SFX)
