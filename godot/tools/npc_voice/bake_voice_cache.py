# -*- coding: utf-8 -*-
"""NPC 語音快取離線烘焙：讀 data/npc_life/voices.json（每名 HERO 的聲線）＋ social.json 的 voice 台詞，
呼叫本機 TTS 引擎（AivisSpeech／VOICEVOX 相容 API：audio_query＋synthesis），
寫進 godot/assets/voice/cache/<lang>/<key>.wav，並更新 godot/assets/voice/voice_index.json（含長度與 30 Hz 音量包絡）。
key 的算法必須與 systems/npc_life/npc_voice.gd 的 clip_key 一致。只用本機免費引擎；只用 Python 標準函式庫。
只需要開 voices.json 裡 heroes 用到的引擎（目前只有 AivisSpeech：D:\\Tools\\TTS\\start_aivis.cmd）；
開工前會先檢查，沒開就直接說要開哪個，不會半途失敗。烘焙前先預熱每個聲線（AivisSpeech 冷模型約 7 s）。
用法：python bake_voice_cache.py [--langs=ja] [--topics=mk_greet,...] [--force]
之後：godot --headless --path godot --import
"""
import array, hashlib, io, json, math, os, struct, sys, time, urllib.parse, urllib.request, wave

GODOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
VOICES = os.path.join(GODOT, "data", "npc_life", "voices.json")
SOCIAL = os.path.join(GODOT, "data", "npc_life", "social.json")
OUTDIR = os.path.join(GODOT, "assets", "voice")
INDEX = os.path.join(OUTDIR, "voice_index.json")
ENV_HZ = 30.0


def clip_key(hero, lang, v, text):
    spk = v.get("speaker", "")
    spk_s = str(int(spk)) if isinstance(spk, (int, float)) else str(spk)
    sig = "%s|%s|%s|%s|%.2f|%s" % (hero, lang, v.get("engine", ""), spk_s, float(v.get("speed", 1.0)), text)
    return hashlib.sha1(sig.encode("utf-8")).hexdigest()[:16]


def http(url, data=None, ctype=None, timeout=300):
    req = urllib.request.Request(url, data=data, method="POST" if (data is not None or ctype == "post") else "GET")
    if ctype and ctype != "post":
        req.add_header("Content-Type", ctype)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, r.read()


def alive(eng):
    try:
        return http(eng["url"] + "/version", timeout=2)[0] == 200
    except Exception:
        return False


def fix_wav(b):
    """串流式 WAV 的 RIFF／data 長度可能是 0xFFFFFFFF：改成實際長度。"""
    if b[:4] != b"RIFF":
        return b
    b = bytearray(b)
    b[4:8] = struct.pack("<I", len(b) - 8)
    i = 12
    while i + 8 <= len(b):
        cid = bytes(b[i:i + 4]); size = struct.unpack("<I", b[i + 4:i + 8])[0]
        if cid == b"data":
            b[i + 4:i + 8] = struct.pack("<I", len(b) - i - 8); break
        i += 8 + size + (size & 1)
    return bytes(b)


def synth(eng, v, text):
    url = eng["url"]
    spk = int(v["speaker"])
    _, q = http(f"{url}/audio_query?" + urllib.parse.urlencode({"text": text, "speaker": spk}), ctype="post", timeout=120)
    query = json.loads(q)
    if "speed" in v: query["speedScale"] = float(v["speed"])
    if "pitch" in v: query["pitchScale"] = float(v["pitch"])
    if "intonation" in v: query["intonationScale"] = float(v["intonation"])
    _, wav = http(f"{url}/synthesis?speaker={spk}", json.dumps(query).encode("utf-8"), "application/json")
    return fix_wav(wav)


def envelope(wav):
    """16-bit PCM → 30 Hz RMS（每 4 個取樣取 1），正規化到 0..1；與 npc_voice.gd 的 envelope_from_wav 同算法。"""
    with wave.open(io.BytesIO(wav)) as w:
        ch, sr, sw, n = w.getnchannels(), w.getframerate(), w.getsampwidth(), w.getnframes()
        raw = w.readframes(n)
    if sw != 2:
        raise ValueError("只支援 16-bit PCM")
    a = array.array("h"); a.frombytes(raw)
    mono = a[::ch]
    frame = int(sr / ENV_HZ)
    env = []
    for k in range(0, len(mono), frame):
        seg = mono[k:k + frame:4]
        env.append(math.sqrt(sum((s / 32768.0) ** 2 for s in seg) / len(seg)) if len(seg) else 0.0)
    peak = max(env) if env and max(env) > 1e-6 else 1.0
    return [round(min(e / peak, 1.0), 3) for e in env], len(mono) / sr


def main():
    args = dict(a[2:].split("=", 1) if "=" in a else (a[2:], "1") for a in sys.argv[1:] if a.startswith("--"))
    langs = args.get("langs", "ja").split(",")
    only = set(args["topics"].split(",")) if "topics" in args else None
    voices = json.load(open(VOICES, encoding="utf-8"))
    social = json.load(open(SOCIAL, encoding="utf-8"))
    index = json.load(open(INDEX, encoding="utf-8")) if os.path.exists(INDEX) else {"clips": {}}
    # 只檢查／預熱實際用到的引擎與聲線
    need = {}
    for lang in langs:
        for hv in voices["heroes"].values():
            v = hv.get(lang)
            if v:
                need.setdefault(v["engine"], set()).add(int(v["speaker"]))
    down = [e for e in need if not alive(voices["engines"][e])]
    if down:
        sys.exit("要先開引擎：" + "、".join(f"{e}（{voices['engines'][e]['label']}，{voices['engines'][e]['url']}）" for e in down))
    for e, spks in need.items():
        for s in sorted(spks):
            t0 = time.perf_counter()
            http(f"{voices['engines'][e]['url']}/initialize_speaker?speaker={s}&skip_reinit=true", ctype="post", timeout=120)
            print(f"預熱 {e} {s}：{time.perf_counter() - t0:.2f}s")
    made = skipped = 0
    for lang in langs:
        os.makedirs(os.path.join(OUTDIR, "cache", lang), exist_ok=True)
        for t in social["topics"]:
            if "voice" not in t or lang not in t["voice"] or (only and t["id"] not in only):
                continue
            for i, ln in enumerate(t["lines"]):
                hero = ln[0]
                v = voices["heroes"].get(hero, {}).get(lang)
                if not v:
                    continue
                text = t["voice"][lang][i]
                key = clip_key(hero, lang, v, text)
                rel = f"cache/{lang}/{key}.wav"
                path = os.path.join(OUTDIR, rel)
                if key in index["clips"] and os.path.exists(path) and "force" not in args:
                    skipped += 1
                    continue
                t0 = time.perf_counter()
                wav = synth(voices["engines"][v["engine"]], v, text)
                gen = time.perf_counter() - t0
                open(path, "wb").write(wav)
                env, dur = envelope(wav)
                index["clips"][key] = {"file": "res://assets/voice/" + rel, "dur": round(dur, 3), "env": env, "hero": hero, "lang": lang,
                                       "engine": v["engine"], "voice": v.get("label", ""), "topic": t["id"], "line": i, "text": text, "gen_s": round(gen, 3)}
                made += 1
                print(f"{lang} {t['id']}#{i} {hero:6s} {v['engine']:8s} gen {gen:5.2f}s dur {dur:5.2f}s  {text}")
    json.dump(index, open(INDEX, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"made {made} skipped {skipped} → {INDEX}")


if __name__ == "__main__":
    main()
