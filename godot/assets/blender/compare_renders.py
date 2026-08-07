# Before / After 併圖
#
#   blender -b -P assets/blender/compare_renders.py -- <before.png> <after.png> <out.png>
#
# 為什麼用 Blender 跑：這台沒有 PIL、沒有 ImageMagick、系統 python 也沒有
# numpy —— 但 Blender 自己帶著全套（bpy.data.images 讀寫 PNG、內建 numpy）。
# 與其為了一張併圖裝東西，不如用已經在管線裡的工具。
import bpy
import sys
import numpy as np

A = sys.argv[sys.argv.index("--") + 1:]
before_p, after_p, out_p = A[0], A[1], A[2]

before = bpy.data.images.load(before_p)
after = bpy.data.images.load(after_p)
w0, h0 = before.size
w1, h1 = after.size
assert (w0, h0) == (w1, h1), "兩張圖尺寸不同：%sx%s vs %sx%s" % (w0, h0, w1, h1)

gap = 16
W, H = w0 * 2 + gap, h0
buf = np.zeros((H, W, 4), dtype=np.float32)
buf[:, :, 3] = 1.0
buf[:, :, 0:3] = 0.08                      # 中縫的分隔色

b = np.array(before.pixels[:], dtype=np.float32).reshape(h0, w0, 4)
a = np.array(after.pixels[:], dtype=np.float32).reshape(h1, w1, 4)
buf[:, 0:w0] = b
buf[:, w0 + gap:] = a

out = bpy.data.images.new("cmp", width=W, height=H, alpha=False)
out.pixels = buf.reshape(-1).tolist()
out.filepath_raw = out_p
out.file_format = "PNG"
out.save()
print("wrote %s（%dx%d｜左 BEFORE / 右 AFTER）" % (out_p, W, H))
