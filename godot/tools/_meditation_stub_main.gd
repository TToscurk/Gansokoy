extends Node3D
## verify_meditation.gd 用的「假 main」：只提供冥想控制器需要的最小介面。
##
## 為什麼不直接載 main.tscn：獸道要載 20~30 秒，而且 main.tscn 一開場就跑序章
## 演出（會鎖住時間、鎖住輸入、播獨白），那樣「能不能冥想」的斷言會變成在測
## 開場而不是測冥想。真 main 的掛載與按鍵走 tools/_shot_meditation.gd。

var player: Node = null
var current_id := "trail"
var map_root: Node = null
