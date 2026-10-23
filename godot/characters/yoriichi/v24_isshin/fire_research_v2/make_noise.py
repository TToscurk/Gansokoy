"""FIRE_RESEARCH_V2：火焰著色器用的可平鋪噪聲（原創，無遊戲資料）。256×256、四方向無縫。
R＝低頻 fbm（火舌主形變）、G＝Worley 細胞邊（撕裂／分岔的破口）、B＝高頻 fbm（邊緣細節與溫度抖動）。
線性資料：shader 端不得加 source_color。執行：python make_noise.py
"""
from pathlib import Path
import numpy as np
from PIL import Image

S = 256
rng = np.random.default_rng(90210)

def spectral(beta, lo, hi):
    f = np.fft.fftfreq(S)
    k = np.sqrt(f[None, :] ** 2 + f[:, None] ** 2) * S
    amp = np.where((k >= lo) & (k <= hi), 1.0 / np.maximum(k, 1) ** beta, 0.0)
    z = np.fft.ifft2(amp * np.exp(2j * np.pi * rng.random((S, S)))).real
    return (z - z.min()) / np.ptp(z)

def worley(n):
    pts = rng.random((n, 2)) * S
    Y, X = np.mgrid[0:S, 0:S].astype(float)
    d1 = np.full((S, S), 1e9); d2 = np.full((S, S), 1e9)
    for px, py in pts:
        dx = np.abs(X - px); dx = np.minimum(dx, S - dx)
        dy = np.abs(Y - py); dy = np.minimum(dy, S - dy)
        d = np.sqrt(dx * dx + dy * dy)
        d2 = np.where(d < d1, d1, np.minimum(d2, d)); d1 = np.minimum(d1, d)
    e = d2 - d1                      # 細胞邊緣＝0
    return np.clip(e / np.percentile(e, 98), 0, 1)

r = spectral(1.6, 1, 24)
g = worley(42)
b = spectral(1.2, 6, 90)
img = np.dstack([r, g, b])
Image.fromarray(np.uint8(img * 255 + 0.5), "RGB").save(Path(__file__).parent / "fire_noise_v2.png")
seam = max(np.abs(img[0] - img[-1]).max(), np.abs(img[:, 0] - img[:, -1]).max())
print("saved; edge step (should be small, tileable):", round(float(seam), 3))
