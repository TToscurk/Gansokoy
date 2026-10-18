class_name SecondaryMotionProfile
extends Resource
## 一副骨架的二次運動設定（骨鏈清單＋等級參數）。同一個元件吃不同的 profile → 適用不同 rig。

@export var rig_name := ""
@export var chains: Array[SecondaryChain] = []
## 輕量級（Tier 1）更新頻率；增強級（Tier 2）每幀＋子步
@export var lightweight_hz := 30.0
@export var enhanced_substeps := 2
## 自動分級距離（m，到主相機）：< enhanced_dist → 2、< lightweight_dist → 1、其餘 0
@export var enhanced_dist := 12.0
@export var lightweight_dist := 35.0
