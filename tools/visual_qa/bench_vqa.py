"""Visual QA 效能／記憶體量測：跑一次 vqa.py，期間每 0.1 s 取樣整個行程樹（Python＋Blender＋Godot）的 RSS 峰值。
  python tools/visual_qa/bench_vqa.py -- <vqa.py 參數…>"""
import subprocess
import sys
import time

import psutil

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
t0 = time.time()
p = subprocess.Popen([sys.executable, "tools/visual_qa/vqa.py", *args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
root = psutil.Process(p.pid)
peak = {}
while p.poll() is None:
    try:
        for c in [root] + root.children(recursive=True):
            try:
                n = c.name()
                r = c.memory_info().rss
                peak[n] = max(peak.get(n, 0), r)
            except psutil.Error:
                pass
    except psutil.Error:
        pass
    time.sleep(0.1)
out = p.stdout.read().decode("utf-8", "replace")
print(out.strip().splitlines()[-1] if out.strip() else "(no output)")
print(f"[BENCH] wall {time.time() - t0:.1f} s, exit {p.returncode}")
for n, r in sorted(peak.items(), key=lambda x: -x[1]):
    print(f"[BENCH] peak RSS {n}: {r / 2**20:.0f} MiB")
