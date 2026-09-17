#!/usr/bin/env python
"""CC0 素材 → 遊戲音效建構管線。

來源全部為 CC0 / Public Domain（見 docs/audio_sources.md）。
原始錄音多為 192 kHz、單檔含多次撞擊，這裡負責：
  1. 以瞬態偵測切出單次撞擊
  2. 降頻至 44.1 kHz 單聲道
  3. 修剪靜音、加淡入淡出、峰值正規化到 -1 dBFS
  4. 分層混音（揮擊 + 火焰層等）
"""
import os, subprocess, numpy as np, wave

SR = 44100
PEAK = 10 ** (-1.0 / 20.0)
# 專案根目錄（tools/audio/ 的上兩層）。
_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
# 原始下載包放在 work/sfx_sourcing/（約 160 MB，.gitignore 排除 work/）。
# 這些腳本本身在版控內，重跑前需先依 docs/audio_sources.md 重新下載素材。
EX = os.path.join(_ROOT, "work", "sfx_sourcing", "ex")
CM = os.path.join(_ROOT, "work", "sfx_sourcing", "commons")
OUT = os.path.join(_ROOT, "godot", "assets", "audio", "sfx")


def load(p, sr=SR):
    r = subprocess.run(["ffmpeg", "-v", "error", "-i", p, "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"],
                       capture_output=True, timeout=180)
    x = np.frombuffer(r.stdout, dtype=np.float32).astype(np.float64)
    return x.copy()


def src(*parts):
    return os.path.join(EX, *parts)


def env_blocks(x, w_ms=10.0):
    w = max(int(w_ms / 1000.0 * SR), 1)
    k = len(x) // w
    if k == 0:
        return np.array([np.max(np.abs(x))]), w
    return np.abs(x[:k * w]).reshape(k, w).max(axis=1), w


def slice_hits(x, thresh=0.25, min_gap=0.25, pre=0.008, dur=0.55):
    """切出單次撞擊。thresh 相對於全檔峰值。"""
    b, w = env_blocks(x)
    peak = b.max() + 1e-12
    b = b / peak
    hits, last = [], -1e9
    for i, v in enumerate(b):
        t = i * w / SR
        if v > thresh and t - last > min_gap:
            hits.append(t)
            last = t
    out = []
    for t in hits:
        a = max(int((t - pre) * SR), 0)
        z = min(a + int(dur * SR), len(x))
        seg = x[a:z]
        if len(seg) > int(0.05 * SR):
            out.append(seg)
    return out


def trim(x, thresh=0.0015):
    idx = np.where(np.abs(x) > thresh)[0]
    if len(idx) == 0:
        return x
    return x[idx[0]:idx[-1] + 1]


def fade(x, fin=0.004, fout=0.05):
    x = x.copy()
    ni, no = int(fin * SR), int(fout * SR)
    ni, no = min(ni, len(x)), min(no, len(x))
    if ni > 0:
        x[:ni] *= np.linspace(0, 1, ni)
    if no > 0:
        x[-no:] *= np.linspace(1, 0, no)
    return x


def norm(x, peak=PEAK):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 1e-9 else x


def onepole_lp(x, fc):
    a = np.exp(-2.0 * np.pi * fc / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def lp(x, fc):
    """兩極低通（串兩次一極），避免依賴 scipy。"""
    return onepole_lp(onepole_lp(x, fc), fc)


def hp(x, fc):
    return x - lp(x, fc)


def resample_pitch(x, ratio):
    """ratio>1 = 變長、變慢、變低音（體型變大）；ratio<1 = 變短、變高。

    ⚠ 2026-09-17 修正：原本寫 n = len(x)/ratio，方向剛好相反 ——
    ratio=1.3 會讓 440 Hz 變成 1143 Hz（實測），與所有呼叫點的註解意圖
    （「變慢等於體型變大」）完全相反，山犬整組音效因此偏高偏小。
    """
    n = int(len(x) * ratio)
    if n < 8:
        return x
    src_i = np.linspace(0, len(x) - 1, n)
    return np.interp(src_i, np.arange(len(x)), x)


def mix(*layers):
    n = max(len(l) for l in layers)
    out = np.zeros(n)
    for l in layers:
        out[:len(l)] += l
    return out


def gain(x, db):
    return x * (10 ** (db / 20.0))


def pad(x, sec):
    n = int(sec * SR)
    return np.concatenate([x, np.zeros(max(n - len(x), 0))]) if len(x) < n else x


def save(name, x, fin=0.004, fout=0.05):
    x = norm(fade(trim(x), fin, fout))
    p = os.path.join(OUT, name)
    with wave.open(p, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
    print(f"  {name:28s} {len(x)/SR:5.2f}s")
    return p
