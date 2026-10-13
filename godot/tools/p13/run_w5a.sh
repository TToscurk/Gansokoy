#!/usr/bin/env bash
# 共用: W5A のビルド＋撮影＋比較画像（bash tools/p13/run_w5a.sh <tag> ）
set -e
cd D:/神社/shrine/godot
TAG="$1"
W="C:/Users/B365/AppData/Local/hermes/cache/scratch/w5a/$TAG"
G=D:/Godot/Godot_v4.7.2-stable_win64_console.exe
rm -rf "$W"; mkdir -p "$W"
$G --headless --path . --script res://tools/p13/build_w4_pilot.gd -- --build 2>&1 | grep -v -i "wasapi\|hr !=" | grep -E "W5A|W4B\] (W4Steps|save)|SCRIPT ERROR|Parse Error|ERROR|WARNING" | cut -c1-260
$G --path . --script res://tools/p13/shot_w4.gd -- "$W/" w4 "w5" 2>&1 | grep -E "W4S\] (boot|w5)|SCRIPT ERROR|Parse Error|DONE" | cut -c1-120
cd "$W"
uv run --no-project --with pillow python - <<'EOF'
from PIL import Image
for v in ["up_s53","up_s56","up_s58","w5_wallR","w5_wallL","w5_baseR","w5_highR","w5_highL","w5_landR"]:
    try:
        a=Image.open(f"w5_w4b__{v}.png").convert("RGB"); b=Image.open(f"w5_w5a__{v}.png").convert("RGB")
    except Exception as e:
        print("skip",v,e); continue
    w,h=a.size; s=0.5
    a=a.resize((int(w*s),int(h*s))); b=b.resize((int(w*s),int(h*s)))
    c=Image.new("RGB",(a.width*2+8,a.height),(255,255,255)); c.paste(a,(0,0)); c.paste(b,(a.width+8,0)); c.save(f"cmp_{v}.jpg",quality=88)
print("cmp ok")
EOF
