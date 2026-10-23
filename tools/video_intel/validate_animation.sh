#!/usr/bin/env bash
# validate_animation 包裝：優先用獨立 venv（numpy＋pillow），找不到再用 PATH 上的 python。
# 例：bash tools/video_intel/validate_animation.sh --scene res://characters/yoriichi/v24_isshin/isshin_slash_demo.tscn \
#        --output D:/research/video_intel_poc/p1/run1 --scene-args "--tour --no-audio" --proj-check
#     bash tools/video_intel/validate_animation.sh --input D:/research/video_intel_poc/p1/run1
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${VIDEO_INTEL_PYTHON:-D:/Tools/video_intel/venv/Scripts/python.exe}"
[ -x "$PY" ] || PY=python
exec "$PY" "$HERE/validate_animation.py" "$@"
