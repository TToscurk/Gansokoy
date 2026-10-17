extends "res://tools/beast_path/s01_r3_shots.gd"
## S01 Blender 環境資產 Demo（R4 Demo）審圖鏡位：沿用 R3 全部鏡位，再加 Demo 區（東側谷壁腳＋草地）的四張。
## Before＝R3 Stage 1 場景（Demo 掛上前）、After＝S01Dress 掛上後；同一支腳本、同一組鏡位、同一時刻。
##   godot --path godot --script res://tools/beast_path/s01_demo_shots.gd -- --map=beast_path --out=<dir> --hour=10 [--only=a,b]
## 新增（全部固定世界座標，與規劃無關）：
##   d_tps_f1   TPS：主路上離 Demo 岩組 F1（東壁腳 (53.5, −14)）最近處，朝岩看
##   d_close    自由鏡位：谷底 1.7 m 高、F1 西北約 14 m——岩、坡腳、植物的接合近景
##   d_wide     自由鏡位：Demo 區西北上方 10 m，往東南看整片（草地＋谷壁腳＋林緣）
##   d_wide_s   自由鏡位：農田西側上方 9 m 往東北看（谷壁腳一路到北段）

const F1 := Vector2(53.5, -14.0)


func _views() -> Array:
	var v: Array = super._views()
	var sr := _nearest_s(F1)
	var c: Vector2 = lib.main.pos_at(sr)
	var d := F1 - c
	v.append({"name": "d_tps_f1", "at": [c.x, c.y], "face": rad_to_deg(atan2(d.x, -d.y)), "pitch": -0.10})
	v.append(_free("d_close", Vector2(41.0, -7.0), Vector2(53.0, -15.5), 1.7, 1.2))
	v.append(_free("d_wide", Vector2(12.0, 10.0), Vector2(50.0, -12.0), 10.0, 1.0))
	v.append(_free("d_wide_s", Vector2(26.0, -48.0), Vector2(52.0, -6.0), 9.0, 2.0))
	# ---- R5 擴區（南段：鳥居南側草地 → 西南林、主路 z −55 … −99）
	##   e_tps_e   TPS：主路 z≈−75，朝東南看（左＝開闊草地、右前＝中東林；草地 → 林的過渡）
	##   e_close   自由鏡位：林緣 1.5 m 高、看 6–8 m 外的樹腳（露根、蕨、草、土的接合）
	##   e_wide    自由鏡位：主路 z −50 上方 12 m，往南看整片（草地 → 林緣 → 林內的疏密）
	##   （穿林的一般 TPS＝既有 s86_fwd）
	var se := _nearest_s(Vector2(-7.0, -75.0))
	var ce: Vector2 = lib.main.pos_at(se)
	var de := Vector2(10.0, -86.0) - ce
	v.append({"name": "e_tps_e", "at": [ce.x, ce.y], "face": rad_to_deg(atan2(de.x, -de.y)), "pitch": -0.12})
	v.append(_free("e_close", Vector2(-7.0, -85.5), Vector2(-12.8, -88.6), 1.5, 0.5))
	v.append(_free("e_wide", Vector2(-14.0, -50.0), Vector2(-4.0, -86.0), 12.0, 1.0))
	return v
