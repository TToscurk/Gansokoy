extends RefCounted

const OUT_DIR := "res://maps/village/"
const MAP_ID := "village"
const MODULES := "res://data/town_modules.json"
const SEED := 20260806

const HALF := 300.0
const PLAZA := Vector2(0, 30)
const CORE := 196.0

const RIVER_SPINE := [
	Vector2(108, -300), Vector2(96, -236), Vector2(74, -168), Vector2(86, -108),
	Vector2(64, -50), Vector2(62, -6), Vector2(66, 30), Vector2(78, 72),
	Vector2(64, 120), Vector2(56, 168), Vector2(72, 224), Vector2(64, 300),
]
const RIVER_HALF := 7.0
const RIVER_DEPTH := 2.5
const BANK_PATH := 11.4

const MAIN_EW_Z := 30.0
const MAIN_EW_W := 12.0

const BRIDGES := [
	{"kind": "bridge_main", "x": 66.0, "z": 30.0, "yaw": 0.0},
	{"kind": "bridge_small", "x": 76.8, "z": -80.0, "yaw": 0.0},
	{"kind": "bridge_small", "x": 58.9, "z": 140.0, "yaw": 0.0},
]

const TOWERS := [
	{"kind": "tower_fire", "x": 9.5, "z": -132.0, "yaw": 0.20,
	 "why": "本通北端終點"},
	{"kind": "tower_bell", "x": 8.5, "z": 196.0, "yaw": -0.15,
	 "why": "本通南端終點"},
	{"kind": "tower_mill", "x": 62.5, "z": 89.0, "yaw": 1.5708,
	 "why": "z=85 橫街的河岸終點；水輪朝河"},
]

const UNOMITEI_ANCHOR := Vector2(50.0, 2.0)
