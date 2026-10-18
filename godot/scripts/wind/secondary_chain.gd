class_name SecondaryChain
extends Resource
## 二次運動骨鏈（WindSecondaryMotion 用）。root_bone → tip_bone 必須是同一條父子鏈（元件會驗證）。
## 單位：stiffness＝回復角頻率²（1/s²）、damping＝阻尼比 ζ、max_angle_deg＝整條鏈末端相對動畫姿勢的最大偏擺。

@export var label := ""
@export var root_bone := ""
@export var tip_bone := ""
@export_enum("hair", "tail", "cloth", "sleeve", "feather", "ornament", "ear") var kind := 1
@export_range(1.0, 400.0) var stiffness := 40.0
@export_range(0.05, 2.0) var damping := 0.45
## 風的影響（相對空氣速度 m/s → 偏擺；0＝不吃風）
@export_range(0.0, 2.0) var wind_influence := 1.0
## 身體加速度／轉向造成的慣性落後（0＝不吃）
@export_range(0.0, 2.0) var inertia := 1.0
@export_range(0.0, 90.0) var max_angle_deg := 35.0
## 重力下垂（對動畫姿勢再加的下垂；大多數已有動畫的鏈＝0）
@export_range(0.0, 1.0) var gravity := 0.0
## 最低需要的模擬等級（1＝輕量就跑；2＝只在增強級跑，例如耳朵細節）
@export_range(1, 2) var min_tier := 1
